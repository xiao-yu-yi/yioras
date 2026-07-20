/// 忧珠商城领域模型（文档 3.9 装扮/靓号/抽奖/兑换记录，对齐 server types.go）。
library;

/// 装扮（头像框）商品（对齐 DecorationItem）
class Decoration {
  const Decoration({
    required this.id,
    required this.name,
    this.kind = 1,
    this.preview = '',
    this.price = 0,
    this.durationDays = 0,
    this.owned = false,
  });

  final int id;
  final String name;

  /// 1 头像框（气泡已裁剪）
  final int kind;
  final String preview;
  final int price;

  /// 有效天数，0=永久
  final int durationDays;

  /// 当前用户是否已拥有（未过期）
  final bool owned;

  factory Decoration.fromJson(Map<String, dynamic> json) => Decoration(
    id: (json['id'] as num).toInt(),
    name: json['name'] as String? ?? '',
    kind: (json['kind'] as num?)?.toInt() ?? 1,
    preview: json['preview'] as String? ?? '',
    price: (json['price'] as num?)?.toInt() ?? 0,
    durationDays: (json['durationDays'] as num?)?.toInt() ?? 0,
    owned: json['owned'] as bool? ?? false,
  );

  Decoration copyWith({bool? owned}) => Decoration(
    id: id,
    name: name,
    kind: kind,
    preview: preview,
    price: price,
    durationDays: durationDays,
    owned: owned ?? this.owned,
  );
}

/// 我的装扮仓库条目（对齐 MyDecorationItem）
class MyDecoration {
  const MyDecoration({
    required this.decorationId,
    required this.name,
    this.kind = 1,
    this.preview = '',
    this.worn = false,
    this.expireAt,
    this.expired = false,
  });

  final int decorationId;
  final String name;
  final int kind;
  final String preview;
  final bool worn;

  /// null=永久
  final DateTime? expireAt;
  final bool expired;

  factory MyDecoration.fromJson(Map<String, dynamic> json) {
    final expireMs = (json['expireAt'] as num?)?.toInt() ?? 0;
    return MyDecoration(
      decorationId: (json['decorationId'] as num).toInt(),
      name: json['name'] as String? ?? '',
      kind: (json['kind'] as num?)?.toInt() ?? 1,
      preview: json['preview'] as String? ?? '',
      worn: json['worn'] as bool? ?? false,
      expireAt: expireMs > 0
          ? DateTime.fromMillisecondsSinceEpoch(expireMs)
          : null,
      expired: json['expired'] as bool? ?? false,
    );
  }

  MyDecoration copyWith({bool? worn}) => MyDecoration(
    decorationId: decorationId,
    name: name,
    kind: kind,
    preview: preview,
    worn: worn ?? this.worn,
    expireAt: expireAt,
    expired: expired,
  );
}

/// 靓号 SKU（对齐 PrettyNoItem）
class PrettyNo {
  const PrettyNo({
    required this.id,
    required this.no,
    this.rarity = 1,
    this.price = 0,
  });

  final int id;
  final String no;

  /// 1 普通 / 2 稀有 / 3 传说
  final int rarity;
  final int price;

  String get rarityLabel => switch (rarity) {
    3 => '传说',
    2 => '稀有',
    _ => '普通',
  };

  factory PrettyNo.fromJson(Map<String, dynamic> json) => PrettyNo(
    id: (json['id'] as num).toInt(),
    no: json['no'] as String? ?? '',
    rarity: (json['rarity'] as num?)?.toInt() ?? 1,
    price: (json['price'] as num?)?.toInt() ?? 0,
  );
}

/// 抽奖奖品（对齐 PrizeItem；weight 用于概率公示）
class LotteryPrize {
  const LotteryPrize({
    required this.id,
    required this.name,
    this.kind = 1,
    this.amount = 0,
    this.weight = 0,
  });

  final int id;
  final String name;

  /// 1 忧珠 / 2 装扮
  final int kind;
  final int amount;
  final int weight;

  factory LotteryPrize.fromJson(Map<String, dynamic> json) => LotteryPrize(
    id: (json['id'] as num).toInt(),
    name: json['name'] as String? ?? '',
    kind: (json['kind'] as num?)?.toInt() ?? 1,
    amount: (json['amount'] as num?)?.toInt() ?? 0,
    weight: (json['weight'] as num?)?.toInt() ?? 0,
  );
}

/// 奖池（对齐 LotteryPoolsResp）
class LotteryPool {
  const LotteryPool({required this.cost, required this.prizes});

  /// 单次抽奖消耗忧珠
  final int cost;
  final List<LotteryPrize> prizes;

  factory LotteryPool.fromJson(Map<String, dynamic> json) => LotteryPool(
    cost: (json['cost'] as num?)?.toInt() ?? 0,
    prizes: (json['prizes'] as List<dynamic>? ?? const [])
        .map((e) => LotteryPrize.fromJson(e as Map<String, dynamic>))
        .toList(),
  );
}

/// 抽奖结果（对齐 DrawResp）
class DrawResult {
  const DrawResult({required this.prize, required this.balance});

  final LotteryPrize prize;
  final int balance;

  factory DrawResult.fromJson(Map<String, dynamic> json) => DrawResult(
    prize: LotteryPrize.fromJson(json['prize'] as Map<String, dynamic>),
    balance: (json['balance'] as num?)?.toInt() ?? 0,
  );
}

/// 兑换记录（对齐 ExchangeRecordItem）
class ExchangeRecord {
  const ExchangeRecord({
    required this.id,
    required this.kind,
    required this.name,
    required this.cost,
    required this.createdAt,
  });

  final int id;

  /// 1 装扮 / 2 靓号 / 3 抽奖
  final int kind;
  final String name;
  final int cost;
  final DateTime createdAt;

  String get kindLabel => switch (kind) {
    2 => '靓号',
    3 => '抽奖',
    _ => '装扮',
  };

  factory ExchangeRecord.fromJson(Map<String, dynamic> json) => ExchangeRecord(
    id: (json['id'] as num).toInt(),
    kind: (json['kind'] as num?)?.toInt() ?? 1,
    name: json['name'] as String? ?? '',
    cost: (json['cost'] as num?)?.toInt() ?? 0,
    createdAt: DateTime.fromMillisecondsSinceEpoch(
      (json['createdAt'] as num?)?.toInt() ?? 0,
    ),
  );
}
