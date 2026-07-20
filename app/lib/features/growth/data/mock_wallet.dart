import '../model/growth_models.dart';

/// Mock 层共享忧珠钱包：growth（任务/签到）与 mall（兑换/抽奖）、
/// post_detail（付费解锁）共用余额与流水，保证演示链路账目一致。
abstract final class MockYouzhuWallet {
  static int balance = 1350;
  static bool signedToday = false;
  static int continuous = 3;
  static int _nextLogId = 5000;

  static final List<YouzhuLog> logs = List.generate(26, (i) {
    final types = [1, 2, 1, 4, 2, 5, 1, 6, 2, 3];
    final bizType = types[i % types.length];
    final income = bizType != 4 && bizType != 5;
    final amount = income ? 10 + (i * 7) % 40 : -(30 + (i * 11) % 120);
    return YouzhuLog(
      id: 4000 - i,
      bizType: bizType,
      amount: amount,
      balanceAfter: 1350 - i * 13,
      remark: switch (bizType) {
        1 => '完成任务「每日点赞」',
        2 => '第 ${9 - i % 7} 天连续签到',
        3 => '内测活动补偿发放',
        4 => '兑换头像框「星河漫游」',
        5 => '积分抽奖消耗',
        _ => '解锁付费帖分成',
      },
      createdAt: DateTime.now().subtract(Duration(hours: 5 + i * 16)),
    );
  });

  /// 入账/扣款并记流水；余额不足抛前由调用方校验
  static void apply({
    required int bizType,
    required int amount,
    required String remark,
  }) {
    balance += amount;
    logs.insert(
      0,
      YouzhuLog(
        id: _nextLogId++,
        bizType: bizType,
        amount: amount,
        balanceAfter: balance,
        remark: remark,
        createdAt: DateTime.now(),
      ),
    );
  }
}
