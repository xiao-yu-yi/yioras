import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yiora/core/network/api_exception.dart';
import 'package:yiora/features/search/controller/search_controller.dart';
import 'package:yiora/features/search/data/search_repository.dart';

/// 可编程假仓库：可注入延迟与失败，记录请求
class _FakeSearchRepository implements SearchRepository {
  final List<({SearchType type, String kw, int page})> calls = [];
  bool fail = false;

  /// 每次请求的可选延迟（模拟慢请求，测竞态丢弃）
  Duration delay = Duration.zero;

  @override
  Future<SearchResultPage> search({
    required SearchType type,
    required String kw,
    int page = 1,
    int size = 20,
  }) async {
    calls.add((type: type, kw: kw, page: page));
    if (delay > Duration.zero) {
      await Future<void>.delayed(delay);
    }
    if (fail) {
      throw const ApiException(code: 500, message: '搜索失败');
    }
    return SearchResultPage(
      posts: type == SearchType.post
          ? [SearchPostItem(id: page * 10, title: '$kw 的结果 p$page')]
          : const [],
      users: type == SearchType.user
          ? [SearchUserItem(id: page, nickname: '$kw 用户')]
          : const [],
      hasMore: page < 2,
    );
  }
}

ProviderContainer _container(SearchRepository repo) {
  final container = ProviderContainer(
    overrides: [searchRepositoryProvider.overrideWithValue(repo)],
  );
  addTearDown(container.dispose);
  // autoDispose：挂常驻监听防止测试中的异步间隙触发释放
  container.listen(searchControllerProvider, (_, _) {});
  return container;
}

void main() {
  test('空关键词回 idle，不发请求', () async {
    final repo = _FakeSearchRepository();
    final container = _container(repo);

    await container
        .read(searchControllerProvider.notifier)
        .search('   ');

    expect(container.read(searchControllerProvider), isA<SearchIdle>());
    expect(repo.calls, isEmpty);
  });

  test('搜索成功进入 data 态并携带结果', () async {
    final repo = _FakeSearchRepository();
    final container = _container(repo);

    await container.read(searchControllerProvider.notifier).search('flutter');

    final state = container.read(searchControllerProvider);
    expect(state, isA<SearchData>());
    final data = state as SearchData;
    expect(data.kw, 'flutter');
    expect(data.result.posts.single.title, 'flutter 的结果 p1');
    expect(data.hasMore, isTrue);
  });

  test('切类型沿用关键词重新搜索', () async {
    final repo = _FakeSearchRepository();
    final container = _container(repo);
    final controller = container.read(searchControllerProvider.notifier);

    await controller.search('yiora');
    await controller.changeType(SearchType.user);

    expect(repo.calls, [
      (type: SearchType.post, kw: 'yiora', page: 1),
      (type: SearchType.user, kw: 'yiora', page: 1),
    ]);
    final data = container.read(searchControllerProvider) as SearchData;
    expect(data.type, SearchType.user);
    expect(data.result.users.single.nickname, 'yiora 用户');
  });

  test('分页拼接且末页收口', () async {
    final repo = _FakeSearchRepository();
    final container = _container(repo);
    final controller = container.read(searchControllerProvider.notifier);

    await controller.search('go');
    await controller.loadMore();

    final data = container.read(searchControllerProvider) as SearchData;
    expect(data.result.posts.length, 2);
    expect(data.page, 2);
    expect(data.hasMore, isFalse, reason: '假仓库只有两页');
  });

  test('慢请求被新请求取代时丢弃旧结果（防串扰）', () async {
    final repo = _FakeSearchRepository()
      ..delay = const Duration(milliseconds: 100);
    final container = _container(repo);
    final controller = container.read(searchControllerProvider.notifier);

    // 旧词慢请求未返回时发起新词搜索
    final slow = controller.search('old');
    await Future<void>.delayed(const Duration(milliseconds: 10));
    repo.delay = Duration.zero;
    await controller.search('new');
    await slow;

    final data = container.read(searchControllerProvider) as SearchData;
    expect(data.kw, 'new', reason: '旧请求结果不得覆盖新请求');
  });

  test('搜索失败进入 error 态，可重试恢复', () async {
    final repo = _FakeSearchRepository()..fail = true;
    final container = _container(repo);
    final controller = container.read(searchControllerProvider.notifier);

    await controller.search('boom');
    expect(container.read(searchControllerProvider), isA<SearchError>());

    repo.fail = false;
    await controller.retry();
    expect(container.read(searchControllerProvider), isA<SearchData>());
  });
}
