import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_exception.dart';
import '../data/search_repository.dart';

/// 搜索页状态机。
///
/// - idle：未输入关键词（展示引导）
/// - loading：首屏搜索中
/// - data：结果就绪（含空结果与分页态）
/// - error：首屏失败（可重试）
sealed class SearchState {
  const SearchState();
}

class SearchIdle extends SearchState {
  const SearchIdle();
}

class SearchLoading extends SearchState {
  const SearchLoading();
}

class SearchError extends SearchState {
  const SearchError(this.message);

  final String message;
}

class SearchData extends SearchState {
  const SearchData({
    required this.kw,
    required this.type,
    required this.result,
    required this.page,
    required this.hasMore,
    this.loadingMore = false,
    this.loadMoreError,
  });

  final String kw;
  final SearchType type;
  final SearchResultPage result;
  final int page;
  final bool hasMore;
  final bool loadingMore;
  final String? loadMoreError;

  bool get isEmpty => result.countOf(type) == 0;

  SearchData copyWith({
    SearchResultPage? result,
    int? page,
    bool? hasMore,
    bool? loadingMore,
    String? Function()? loadMoreError,
  }) {
    return SearchData(
      kw: kw,
      type: type,
      result: result ?? this.result,
      page: page ?? this.page,
      hasMore: hasMore ?? this.hasMore,
      loadingMore: loadingMore ?? this.loadingMore,
      loadMoreError: loadMoreError != null
          ? loadMoreError()
          : this.loadMoreError,
    );
  }
}

/// 全局搜索控制器：五类单选 + 防抖由页面控制，这里保证请求串行一致性。
/// 命名避开 Material 的 SearchController。
class GlobalSearchController extends Notifier<SearchState> {
  static const int pageSize = 20;

  SearchRepository get _repo => ref.read(searchRepositoryProvider);

  /// 当前生效的查询（防串扰：旧请求返回时若已换词/换类，丢弃结果）
  String _kw = '';
  SearchType _type = SearchType.post;
  int _seq = 0;

  @override
  SearchState build() => const SearchIdle();

  SearchType get currentType => _type;

  /// 发起新搜索（换词/换类共用）。空词回 idle。
  Future<void> search(String kw, {SearchType? type}) async {
    final keyword = kw.trim();
    _type = type ?? _type;
    _kw = keyword;
    final seq = ++_seq;

    if (keyword.isEmpty) {
      state = const SearchIdle();
      return;
    }

    state = const SearchLoading();
    try {
      final result = await _repo.search(
        type: _type,
        kw: keyword,
        page: 1,
        size: pageSize,
      );
      // 已被更新的查询取代 / 页面已销毁：丢弃结果
      if (seq != _seq || !ref.mounted) return;
      state = SearchData(
        kw: keyword,
        type: _type,
        result: result,
        page: 1,
        hasMore: result.hasMore,
      );
    } on ApiException catch (e) {
      if (seq != _seq || !ref.mounted) return;
      state = SearchError(e.message);
    }
  }

  /// 切换搜索类型：沿用当前关键词重新搜索
  Future<void> changeType(SearchType type) async {
    if (type == _type) return;
    await search(_kw, type: type);
  }

  Future<void> retry() => search(_kw, type: _type);

  Future<void> loadMore() async {
    final current = state;
    if (current is! SearchData || current.loadingMore || !current.hasMore) {
      return;
    }

    final seq = _seq;
    state = current.copyWith(loadingMore: true, loadMoreError: () => null);
    try {
      final next = await _repo.search(
        type: current.type,
        kw: current.kw,
        page: current.page + 1,
        size: pageSize,
      );
      if (seq != _seq || !ref.mounted) return;
      state = current.copyWith(
        result: SearchResultPage(
          posts: [...current.result.posts, ...next.posts],
          users: [...current.result.users, ...next.users],
          circles: [...current.result.circles, ...next.circles],
          topics: [...current.result.topics, ...next.topics],
          software: [...current.result.software, ...next.software],
          hasMore: next.hasMore,
        ),
        page: current.page + 1,
        hasMore: next.hasMore,
        loadingMore: false,
      );
    } on ApiException catch (e) {
      if (seq != _seq || !ref.mounted) return;
      state = current.copyWith(
        loadingMore: false,
        loadMoreError: () => e.message,
      );
    }
  }
}

final searchControllerProvider =
    NotifierProvider.autoDispose<GlobalSearchController, SearchState>(
      GlobalSearchController.new,
    );
