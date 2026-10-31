const identityDocumentTypes = [
  'Aadhaar',
  'PAN card',
  'Driving licence',
  'Passport',
  'Voter ID',
  'Other',
];

class IdentityDocument {
  IdentityDocument({
    this.id,
    required this.type,
    required this.holder,
    required this.expiry,
    required this.note,
    required this.createdAt,
    this.idNumber = '',
    this.secureDetails = '',
    this.artworkPath,
  });

  int? id;
  String type, holder;

  /// Month of expiry as `YYYY-MM`, or empty when the document does not expire.
  String expiry, note;
  String idNumber, secureDetails;
  String? artworkPath;
  DateTime createdAt;

  bool get expired {
    if (expiry.length < 7) return false;
    final year = int.parse(expiry.substring(0, 4));
    final month = int.parse(expiry.substring(5, 7));
    final now = DateTime.now();
    return year < now.year || (year == now.year && month < now.month);
  }

  String get expiryLabel {
    if (expiry.length < 7) return 'No expiry date';
    return '${expired ? 'Expired' : 'Valid until'} ${expiry.substring(5, 7)}/${expiry.substring(0, 4)}';
  }

  factory IdentityDocument.fromRow(Map<String, Object?> row) =>
      IdentityDocument(
        id: row['id'] as int?,
        type: row['doc_type'] as String,
        holder: row['holder'] as String,
        expiry: row['expiry'] as String,
        note: row['note'] as String,
        secureDetails: row['secure_details'] as String? ?? '',
        artworkPath: row['artwork_path'] as String?,
        createdAt:
            DateTime.fromMillisecondsSinceEpoch(row['created_at'] as int),
      );

  Map<String, Object?> toRow() => {
        'doc_type': type,
        'holder': holder,
        'expiry': expiry,
        'note': note,
        'secure_details': secureDetails,
        'artwork_path': artworkPath,
        'created_at': createdAt.millisecondsSinceEpoch,
      };
}
