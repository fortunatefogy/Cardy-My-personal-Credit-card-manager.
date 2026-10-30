import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import 'card_catalogue.dart';
import 'card_catalogue_service.dart';

const _orange = Color(0xFFFF7A00);
const _muted = Color(0xFFA1A1AA);

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
      final cards = await CardCatalogueService.instance.list(forceRefresh: force);
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
          '${card.name} ${card.bank} ${card.category} ${card.summary}'.toLowerCase().contains(query);
      return matchesQuery && (_bank == 'All banks' || card.bank == _bank);
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final banks = _cards.map((card) => card.displayBank).toSet().toList()..sort();
    final visible = _visible;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Card catalogue'),
        actions: [
          IconButton(
            tooltip: 'Refresh catalogue',
            onPressed: _refreshing ? null : () => _load(force: true),
            icon: _refreshing
                ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.refresh),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: _orange))
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
                          prefixIcon: const Icon(Icons.search),
                          hintText: 'Search card, bank or feature',
                          suffixIcon: _search.text.isEmpty ? null : IconButton(
                            onPressed: () { _search.clear(); setState(() {}); },
                            icon: const Icon(Icons.close),
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),
                      SizedBox(
                        height: 42,
                        child: ListView(
                          scrollDirection: Axis.horizontal,
                          children: [
                            'All banks', ...banks,
                          ].map((bank) => Padding(
                            padding: const EdgeInsets.only(right: 8),
                            child: ChoiceChip(
                              label: Text(bank),
                              selected: _bank == bank,
                              onSelected: (_) => setState(() => _bank = bank),
                            ),
                          )).toList(),
                        ),
                      ),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: Text('${visible.length} cards · CardTrail catalogue · cached on this device',
                          style: const TextStyle(color: _muted, fontSize: 12)),
                      ),
                    ],
                  ),
                ),
                if (_error != null)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: MaterialBanner(
                      content: Text('Could not refresh CardTrail. ${_cards.isEmpty ? _error : 'Showing the local catalogue cache.'}'),
                      actions: [TextButton(onPressed: () => _load(force: true), child: const Text('Retry'))],
                    ),
                  ),
                Expanded(
                  child: visible.isEmpty
                      ? Center(child: Text(_cards.isEmpty ? 'No catalogue cached yet.' : 'No matching cards.', style: const TextStyle(color: _muted)))
                      : ListView.separated(
                          padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
                          itemCount: visible.length,
                          separatorBuilder: (_, __) => const SizedBox(height: 9),
                          itemBuilder: (context, index) {
                            final card = visible[index];
                            return Card(
                              child: ListTile(
                                leading: const CircleAvatar(backgroundColor: Color(0x263D3D3D), child: Icon(Icons.credit_card, color: _orange)),
                                title: Text(card.name, maxLines: 2, overflow: TextOverflow.ellipsis),
                                subtitle: Text('${card.displayBank}${card.category.isEmpty ? '' : ' · ${card.category}'}', style: const TextStyle(color: _muted)),
                                trailing: const Icon(Icons.chevron_right),
                                onTap: () async {
                                  final selected = await Navigator.of(context).push<CardCatalogEntry>(
                                    MaterialPageRoute(builder: (_) => _CardCatalogueDetailPage(entry: card)),
                                  );
                                  if (selected != null && context.mounted) Navigator.pop(context, selected);
                                },
                              ),
                            );
                          },
                        ),
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
  State<_CardCatalogueDetailPage> createState() => _CardCatalogueDetailPageState();
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
    setState(() { _loading = true; _error = null; });
    try {
      final detail = await CardCatalogueService.instance.details(_entry, forceRefresh: force);
      if (mounted) setState(() { _entry = detail; _loading = false; });
    } catch (error) {
      if (mounted) setState(() { _loading = false; _error = error.toString(); });
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(
          title: const Text('Card details'),
          actions: [
            IconButton(onPressed: _loading ? null : () => _load(force: true), icon: const Icon(Icons.refresh), tooltip: 'Refresh details'),
          ],
        ),
        body: _loading
            ? const Center(child: CircularProgressIndicator(color: _orange))
            : ListView(
                padding: const EdgeInsets.fromLTRB(18, 12, 18, 28),
                children: [
                  Text(_entry.name, style: const TextStyle(fontSize: 25, fontWeight: FontWeight.w800)),
                  const SizedBox(height: 5),
                  Text('${_entry.displayBank}${_entry.category.isEmpty ? '' : ' · ${_entry.category}'}', style: const TextStyle(color: _muted)),
                  const SizedBox(height: 14),
                  if (_error != null) _notice('Could not refresh details. ${_entry.details.isEmpty ? _error : 'Showing cached details.'}'),
                  if (_entry.summary.isNotEmpty) _section('About this card', _entry.summary),
                  if (_entry.details.isNotEmpty) ...[
                    const Text('Card details', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
                    const SizedBox(height: 8),
                    ..._entry.details.entries.map((item) => _detailRow(item.key, item.value)),
                  ] else
                    _notice('No detailed data was available in the page. You can still add the card and edit its details.'),
                  const SizedBox(height: 16),
                  _notice('Card details are sourced from CardTrail and may differ from current issuer terms. Confirm fees and benefits with the issuer before relying on them.'),
                  const SizedBox(height: 12),
                  OutlinedButton.icon(
                    onPressed: () => launchUrl(Uri.parse(_entry.detailUrl), mode: LaunchMode.externalApplication),
                    icon: const Icon(Icons.open_in_new),
                    label: const Text('Open CardTrail source'),
                  ),
                  const SizedBox(height: 8),
                  FilledButton.icon(
                    onPressed: () => Navigator.pop(context, _entry),
                    style: FilledButton.styleFrom(backgroundColor: _orange, foregroundColor: Colors.black),
                    icon: const Icon(Icons.add),
                    label: const Text('Add to my cards'),
                  ),
                ],
              ),
      );

  Widget _section(String title, String text) => Padding(
        padding: const EdgeInsets.only(bottom: 16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
          const SizedBox(height: 6),
          Text(text, style: const TextStyle(height: 1.4)),
        ]),
      );

  Widget _detailRow(String label, String value) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Container(
          padding: const EdgeInsets.all(13),
          decoration: BoxDecoration(color: const Color(0xFF1C1C1E), borderRadius: BorderRadius.circular(13)),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(label, style: const TextStyle(color: _muted, fontSize: 12)),
            const SizedBox(height: 3),
            Text(value),
          ]),
        ),
      );

  Widget _notice(String text) => Container(
        margin: const EdgeInsets.only(bottom: 13),
        padding: const EdgeInsets.all(13),
        decoration: BoxDecoration(color: const Color(0xFF1C1C1E), borderRadius: BorderRadius.circular(13)),
        child: Text(text, style: const TextStyle(color: _muted, height: 1.35)),
      );
}
