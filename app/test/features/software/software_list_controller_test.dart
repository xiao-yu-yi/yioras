import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yiora/core/network/api_exception.dart';
import 'package:yiora/features/software/controller/software_list_controller.dart';
import 'package:yiora/features/software/data/software_repository.dart';
import 'package:yiora/features/software/model/software.dart';

/// 可编程假仓库：记录筛选参数并按页下发数据
class _FakeSoftwareRepository implements SoftwareRepository {
  final List<({int type, int categoryId, SoftwareSort sort, int page})> calls =
      [];
  bool failList = false;

  /// 总条数（用于分页 hasMore 判断）
  int total = 45;

  static SoftwareItem _item(int id) => SoftwareItem(
    id: id,
    name: '软件$id',
    createdAt: DateTime(2026, 7, 1),
  );

  @override
  Future<SoftwarePage> fetchList({
    int type = 0,
    int categoryId = 0,
    SoftwareSort sort = SoftwareSort.newest,
    int page = 1,
    int size = 20,
  }) async {
    calls.add((type: type, categoryId: categoryId, sort: sort, page: page));
    if (failList) {
      throw const ApiException(code: 500, message: '加载失败');
    }
    final start = (page - 1) * size;
    final end = (start + size).clamp(0, total);
    return SoftwarePage(
      list: [for (var i = start; i < end; i++) _item(i + 1)],
      hasMore: end < total,
    );
  }

  @override
  Future<SoftwareDetail> fetchDetail(int id) => throw UnimplementedError();

  @override
  Future<SoftwareDownload> resolveDownload(int id, {int versionId = 0}) =>
      throw UnimplementedError();

  @override
  Future<List<SoftwareCategory>> fetchCategories(int type) async => const [];
}

ProviderContainer _container(SoftwareRepository repo) {
  final container = ProviderContainer(
    overrides: [softwareRepositoryProvider.overrideWithValue(repo)],
  );
  addTearDown(container.dispose);
  return container;
}

void main() {
  test('首屏默认：全部类型 + 最新排序 + 第一页', () async {
    final repo = _FakeSoftwareRepository();
    final container = _container(repo);

    final state = await container.read(softwareListControllerProvider.future);

    expect(state.items.length, 20);
    expect(state.hasMore, isTrue);
    expect(repo.calls.single, (
      type: 0,
      categoryId: 0,
      sort: SoftwareSort.newest,
      page: 1,
    ));
  });

  test('上拉加载第二页并拼接', () async {
    final repo = _FakeSoftwareRepository();
    final container = _container(repo);
    await container.read(softwareListControllerProvider.future);

    await container.read(softwareListControllerProvider.notifier).loadMore();

    final state = container.read(softwareListControllerProvider).value!;
    expect(state.items.length, 40);
    expect(state.page, 2);
    expect(state.hasMore, isTrue);

    // 末页后 hasMore 收口
    await container.read(softwareListControllerProvider.notifier).loadMore();
    final last = container.read(softwareListControllerProvider).value!;
    expect(last.items.length, 45);
    expect(last.hasMore, isFalse);
  });

  test('切类型重置到第一页且分类清零', () async {
    final repo = _FakeSoftwareRepository();
    final container = _container(repo);
    await container.read(softwareListControllerProvider.future);

    // 先选一个分类，再切类型
    await container
        .read(softwareListControllerProvider.notifier)
        .applyFilter(categoryId: 3);
    await container
        .read(softwareListControllerProvider.notifier)
        .applyFilter(type: 2);

    final state = container.read(softwareListControllerProvider).value!;
    expect(state.type, 2);
    expect(state.categoryId, 0, reason: '切类型后二级分类应清零');
    expect(state.page, 1);
    expect(repo.calls.last, (
      type: 2,
      categoryId: 0,
      sort: SoftwareSort.newest,
      page: 1,
    ));
  });

  test('分页失败：保留旧列表并给出可重试错误', () async {
    final repo = _FakeSoftwareRepository();
    final container = _container(repo);
    await container.read(softwareListControllerProvider.future);

    repo.failList = true;
    await container.read(softwareListControllerProvider.notifier).loadMore();

    final state = container.read(softwareListControllerProvider).value!;
    expect(state.items.length, 20);
    expect(state.loadMoreError, '加载失败');
    expect(state.loadingMore, isFalse);
  });
}
