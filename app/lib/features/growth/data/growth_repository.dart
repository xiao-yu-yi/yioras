import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/config/app_config.dart';
import '../../../core/network/api_client.dart';
import '../../../core/network/api_exception.dart';
import '../../../core/network/api_response.dart';
import '../model/growth_models.dart';
import 'mock_wallet.dart';

/// 成长激励仓库（任务/签到/忧珠）；统一抛 [ApiException]。
abstract interface class GrowthRepository {
  /// GET /tasks 任务中心（含签到状态）
  Future<TaskCenter> fetchTaskCenter();

  /// POST /tasks/sign-in 签到（重复签到服务端报错）
  Future<SignInResult> signIn();

  /// POST /tasks/:id/claim 领取任务奖励
  Future<ClaimResult> claimTask(int taskId);

  /// GET /youzhu/account 忧珠余额
  Future<YouzhuAccount> fetchAccount();

  /// GET /youzhu/logs 收支流水（页码分页，bizType=0 全部）
  Future<List<YouzhuLog>> fetchLogs({YouzhuBizType bizType, int page, int size});
}

class GrowthRepositoryHttp implements GrowthRepository {
  GrowthRepositoryHttp(this._dio);

  final Dio _dio;

  @override
  Future<TaskCenter> fetchTaskCenter() => _guard(() async {
    final resp = await _dio.get<Map<String, dynamic>>(
      '${AppConfig.apiPrefix}/tasks',
    );
    return ApiResponse.fromJson(
      resp.data!,
      (data) => TaskCenter.fromJson(data as Map<String, dynamic>),
    ).unwrap();
  });

  @override
  Future<SignInResult> signIn() => _guard(() async {
    final resp = await _dio.post<Map<String, dynamic>>(
      '${AppConfig.apiPrefix}/tasks/sign-in',
    );
    return ApiResponse.fromJson(
      resp.data!,
      (data) => SignInResult.fromJson(data as Map<String, dynamic>),
    ).unwrap();
  });

  @override
  Future<ClaimResult> claimTask(int taskId) => _guard(() async {
    final resp = await _dio.post<Map<String, dynamic>>(
      '${AppConfig.apiPrefix}/tasks/$taskId/claim',
    );
    return ApiResponse.fromJson(
      resp.data!,
      (data) => ClaimResult.fromJson(data as Map<String, dynamic>),
    ).unwrap();
  });

  @override
  Future<YouzhuAccount> fetchAccount() => _guard(() async {
    final resp = await _dio.get<Map<String, dynamic>>(
      '${AppConfig.apiPrefix}/youzhu/account',
    );
    return ApiResponse.fromJson(
      resp.data!,
      (data) => YouzhuAccount.fromJson(data as Map<String, dynamic>),
    ).unwrap();
  });

  @override
  Future<List<YouzhuLog>> fetchLogs({
    YouzhuBizType bizType = YouzhuBizType.all,
    int page = 1,
    int size = 20,
  }) => _guard(() async {
    final resp = await _dio.get<Map<String, dynamic>>(
      '${AppConfig.apiPrefix}/youzhu/logs',
      queryParameters: {
        if (bizType != YouzhuBizType.all) 'bizType': bizType.value,
        'page': page,
        'size': size,
      },
    );
    return ApiResponse.fromJson(
      resp.data!,
      (data) => (data as List<dynamic>? ?? const [])
          .map((e) => YouzhuLog.fromJson(e as Map<String, dynamic>))
          .toList(),
    ).unwrap();
  });

  Future<T> _guard<T>(Future<T> Function() action) async {
    try {
      return await action();
    } on DioException catch (e) {
      throw ApiException.fromDio(e);
    }
  }
}

/// Mock 实现：任务/签到状态在会话内生效，余额与流水走共享钱包
/// [MockYouzhuWallet]（与商城/付费解锁 Mock 账目一致）。
class GrowthRepositoryMock implements GrowthRepository {
  static final Set<int> _claimed = {};

  static const _taskSeeds = [
    (1, '每日签到', 1, 'sign_in', 1, 10, 5),
    (2, '浏览 5 篇帖子', 1, 'view', 5, 10, 5),
    (3, '点赞 3 次', 1, 'like', 3, 10, 5),
    (4, '发表 1 条评论', 1, 'comment', 1, 15, 8),
    (5, '发布 1 篇动态', 1, 'post', 1, 20, 10),
    (6, '完善个人资料', 2, 'profile', 1, 30, 15),
    (7, '加入 3 个圈子', 2, 'join_circle', 3, 30, 15),
    (8, '首次发布软件', 2, 'software', 1, 50, 30),
  ];

  @override
  Future<TaskCenter> fetchTaskCenter() async {
    await Future<void>.delayed(const Duration(milliseconds: 450));
    final signedToday = MockYouzhuWallet.signedToday;
    final continuous = MockYouzhuWallet.continuous;
    return TaskCenter(
      signedToday: signedToday,
      continuous: continuous,
      nextReward: 10 + ((continuous + (signedToday ? 0 : 1)) ~/ 3) * 5,
      tasks: [
        for (final s in _taskSeeds)
          GrowthTask(
            id: s.$1,
            name: s.$2,
            type: s.$3,
            action: s.$4,
            target: s.$5,
            // 模拟部分任务已达成可领取
            progress: _claimed.contains(s.$1)
                ? s.$5
                : (s.$1 % 3 == 0 ? s.$5 : s.$5 - 1).clamp(0, s.$5),
            rewardYouzhu: s.$6,
            rewardExp: s.$7,
            status: _claimed.contains(s.$1)
                ? 2
                : (s.$1 % 3 == 0 ? 1 : 0),
          ),
      ],
    );
  }

  @override
  Future<SignInResult> signIn() async {
    await Future<void>.delayed(const Duration(milliseconds: 500));
    if (MockYouzhuWallet.signedToday) {
      throw const ApiException(code: 42900, message: '今天已经签过到了');
    }
    MockYouzhuWallet.signedToday = true;
    MockYouzhuWallet.continuous += 1;
    final continuous = MockYouzhuWallet.continuous;
    final reward = 10 + (continuous ~/ 3) * 5;
    MockYouzhuWallet.apply(
      bizType: 2,
      amount: reward,
      remark: '第 $continuous 天连续签到',
    );
    return SignInResult(
      reward: reward,
      continuous: continuous,
      balance: MockYouzhuWallet.balance,
    );
  }

  @override
  Future<ClaimResult> claimTask(int taskId) async {
    await Future<void>.delayed(const Duration(milliseconds: 450));
    if (!_claimed.add(taskId)) {
      throw const ApiException(code: 42900, message: '奖励已领取过了');
    }
    final seed = _taskSeeds.firstWhere(
      (s) => s.$1 == taskId,
      orElse: () => throw const ApiException(code: 40400, message: '任务不存在'),
    );
    MockYouzhuWallet.apply(
      bizType: 1,
      amount: seed.$6,
      remark: '完成任务「${seed.$2}」',
    );
    return ClaimResult(reward: seed.$6, balance: MockYouzhuWallet.balance);
  }

  @override
  Future<YouzhuAccount> fetchAccount() async {
    await Future<void>.delayed(const Duration(milliseconds: 350));
    return YouzhuAccount(
      balance: MockYouzhuWallet.balance,
      signedToday: MockYouzhuWallet.signedToday,
    );
  }

  @override
  Future<List<YouzhuLog>> fetchLogs({
    YouzhuBizType bizType = YouzhuBizType.all,
    int page = 1,
    int size = 20,
  }) async {
    await Future<void>.delayed(const Duration(milliseconds: 400));
    final filtered = bizType == YouzhuBizType.all
        ? MockYouzhuWallet.logs
        : MockYouzhuWallet.logs
              .where((l) => l.bizType == bizType.value)
              .toList();
    final start = ((page - 1) * size).clamp(0, filtered.length);
    final end = (start + size).clamp(0, filtered.length);
    return filtered.sublist(start, end);
  }
}

final growthRepositoryProvider = Provider<GrowthRepository>((ref) {
  if (AppConfig.useMock) return GrowthRepositoryMock();
  return GrowthRepositoryHttp(ref.watch(dioProvider));
});
