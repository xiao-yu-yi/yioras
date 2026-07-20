import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_exception.dart';
import '../data/software_repository.dart';
import '../model/software.dart';

/// 软件库列表状态：类型/分类/排序筛选 + 页码分页。
class SoftwareListState {
  const SoftwareListState({
    required this.items,
    required this.type,
    required this.categoryId,
    required this.sort,
    required this.page,
    required this.hasMore,
    this.loadingMore = false,
    this.loadMoreError,
  });

  final List<SoftwareItem> items;

  /// 0 全部 / 1 应用 / 2 游戏
  final int type;

  /// 0 全部分类
  final int categoryId;
  final SoftwareSort sort;
  final int page;
  final bool hasMore;
  final bool loadingMore;
  final String? loadMoreError;

  SoftwareListState copyWith({
    List<SoftwareItem>? items,
    int? type,
    int? categoryId,
    SoftwareSort? sort,
    int? page,
    bool? hasMore,
    bool? loadingMore,
    String? Function()? loadMoreError,
  }) {
    return SoftwareListState(
      items: items ?? this.items,
      type: type ?? this.type,
      categoryId: categoryId ?? this.categoryId,
      sort: sort ?? this.sort,
      page: page ?? this.page,
      hasMore: hasMore ?? this.hasMore,
      loadingMore: loadingMore ?? this.loadingMore,
      loadMoreError: loadMoreError != null
          ? loadMoreError()
          : this.loadMoreError,
    );
  }
}

/// 软件库列表控制器：切筛选重置到第一页；上拉加载下一页。
class SoftwareListController extends AsyncNotifier<SoftwareListState> {
  static const int pageSize = 20;

  SoftwareRepository get _repo => ref.read(softwareRepositoryProvider);

  // 当前筛选（build 重入时保持）
  int _type = 0;
  int _categoryId = 0;
  SoftwareSort _sort = SoftwareSort.newest;

  @override
  Future<SoftwareListState> build() async {
    final page = await _repo.fetchList(
      type: _type,
      categoryId: _categoryId,
      sort: _sort,
      page: 1,
      size: pageSize,
    );
    return SoftwareListState(
      items: page.list,
      type: _type,
      categoryId: _categoryId,
      sort: _sort,
      page: 1,
      hasMore: page.hasMore,
    );
  }

  Future<void> retryFirstLoad() async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(build);
  }

  Future<void> refresh() async {
    final page = await _repo.fetchList(
      type: _type,
      categoryId: _categoryId,
      sort: _sort,
      page: 1,
      size: pageSize,
    );
    state = AsyncData(
      SoftwareListState(
        items: page.list,
        type: _type,
        categoryId: _categoryId,
        sort: _sort,
        page: 1,
        hasMore: page.hasMore,
      ),
    );
  }

  /// 切换筛选（类型/分类/排序任一变化）：回到第一页并重新加载。
  /// 切类型时分类自动清零（二级分类跟随类型）。
  Future<void> applyFilter({int? type, int? categoryId, SoftwareSort? sort}) async {
    final nextType = type ?? _type;
    _categoryId = type != null && type != _type ? 0 : (categoryId ?? _categoryId);
    _type = nextType;
    _sort = sort ?? _sort;
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
      final next = await _repo.fetchList(
        type: current.type,
        categoryId: current.categoryId,
        sort: current.sort,
        page: current.page + 1,
        size: pageSize,
      );
      state = AsyncData(
        current.copyWith(
          items: [...current.items, ...next.list],
          page: current.page + 1,
          hasMore: next.hasMore,
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

final softwareListControllerProvider =
    AsyncNotifierProvider<SoftwareListController, SoftwareListState>(
      SoftwareListController.new,
    );

/// 列表筛选用分类数据源（type: 0全部 1应用 2游戏）
final softwareCategoryListProvider = FutureProvider.autoDispose
    .family<List<SoftwareCategory>, int>((ref, type) {
      return ref.watch(softwareRepositoryProvider).fetchCategories(type);
    });
