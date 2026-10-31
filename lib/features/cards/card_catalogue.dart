import 'dart:convert';

class CardCatalogEntry {
  const CardCatalogEntry({
    required this.slug,
    required this.name,
    required this.bank,
    required this.detailUrl,
    this.category = '',
    this.summary = '',
    this.details = const {},
    this.checkedAt,
    this.detailsCheckedAt,
  });

  final String slug;
  final String name;
  final String bank;
  final String detailUrl;
  final String category;
  final String summary;
  final Map<String, String> details;
  final DateTime? checkedAt;
  final DateTime? detailsCheckedAt;

  Map<String, Object?> toRow() => {
        'slug': slug,
        'name': name,
        'bank': bank,
        'detail_url': detailUrl,
        'category': category,
        'summary': summary,
        'details_json': jsonEncode(details),
        'checked_at':
            (checkedAt ?? DateTime.now()).toUtc().millisecondsSinceEpoch,
        'details_checked_at': detailsCheckedAt?.toUtc().millisecondsSinceEpoch,
      };

  factory CardCatalogEntry.fromRow(Map<String, Object?> row) {
    final rawDetails =
        jsonDecode(row['details_json'] as String) as Map<String, dynamic>;
    return CardCatalogEntry(
      slug: row['slug'] as String,
      name: row['name'] as String,
      bank: row['bank'] as String,
      detailUrl: row['detail_url'] as String,
      category: row['category'] as String,
      summary: row['summary'] as String,
      details: rawDetails.map((key, value) => MapEntry(key, value.toString())),
      checkedAt: DateTime.fromMillisecondsSinceEpoch(row['checked_at'] as int,
              isUtc: true)
          .toLocal(),
      detailsCheckedAt: row['details_checked_at'] == null
          ? null
          : DateTime.fromMillisecondsSinceEpoch(
                  row['details_checked_at'] as int,
                  isUtc: true)
              .toLocal(),
    );
  }

  CardCatalogEntry copyWith({
    String? bank,
    String? category,
    String? summary,
    Map<String, String>? details,
    DateTime? checkedAt,
    DateTime? detailsCheckedAt,
  }) =>
      CardCatalogEntry(
        slug: slug,
        name: name,
        bank: bank ?? this.bank,
        detailUrl: detailUrl,
        category: category ?? this.category,
        summary: summary ?? this.summary,
        details: details ?? this.details,
        checkedAt: checkedAt ?? this.checkedAt,
        detailsCheckedAt: detailsCheckedAt ?? this.detailsCheckedAt,
      );

  String get displayBank => bank.isEmpty ? 'Issuer not listed' : bank;
  double? get annualFee => _money(details['Annual Fee']);
  double? get forexMarkup => _percent(details['Forex Markup']);
  double? get cardTrailScore => _score(details['CardTrail Score']);
  String? get imageUrl => details['Image'] == null
      ? null
      : 'https://cardtrail.in${details['Image']}';

  double? get cashbackRate {
    final description =
        '${details['Reward Currency'] ?? ''} ${details['About This Card'] ?? ''}'
            .toLowerCase();
    final isCashbackCategory = category.toLowerCase() == 'cashback';
    if (!isCashbackCategory && !description.contains('cashback')) return null;
    final match = RegExp(r'(\d+(?:\.\d+)?)\s*%')
        .firstMatch(details['Base Reward Rate'] ?? '');
    return match == null ? null : double.tryParse(match.group(1)!);
  }

  static double? _money(String? value) {
    if (value == null) return null;
    final match =
        RegExp(r'(\d[\d,]*(?:\.\d+)?)').firstMatch(value.replaceAll('₹', ''));
    return match == null
        ? null
        : double.tryParse(match.group(1)!.replaceAll(',', ''));
  }

  static double? _percent(String? value) {
    if (value == null) return null;
    final match = RegExp(r'(\d+(?:\.\d+)?)\s*%').firstMatch(value);
    return match == null ? null : double.tryParse(match.group(1)!);
  }

  static double? _score(String? value) {
    if (value == null) return null;
    final match =
        RegExp(r'(\d+(?:\.\d+)?)\s*(?:/\s*10|out of 10)').firstMatch(value);
    return match == null ? null : double.tryParse(match.group(1)!);
  }
}
