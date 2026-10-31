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
  static const clientDataUrl = 'https://cardtrail.in/data/cards-client.json';
  static const searchIndexUrl = 'https://cardtrail.in/search-index.json';
  static const _hosts = {'cardtrail.in', 'www.cardtrail.in'};
  static const _userAgent = 'Cardy/1.0 (personal card catalogue)';
  static const _freshFor = Duration(hours: 24);
  static const _expectedCatalogueSize = 200;
  static const _maxBodyBytes = 5 * 1024 * 1024;
  static const _attemptsPerRequest = 2;
  static const _retryDelay = Duration(milliseconds: 700);
  String? _robotsText;

  final _validators = <String, ({String? etag, String? lastModified})>{};
  final _bodyCache = <String, String>{};

  Future<List<CardCatalogEntry>> list({bool forceRefresh = false}) async {
    final db = await LocalDatabase.instance.database;
    final cached = await db.query('card_catalogue',
        orderBy: 'bank COLLATE NOCASE, name COLLATE NOCASE');
    if (!forceRefresh && await _cacheIsFresh(db, cached.length)) {
      return cached.map(CardCatalogEntry.fromRow).toList();
    }

    var entries = <String, CardCatalogEntry>{};
    try {
      final clientEntries = clientEntriesFromJson(
          jsonDecode(await _get(Uri.parse(clientDataUrl))) as List<dynamic>);
      entries = _mergeEntries(entries, clientEntries);
    } catch (_) {
      // The structured feed is preferred but optional; fall back to scraping.
    }
    if (entries.length < _expectedCatalogueSize) {
      try {
        entries = _mergeEntries(
            entries, parseCatalogue(await _get(Uri.parse(catalogueUrl))));
      } catch (_) {
        // Keep whatever entries were already collected.
      }
    }
    if (entries.length < _expectedCatalogueSize) {
      try {
        entries = _mergeEntries(entries, await _readCardSitemaps());
      } catch (_) {
        // Sitemaps are the last discovery channel before using the cache.
      }
    }
    if (entries.length < _expectedCatalogueSize) {
      final searchIndex = <String, CardCatalogEntry>{};
      try {
        jsonDecode(await _get(Uri.parse(searchIndexUrl)))
            .cast<Map<String, dynamic>>()
            .forEach((row) {
          final slug = _slugFromSearchUrl(row['url']?.toString() ?? '');
          if (slug == null) return;
          searchIndex[slug] = CardCatalogEntry(
            slug: slug,
            name: row['title']?.toString() ?? titleFromSlug(slug),
            bank: row['bank']?.toString() ?? '',
            detailUrl: 'https://cardtrail.in/cards/$slug/',
            summary: row['description']?.toString() ?? '',
            checkedAt: DateTime.now(),
          );
        });
      } catch (_) {
        // Descriptions are a bonus; the catalogue can still be built without them.
      }
      entries = _mergeEntries(
          entries,
          searchIndex.values
              .where((entry) => !entries.containsKey(entry.slug))
              .toList());
    }

    if (entries.isEmpty) {
      if (cached.isNotEmpty)
        return cached.map(CardCatalogEntry.fromRow).toList();
      throw const CardCatalogueException(
          'CardTrail returned no card entries that Cardy could recognize.');
    }

    final checkedAt = DateTime.now();
    await db.transaction((txn) async {
      for (final entry in entries.values) {
        final previous = await txn.query('card_catalogue',
            where: 'slug = ?', whereArgs: [entry.slug], limit: 1);
        final previousEntry =
            previous.isEmpty ? null : CardCatalogEntry.fromRow(previous.first);
        final merged = entry.copyWith(
          details:
              entry.details.isNotEmpty ? entry.details : previousEntry?.details,
          summary: entry.summary.isNotEmpty
              ? entry.summary
              : previousEntry?.summary ?? entry.summary,
          checkedAt: checkedAt,
          detailsCheckedAt: previousEntry?.detailsCheckedAt,
        );
        await txn.insert('card_catalogue', merged.toRow(),
            conflictAlgorithm: ConflictAlgorithm.replace);
      }
    });
    final rows = await db.query('card_catalogue',
        orderBy: 'bank COLLATE NOCASE, name COLLATE NOCASE');
    return rows.map(CardCatalogEntry.fromRow).toList();
  }

  Future<CardCatalogEntry> details(CardCatalogEntry entry,
      {bool forceRefresh = false}) async {
    final cached = entry.detailsCheckedAt != null &&
        entry.details.isNotEmpty &&
        DateTime.now().difference(entry.detailsCheckedAt!) <
            const Duration(days: 14);
    if (cached && !forceRefresh) return entry;

    final page = await _get(Uri.parse(entry.detailUrl));
    final detail = parseDetails(page, entry);
    final db = await LocalDatabase.instance.database;
    await db.insert('card_catalogue', detail.toRow(),
        conflictAlgorithm: ConflictAlgorithm.replace);
    return detail;
  }

  Future<bool> _cacheIsFresh(Database db, int cachedCount) async {
    if (cachedCount < _expectedCatalogueSize) return false;
    final rows = await db
        .rawQuery('SELECT MAX(checked_at) AS latest FROM card_catalogue');
    final latest = rows.isEmpty ? null : rows.first['latest'] as int?;
    if (latest == null) return false;
    final latestTime = DateTime.fromMillisecondsSinceEpoch(latest, isUtc: true);
    return DateTime.now().isBefore(latestTime.add(_freshFor));
  }

  Future<String> _get(Uri uri) async {
    if (uri.scheme != 'https' || !_hosts.contains(uri.host)) {
      throw const CardCatalogueException(
          'CardTrail link was not on its trusted HTTPS host.');
    }
    if (uri.path != '/robots.txt') {
      _robotsText ??= await _loadRobots();
      if (!robotsAllows(_robotsText!, uri.path)) {
        throw const CardCatalogueException(
            'CardTrail robots.txt disallows this page.');
      }
    }
    Object? lastError;
    for (var attempt = 0; attempt < _attemptsPerRequest; attempt++) {
      if (attempt > 0) await Future<void>.delayed(_retryDelay);
      try {
        return await _getOnce(uri);
      } on CardCatalogueRetryableException catch (error) {
        lastError = error;
        continue;
      }
    }
    if (lastError is CardCatalogueException) {
      throw lastError;
    }
    throw CardCatalogueException('CardTrail request failed. $lastError');
  }

  Future<String> _getOnce(Uri uri) async {
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 15);
    client.userAgent = _userAgent;
    final validator = _validators[uri.toString()];
    try {
      final request =
          await client.getUrl(uri).timeout(const Duration(seconds: 20));
      request.headers
          .set(HttpHeaders.acceptHeader, 'text/html,application/json');
      request.headers.set(HttpHeaders.cacheControlHeader, 'no-cache');
      if (validator?.etag case final etag?) {
        request.headers.set(HttpHeaders.ifNoneMatchHeader, etag);
      }
      if (validator?.lastModified case final lastModified?) {
        request.headers.set(HttpHeaders.ifModifiedSinceHeader, lastModified);
      }
      final response =
          await request.close().timeout(const Duration(seconds: 25));
      if (response.statusCode == HttpStatus.notModified) {
        final cachedBody = _bodyCache[uri.toString()];
        if (cachedBody != null) return cachedBody;
        // Stale validator with no cached body; refetch without validators.
        _validators.remove(uri.toString());
        throw const CardCatalogueRetryableException(
            'Stale conditional request.');
      }
      if (response.statusCode == HttpStatus.tooManyRequests ||
          response.statusCode >= 500) {
        throw const CardCatalogueRetryableException(
            'CardTrail is temporarily unavailable.');
      }
      final redirects = response.redirects;
      var finalUri = uri;
      for (final redirect in redirects) {
        finalUri = finalUri.resolveUri(redirect.location);
        if (finalUri.scheme != 'https' || !_hosts.contains(finalUri.host)) {
          throw const CardCatalogueException(
              'CardTrail redirected outside its trusted host.');
        }
      }
      if (response.statusCode != HttpStatus.ok) {
        throw CardCatalogueException(
            'CardTrail returned HTTP ${response.statusCode}.');
      }
      final contentType = response.headers.contentType?.mimeType;
      if (contentType != null &&
          !_acceptedMimeTypes(uri).contains(contentType)) {
        throw CardCatalogueException(
            'CardTrail returned unexpected content type $contentType.');
      }
      final declaredLength = response.contentLength;
      if (declaredLength > 0 && declaredLength > _maxBodyBytes) {
        throw const CardCatalogueException(
            'The CardTrail page was larger than expected.');
      }
      final bytes = await response
          .fold<List<int>>(<int>[], (all, chunk) => all..addAll(chunk));
      if (bytes.length > _maxBodyBytes) {
        throw const CardCatalogueException(
            'The CardTrail page was larger than expected.');
      }
      final body = utf8.decode(bytes, allowMalformed: true);
      final etag = response.headers.value(HttpHeaders.etagHeader);
      final lastModified =
          response.headers.value(HttpHeaders.lastModifiedHeader);
      if (etag != null || lastModified != null) {
        _validators[uri.toString()] = (etag: etag, lastModified: lastModified);
        if (_bodyCache.length > 32) _bodyCache.clear();
        _bodyCache[uri.toString()] = body;
      }
      return body;
    } finally {
      client.close(force: true);
    }
  }

  static Set<String> _acceptedMimeTypes(Uri uri) {
    if (uri.path.endsWith('.json')) {
      return {'application/json', 'text/json'};
    }
    if (uri.path.endsWith('.xml')) {
      return {'application/xml', 'text/xml', 'application/rss+xml'};
    }
    return {'text/html', 'application/xhtml+xml', 'text/plain', 'text/xml'};
  }

  Future<String> _loadRobots() async {
    try {
      return await _get(Uri.parse('https://cardtrail.in/robots.txt'));
    } catch (_) {
      return '';
    }
  }

  static bool robotsAllows(String robots, String path) {
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
    final matching = groups
        .where((group) => group.agents
            .any((agent) => agent == '*' || agent.contains('cardy')))
        .toList();
    if (matching.isEmpty) return true;
    final candidates = matching.expand((group) => group.rules).where((rule) {
      final pattern = '^${RegExp.escape(rule.$2).replaceAll(r'\*', '.*')}'
          '${rule.$2.endsWith(r'$') ? r'$' : ''}';
      return RegExp(pattern).hasMatch(path);
    }).toList();
    if (candidates.isEmpty) return true;
    candidates.sort((a, b) => b.$2
        .replaceAll(RegExp(r'[*$]'), '')
        .length
        .compareTo(a.$2.replaceAll(RegExp(r'[*$]'), '').length));
    return candidates.first.$1;
  }

  static List<CardCatalogEntry> clientEntriesFromJson(List<dynamic> data) {
    final entries = <String, CardCatalogEntry>{};
    for (final item in data) {
      if (item is! Map) continue;
      final slug = item['s']?.toString() ?? '';
      final name = item['n']?.toString() ?? '';
      if (slug.isEmpty || name.isEmpty) continue;
      final lounge = item['lg'];
      final loungeAccess = lounge is num
          ? lounge < 0
              ? 'Unlimited'
              : '${lounge.toInt()} visit(s)'
          : null;
      final highlights = item['h'];
      entries[slug] = CardCatalogEntry(
        slug: slug,
        name: name,
        bank: item['b']?.toString() ?? '',
        detailUrl: 'https://cardtrail.in/cards/$slug/',
        category: _friendlyCategory(item['cat']?.toString() ?? ''),
        details: {
          if (item['af'] is num && (item['af'] as num) > 0)
            'Annual Fee': '₹${_moneyText((item['af'] as num).toDouble())}',
          if (item['fx'] is num) 'Forex Markup': '${item['fx']}%',
          if (item['sc'] is num) 'CardTrail Score': '${item['sc']} / 10',
          if (loungeAccess != null) 'Lounge Access': loungeAccess,
          if (highlights is List && highlights.isNotEmpty)
            'Key Highlights':
                highlights.map((highlight) => highlight.toString()).join('\n'),
        },
        checkedAt: DateTime.now(),
      );
    }
    return entries.values.toList();
  }

  static String _moneyText(double value) {
    final rounded = value.roundToDouble();
    if (rounded == value) {
      final digits = rounded.toStringAsFixed(0);
      final buffer = StringBuffer();
      for (var i = 0; i < digits.length; i++) {
        final remaining = digits.length - i;
        buffer.write(digits[i]);
        if (remaining > 1 && remaining % 3 == 1) buffer.write(',');
      }
      return buffer.toString();
    }
    return value.toString();
  }

  static String _friendlyCategory(String raw) {
    if (raw.isEmpty) return '';
    return raw
        .split(RegExp(r'[-_]'))
        .where((part) => part.isNotEmpty)
        .map((part) =>
            '${part[0].toUpperCase()}${part.substring(1).toLowerCase()}')
        .join(' ');
  }

  static String? _slugFromSearchUrl(String url) {
    final uri =
        Uri.tryParse(url.startsWith('http') ? url : 'https://cardtrail.in$url');
    if (uri == null || !_hosts.contains(uri.host)) return null;
    final parts = uri.pathSegments.where((part) => part.isNotEmpty).toList();
    if (parts.length != 2 || parts.first != 'cards') return null;
    const excluded = {'cards', 'page', 'category'};
    return excluded.contains(parts.last) ? null : parts.last;
  }

  static Map<String, CardCatalogEntry> _mergeEntries(
    Map<String, CardCatalogEntry> base,
    List<CardCatalogEntry> additions,
  ) {
    for (final entry in additions) {
      base.putIfAbsent(entry.slug, () => entry);
    }
    return base;
  }

  static List<CardCatalogEntry> parseCatalogue(String source) {
    final document = html_parser.parse(source);
    final entries = <String, CardCatalogEntry>{};
    for (final link in document.querySelectorAll('a[href]')) {
      final href = link.attributes['href'];
      final base = Uri.parse(catalogueUrl);
      final relative = href == null ? null : Uri.tryParse(href);
      final uri = relative == null ? null : base.resolveUri(relative);
      if (uri == null ||
          !_hosts.contains(uri.host) ||
          !uri.path.startsWith('/cards/')) continue;
      final pathParts =
          uri.pathSegments.where((part) => part.isNotEmpty).toList();
      if (pathParts.length != 2) continue;
      final slug = pathParts.last;
      if (const {'cards', 'page', 'category'}.contains(slug)) continue;
      var name = clean(link.text);
      if (name.isEmpty) {
        name = clean(link.querySelector('img')?.attributes['alt'] ?? '');
      }
      name = name.replaceAll(
          RegExp(
              r'\s+(?:HDFC|Axis|ICICI|SBI|Kotak|Amex|IDFC|RBL|HSBC|AU)\s+\d(?:\.\d+)?$'),
          '');
      if (name.length < 3 || name.length > 100) name = titleFromSlug(slug);
      final bank = bankFromText('$name ${clean(link.text)}');
      entries.putIfAbsent(
          slug,
          () => CardCatalogEntry(
                slug: slug,
                name: name,
                bank: bank,
                detailUrl: 'https://cardtrail.in/cards/$slug/',
              ));
    }
    return entries.values.toList();
  }

  static CardCatalogEntry parseDetails(String source, CardCatalogEntry entry) {
    final document = html_parser.parse(source);
    final text = clean(document.body?.text ?? '');
    final lines = (document.body?.text ?? '')
        .split(RegExp(r'\r?\n'))
        .map(clean)
        .where((s) => s.isNotEmpty)
        .toList();
    final ldProduct = _ldJsonProduct(source);
    final title = clean(
        document.querySelector('h1')?.text ?? ldProduct['name'] ?? entry.name);
    final about = section(text, 'About This Card', 'Pros & Cons').isNotEmpty
        ? section(text, 'About This Card', 'Pros & Cons')
        : ldProduct['description'] ?? '';
    final highlights = section(text, 'Key Highlights', 'Compare With');
    final prosCons = section(text, 'Pros & Cons', 'Fee Details');
    final fee = capture(
            text,
            RegExp(
                r'Annual Fee\s*(₹\s*[\d,]+(?:\.\d+)?|Lifetime free|Free|Nil)',
                caseSensitive: false)) ??
        (ldProduct['price'] == null ? null : '₹${ldProduct['price']}');
    final joiningFee = capture(text,
        RegExp(r'Joining Fee\s*(₹\s*[\d,]+(?:\.\d+)?|Lifetime free|Free|Nil)'));
    final forex = capture(
        text, RegExp(r'Forex Markup\s*([\d.]+\s*%)', caseSensitive: false));
    final reward = capture(text,
            RegExp(r'Reward Rate\s*([\d.]+\s*%)', caseSensitive: false)) ??
        capture(
            text, RegExp(r'Base Rate\s*([\d.]+\s*%)', caseSensitive: false));
    final maxReward = capture(
        text,
        RegExp(
            r'(?:Reward Rate|Base Rate)\s*[\d.]+\s*%\s*(?:Up to|Max(?:imum)? Rate)\s*([\d.]+\s*%)',
            caseSensitive: false));
    final waiver = capture(
        text,
        RegExp(
            r'Fee Waiver Condition\s*(.*?)\s*(?:Fuel Surcharge Waiver|EMI Conversion|Reward Structure|Lounge Access)',
            caseSensitive: false));
    final fuelWaiver = capture(
        text,
        RegExp(r'Fuel Surcharge Waiver\s*(Yes|No|[\d.]+\s*%)',
            caseSensitive: false));
    final emi = capture(
        text, RegExp(r'EMI Conversion\s*(Yes|No)', caseSensitive: false));
    final loungeValue = r'(?:Unlimited|None|[0-9]+)';
    final domesticLounge = capture(text,
        RegExp('Domestic Lounges\\s*($loungeValue)', caseSensitive: false));
    final internationalLounge = capture(
        text,
        RegExp('International Lounges\\s*($loungeValue)',
            caseSensitive: false));
    final rewardCurrency = capture(
        text,
        RegExp(
            r'Currency\s+([A-Za-z ]+?)(?=\s+Welcome Bonus|\s+Lounge Access|$)',
            caseSensitive: false));
    final welcomeBonus = capture(
        text,
        RegExp(
            r'Welcome Bonus\s+(.*?)(?=\s+(?:Lounge Access|Reward Structure|Fee Details))',
            caseSensitive: false));
    final minIncome = capture(
        text,
        RegExp(r'Min Income\s+(.*?)(?=\s+Compare This Card|\s+CardTrail Score)',
            caseSensitive: false));
    final bestFor = capture(
        text,
        RegExp(
            r'Best For\s+(.*?)(?=\s+Annual Fee|\s+Base Reward|\s+Max Reward|\s+Forex Markup|\s+Network)',
            caseSensitive: false));
    final score = capture(
        text,
        RegExp(r'CardTrail Score\s*(\d+(?:\.\d+)?)\s*/\s*10',
            caseSensitive: false));
    final network = capture(
        text,
        RegExp(r'Network\s+([A-Za-z ]+?)(?:\s+Min Income|\s+CardTrail Score|$)',
            caseSensitive: false));
    final category = lines.firstWhere(
        (line) => const {
              'Travel',
              'Shopping',
              'Cashback',
              'Fuel',
              'Lifestyle',
              'Rewards',
              'Premium',
              'Super Premium',
              'Entry Level',
              'Business',
              'Entertainment'
            }.contains(line),
        orElse: () => entry.category);
    final bank = entry.bank.isNotEmpty
        ? entry.bank
        : bankFromText(
            '${document.querySelector('img[alt*="logo"]')?.attributes['alt'] ?? ''} $text',
            fallback: entry.bank);

    final effectiveHighlights = highlights.isNotEmpty
        ? highlights
        : entry.details['Key Highlights'] ?? '';
    final details = <String, String>{
      if (fee != null) 'Annual Fee': fee,
      if (joiningFee != null) 'Joining Fee': joiningFee,
      if (waiver != null) 'Fee Waiver Condition': waiver,
      if (forex != null) 'Forex Markup': forex,
      if (reward != null) 'Base Reward Rate': reward,
      if (maxReward != null) 'Maximum Reward Rate': maxReward,
      if (rewardCurrency != null) 'Reward Currency': rewardCurrency.trim(),
      if (welcomeBonus != null) 'Welcome Bonus': welcomeBonus,
      if (network != null) 'Network': network.trim(),
      if (domesticLounge != null) 'Domestic Lounges': domesticLounge,
      if (internationalLounge != null)
        'International Lounges': internationalLounge,
      if (fuelWaiver != null) 'Fuel Surcharge Waiver': fuelWaiver,
      if (emi != null) 'EMI Conversion': emi,
      if (minIncome != null) 'Minimum Income': minIncome,
      if (bestFor != null) 'Best For': bestFor,
      if (score != null) 'CardTrail Score': '$score / 10',
      if (about.isNotEmpty) 'About This Card': about,
      if (effectiveHighlights.isNotEmpty) 'Key Highlights': effectiveHighlights,
      if (prosCons.isNotEmpty) 'Pros & Cons': prosCons,
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

  static Map<String, String?> _ldJsonProduct(String source) {
    final document = html_parser.parse(source);
    Map? product;
    for (final script
        in document.querySelectorAll('script[type="application/ld+json"]')) {
      final decoded = () {
        try {
          return jsonDecode(script.text);
        } catch (_) {
          return null;
        }
      }();
      if (decoded is Map &&
          decoded['@type']?.toString().toLowerCase() == 'product') {
        product = decoded;
        break;
      }
    }
    if (product == null) return const {};
    final brand = product['brand'];
    final brandName = brand is Map ? brand['name'] : brand;
    return {
      'name': product['name']?.toString(),
      'description': product['description']?.toString(),
      'price': switch (product['offers']) {
        Map offers when offers['price'] != null => offers['price'].toString(),
        _ => null,
      },
      if (brandName != null) 'brand': brandName.toString(),
    };
  }

  static String section(String text, String start, String end) {
    final startAt = text.toLowerCase().indexOf(start.toLowerCase());
    if (startAt < 0) return '';
    final bodyStart = startAt + start.length;
    final endAt = text.toLowerCase().indexOf(end.toLowerCase(), bodyStart);
    final limit =
        bodyStart + 1400 < text.length ? bodyStart + 1400 : text.length;
    return text.substring(bodyStart, endAt < 0 ? limit : endAt).trim();
  }

  static String? capture(String text, RegExp expression) =>
      expression.firstMatch(text)?.group(1)?.trim();

  static String clean(String text) =>
      text.replaceAll(RegExp(r'\s+'), ' ').trim();

  static String bankFromText(String text, {String fallback = ''}) {
    final value = text.toLowerCase();
    const banks = <String, List<String>>{
      'HDFC Bank': ['hdfc'],
      'Axis Bank': ['axis'],
      'ICICI Bank': ['icici'],
      'SBI Card': ['sbi'],
      'Kotak Mahindra Bank': ['kotak'],
      'American Express': ['amex', 'american express'],
      'IDFC FIRST Bank': ['idfc'],
      'RBL Bank': ['rbl'],
      'HSBC': ['hsbc'],
      'AU Small Finance Bank': ['au small finance', ' au '],
      'IndusInd Bank': ['indusind'],
      'Bank of Baroda': ['bank of baroda', 'bob'],
      'Federal Bank': ['federal bank'],
      'Standard Chartered': ['standard chartered'],
      'YES Bank': ['yes bank'],
      'DBS Bank': ['dbs'],
      'Bank of India': ['bank of india'],
      'Indian Bank': ['indian bank'],
    };
    for (final entry in banks.entries) {
      if (entry.value.any(value.contains)) return entry.key;
    }
    return fallback;
  }

  static String titleFromSlug(String slug) => slug
      .split('-')
      .map((part) =>
          part.isEmpty ? part : '${part[0].toUpperCase()}${part.substring(1)}')
      .join(' ');

  Future<List<CardCatalogEntry>> _readCardSitemaps() async {
    final pending = <Uri>[
      Uri.parse('https://cardtrail.in/sitemap-index.xml'),
      Uri.parse('https://cardtrail.in/wp-sitemap.xml'),
      Uri.parse('https://cardtrail.in/sitemap_index.xml'),
      Uri.parse('https://cardtrail.in/sitemap.xml'),
    ];
    for (final line in (_robotsText ?? '').split(RegExp(r'\r?\n'))) {
      final match = RegExp(r'^\s*Sitemap:\s*(\S+)', caseSensitive: false)
          .firstMatch(line);
      final sitemap = match == null ? null : Uri.tryParse(match.group(1)!);
      if (sitemap != null && _hosts.contains(sitemap.host))
        pending.add(sitemap);
    }

    final visited = <String>{};
    final entries = <String, CardCatalogEntry>{};
    while (pending.isNotEmpty && visited.length < 50) {
      final mapUri = pending.removeAt(0);
      if (!_hosts.contains(mapUri.host) || !visited.add(mapUri.toString()))
        continue;
      try {
        final doc = html_parser.parse(await _get(mapUri));
        for (final node in doc.querySelectorAll('loc')) {
          final uri = Uri.tryParse(node.text.trim());
          if (uri == null || !_hosts.contains(uri.host)) continue;
          final parts =
              uri.pathSegments.where((part) => part.isNotEmpty).toList();
          if (uri.path.startsWith('/cards/') && parts.length == 2) {
            final slug = parts.last;
            entries.putIfAbsent(
                slug,
                () => CardCatalogEntry(
                      slug: slug,
                      name: titleFromSlug(slug),
                      bank: bankFromText(slug.replaceAll('-', ' ')),
                      detailUrl: 'https://cardtrail.in/cards/$slug/',
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

class CardCatalogueRetryableException extends CardCatalogueException {
  const CardCatalogueRetryableException(super.message);
}

class CardCatalogueException implements Exception {
  const CardCatalogueException(this.message);
  final String message;
  @override
  String toString() => message;
}
