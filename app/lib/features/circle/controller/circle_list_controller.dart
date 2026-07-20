import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/circle_repository.dart';
import '../model/circle.dart';

/// 发现圈子页状态：当前排序 + 圈子列表。
class CircleListState {
  const CircleListState({required this.sort, required this.circles});

  final CircleSort sort;
  final List<Circle> circles;
}

/// 发现圈子控制器：加载列表 / 切换排序 / 刷新。
class CircleListController extends AsyncNotifier<CircleListState> {
  CircleRepository get _repo => ref.read(circleRepositoryProvider);

  /// 切排序时沿用上次选择（异常重建后回到默认最热）
  CircleSort _sort = CircleSort.hot;

  @override
  Future<CircleListState> build() async {
    final circles = await _repo.fetchCircles(sort: _sort);
    return CircleListState(sort: _sort, circles: circles);
  }

  /// 切换排序：走 loading 态重拉（列表通常很短，无需保旧数据）
  Future<void> changeSort(CircleSort sort) async {
    if (_sort == sort && state.hasValue) return;
    _sort = sort;
    state = const AsyncLoading();
    state = await AsyncValue.guard(build);
  }

  Future<void> refresh() async {
    final circles = await _repo.fetchCircles(sort: _sort);
    state = AsyncData(CircleListState(sort: _sort, circles: circles));
  }

  Future<void> retry() async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(build);
  }
}

final circleListControllerProvider =
    AsyncNotifierProvider<CircleListController, CircleListState>(
      CircleListController.new,
    );
