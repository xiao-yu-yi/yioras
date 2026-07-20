import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yiora/core/network/api_exception.dart';
import 'package:yiora/features/feed/model/post.dart';
import 'package:yiora/features/topic/controller/topic_posts_controller.dart';
import 'package:yiora/features/topic/data/topic_repository.dart';

class _FakeTopicRepository implements TopicRepository {
  final List<TopicPostSort> receivedSorts = [];
  bool fail = false;

  static Post _post(int id) => Post(
    id: id,
    author: const PostAuthor(id: 1, nickname: '测试'),
    content: '内容$id',
    createdAt: DateTime(2026, 7, 1),
  );

  @override
  Future<TopicPostsPage> fetchTopicPosts(
    int topicId, {
    TopicPostSort sort = TopicPostSort.hot,
    int page = 1,
    int size = 20,
  }) async {
    receivedSorts.add(sort);
    if (fail) throw const ApiException(code: 500, message: '加载失败');
    return TopicPostsPage(
      topic: const TopicInfo(id: 3, name: 'Flutter', postCount: 1287),
      posts: sort == TopicPostSort.hot ? [_post(9), _post(8)] : [_post(1)],
      hasMore: false,
    );
  }

  @override
  Future<TopicInfo> resolveByName(String name) async {
    if (name != 'Flutter') {
      throw const ApiException(code: 40400, message: '话题不存在');
    }
    return const TopicInfo(id: 3, name: 'Flutter', postCount: 1287);
  }
}

ProviderContainer _container(TopicRepository repo) {
  final container = ProviderContainer(
    overrides: [topicRepositoryProvider.overrideWithValue(repo)],
  );
  addTearDown(container.dispose);
  container.listen(topicPostsControllerProvider(3), (_, _) {});
  return container;
}

void main() {
  test('默认最热加载（对齐服务端默认排序）', () async {
    final repo = _FakeTopicRepository();
    final container = _container(repo);

    final state = await container.read(topicPostsControllerProvider(3).future);

    expect(state.sort, TopicPostSort.hot);
    expect(state.topic.name, 'Flutter');
    expect(state.posts.map((p) => p.id), [9, 8]);
    expect(repo.receivedSorts, [TopicPostSort.hot]);
  });

  test('切最新重拉并替换列表', () async {
    final repo = _FakeTopicRepository();
    final container = _container(repo);
    await container.read(topicPostsControllerProvider(3).future);

    await container
        .read(topicPostsControllerProvider(3).notifier)
        .changeSort(TopicPostSort.newest);

    final state = container.read(topicPostsControllerProvider(3)).value!;
    expect(state.sort, TopicPostSort.newest);
    expect(state.posts.map((p) => p.id), [1]);
    expect(state.sortSwitching, isFalse);
  });

  test('切换失败：回滚原排序并保留旧列表', () async {
    final repo = _FakeTopicRepository();
    final container = _container(repo);
    await container.read(topicPostsControllerProvider(3).future);

    repo.fail = true;
    await expectLater(
      container
          .read(topicPostsControllerProvider(3).notifier)
          .changeSort(TopicPostSort.newest),
      throwsA(isA<ApiException>()),
    );

    final state = container.read(topicPostsControllerProvider(3)).value!;
    expect(state.sort, TopicPostSort.hot);
    expect(state.posts.map((p) => p.id), [9, 8]);
  });

  test('resolveByName：未知话题抛 40400', () async {
    final repo = _FakeTopicRepository();
    await expectLater(
      repo.resolveByName('不存在的话题'),
      throwsA(
        isA<ApiException>().having((e) => e.code, 'code', 40400),
      ),
    );
  });
}
