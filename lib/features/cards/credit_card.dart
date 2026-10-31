class CreditCard {
  CreditCard({
    required this.bank,
    required this.name,
    required this.network,
    required this.nickname,
    this.annualFee = 0,
    this.cashback = 0,
    this.rewardRate = 0,
    this.pointValue = 0,
    this.categories = '',
    this.notes = '',
    this.secureDetails = '',
    this.cardNumber = '',
    this.expiryDate = '',
    this.cvv = '',
    this.active = true,
    this.rewardsStack = false,
    this.styleSeed = -1,
    this.databaseId,
    this.artworkPath,
  });

  String bank, name, network, nickname, categories, notes;
  String secureDetails, cardNumber, expiryDate, cvv;
  double annualFee, cashback, rewardRate, pointValue;
  bool active, rewardsStack;
  int styleSeed;
  int? databaseId;
  String? artworkPath;

  Map<String, dynamic> toJson() => {
        'bank': bank,
        'name': name,
        'network': network,
        'nickname': nickname,
        'annualFee': annualFee,
        'cashback': cashback,
        'rewardRate': rewardRate,
        'pointValue': pointValue,
        'categories': categories,
        'notes': notes,
        'secureDetails': secureDetails,
        'active': active,
        'rewardsStack': rewardsStack,
        'styleSeed': styleSeed,
        'artworkPath': artworkPath,
      };

  factory CreditCard.fromJson(Map<String, dynamic> json) => CreditCard(
        bank: json['bank'] ?? '',
        name: json['name'] ?? '',
        network: json['network'] ?? 'Visa',
        nickname: json['nickname'] ?? '',
        annualFee: (json['annualFee'] ?? 0).toDouble(),
        cashback: (json['cashback'] ?? 0).toDouble(),
        rewardRate: (json['rewardRate'] ?? 0).toDouble(),
        pointValue: (json['pointValue'] ?? 0).toDouble(),
        categories: json['categories'] ?? '',
        notes: json['notes'] ?? '',
        secureDetails: json['secureDetails'] ?? '',
        active: json['active'] ?? true,
        rewardsStack: json['rewardsStack'] ?? false,
        styleSeed: json['styleSeed'] ?? -1,
        artworkPath: json['artworkPath'],
      );

  Map<String, Object?> toDatabase() => {
        if (databaseId != null) 'id': databaseId,
        'bank': bank,
        'name': name,
        'network': network,
        'nickname': nickname,
        'annual_fee': annualFee,
        'cashback': cashback,
        'reward_rate': rewardRate,
        'point_value': pointValue,
        'categories': categories,
        'notes': notes,
        'secure_details': secureDetails,
        'active': active ? 1 : 0,
        'rewards_stack': rewardsStack ? 1 : 0,
        'style_seed': styleSeed,
        'artwork_path': artworkPath,
      };

  factory CreditCard.fromDatabase(Map<String, Object?> row) => CreditCard(
        databaseId: row['id'] as int?,
        bank: row['bank'] as String,
        name: row['name'] as String,
        network: row['network'] as String,
        nickname: row['nickname'] as String,
        annualFee: (row['annual_fee'] as num).toDouble(),
        cashback: (row['cashback'] as num).toDouble(),
        rewardRate: (row['reward_rate'] as num).toDouble(),
        pointValue: (row['point_value'] as num).toDouble(),
        categories: row['categories'] as String,
        notes: row['notes'] as String,
        secureDetails: row['secure_details'] as String? ?? '',
        active: row['active'] == 1,
        rewardsStack: row['rewards_stack'] == 1,
        styleSeed: row['style_seed'] as int? ?? -1,
        artworkPath: row['artwork_path'] as String?,
      );
}
