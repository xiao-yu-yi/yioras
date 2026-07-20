import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/cache/key_value_cache.dart';
import '../../../core/network/api_exception.dart';
import '../data/feed_repository.dart';
import '../model/post.dart';

/// 推荐流已加载数据 + 分页状态。
/// 首屏 loading/error 由外层 AsyncValue 表达，本模型只描述「有数据之后」的状态。
class FeedState {
  const FeedState({
    required this.posts,
    required this.nextCursor,
    required this.hasMore,
    this.loadingMore = false,
    this.loadMoreError,
  });

  final List<Post> posts;
  final String? nextCursor;
  final bool hasMore;

  /// 上拉加载中（底部转圈）
  final bool loadingMore;

  /// 加载更多失败的文案（底部点击重试）
  final String? loadMoreError;

  FeedState copyWith({
    List<Post>? posts,
    String? nextCursor,
    bool? hasMore,
    bool? loadingMore,
    String? Function()? loadMoreError,
  }) {
    return FeedState(
      posts: posts ?? this.posts,
      nextCursor: nextCursor ?? this.nextCursor,
      hasMore: hasMore ?? this.hasMore,
      loadingMore: loadingMore ?? this.loadingMore,
      loadMoreError: loadMoreError != null
          ? loadMoreError()
          : this.loadMoreError,
    );
  }
}

/// 推荐流控制器：首屏加载 / 下拉刷新 / 上拉分页。
///
/// SWR 缓存策略（文档 3.2「列表数据 SWR 式缓存」）：
/// 冷启动命中本地缓存则先渲染缓存，同时后台刷新替换并回写；
/// 后台刷新失败静默保留缓存（用户可下拉刷新感知错误）。
class FeedController extends AsyncNotifier<FeedState> {
  static const int pageSize = 20;
  static const cacheKey = 'feed_recommend_v1';

  /// 缓存兜底时效：超过后视为无缓存走全量 loading
  static const cacheMaxAge = Duration(hours: 24);

  FeedRepository get _repo => ref.read(feedRepositoryProvider);

  KeyValueCache get _cache => ref.read(cacheProvider);

  @override
  Future<FeedState> build() async {
    final cached = _readCache();
    if (cached != null) {
      // 先出缓存，后台刷新（stale-while-revalidate）
      unawaited(_revalidate());
      return cached;
    }
    final page = await _fetchAndCacheFirstPage();
    return _stateOf(page);
  }

  FeedState _stateOf(PostPage page) => FeedState(
    posts: page.list,
    nextCursor: page.nextCursor,
    hasMore: page.hasMore,
  );

  FeedState? _readCache() {
    final json = _cache.readJson(cacheKey, maxAge: cacheMaxAge);
    if (json == null) return null;
    try {
      final page = PostPage.fromJson(json);
      if (page.list.isEmpty) return null;
      return _stateOf(page);
    } catch (_) {
      // 缓存结构升级或损坏：按无缓存处理
      return null;
    }
  }

  Future<PostPage> _fetchAndCacheFirstPage() async {
    final page = await _repo.fetchRecommend(size: pageSize);
    await _cache.writeJson(cacheKey, {
      'list': [for (final post in page.list) post.toJson()],
      'nextCursor': page.nextCursor,
      'hasMore': page.hasMore,
    });
    return page;
  }

  Future<void> _revalidate() async {
    try {
      final page = await _fetchAndCacheFirstPage();
      if (ref.mounted) state = AsyncData(_stateOf(page));
    } on ApiException {
      // 静默：保留缓存内容
    }
  }

  /// 下拉刷新：重拉第一页。已有数据时失败不清列表，把异常抛给页面提示。
  Future<void> refresh() async {
    final page = await _fetchAndCacheFirstPage();
    state = AsyncData(_stateOf(page));
  }

  /// 首屏失败后的重试：走 loading 态重新执行 build
  Future<void> retryFirstLoad() async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(build);
  }

  /// 上拉加载下一页；并发调用与到底后调用直接忽略
  Future<void> loadMore() async {
    final current = state.value;
    if (current == null || current.loadingMore || !current.hasMore) return;

    state = AsyncData(
      current.copyWith(loadingMore: true, loadMoreError: () => null),
    );
    try {
      final page = await _repo.fetchRecommend(
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
}

final feedControllerProvider = AsyncNotifierProvider<FeedController, FeedState>(
  FeedController.new,
);
