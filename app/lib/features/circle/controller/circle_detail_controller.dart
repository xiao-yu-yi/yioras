import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_exception.dart';
import '../../feed/model/post.dart';
import '../data/circle_repository.dart';
import '../model/circle.dart';
import 'circle_list_controller.dart';

/// 圈子详情页状态：圈子信息 + 圈内帖子流（最新/最热双 Tab）分页。
class CircleDetailState {
  const CircleDetailState({
    required this.circle,
    required this.posts,
    required this.nextCursor,
    required this.hasMore,
    this.sort = CirclePostSort.newest,
    this.sortSwitching = false,
    this.loadingMore = false,
    this.loadMoreError,
    this.joinBusy = false,
  });

  final Circle circle;
  final List<Post> posts;
  final String? nextCursor;
  final bool hasMore;

  /// 圈内流当前排序 Tab
  final CirclePostSort sort;

  /// 切 Tab 重拉帖子中（帖子区局部 loading，头部信息保留）
  final bool sortSwitching;
  final bool loadingMore;
  final String? loadMoreError;

  /// 加入/退出请求进行中（按钮转圈防重复提交）
  final bool joinBusy;

  CircleDetailState copyWith({
    Circle? circle,
    List<Post>? posts,
    String? nextCursor,
    bool? hasMore,
    CirclePostSort? sort,
    bool? sortSwitching,
    bool? loadingMore,
    String? Function()? loadMoreError,
    bool? joinBusy,
  }) {
    return CircleDetailState(
      circle: circle ?? this.circle,
      posts: posts ?? this.posts,
      nextCursor: nextCursor ?? this.nextCursor,
      hasMore: hasMore ?? this.hasMore,
      sort: sort ?? this.sort,
      sortSwitching: sortSwitching ?? this.sortSwitching,
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

  /// 当前排序（build 重入时保持）
  CirclePostSort _sort = CirclePostSort.newest;

  @override
  Future<CircleDetailState> build() async {
    // 顺序拉取，保证失败时向上抛原始 ApiException（.wait 会包成 ParallelWaitError）
    final circle = await _repo.fetchCircleDetail(circleId);
    final page = await _repo.fetchCirclePosts(
      circleId,
      sort: _sort,
      size: pageSize,
    );
    return CircleDetailState(
      circle: circle,
      posts: page.list,
      nextCursor: page.nextCursor,
      hasMore: page.hasMore,
      sort: _sort,
    );
  }

  Future<void> refresh() async {
    final circle = await _repo.fetchCircleDetail(circleId);
    final page = await _repo.fetchCirclePosts(
      circleId,
      sort: _sort,
      size: pageSize,
    );
    state = AsyncData(
      CircleDetailState(
        circle: circle,
        posts: page.list,
        nextCursor: page.nextCursor,
        hasMore: page.hasMore,
        sort: _sort,
      ),
    );
  }

  Future<void> retryFirstLoad() async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(build);
  }

  /// 切换圈内流排序 Tab：保留头部信息，仅帖子区重拉。
  /// 失败回滚到原 Tab 并抛 [ApiException] 由页面提示。
  Future<void> changeSort(CirclePostSort sort) async {
    final current = state.value;
    if (current == null || current.sortSwitching || sort == current.sort) {
      return;
    }

    _sort = sort;
    state = AsyncData(
      current.copyWith(
        sort: sort,
        sortSwitching: true,
        loadMoreError: () => null,
      ),
    );
    try {
      final page = await _repo.fetchCirclePosts(
        circleId,
        sort: sort,
        size: pageSize,
      );
      final latest = state.value ?? current;
      state = AsyncData(
        latest.copyWith(
          posts: page.list,
          nextCursor: page.nextCursor,
          hasMore: page.hasMore,
          sortSwitching: false,
        ),
      );
    } on ApiException {
      _sort = current.sort;
      final latest = state.value ?? current;
      state = AsyncData(
        latest.copyWith(sort: current.sort, sortSwitching: false),
      );
      rethrow;
    }
  }

  Future<void> loadMore() async {
    final current = state.value;
    if (current == null ||
        current.loadingMore ||
        current.sortSwitching ||
        !current.hasMore) {
      return;
    }

    state = AsyncData(
      current.copyWith(loadingMore: true, loadMoreError: () => null),
    );
    try {
      final page = await _repo.fetchCirclePosts(
        circleId,
        sort: current.sort,
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
