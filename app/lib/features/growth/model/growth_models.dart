/// 成长激励领域模型（文档 3.9 任务中心/签到/忧珠，对齐 server types.go）。
library;

/// 任务条目（对齐 TaskItem）
class GrowthTask {
  const GrowthTask({
    required this.id,
    required this.name,
    this.type = 1,
    this.action = '',
    this.target = 1,
    this.progress = 0,
    this.rewardYouzhu = 0,
    this.rewardExp = 0,
    this.status = 0,
  });

  final int id;
  final String name;

  /// 1 每日 / 2 新手
  final int type;
  final String action;
  final int target;
  final int progress;
  final int rewardYouzhu;
  final int rewardExp;

  /// 0 进行中 / 1 可领取 / 2 已领取
  final int status;

  factory GrowthTask.fromJson(Map<String, dynamic> json) => GrowthTask(
    id: (json['id'] as num).toInt(),
    name: json['name'] as String? ?? '',
    type: (json['type'] as num?)?.toInt() ?? 1,
    action: json['action'] as String? ?? '',
    target: (json['target'] as num?)?.toInt() ?? 1,
    progress: (json['progress'] as num?)?.toInt() ?? 0,
    rewardYouzhu: (json['rewardYouzhu'] as num?)?.toInt() ?? 0,
    rewardExp: (json['rewardExp'] as num?)?.toInt() ?? 0,
    status: (json['status'] as num?)?.toInt() ?? 0,
  );

  GrowthTask copyWith({int? progress, int? status}) => GrowthTask(
    id: id,
    name: name,
    type: type,
    action: action,
    target: target,
    progress: progress ?? this.progress,
    rewardYouzhu: rewardYouzhu,
    rewardExp: rewardExp,
    status: status ?? this.status,
  );
}

/// 任务中心响应（对齐 TasksResp）
class TaskCenter {
  const TaskCenter({
    required this.signedToday,
    required this.continuous,
    required this.nextReward,
    required this.tasks,
  });

  final bool signedToday;

  /// 连续签到天数（未签今天则为截至昨天）
  final int continuous;

  /// 下一次签到可得忧珠
  final int nextReward;
  final List<GrowthTask> tasks;

  factory TaskCenter.fromJson(Map<String, dynamic> json) => TaskCenter(
    signedToday: json['signedToday'] as bool? ?? false,
    continuous: (json['continuous'] as num?)?.toInt() ?? 0,
    nextReward: (json['nextReward'] as num?)?.toInt() ?? 0,
    tasks: (json['tasks'] as List<dynamic>? ?? const [])
        .map((e) => GrowthTask.fromJson(e as Map<String, dynamic>))
        .toList(),
  );

  TaskCenter copyWith({
    bool? signedToday,
    int? continuous,
    int? nextReward,
    List<GrowthTask>? tasks,
  }) => TaskCenter(
    signedToday: signedToday ?? this.signedToday,
    continuous: continuous ?? this.continuous,
    nextReward: nextReward ?? this.nextReward,
    tasks: tasks ?? this.tasks,
  );
}

/// 签到结果（对齐 SignInResp）
class SignInResult {
  const SignInResult({
    required this.reward,
    required this.continuous,
    required this.balance,
  });

  final int reward;
  final int continuous;
  final int balance;

  factory SignInResult.fromJson(Map<String, dynamic> json) => SignInResult(
    reward: (json['reward'] as num?)?.toInt() ?? 0,
    continuous: (json['continuous'] as num?)?.toInt() ?? 0,
    balance: (json['balance'] as num?)?.toInt() ?? 0,
  );
}

/// 领奖结果（对齐 ClaimResp）
class ClaimResult {
  const ClaimResult({required this.reward, required this.balance});

  final int reward;
  final int balance;

  factory ClaimResult.fromJson(Map<String, dynamic> json) => ClaimResult(
    reward: (json['reward'] as num?)?.toInt() ?? 0,
    balance: (json['balance'] as num?)?.toInt() ?? 0,
  );
}

/// 忧珠账户（对齐 YouzhuAccountResp）
class YouzhuAccount {
  const YouzhuAccount({required this.balance, required this.signedToday});

  final int balance;
  final bool signedToday;

  factory YouzhuAccount.fromJson(Map<String, dynamic> json) => YouzhuAccount(
    balance: (json['balance'] as num?)?.toInt() ?? 0,
    signedToday: json['signedToday'] as bool? ?? false,
  );
}

/// 忧珠流水业务类型（对齐 youzhu_log.biz_type）
enum YouzhuBizType {
  all(0, '全部'),
  task(1, '任务'),
  signIn(2, '签到'),
  operation(3, '运营'),
  exchange(4, '兑换'),
  lottery(5, '抽奖'),
  paidUnlock(6, '付费解锁');

  const YouzhuBizType(this.value, this.label);

  final int value;
  final String label;

  static YouzhuBizType fromValue(int value) => values.firstWhere(
    (t) => t.value == value,
    orElse: () => YouzhuBizType.all,
  );
}

/// 忧珠流水条目（对齐 YouzhuLogItem）
class YouzhuLog {
  const YouzhuLog({
    required this.id,
    required this.bizType,
    required this.amount,
    required this.balanceAfter,
    this.remark = '',
    required this.createdAt,
  });

  final int id;
  final int bizType;

  /// 正数收入 / 负数支出
  final int amount;
  final int balanceAfter;
  final String remark;
  final DateTime createdAt;

  factory YouzhuLog.fromJson(Map<String, dynamic> json) => YouzhuLog(
    id: (json['id'] as num).toInt(),
    bizType: (json['bizType'] as num?)?.toInt() ?? 0,
    amount: (json['amount'] as num?)?.toInt() ?? 0,
    balanceAfter: (json['balanceAfter'] as num?)?.toInt() ?? 0,
    remark: json['remark'] as String? ?? '',
    createdAt: DateTime.fromMillisecondsSinceEpoch(
      (json['createdAt'] as num?)?.toInt() ?? 0,
    ),
  );
}
