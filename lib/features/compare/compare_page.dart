import 'package:flutter/material.dart';
import 'package:hugeicons/hugeicons.dart';

import '../cards/credit_card.dart';
import '../../theme/cardy_palette.dart';

class ComparePage extends StatefulWidget {
  const ComparePage({super.key, required this.cards});
  final List<CreditCard> cards;
  @override
  State<ComparePage> createState() => _ComparePageState();
}

class _ComparePageState extends State<ComparePage> {
  final amount = TextEditingController();
  String? selectedCategory;
  List<_Result> results = [];
  bool calculated = false;

  List<String> get categories => widget.cards
      .expand((card) => card.categories.split(RegExp(r'[,;/|]')))
      .map((category) => category.trim())
      .where((category) => category.isNotEmpty)
      .toSet()
      .toList()
    ..sort();

  void _calculate() {
    final spend = double.tryParse(amount.text.replaceAll(',', '')) ?? 0;
    final active = widget.cards.where((card) {
      if (!card.active) return false;
      if (selectedCategory == null) return true;
      return card.categories.split(RegExp(r'[,;/|]')).any((value) =>
          value.trim().toLowerCase() == selectedCategory!.toLowerCase());
    }).toList();
    if (spend <= 0 || active.isEmpty) {
      results = [];
      setState(() => calculated = true);
      return;
    }
    results = active.map((c) {
      final cashback = spend * c.cashback / 100;
      final points = spend / 100 * c.rewardRate * c.pointValue;
      final estimated = c.rewardsStack
          ? cashback + points
          : (cashback > points ? cashback : points);
      return _Result(c, estimated, cashback, points, spend - estimated);
    }).toList()
      ..sort((a, b) => b.savings.compareTo(a.savings));
    setState(() => calculated = true);
  }

  @override
  Widget build(BuildContext context) => ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Text(
            'Best card finder',
            style: TextStyle(fontSize: 24, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 6),
          Text(
            'Estimate rewards from the rates you entered.',
            style: TextStyle(color: muted),
          ),
          const SizedBox(height: 18),
          DropdownButtonFormField<String?>(
            value: selectedCategory,
            decoration: const InputDecoration(labelText: 'Reward category'),
            items: [
              const DropdownMenuItem<String?>(
                value: null,
                child: Text('All categories'),
              ),
              ...categories.map(
                (category) => DropdownMenuItem<String?>(
                  value: category,
                  child: Text(category),
                ),
              ),
            ],
            onChanged: (value) => setState(() {
              selectedCategory = value;
              calculated = false;
            }),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: amount,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(
              labelText: 'Purchase amount (₹)',
              hintText: 'e.g. 20000',
            ),
          ),
          const SizedBox(height: 14),
          SizedBox(
            height: 50,
            child: FilledButton.icon(
              onPressed: _calculate,
              icon: const HugeIcon(icon: HugeIcons.strokeRoundedSparkles),
              label: const Text('Compare my cards'),
              style: FilledButton.styleFrom(
                backgroundColor: accentColor,
                foregroundColor:
                    isCardyDarkMode ? const Color(0xFF111111) : Colors.white,
              ),
            ),
          ),
          if (calculated) ...[
            const SizedBox(height: 20),
            if (results.isEmpty)
              Text(
                widget.cards.where((card) => card.active).isEmpty
                    ? 'Add an active card to compare.'
                    : selectedCategory != null &&
                            !widget.cards.any((card) =>
                                card.active &&
                                card.categories.split(RegExp(r'[,;/|]')).any(
                                    (value) =>
                                        value.trim().toLowerCase() ==
                                        selectedCategory!.toLowerCase()))
                        ? 'No active cards have the $selectedCategory category.'
                        : 'Enter a valid purchase amount to compare.',
                style: TextStyle(color: muted),
              )
            else ...[
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: accentColor.withValues(alpha: .12),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Text(
                  'Estimate based only on the rates you entered. Unconfirmed cashback and points are not added together. Caps, eligibility, exclusions and fees are not applied.',
                  style: TextStyle(color: muted),
                ),
              ),
              const SizedBox(height: 12),
              ...results.asMap().entries.map(
                    (e) => Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: surface,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: panelBorder),
                          boxShadow: [
                            BoxShadow(
                              color: panelShadow,
                              blurRadius: 16,
                              offset: const Offset(0, 5),
                            ),
                          ],
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                if (e.key == 0)
                                  HugeIcon(
                                    icon: HugeIcons.strokeRoundedTrophy,
                                    color: accentColor,
                                    size: 19,
                                  ),
                                if (e.key == 0) const SizedBox(width: 6),
                                Expanded(
                                  child: Text(
                                    e.value.card.nickname.isEmpty
                                        ? e.value.card.name
                                        : e.value.card.nickname,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w700,
                                      fontSize: 16,
                                    ),
                                  ),
                                ),
                                Text(
                                  '₹${e.value.savings.toStringAsFixed(0)} estimated rewards',
                                  style: const TextStyle(
                                    color: Color(0xFF7DE0A1),
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            Text(
                              'Cashback rule ₹${e.value.cashback.toStringAsFixed(0)} · Points rule ₹${e.value.points.toStringAsFixed(0)} · Net purchase cost after estimated rewards ₹${e.value.cost.toStringAsFixed(0)}',
                              style: TextStyle(color: muted, fontSize: 12),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
            ],
          ],
        ],
      );
}

class _Result {
  _Result(this.card, this.savings, this.cashback, this.points, this.cost);
  final CreditCard card;
  final double savings, cashback, points, cost;
}
