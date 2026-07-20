import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_exception.dart';
import '../data/growth_repository.dart';
import '../model/growth_models.dart';

/// 任务中心控制器：签到与领奖成功后原地更新状态（不整页重拉）。
class TaskCenterController extends AsyncNotifier<TaskCenter> {
  GrowthRepository get _repo => ref.read(growthRepositoryProvider);

  @override
  Future<TaskCenter> build() => _repo.fetchTaskCenter();

  Future<void> retryFirstLoad() async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(build);
  }

  /// 签到；返回奖励结果供页面提示。失败抛 [ApiException]。
  Future<SignInResult> signIn() async {
    final result = await _repo.signIn();
    final current = state.value;
    if (current != null) {
      state = AsyncData(
        current.copyWith(
          signedToday: true,
          continuous: result.continuous,
          tasks: [
            for (final t in current.tasks)
              // 签到类任务同步置可领取/完成态（服务端为准，这里乐观推进进度）
              if (t.action == 'sign_in' && t.status == 0)
                t.copyWith(progress: t.target, status: 1)
              else
                t,
          ],
        ),
      );
    }
    return result;
  }

  /// 领取任务奖励；成功置已领取。失败抛 [ApiException]。
  Future<ClaimResult> claim(int taskId) async {
    final result = await _repo.claimTask(taskId);
    final current = state.value;
    if (current != null) {
      state = AsyncData(
        current.copyWith(
          tasks: [
            for (final t in current.tasks)
              if (t.id == taskId) t.copyWith(status: 2) else t,
          ],
        ),
      );
    }
    return result;
  }
}

final taskCenterControllerProvider =
    AsyncNotifierProvider.autoDispose<TaskCenterController, TaskCenter>(
      TaskCenterController.new,
    );

/// 忧珠流水列表状态（类型筛选 + 页码分页）
class YouzhuLogsState {
  const YouzhuLogsState({
    required this.logs,
    required this.bizType,
    required this.page,
    required this.hasMore,
    this.loadingMore = false,
    this.loadMoreError,
  });

  final List<YouzhuLog> logs;
  final YouzhuBizType bizType;
  final int page;
  final bool hasMore;
  final bool loadingMore;
  final String? loadMoreError;

  YouzhuLogsState copyWith({
    List<YouzhuLog>? logs,
    YouzhuBizType? bizType,
    int? page,
    bool? hasMore,
    bool? loadingMore,
    String? Function()? loadMoreError,
  }) {
    return YouzhuLogsState(
      logs: logs ?? this.logs,
      bizType: bizType ?? this.bizType,
      page: page ?? this.page,
      hasMore: hasMore ?? this.hasMore,
      loadingMore: loadingMore ?? this.loadingMore,
      loadMoreError: loadMoreError != null
          ? loadMoreError()
          : this.loadMoreError,
    );
  }
}

/// 忧珠流水控制器：切类型回第一页。
class YouzhuLogsController extends AsyncNotifier<YouzhuLogsState> {
  static const int pageSize = 20;

  GrowthRepository get _repo => ref.read(growthRepositoryProvider);

  YouzhuBizType _bizType = YouzhuBizType.all;

  @override
  Future<YouzhuLogsState> build() async {
    final logs = await _repo.fetchLogs(
      bizType: _bizType,
      page: 1,
      size: pageSize,
    );
    return YouzhuLogsState(
      logs: logs,
      bizType: _bizType,
      page: 1,
      hasMore: logs.length >= pageSize,
    );
  }

  Future<void> retryFirstLoad() async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(build);
  }

  Future<void> changeBizType(YouzhuBizType bizType) async {
    if (bizType == _bizType) return;
    _bizType = bizType;
    state = const AsyncLoading();
    state = await AsyncValue.guard(build);
  }

  Future<void> loadMore() async {
    final current = state.value;
    if (current == null || current.loadingMore || !current.hasMore) return;

    state = AsyncData(
      current.copyWith(loadingMore: true, loadMoreError: () => null),
    );
    try {
      final next = await _repo.fetchLogs(
        bizType: current.bizType,
        page: current.page + 1,
        size: pageSize,
      );
      state = AsyncData(
        current.copyWith(
          logs: [...current.logs, ...next],
          page: current.page + 1,
          hasMore: next.length >= pageSize,
          loadingMore: false,
        ),
      );
    } on ApiException catch (e) {
      state = AsyncData(
        current.copyWith(loadingMore: false, loadMoreError: () => e.message),
      );
    }
  }
}

final youzhuLogsControllerProvider =
    AsyncNotifierProvider.autoDispose<YouzhuLogsController, YouzhuLogsState>(
      YouzhuLogsController.new,
    );

/// 忧珠账户数据源（资产页头卡）
final youzhuAccountProvider = FutureProvider.autoDispose<YouzhuAccount>((ref) {
  return ref.watch(growthRepositoryProvider).fetchAccount();
});
