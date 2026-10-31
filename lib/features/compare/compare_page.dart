import 'package:flutter/material.dart';
import 'package:hugeicons/hugeicons.dart';

import '../cards/card_catalogue.dart';
import '../cards/card_catalogue_service.dart';
import '../cards/credit_card.dart';
import '../assistant/gemini_chat_service.dart';
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
  List<CardCatalogEntry> _catalogue = const [];
  List<_Result> results = [];
  bool calculated = false;

  @override
  void initState() {
    super.initState();
    _loadCatalogue();
  }

  Future<void> _loadCatalogue() async {
    try {
      final entries = await CardCatalogueService.instance.list();
      if (mounted) setState(() => _catalogue = entries);
    } catch (_) {
      if (mounted) setState(() => _catalogue = const []);
    }
  }

  List<String> _categoriesOf(CreditCard card) {
    if (card.categories.trim().isNotEmpty) {
      return card.categories.split(RegExp(r'[,;/|]')).toList();
    }
    final entry = GeminiChatService.matchCatalogueEntry(card, _catalogue);
    return entry == null || entry.category.isEmpty
        ? const []
        : [entry.category];
  }

  List<String> get categories => widget.cards
      .expand(_categoriesOf)
      .map((category) => category.trim())
      .where((category) => category.isNotEmpty)
      .toSet()
      .toList()
    ..sort();

  void _calculate() {
    final spend = double.tryParse(amount.text.replaceAll(',', '')) ?? 0;
    if (spend <= 0) {
      results = [];
      setState(() => calculated = true);
      return;
    }
    results = widget.cards
        .where((card) => card.active)
        .where((card) =>
            selectedCategory == null ||
            _categoriesOf(card).any((value) =>
                value.trim().toLowerCase() == selectedCategory!.toLowerCase()))
        .map((card) => _evaluate(card, spend))
        .toList()
      ..sort((a, b) {
        if (a.known != b.known) return a.known ? -1 : 1;
        return b.savings.compareTo(a.savings);
      });
    setState(() => calculated = true);
  }

  _Result _evaluate(CreditCard card, double spend) {
    final entry = GeminiChatService.matchCatalogueEntry(card, _catalogue);
    final cashbackPct =
        card.cashback > 0 ? card.cashback : (entry?.cashbackRate ?? 0);
    final userPointsPct = card.rewardRate > 0 && card.pointValue > 0
        ? card.rewardRate / 100 * card.pointValue
        : 0.0;
    final catalogRate = _pointsRatePercent(entry);
    final pointsPct = userPointsPct > 0 ? userPointsPct : (catalogRate ?? 0.0);
    final known = cashbackPct > 0 || pointsPct > 0;
    final paired = card.rewardsStack && cashbackPct > 0 && pointsPct > 0;
    final effectivePct = paired
        ? cashbackPct + pointsPct
        : (cashbackPct > pointsPct ? cashbackPct : pointsPct);
    final savings = known ? spend * effectivePct / 100 : 0.0;
    final cashback = spend * cashbackPct / 100;
    final points = spend * pointsPct / 100;
    return _Result(
      card: card,
      entry: entry,
      catalogRate: catalogRate,
      savings: savings,
      cashback: cashback,
      points: points,
      cost: spend - savings,
      known: known,
      paired: paired,
    );
  }

  double? _pointsRatePercent(CardCatalogEntry? entry) {
    if (entry == null) return null;
    final currency = (entry.details['Reward Currency'] ?? '').toLowerCase();
    final isCashback = entry.category.toLowerCase() == 'cashback' ||
        currency.contains('cashback');
    if (isCashback) return null;
    final match = RegExp(r'(\d+(?:\.\d+)?)\s*%')
        .firstMatch(entry.details['Base Reward Rate'] ?? '');
    return match == null ? null : double.tryParse(match.group(1)!);
  }

  String? _checkedLabel(CardCatalogEntry entry) {
    final checked = entry.detailsCheckedAt ?? entry.checkedAt;
    if (checked == null) return null;
    final d = checked.day.toString().padLeft(2, '0');
    final m = checked.month.toString().padLeft(2, '0');
    return '$d/$m/${checked.year}';
  }

  @override
  Widget build(BuildContext context) => ListView(
        padding: const EdgeInsets.all(20),
        children: [
          const Text(
            'Best card finder',
            style: TextStyle(fontSize: 24, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 6),
          Text(
            _catalogue.isEmpty
                ? 'Estimate rewards from the rates you entered. Loading CardTrail catalogue…'
                : 'Estimates use your entered rates, filled in from the CardTrail catalogue where data is missing.',
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
              Text(_emptyMessage(), style: TextStyle(color: muted))
            else ...[
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: accentColor.withValues(alpha: .12),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Text(
                  _catalogue.isEmpty
                      ? 'Catalogue data unavailable — comparing only on the rates you entered. Caps, eligibility, exclusions and fees are not applied.'
                      : 'Missing rates are filled from the CardTrail catalogue. Caps, eligibility, exclusions and fees are not applied.',
                  style: TextStyle(color: muted),
                ),
              ),
              const SizedBox(height: 12),
              ...results.asMap().entries.map(
                    (e) => Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: _buildResultCard(e.key, e.value),
                    ),
                  ),
            ],
          ],
        ],
      );

  String _emptyMessage() {
    if (!widget.cards.any((card) => card.active)) {
      return 'Add an active card to compare.';
    }
    if (selectedCategory != null &&
        !widget.cards.any((card) =>
            card.active &&
            _categoriesOf(card).any((value) =>
                value.trim().toLowerCase() ==
                selectedCategory!.toLowerCase()))) {
      return 'No active cards have the $selectedCategory category.';
    }
    return 'Enter a valid purchase amount to compare.';
  }

  Widget _buildResultCard(int rank, _Result r) {
    final title = r.card.nickname.isEmpty ? r.card.name : r.card.nickname;
    return Container(
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
              if (rank == 0 && r.known)
                HugeIcon(
                  icon: HugeIcons.strokeRoundedTrophy,
                  color: accentColor,
                  size: 19,
                ),
              if (rank == 0 && r.known) const SizedBox(width: 6),
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 16,
                  ),
                ),
              ),
              Text(
                r.known
                    ? '₹${r.savings.toStringAsFixed(0)} estimated rewards'
                    : 'No reward data',
                style: TextStyle(
                  color: r.known ? const Color(0xFF7DE0A1) : muted,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          if (r.known)
            Text(
              r.paired
                  ? 'Cashback ₹${r.cashback.toStringAsFixed(0)} + Points ₹${r.points.toStringAsFixed(0)} · Net purchase cost after estimated rewards ₹${r.cost.toStringAsFixed(0)}'
                  : 'Cashback rule ₹${r.cashback.toStringAsFixed(0)} · Points rule ₹${r.points.toStringAsFixed(0)} · Net purchase cost after estimated rewards ₹${r.cost.toStringAsFixed(0)}',
              style: TextStyle(color: muted, fontSize: 12),
            )
          else
            Text(
              'No reward rate found on the card or in the CardTrail catalogue. Enter the card\'s rates to compare it accurately.',
              style: TextStyle(color: muted, fontSize: 12),
            ),
          if (r.catalogRate != null) ...[
            const SizedBox(height: 6),
            Text(
              'Base reward rate ${r.entry!.details['Base Reward Rate']} from CardTrail'
              '${(() {
                final label = _checkedLabel(r.entry!);
                return label == null ? '' : ' (checked $label)';
              })()}',
              style: TextStyle(color: muted, fontSize: 11),
            ),
          ],
        ],
      ),
    );
  }
}

class _Result {
  _Result({
    required this.card,
    required this.entry,
    required this.catalogRate,
    required this.savings,
    required this.cashback,
    required this.points,
    required this.cost,
    required this.known,
    required this.paired,
  });
  final CreditCard card;
  final CardCatalogEntry? entry;
  final double? catalogRate;
  final double savings, cashback, points, cost;
  final bool known, paired;
}
