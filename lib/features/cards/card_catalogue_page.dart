import 'package:silky_scroll/silky_scroll.dart';
import 'package:flutter/material.dart';
import 'package:hugeicons/hugeicons.dart';
import 'package:url_launcher/url_launcher.dart';

import 'card_catalogue.dart';
import '../../theme/cardy_transitions.dart';
import 'card_catalogue_service.dart';
import '../../theme/cardy_palette.dart';

class CardCataloguePage extends StatefulWidget {
  const CardCataloguePage({super.key});

  @override
  State<CardCataloguePage> createState() => _CardCataloguePageState();
}

class _CardCataloguePageState extends State<CardCataloguePage> {
  final _search = TextEditingController();
  List<CardCatalogEntry> _cards = [];
  bool _loading = true;
  bool _refreshing = false;
  String? _error;
  String _bank = 'All banks';

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _load({bool force = false}) async {
    setState(() {
      _loading = _cards.isEmpty;
      _refreshing = force;
      _error = null;
    });
    try {
      final cards =
          await CardCatalogueService.instance.list(forceRefresh: force);
      if (!mounted) return;
      setState(() {
        _cards = cards;
        _loading = false;
        _refreshing = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _refreshing = false;
        _error = error.toString();
      });
    }
  }

  List<CardCatalogEntry> get _visible {
    final query = _search.text.trim().toLowerCase();
    return _cards.where((card) {
      final matchesQuery = query.isEmpty ||
          '${card.name} ${card.bank} ${card.category} ${card.summary}'
              .toLowerCase()
              .contains(query);
      return matchesQuery && (_bank == 'All banks' || card.bank == _bank);
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final banks = _cards.map((card) => card.displayBank).toSet().toList()
      ..sort();
    final visible = _visible;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Card catalogue'),
        actions: [
          IconButton(
            tooltip: 'Refresh catalogue',
            onPressed: _refreshing ? null : () => _load(force: true),
            icon: _refreshing
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2))
                : const HugeIcon(icon: HugeIcons.strokeRoundedRefreshCw),
          ),
        ],
      ),
      body: _loading
          ? Center(child: CircularProgressIndicator(color: accentColor))
          : Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 10),
                  child: Column(
                    children: [
                      TextField(
                        controller: _search,
                        onChanged: (_) => setState(() {}),
                        decoration: InputDecoration(
                          prefixIcon: const HugeIcon(
                              icon: HugeIcons.strokeRoundedSearch01),
                          hintText: 'Search card, bank or feature',
                          suffixIcon: _search.text.isEmpty
                              ? null
                              : IconButton(
                                  onPressed: () {
                                    _search.clear();
                                    setState(() {});
                                  },
                                  icon: const HugeIcon(
                                      icon: HugeIcons.strokeRoundedCancel01),
                                ),
                        ),
                      ),
                      const SizedBox(height: 8),
                      SizedBox(
                        height: 42,
                        child: SilkyScroll(
                            direction: Axis.horizontal,
                            physics: const BouncingScrollPhysics(),
                            edgeLockingDelay: Duration.zero,
                            overScrollingLockingDelay: Duration.zero,
                            builder: (_, scrollController, scrollPhysics) =>
                                ListView(
                                  controller: scrollController,
                                  physics: scrollPhysics,
                                  scrollDirection: Axis.horizontal,
                                  children: [
                                    'All banks',
                                    ...banks,
                                  ]
                                      .map((bank) => Padding(
                                            padding:
                                                const EdgeInsets.only(right: 8),
                                            child: ChoiceChip(
                                              label: Text(bank),
                                              selected: _bank == bank,
                                              onSelected: (_) =>
                                                  setState(() => _bank = bank),
                                            ),
                                          ))
                                      .toList(),
                                )),
                      ),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                            '${visible.length} cards · CardTrail catalogue · cached on this device',
                            style: TextStyle(color: muted, fontSize: 12)),
                      ),
                    ],
                  ),
                ),
                if (_error != null)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: MaterialBanner(
                      content: Text(
                          'Could not refresh CardTrail. ${_cards.isEmpty ? _error : 'Showing the local catalogue cache.'}'),
                      actions: [
                        TextButton(
                            onPressed: () => _load(force: true),
                            child: const Text('Retry'))
                      ],
                    ),
                  ),
                Expanded(
                  child: visible.isEmpty
                      ? Center(
                          child: Text(
                              _cards.isEmpty
                                  ? 'No catalogue cached yet.'
                                  : 'No matching cards.',
                              style: TextStyle(color: muted)))
                      : SilkyScroll(
                          physics: const BouncingScrollPhysics(),
                          edgeLockingDelay: Duration.zero,
                          overScrollingLockingDelay: Duration.zero,
                          builder: (_, scrollController, scrollPhysics) =>
                              ListView.separated(
                                controller: scrollController,
                                physics: scrollPhysics,
                                padding:
                                    const EdgeInsets.fromLTRB(16, 4, 16, 24),
                                itemCount: visible.length,
                                separatorBuilder: (_, __) =>
                                    const SizedBox(height: 9),
                                itemBuilder: (context, index) {
                                  final card = visible[index];
                                  final fee = card.annualFee;
                                  return Card(
                                    child: ListTile(
                                      leading: CircleAvatar(
                                          backgroundColor: surface,
                                          child: HugeIcon(
                                              icon: HugeIcons
                                                  .strokeRoundedCreditCard,
                                              color: accentColor)),
                                      title: Text(card.name,
                                          maxLines: 2,
                                          overflow: TextOverflow.ellipsis),
                                      subtitle: Text(
                                          '${card.displayBank}'
                                          '${card.category.isEmpty ? '' : ' · ${card.category}'}'
                                          '${fee == null || fee <= 0 ? '' : ' · ₹${fee.toStringAsFixed(0)} fee'}',
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: TextStyle(color: muted)),
                                      trailing: card.cardTrailScore == null
                                          ? const HugeIcon(
                                              icon: HugeIcons
                                                  .strokeRoundedArrowRight01)
                                          : Text(
                                              card.cardTrailScore!
                                                  .toStringAsFixed(1),
                                              style: TextStyle(
                                                  color: isCardyDarkMode
                                                      ? const Color(0xFF7DE0A1)
                                                      : const Color(0xFF0B7A45),
                                                  fontWeight: FontWeight.w700)),
                                      onTap: () async {
                                        final selected =
                                            await Navigator.of(context)
                                                .push<CardCatalogEntry>(
                                          cardyPageRoute(
                                            (_) => _CardCatalogueDetailPage(
                                                entry: card),
                                          ),
                                        );
                                        if (selected != null && context.mounted)
                                          Navigator.pop(context, selected);
                                      },
                                    ),
                                  );
                                },
                              )),
                ),
              ],
            ),
    );
  }
}

class _CardCatalogueDetailPage extends StatefulWidget {
  const _CardCatalogueDetailPage({required this.entry});
  final CardCatalogEntry entry;
  @override
  State<_CardCatalogueDetailPage> createState() =>
      _CardCatalogueDetailPageState();
}

class _CardCatalogueDetailPageState extends State<_CardCatalogueDetailPage> {
  late CardCatalogEntry _entry = widget.entry;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load({bool force = false}) async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final detail = await CardCatalogueService.instance
          .details(_entry, forceRefresh: force);
      if (mounted)
        setState(() {
          _entry = detail;
          _loading = false;
        });
    } catch (error) {
      if (mounted)
        setState(() {
          _loading = false;
          _error = error.toString();
        });
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(
          title: const Text('Card details'),
          actions: [
            IconButton(
                onPressed: _loading ? null : () => _load(force: true),
                icon: const HugeIcon(icon: HugeIcons.strokeRoundedRefreshCw),
                tooltip: 'Refresh details'),
          ],
        ),
        body: _loading
            ? Center(child: CircularProgressIndicator(color: accentColor))
            : SilkyScroll(
                physics: const BouncingScrollPhysics(),
                edgeLockingDelay: Duration.zero,
                overScrollingLockingDelay: Duration.zero,
                builder: (_, scrollController, scrollPhysics) => ListView(
                      controller: scrollController,
                      physics: scrollPhysics,
                      padding: const EdgeInsets.fromLTRB(18, 12, 18, 28),
                      children: [
                        Text(_entry.name,
                            style: const TextStyle(
                                fontSize: 25, fontWeight: FontWeight.w800)),
                        const SizedBox(height: 5),
                        Text(
                            '${_entry.displayBank}${_entry.category.isEmpty ? '' : ' · ${_entry.category}'}',
                            style: TextStyle(color: muted)),
                        const SizedBox(height: 14),
                        if (_entry.imageUrl != null) ...[
                          ClipRRect(
                            borderRadius: BorderRadius.circular(16),
                            child: Image.network(
                              _entry.imageUrl!,
                              height: 170,
                              width: double.infinity,
                              fit: BoxFit.cover,
                              errorBuilder: (_, __, ___) =>
                                  const SizedBox.shrink(),
                            ),
                          ),
                          Padding(
                            padding: const EdgeInsets.only(top: 4),
                            child: Text('Card artwork provided by CardTrail',
                                style: TextStyle(color: muted, fontSize: 11)),
                          ),
                          const SizedBox(height: 12),
                        ],
                        if (_error != null)
                          _notice(
                              'Could not refresh details. ${_entry.details.isEmpty ? _error : 'Showing cached details.'}'),
                        if (_entry.summary.isNotEmpty)
                          _section('About this card', _entry.summary),
                        if (_entry.details.isNotEmpty) ...[
                          const Text('Card details',
                              style: TextStyle(
                                  fontSize: 18, fontWeight: FontWeight.w700)),
                          const SizedBox(height: 8),
                          ..._entry.details.entries
                              .map((item) => _detailRow(item.key, item.value)),
                        ] else
                          _notice(
                              'No detailed data was available in the page. You can still add the card and edit its details.'),
                        const SizedBox(height: 16),
                        _notice('Card details are sourced from CardTrail'
                            '${_entry.detailsCheckedAt == null ? '' : ' · last checked ${_entry.detailsCheckedAt!.day}/${_entry.detailsCheckedAt!.month}/${_entry.detailsCheckedAt!.year}'}'
                            ' and may differ from current issuer terms. Confirm fees and benefits with the issuer before relying on them.'),
                        const SizedBox(height: 12),
                        OutlinedButton.icon(
                          onPressed: () => launchUrl(
                              Uri.parse(_entry.detailUrl),
                              mode: LaunchMode.externalApplication),
                          icon: const HugeIcon(
                              icon: HugeIcons.strokeRoundedArrowUpRight01),
                          label: const Text('Open CardTrail source'),
                        ),
                        const SizedBox(height: 8),
                        FilledButton.icon(
                          onPressed: () => Navigator.pop(context, _entry),
                          style: FilledButton.styleFrom(
                              backgroundColor: accentColor,
                              foregroundColor: isCardyDarkMode
                                  ? const Color(0xFF171719)
                                  : Colors.white),
                          icon: const HugeIcon(
                              icon: HugeIcons.strokeRoundedAdd01),
                          label: const Text('Add to my cards'),
                        ),
                      ],
                    )),
      );

  Widget _section(String title, String text) => Padding(
        padding: const EdgeInsets.only(bottom: 16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title,
              style:
                  const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
          const SizedBox(height: 6),
          Text(text, style: const TextStyle(height: 1.4)),
        ]),
      );

  Widget _detailRow(String label, String value) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Container(
          padding: const EdgeInsets.all(13),
          decoration: BoxDecoration(
              color: surface, borderRadius: BorderRadius.circular(13)),
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(label, style: TextStyle(color: muted, fontSize: 12)),
            const SizedBox(height: 3),
            Text(value),
          ]),
        ),
      );

  Widget _notice(String text) => Container(
        margin: const EdgeInsets.only(bottom: 13),
        padding: const EdgeInsets.all(13),
        decoration: BoxDecoration(
            color: surface, borderRadius: BorderRadius.circular(13)),
        child: Text(text, style: TextStyle(color: muted, height: 1.35)),
      );
}
