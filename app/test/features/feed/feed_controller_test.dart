import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yiora/core/network/api_exception.dart';
import 'package:yiora/features/feed/controller/feed_controller.dart';
import 'package:yiora/features/feed/data/feed_repository.dart';
import 'package:yiora/features/feed/model/post.dart';

/// 可编程假仓库：按调用次数依次返回脚本化结果
class _FakeFeedRepository implements FeedRepository {
  _FakeFeedRepository(this._script);

  final List<Future<PostPage> Function(String? cursor)> _script;
  int calls = 0;
  final List<String?> receivedCursors = [];

  @override
  Future<PostPage> fetchRecommend({String? cursor, int size = 20}) {
    receivedCursors.add(cursor);
    final step = _script[calls.clamp(0, _script.length - 1)];
    calls++;
    return step(cursor);
  }
}

Post _post(int id) => Post(
  id: id,
  author: const PostAuthor(id: 1, nickname: '测试'),
  content: '内容 $id',
  createdAt: DateTime(2026, 7, 20),
);

PostPage _page(List<int> ids, {String? next}) => PostPage(
  list: ids.map(_post).toList(),
  nextCursor: next,
  hasMore: next != null,
);

ProviderContainer _container(FeedRepository repo) {
  final container = ProviderContainer(
    overrides: [feedRepositoryProvider.overrideWithValue(repo)],
  );
  addTearDown(container.dispose);
  return container;
}

void main() {
  test('首屏加载第一页', () async {
    final repo = _FakeFeedRepository([
      (cursor) async => _page([1, 2, 3], next: '3'),
    ]);
    final container = _container(repo);

    final state = await container.read(feedControllerProvider.future);

    expect(state.posts.map((p) => p.id), [1, 2, 3]);
    expect(state.hasMore, isTrue);
    expect(repo.receivedCursors, [null]);
  });

  test('loadMore 追加下一页并透传游标', () async {
    final repo = _FakeFeedRepository([
      (cursor) async => _page([1, 2], next: '2'),
      (cursor) async => _page([3, 4]),
    ]);
    final container = _container(repo);
    await container.read(feedControllerProvider.future);

    await container.read(feedControllerProvider.notifier).loadMore();

    final state = container.read(feedControllerProvider).value!;
    expect(state.posts.map((p) => p.id), [1, 2, 3, 4]);
    expect(state.hasMore, isFalse);
    expect(repo.receivedCursors, [null, '2']);
  });

  test('到底后 loadMore 不再请求', () async {
    final repo = _FakeFeedRepository([
      (cursor) async => _page([1]),
    ]);
    final container = _container(repo);
    await container.read(feedControllerProvider.future);

    await container.read(feedControllerProvider.notifier).loadMore();

    expect(repo.calls, 1);
  });

  test('loadMore 失败保留已有列表并记录错误', () async {
    final repo = _FakeFeedRepository([
      (cursor) async => _page([1, 2], next: '2'),
      (cursor) async =>
          throw const ApiException(code: -1, message: '网络超时，请稍后重试'),
    ]);
    final container = _container(repo);
    await container.read(feedControllerProvider.future);

    await container.read(feedControllerProvider.notifier).loadMore();

    final state = container.read(feedControllerProvider).value!;
    expect(state.posts.length, 2, reason: '失败不清已加载数据');
    expect(state.loadMoreError, '网络超时，请稍后重试');
    expect(state.loadingMore, isFalse);
  });

  test('refresh 重置为第一页', () async {
    final repo = _FakeFeedRepository([
      (cursor) async => _page([1, 2], next: '2'),
      (cursor) async => _page([3, 4]),
      (cursor) async => _page([9], next: '1'),
    ]);
    final container = _container(repo);
    await container.read(feedControllerProvider.future);
    await container.read(feedControllerProvider.notifier).loadMore();

    await container.read(feedControllerProvider.notifier).refresh();

    final state = container.read(feedControllerProvider).value!;
    expect(state.posts.map((p) => p.id), [9]);
    expect(state.hasMore, isTrue);
    expect(repo.receivedCursors.last, isNull, reason: '刷新从头拉取');
  });
}
