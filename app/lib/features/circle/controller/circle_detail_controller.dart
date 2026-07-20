import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_exception.dart';
import '../../feed/model/post.dart';
import '../data/circle_repository.dart';
import '../model/circle.dart';
import 'circle_list_controller.dart';

/// 圈子详情页状态：圈子信息 + 圈内帖子流（最新）分页。
class CircleDetailState {
  const CircleDetailState({
    required this.circle,
    required this.posts,
    required this.nextCursor,
    required this.hasMore,
    this.loadingMore = false,
    this.loadMoreError,
    this.joinBusy = false,
  });

  final Circle circle;
  final List<Post> posts;
  final String? nextCursor;
  final bool hasMore;
  final bool loadingMore;
  final String? loadMoreError;

  /// 加入/退出请求进行中（按钮转圈防重复提交）
  final bool joinBusy;

  CircleDetailState copyWith({
    Circle? circle,
    List<Post>? posts,
    String? nextCursor,
    bool? hasMore,
    bool? loadingMore,
    String? Function()? loadMoreError,
    bool? joinBusy,
  }) {
    return CircleDetailState(
      circle: circle ?? this.circle,
      posts: posts ?? this.posts,
      nextCursor: nextCursor ?? this.nextCursor,
      hasMore: hasMore ?? this.hasMore,
      loadingMore: loadingMore ?? this.loadingMore,
      loadMoreError: loadMoreError != null
          ? loadMoreError()
          : this.loadMoreError,
      joinBusy: joinBusy ?? this.joinBusy,
    );
  }
}

/// 圈子详情控制器（family：circleId）。
class CircleDetailController extends AsyncNotifier<CircleDetailState> {
  CircleDetailController(this.circleId);

  /// family 参数：圈子 ID
  final int circleId;

  static const int pageSize = 20;

  CircleRepository get _repo => ref.read(circleRepositoryProvider);

  @override
  Future<CircleDetailState> build() async {
    // 顺序拉取，保证失败时向上抛原始 ApiException（.wait 会包成 ParallelWaitError）
    final circle = await _repo.fetchCircleDetail(circleId);
    final page = await _repo.fetchCirclePosts(circleId, size: pageSize);
    return CircleDetailState(
      circle: circle,
      posts: page.list,
      nextCursor: page.nextCursor,
      hasMore: page.hasMore,
    );
  }

  Future<void> refresh() async {
    final circle = await _repo.fetchCircleDetail(circleId);
    final page = await _repo.fetchCirclePosts(circleId, size: pageSize);
    state = AsyncData(
      CircleDetailState(
        circle: circle,
        posts: page.list,
        nextCursor: page.nextCursor,
        hasMore: page.hasMore,
      ),
    );
  }

  Future<void> retryFirstLoad() async {
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
      final page = await _repo.fetchCirclePosts(
        circleId,
        cursor: current.nextCursor,
        size: pageSize,
      );
      state = AsyncData(
        current.copyWith(
          posts: [...current.posts, ...page.list],
          nextCursor: page.nextCursor,
          hasMore: page.hasMore,
          loadingMore: false,
        ),
      );
    } on ApiException catch (e) {
      state = AsyncData(
        current.copyWith(loadingMore: false, loadMoreError: () => e.message),
      );
    }
  }

  /// 加入/退出圈子；失败抛 [ApiException] 由页面提示。
  /// 成功后同步刷新发现页列表，保持两处 joined 状态一致。
  Future<void> toggleJoin() async {
    final current = state.value;
    if (current == null || current.joinBusy) return;

    final joined = current.circle.joined;
    state = AsyncData(current.copyWith(joinBusy: true));
    try {
      if (joined) {
        await _repo.quitCircle(circleId);
      } else {
        await _repo.joinCircle(circleId);
      }
      final latest = state.value ?? current;
      state = AsyncData(
        latest.copyWith(
          joinBusy: false,
          circle: latest.circle.copyWith(
            joined: !joined,
            memberCount: latest.circle.memberCount + (joined ? -1 : 1),
          ),
        ),
      );
      ref.invalidate(circleListControllerProvider);
    } on ApiException {
      final latest = state.value ?? current;
      state = AsyncData(latest.copyWith(joinBusy: false));
      rethrow;
    }
  }
}

final circleDetailControllerProvider = AsyncNotifierProvider.family
    .autoDispose<CircleDetailController, CircleDetailState, int>(
      CircleDetailController.new,
    );
