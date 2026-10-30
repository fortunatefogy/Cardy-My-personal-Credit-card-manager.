import 'dart:convert';
import 'dart:io';

import 'package:html/parser.dart' as html_parser;
import 'package:sqflite/sqflite.dart';

import '../../data/local_database.dart';
import 'card_catalogue.dart';

class CardCatalogueService {
  CardCatalogueService._();
  static final instance = CardCatalogueService._();

  static const catalogueUrl = 'https://cardtrail.in/cards/';
  static const _hosts = {'cardtrail.in', 'www.cardtrail.in'};
  static const _userAgent = 'CardWiseAI/1.0 (personal card catalogue)';
  static const _freshFor = Duration(hours: 24);
  static const _expectedCatalogueSize = 200;
  String? _robotsText;

  Future<List<CardCatalogEntry>> list({bool forceRefresh = false}) async {
    final db = await LocalDatabase.instance.database;
    final cached = await db.query('card_catalogue', orderBy: 'bank COLLATE NOCASE, name COLLATE NOCASE');
    final fresh = cached.length >= _expectedCatalogueSize && DateTime.now().difference(
          CardCatalogEntry.fromRow(cached.first).checkedAt ?? DateTime(2000),
        ) < _freshFor;
    if (!forceRefresh && fresh) return cached.map(CardCatalogEntry.fromRow).toList();

    final response = await _get(Uri.parse(catalogueUrl));
    var entries = _parseCatalogue(response);
    if (entries.length < 200) {
      try {
        entries = {for (final e in [...entries, ...await _readCardSitemaps()]) e.slug: e}.values.toList();
      } catch (_) {
        // Keep the public directory entries when sitemap discovery is unavailable.
      }
    }
    if (entries.isEmpty) {
      if (cached.isNotEmpty) return cached.map(CardCatalogEntry.fromRow).toList();
      throw const CardCatalogueException('CardTrail returned no card entries that CardWise could recognize.');
    }

    final checkedAt = DateTime.now();
    await db.transaction((txn) async {
      for (final entry in entries) {
        final previous = await txn.query('card_catalogue', where: 'slug = ?', whereArgs: [entry.slug], limit: 1);
        final previousEntry = previous.isEmpty ? null : CardCatalogEntry.fromRow(previous.first);
        final merged = entry.copyWith(
          details: previousEntry?.details,
          summary: previousEntry?.summary ?? entry.summary,
          checkedAt: checkedAt,
          detailsCheckedAt: previousEntry?.detailsCheckedAt,
        );
        await txn.insert('card_catalogue', merged.toRow(), conflictAlgorithm: ConflictAlgorithm.replace);
      }
    });
    final rows = await db.query('card_catalogue', orderBy: 'bank COLLATE NOCASE, name COLLATE NOCASE');
    return rows.map(CardCatalogEntry.fromRow).toList();
  }

  Future<CardCatalogEntry> details(CardCatalogEntry entry, {bool forceRefresh = false}) async {
    final cached = entry.detailsCheckedAt != null && entry.details.isNotEmpty &&
        DateTime.now().difference(entry.detailsCheckedAt!) < const Duration(days: 14);
    if (cached && !forceRefresh) return entry;

    final page = await _get(Uri.parse(entry.detailUrl));
    final detail = _parseDetails(page, entry);
    final db = await LocalDatabase.instance.database;
    await db.insert('card_catalogue', detail.toRow(), conflictAlgorithm: ConflictAlgorithm.replace);
    return detail;
  }

  Future<String> _get(Uri uri) async {
    if (uri.scheme != 'https' || !_hosts.contains(uri.host)) {
      throw const CardCatalogueException('CardTrail link was not on its trusted HTTPS host.');
    }
    if (uri.path != '/robots.txt') {
      _robotsText ??= await _loadRobots();
      if (!_robotsAllows(_robotsText!, uri.path)) {
        throw const CardCatalogueException('CardTrail robots.txt disallows this page.');
      }
    }
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 15);
    client.userAgent = _userAgent;
    try {
      final request = await client.getUrl(uri).timeout(const Duration(seconds: 20));
      request.headers.set(HttpHeaders.acceptHeader, 'text/html,application/xhtml+xml');
      request.headers.set(HttpHeaders.cacheControlHeader, 'no-cache');
      final response = await request.close().timeout(const Duration(seconds: 25));
      var finalUri = uri;
      for (final redirect in response.redirects) {
        finalUri = finalUri.resolveUri(redirect.location);
        if (finalUri.scheme != 'https' || !_hosts.contains(finalUri.host)) {
          throw const CardCatalogueException('CardTrail redirected outside its trusted host.');
        }
      }
      if (response.statusCode != HttpStatus.ok) {
        throw CardCatalogueException('CardTrail returned HTTP ${response.statusCode}.');
      }
      if (response.contentLength > 5 * 1024 * 1024) {
        throw const CardCatalogueException('The CardTrail page was larger than expected.');
      }
      final bytes = await response.fold<List<int>>(<int>[], (all, chunk) => all..addAll(chunk));
      if (bytes.length > 5 * 1024 * 1024) {
        throw const CardCatalogueException('The CardTrail page was larger than expected.');
      }
      return utf8.decode(bytes, allowMalformed: true);
    } finally {
      client.close(force: true);
    }
  }

  Future<String> _loadRobots() async {
    try {
      return await _get(Uri.parse('https://cardtrail.in/robots.txt'));
    } catch (_) {
      return '';
    }
  }

  bool _robotsAllows(String robots, String path) {
    final groups = <({List<String> agents, List<(bool, String)> rules})>[];
    var agents = <String>[];
    var rules = <(bool, String)>[];
    var hasRule = false;
    void finish() {
      if (agents.isNotEmpty) groups.add((agents: agents, rules: rules));
      agents = <String>[];
      rules = <(bool, String)>[];
      hasRule = false;
    }
    for (final raw in robots.split(RegExp(r'\r?\n'))) {
      final line = raw.split('#').first.trim();
      final colon = line.indexOf(':');
      if (colon <= 0) continue;
      final key = line.substring(0, colon).trim().toLowerCase();
      final value = line.substring(colon + 1).trim();
      if (key == 'user-agent') {
        if (hasRule) finish();
        agents.add(value.toLowerCase());
      } else if ((key == 'allow' || key == 'disallow') && agents.isNotEmpty) {
        hasRule = true;
        if (value.isNotEmpty) rules.add((key == 'allow', value));
      }
    }
    finish();
    final matching = groups.where((group) => group.agents.any((agent) => agent == '*' || agent.contains('cardwiseai'))).toList();
    if (matching.isEmpty) return true;
    final candidates = matching.expand((group) => group.rules).where((rule) {
      final pattern = '^${RegExp.escape(rule.$2).replaceAll(r'\*', '.*')}'
          '${rule.$2.endsWith(r'$') ? r'$' : ''}';
      return RegExp(pattern).hasMatch(path);
    }).toList();
    if (candidates.isEmpty) return true;
    candidates.sort((a, b) => b.$2.replaceAll(RegExp(r'[*$]'), '').length.compareTo(a.$2.replaceAll(RegExp(r'[*$]'), '').length));
    return candidates.first.$1;
  }

  List<CardCatalogEntry> _parseCatalogue(String source) {
    final document = html_parser.parse(source);
    final entries = <String, CardCatalogEntry>{};
    for (final link in document.querySelectorAll('a[href]')) {
      final href = link.attributes['href'];
      final base = Uri.parse(catalogueUrl);
      final relative = href == null ? null : Uri.tryParse(href);
      final uri = relative == null ? null : base.resolveUri(relative);
      if (uri == null || !_hosts.contains(uri.host) || !uri.path.startsWith('/cards/')) continue;
      final pathParts = uri.pathSegments.where((part) => part.isNotEmpty).toList();
      if (pathParts.length != 2) continue;
      final slug = pathParts.last;
      if (const {'cards', 'page', 'category'}.contains(slug)) continue;
      var name = _clean(link.text);
      if (name.isEmpty) {
        name = _clean(link.querySelector('img')?.attributes['alt'] ?? '');
      }
      name = name.replaceAll(RegExp(r'\s+(?:HDFC|Axis|ICICI|SBI|Kotak|Amex|IDFC|RBL|HSBC|AU)\s+\d(?:\.\d)?$'), '');
      if (name.length < 3 || name.length > 100) name = _titleFromSlug(slug);
      final bank = _bankFromText('$name ${_clean(link.text)}');
      entries.putIfAbsent(slug, () => CardCatalogEntry(
            slug: slug,
            name: name,
            bank: bank,
            detailUrl: 'https://cardtrail.in/cards/$slug/',
          ));
    }
    return entries.values.toList();
  }

  CardCatalogEntry _parseDetails(String source, CardCatalogEntry entry) {
    final document = html_parser.parse(source);
    final text = _clean(document.body?.text ?? '');
    final lines = (document.body?.text ?? '').split(RegExp(r'\r?\n')).map(_clean).where((s) => s.isNotEmpty).toList();
    final title = _clean(document.querySelector('h1')?.text ?? entry.name);
    final about = _section(text, 'About This Card', 'Pros & Cons');
    final highlights = _section(text, 'Key Highlights', 'Compare With');
    final fee = _capture(text, RegExp(r'Annual Fee\s*(₹\s*[\d,]+(?:\.\d+)?|Lifetime free|Free|Nil)', caseSensitive: false));
    final forex = _capture(text, RegExp(r'Forex Markup\s*([\d.]+\s*%)', caseSensitive: false));
    final reward = _capture(text, RegExp(r'Reward Rate\s*([\d.]+\s*%)', caseSensitive: false));
    final maxReward = _capture(text, RegExp(r'Reward Rate\s*[\d.]+\s*%\s*Up to\s*([\d.]+\s*%)', caseSensitive: false));
    final waiver = _capture(text, RegExp(r'Fee Waiver Condition\s*(.*?)\s*(?:Fuel Surcharge Waiver|EMI Conversion|Reward Structure|Lounge Access)', caseSensitive: false));
    final domesticLounge = _capture(text, RegExp(r'Domestic Lounges\s*(\d+)', caseSensitive: false));
    final internationalLounge = _capture(text, RegExp(r'International Lounges\s*(\d+)', caseSensitive: false));
    final network = _capture(text, RegExp(r'Network\s+([A-Za-z ]+?)(?:\s+Min Income|\s+CardTrail Score|$)', caseSensitive: false));
    final category = lines.firstWhere((line) => const {'Travel','Shopping','Cashback','Fuel','Lifestyle','Rewards','Premium','Business','Entertainment'}.contains(line), orElse: () => entry.category);
    final bank = _bankFromText('${document.querySelector('img[alt*="logo"]')?.attributes['alt'] ?? ''} $text', fallback: entry.bank);

    final details = <String, String>{
      if (fee != null) 'Annual Fee': fee,
      if (waiver != null) 'Fee Waiver Condition': waiver,
      if (forex != null) 'Forex Markup': forex,
      if (reward != null) 'Base Reward Rate': reward,
      if (maxReward != null) 'Maximum Reward Rate': maxReward,
      if (network != null) 'Network': network.trim(),
      if (domesticLounge != null) 'Domestic Lounges': domesticLounge,
      if (internationalLounge != null) 'International Lounges': internationalLounge,
      if (about.isNotEmpty) 'About This Card': about,
      if (highlights.isNotEmpty) 'Key Highlights': highlights,
    };
    return CardCatalogEntry(
      slug: entry.slug,
      name: title,
      bank: bank,
      detailUrl: entry.detailUrl,
      category: category,
      summary: about,
      details: details,
      checkedAt: entry.checkedAt,
      detailsCheckedAt: DateTime.now(),
    );
  }

  String _section(String text, String start, String end) {
    final startAt = text.toLowerCase().indexOf(start.toLowerCase());
    if (startAt < 0) return '';
    final bodyStart = startAt + start.length;
    final endAt = text.toLowerCase().indexOf(end.toLowerCase(), bodyStart);
    final limit = bodyStart + 1400 < text.length ? bodyStart + 1400 : text.length;
    return text.substring(bodyStart, endAt < 0 ? limit : endAt).trim();
  }

  String? _capture(String text, RegExp expression) => expression.firstMatch(text)?.group(1)?.trim();
  String _clean(String text) => text.replaceAll(RegExp(r'\s+'), ' ').trim();

  String _bankFromText(String text, {String fallback = ''}) {
    final value = text.toLowerCase();
    const banks = <String, List<String>>{
      'HDFC Bank': ['hdfc'], 'Axis Bank': ['axis'], 'ICICI Bank': ['icici'],
      'SBI Card': ['sbi'], 'Kotak Mahindra Bank': ['kotak'], 'American Express': ['amex', 'american express'],
      'IDFC FIRST Bank': ['idfc'], 'RBL Bank': ['rbl'], 'HSBC': ['hsbc'],
      'AU Small Finance Bank': ['au small finance', ' au '], 'IndusInd Bank': ['indusind'],
      'Bank of Baroda': ['bank of baroda', 'bob'], 'Federal Bank': ['federal bank'],
      'Standard Chartered': ['standard chartered'], 'YES Bank': ['yes bank'], 'DBS Bank': ['dbs'],
      'Bank of India': ['bank of india'], 'Indian Bank': ['indian bank'],
    };
    for (final entry in banks.entries) {
      if (entry.value.any(value.contains)) return entry.key;
    }
    return fallback;
  }

  String _titleFromSlug(String slug) => slug.split('-').map((part) => part.isEmpty ? part : '${part[0].toUpperCase()}${part.substring(1)}').join(' ');

  Future<List<CardCatalogEntry>> _readCardSitemaps() async {
    final pending = <Uri>[
      Uri.parse('https://cardtrail.in/wp-sitemap.xml'),
      Uri.parse('https://cardtrail.in/sitemap_index.xml'),
      Uri.parse('https://cardtrail.in/sitemap.xml'),
    ];
    for (final line in (_robotsText ?? '').split(RegExp(r'\r?\n'))) {
      final match = RegExp(r'^\s*Sitemap:\s*(\S+)', caseSensitive: false).firstMatch(line);
      final sitemap = match == null ? null : Uri.tryParse(match.group(1)!);
      if (sitemap != null && _hosts.contains(sitemap.host)) pending.add(sitemap);
    }

    final visited = <String>{};
    final entries = <String, CardCatalogEntry>{};
    while (pending.isNotEmpty && visited.length < 50) {
      final mapUri = pending.removeAt(0);
      if (!_hosts.contains(mapUri.host) || !visited.add(mapUri.toString())) continue;
      try {
        final doc = html_parser.parse(await _get(mapUri));
        for (final node in doc.querySelectorAll('loc')) {
          final uri = Uri.tryParse(node.text.trim());
          if (uri == null || !_hosts.contains(uri.host)) continue;
          final parts = uri.pathSegments.where((part) => part.isNotEmpty).toList();
          if (uri.path.startsWith('/cards/') && parts.length == 2) {
            final slug = parts.last;
            entries.putIfAbsent(slug, () => CardCatalogEntry(
                  slug: slug,
                  name: _titleFromSlug(slug),
                  bank: _bankFromText(slug.replaceAll('-', ' ')),
                  detailUrl: 'https://${uri.host}${uri.path}',
                ));
          } else if (uri.path.toLowerCase().endsWith('.xml')) {
            pending.add(uri);
          }
        }
      } on CardCatalogueException {
        // A missing sitemap variant should not prevent trying the other sitemap roots.
      } catch (_) {
        // Sitemaps are optional; keep trying the remaining roots and child maps.
      }
    }
    return entries.values.toList();
  }
}

class CardCatalogueException implements Exception {
  const CardCatalogueException(this.message);
  final String message;
  @override
  String toString() => message;
}
