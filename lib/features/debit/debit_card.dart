class DebitCard {
  DebitCard({
    this.id,
    required this.bank,
    required this.label,
    required this.holder,
    required this.createdAt,
    this.network = '',
    this.cardNumber = '',
    this.expiryDate = '',
    this.cvv = '',
    this.secureDetails = '',
    this.artworkPath,
  });

  int? id;
  String bank, label, holder, network;
  DateTime createdAt;
  String cardNumber, expiryDate, cvv, secureDetails;
  String? artworkPath;

  int get styleSeed => createdAt.millisecondsSinceEpoch ~/ 1000;

  factory DebitCard.fromRow(Map<String, Object?> row) => DebitCard(
        id: row['id'] as int?,
        bank: row['bank'] as String,
        label: row['label'] as String,
        holder: row['holder'] as String,
        network: row['network'] as String,
        createdAt:
            DateTime.fromMillisecondsSinceEpoch(row['created_at'] as int),
        secureDetails: row['secure_details'] as String,
        artworkPath: row['artwork_path'] as String?,
      );

  Map<String, Object?> toRow() => {
        'bank': bank,
        'label': label,
        'holder': holder,
        'network': network,
        'secure_details': secureDetails,
        'artwork_path': artworkPath,
        'created_at': createdAt.millisecondsSinceEpoch,
      };
}
