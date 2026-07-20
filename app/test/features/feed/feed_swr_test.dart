import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yiora/core/cache/key_value_cache.dart';
import 'package:yiora/core/network/api_exception.dart';
import 'package:yiora/features/feed/controller/feed_controller.dart';
import 'package:yiora/features/feed/data/feed_repository.dart';
import 'package:yiora/features/feed/model/post.dart';

class _FakeFeedRepository implements FeedRepository {
  _FakeFeedRepository({this.fail = false, this.ids = const [1, 2]});

  bool fail;
  List<int> ids;
  int calls = 0;

  @override
  Future<PostPage> fetchRecommend({String? cursor, int size = 20}) async {
    calls++;
    if (fail) {
      throw const ApiException(code: -1, message: '网络超时，请稍后重试');
    }
    return PostPage(
      list: [
        for (final id in ids)
          Post(
            id: id,
            author: const PostAuthor(id: 1, nickname: '作者'),
            content: '内容 $id',
            createdAt: DateTime(2026, 7, 20),
          ),
      ],
      nextCursor: null,
      hasMore: false,
    );
  }
}

ProviderContainer _container(FeedRepository repo, KeyValueCache cache) {
  final container = ProviderContainer(
    overrides: [
      feedRepositoryProvider.overrideWithValue(repo),
      cacheProvider.overrideWithValue(cache),
    ],
  );
  addTearDown(container.dispose);
  return container;
}

void main() {
  test('无缓存：走网络并写缓存', () async {
    final cache = MemoryKeyValueCache();
    final repo = _FakeFeedRepository();
    final container = _container(repo, cache);

    final state = await container.read(feedControllerProvider.future);

    expect(state.posts.map((p) => p.id), [1, 2]);
    expect(repo.calls, 1);
    expect(
      cache.readJson(FeedController.cacheKey),
      isNotNull,
      reason: '首屏成功后回写缓存',
    );
  });

  test('有缓存：先出缓存，后台刷新替换为新数据', () async {
    final cache = MemoryKeyValueCache();
    // 预置旧缓存（帖子 1、2）
    await cache.writeJson(FeedController.cacheKey, {
      'list': [
        Post(
          id: 1,
          author: const PostAuthor(id: 1, nickname: '作者'),
          content: '旧内容',
          createdAt: DateTime(2026, 7, 19),
        ).toJson(),
      ],
      'nextCursor': null,
      'hasMore': false,
    });
    // 网络返回新数据（帖子 9）
    final repo = _FakeFeedRepository(ids: [9]);
    final container = _container(repo, cache);
    final sub = container.listen(feedControllerProvider, (_, _) {});
    addTearDown(sub.close);

    final first = await container.read(feedControllerProvider.future);
    expect(first.posts.single.id, 1, reason: '先返回缓存数据');

    // 等后台刷新完成
    await Future<void>.delayed(const Duration(milliseconds: 50));
    final refreshed = container.read(feedControllerProvider).value!;
    expect(refreshed.posts.single.id, 9, reason: '后台刷新替换为网络数据');
    expect(repo.calls, 1);
  });

  test('有缓存且后台刷新失败：静默保留缓存', () async {
    final cache = MemoryKeyValueCache();
    await cache.writeJson(FeedController.cacheKey, {
      'list': [
        Post(
          id: 1,
          author: const PostAuthor(id: 1, nickname: '作者'),
          content: '缓存内容',
          createdAt: DateTime(2026, 7, 19),
        ).toJson(),
      ],
      'nextCursor': null,
      'hasMore': false,
    });
    final repo = _FakeFeedRepository(fail: true);
    final container = _container(repo, cache);
    final sub = container.listen(feedControllerProvider, (_, _) {});
    addTearDown(sub.close);

    final first = await container.read(feedControllerProvider.future);
    expect(first.posts.single.id, 1);

    await Future<void>.delayed(const Duration(milliseconds: 50));
    final after = container.read(feedControllerProvider);
    expect(after.hasError, isFalse, reason: '后台失败不打断缓存展示');
    expect(after.value!.posts.single.id, 1);
  });
}
