import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_exception.dart';
import '../../feed/model/post.dart';
import '../data/topic_repository.dart';

/// 话题聚合页状态：话题信息 + 帖子流（最热/最新）页码分页。
class TopicPostsState {
  const TopicPostsState({
    required this.topic,
    required this.posts,
    required this.sort,
    required this.page,
    required this.hasMore,
    this.sortSwitching = false,
    this.loadingMore = false,
    this.loadMoreError,
  });

  final TopicInfo topic;
  final List<Post> posts;
  final TopicPostSort sort;
  final int page;
  final bool hasMore;

  /// 切排序重拉中（帖子区局部 loading）
  final bool sortSwitching;
  final bool loadingMore;
  final String? loadMoreError;

  TopicPostsState copyWith({
    TopicInfo? topic,
    List<Post>? posts,
    TopicPostSort? sort,
    int? page,
    bool? hasMore,
    bool? sortSwitching,
    bool? loadingMore,
    String? Function()? loadMoreError,
  }) {
    return TopicPostsState(
      topic: topic ?? this.topic,
      posts: posts ?? this.posts,
      sort: sort ?? this.sort,
      page: page ?? this.page,
      hasMore: hasMore ?? this.hasMore,
      sortSwitching: sortSwitching ?? this.sortSwitching,
      loadingMore: loadingMore ?? this.loadingMore,
      loadMoreError: loadMoreError != null
          ? loadMoreError()
          : this.loadMoreError,
    );
  }
}

/// 话题聚合控制器（family：话题 ID）。默认最热（对齐服务端默认值）。
class TopicPostsController extends AsyncNotifier<TopicPostsState> {
  TopicPostsController(this.topicId);

  final int topicId;

  static const int pageSize = 20;

  TopicRepository get _repo => ref.read(topicRepositoryProvider);

  TopicPostSort _sort = TopicPostSort.hot;

  @override
  Future<TopicPostsState> build() async {
    final result = await _repo.fetchTopicPosts(
      topicId,
      sort: _sort,
      page: 1,
      size: pageSize,
    );
    return TopicPostsState(
      topic: result.topic,
      posts: result.posts,
      sort: _sort,
      page: 1,
      hasMore: result.hasMore,
    );
  }

  Future<void> retryFirstLoad() async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(build);
  }

  Future<void> refresh() async {
    final result = await _repo.fetchTopicPosts(
      topicId,
      sort: _sort,
      page: 1,
      size: pageSize,
    );
    state = AsyncData(
      TopicPostsState(
        topic: result.topic,
        posts: result.posts,
        sort: _sort,
        page: 1,
        hasMore: result.hasMore,
      ),
    );
  }

  /// 切换排序：保留头部，仅帖子区重拉；失败回滚原排序并抛 [ApiException]。
  Future<void> changeSort(TopicPostSort sort) async {
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
      final result = await _repo.fetchTopicPosts(
        topicId,
        sort: sort,
        page: 1,
        size: pageSize,
      );
      final latest = state.value ?? current;
      state = AsyncData(
        latest.copyWith(
          posts: result.posts,
          page: 1,
          hasMore: result.hasMore,
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
      final result = await _repo.fetchTopicPosts(
        topicId,
        sort: current.sort,
        page: current.page + 1,
        size: pageSize,
      );
      state = AsyncData(
        current.copyWith(
          posts: [...current.posts, ...result.posts],
          page: current.page + 1,
          hasMore: result.hasMore,
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

final topicPostsControllerProvider = AsyncNotifierProvider.family
    .autoDispose<TopicPostsController, TopicPostsState, int>(
      TopicPostsController.new,
    );
