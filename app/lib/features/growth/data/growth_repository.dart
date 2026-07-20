import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/config/app_config.dart';
import '../../../core/network/api_client.dart';
import '../../../core/network/api_exception.dart';
import '../../../core/network/api_response.dart';
import '../model/growth_models.dart';

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

/// Mock 实现：内存任务/签到/流水，进度与领奖状态会话内生效。
class GrowthRepositoryMock implements GrowthRepository {
  static bool _signedToday = false;
  static int _continuous = 3;
  static int _balance = 1350;
  static final Set<int> _claimed = {};
  static int _nextLogId = 5000;

  static final List<YouzhuLog> _logs = List.generate(26, (i) {
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
    return TaskCenter(
      signedToday: _signedToday,
      continuous: _signedToday ? _continuous : _continuous,
      nextReward: 10 + ((_continuous + (_signedToday ? 0 : 1)) ~/ 3) * 5,
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
    if (_signedToday) {
      throw const ApiException(code: 42900, message: '今天已经签过到了');
    }
    _signedToday = true;
    _continuous += 1;
    final reward = 10 + (_continuous ~/ 3) * 5;
    _balance += reward;
    _logs.insert(
      0,
      YouzhuLog(
        id: _nextLogId++,
        bizType: 2,
        amount: reward,
        balanceAfter: _balance,
        remark: '第 $_continuous 天连续签到',
        createdAt: DateTime.now(),
      ),
    );
    return SignInResult(
      reward: reward,
      continuous: _continuous,
      balance: _balance,
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
    _balance += seed.$6;
    _logs.insert(
      0,
      YouzhuLog(
        id: _nextLogId++,
        bizType: 1,
        amount: seed.$6,
        balanceAfter: _balance,
        remark: '完成任务「${seed.$2}」',
        createdAt: DateTime.now(),
      ),
    );
    return ClaimResult(reward: seed.$6, balance: _balance);
  }

  @override
  Future<YouzhuAccount> fetchAccount() async {
    await Future<void>.delayed(const Duration(milliseconds: 350));
    return YouzhuAccount(balance: _balance, signedToday: _signedToday);
  }

  @override
  Future<List<YouzhuLog>> fetchLogs({
    YouzhuBizType bizType = YouzhuBizType.all,
    int page = 1,
    int size = 20,
  }) async {
    await Future<void>.delayed(const Duration(milliseconds: 400));
    final filtered = bizType == YouzhuBizType.all
        ? _logs
        : _logs.where((l) => l.bizType == bizType.value).toList();
    final start = ((page - 1) * size).clamp(0, filtered.length);
    final end = (start + size).clamp(0, filtered.length);
    return filtered.sublist(start, end);
  }
}

final growthRepositoryProvider = Provider<GrowthRepository>((ref) {
  if (AppConfig.useMock) return GrowthRepositoryMock();
  return GrowthRepositoryHttp(ref.watch(dioProvider));
});
