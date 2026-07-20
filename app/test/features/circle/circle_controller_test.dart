import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yiora/core/network/api_exception.dart';
import 'package:yiora/features/circle/controller/circle_detail_controller.dart';
import 'package:yiora/features/circle/controller/circle_list_controller.dart';
import 'package:yiora/features/circle/data/circle_repository.dart';
import 'package:yiora/features/circle/model/circle.dart';
import 'package:yiora/features/feed/model/post.dart';

/// 可编程假仓库：记录调用并维护加入状态
class _FakeCircleRepository implements CircleRepository {
  _FakeCircleRepository({List<Circle>? circles})
    : circles = circles ?? [_circle(1), _circle(2, joined: true)];

  final List<Circle> circles;
  final List<CircleSort> receivedSorts = [];
  final List<CirclePostSort> receivedPostSorts = [];
  int joinCalls = 0;
  int quitCalls = 0;
  bool failJoin = false;
  bool failPosts = false;

  /// 圈内流按排序下发的假数据（键：排序）
  Map<CirclePostSort, List<Post>> postsBySort = const {};

  static Circle _circle(int id, {bool joined = false}) => Circle(
    id: id,
    name: '圈子$id',
    intro: '简介$id',
    memberCount: 100 * id,
    joined: joined,
  );

  @override
  Future<List<Circle>> fetchCircles({required CircleSort sort}) async {
    receivedSorts.add(sort);
    return circles;
  }

  @override
  Future<Circle> fetchCircleDetail(int id) async =>
      circles.firstWhere((c) => c.id == id);

  @override
  Future<void> joinCircle(int id) async {
    if (failJoin) {
      throw const ApiException(code: 500, message: '加入失败');
    }
    joinCalls++;
  }

  @override
  Future<void> quitCircle(int id) async => quitCalls++;

  @override
  Future<PostPage> fetchCirclePosts(
    int circleId, {
    CirclePostSort sort = CirclePostSort.newest,
    String? cursor,
    int size = 20,
  }) async {
    receivedPostSorts.add(sort);
    if (failPosts) {
      throw const ApiException(code: 500, message: '加载失败');
    }
    return PostPage(
      list: postsBySort[sort] ?? const [],
      nextCursor: null,
      hasMore: false,
    );
  }
}

Post _post(int id) => Post(
  id: id,
  author: const PostAuthor(id: 1, nickname: '测试'),
  content: '内容$id',
  createdAt: DateTime(2026, 7, 1),
);

ProviderContainer _container(CircleRepository repo) {
  final container = ProviderContainer(
    overrides: [circleRepositoryProvider.overrideWithValue(repo)],
  );
  addTearDown(container.dispose);
  return container;
}

void main() {
  group('CircleListController', () {
    test('默认按最热加载', () async {
      final repo = _FakeCircleRepository();
      final container = _container(repo);

      final state = await container.read(circleListControllerProvider.future);

      expect(state.sort, CircleSort.hot);
      expect(state.circles.length, 2);
      expect(repo.receivedSorts, [CircleSort.hot]);
    });

    test('切换排序重新拉取并透传参数', () async {
      final repo = _FakeCircleRepository();
      final container = _container(repo);
      await container.read(circleListControllerProvider.future);

      await container
          .read(circleListControllerProvider.notifier)
          .changeSort(CircleSort.newest);

      final state = container.read(circleListControllerProvider).value!;
      expect(state.sort, CircleSort.newest);
      expect(repo.receivedSorts, [CircleSort.hot, CircleSort.newest]);
    });

    test('重复选择当前排序不重复请求', () async {
      final repo = _FakeCircleRepository();
      final container = _container(repo);
      await container.read(circleListControllerProvider.future);

      await container
          .read(circleListControllerProvider.notifier)
          .changeSort(CircleSort.hot);

      expect(repo.receivedSorts, [CircleSort.hot]);
    });
  });

  group('CircleDetailController.toggleJoin', () {
    test('未加入时加入：状态翻转且成员数+1', () async {
      final repo = _FakeCircleRepository();
      final container = _container(repo);
      await container.read(circleDetailControllerProvider(1).future);

      await container
          .read(circleDetailControllerProvider(1).notifier)
          .toggleJoin();

      final state = container.read(circleDetailControllerProvider(1)).value!;
      expect(repo.joinCalls, 1);
      expect(state.circle.joined, isTrue);
      expect(state.circle.memberCount, 101);
      expect(state.joinBusy, isFalse);
    });

    test('已加入时退出：状态翻转且成员数-1', () async {
      final repo = _FakeCircleRepository();
      final container = _container(repo);
      await container.read(circleDetailControllerProvider(2).future);

      await container
          .read(circleDetailControllerProvider(2).notifier)
          .toggleJoin();

      final state = container.read(circleDetailControllerProvider(2)).value!;
      expect(repo.quitCalls, 1);
      expect(state.circle.joined, isFalse);
      expect(state.circle.memberCount, 199);
    });

    test('加入失败：抛出异常且状态不变', () async {
      final repo = _FakeCircleRepository()..failJoin = true;
      final container = _container(repo);
      await container.read(circleDetailControllerProvider(1).future);

      await expectLater(
        container.read(circleDetailControllerProvider(1).notifier).toggleJoin(),
        throwsA(isA<ApiException>()),
      );

      final state = container.read(circleDetailControllerProvider(1)).value!;
      expect(state.circle.joined, isFalse);
      expect(state.circle.memberCount, 100);
      expect(state.joinBusy, isFalse);
    });
  });

  group('CircleDetailController.changeSort', () {
    test('默认最新；切最热重拉帖子并替换列表', () async {
      final repo = _FakeCircleRepository()
        ..postsBySort = {
          CirclePostSort.newest: [_post(1)],
          CirclePostSort.hot: [_post(9), _post(8)],
        };
      final container = _container(repo);
      await container.read(circleDetailControllerProvider(1).future);

      expect(repo.receivedPostSorts, [CirclePostSort.newest]);

      await container
          .read(circleDetailControllerProvider(1).notifier)
          .changeSort(CirclePostSort.hot);

      final state = container.read(circleDetailControllerProvider(1)).value!;
      expect(state.sort, CirclePostSort.hot);
      expect(state.posts.map((p) => p.id), [9, 8]);
      expect(state.sortSwitching, isFalse);
      expect(repo.receivedPostSorts, [
        CirclePostSort.newest,
        CirclePostSort.hot,
      ]);
    });

    test('重复选择当前排序不重复请求', () async {
      final repo = _FakeCircleRepository();
      final container = _container(repo);
      await container.read(circleDetailControllerProvider(1).future);

      await container
          .read(circleDetailControllerProvider(1).notifier)
          .changeSort(CirclePostSort.newest);

      expect(repo.receivedPostSorts, [CirclePostSort.newest]);
    });

    test('切换失败：回滚原 Tab 并保留旧列表', () async {
      final repo = _FakeCircleRepository()
        ..postsBySort = {
          CirclePostSort.newest: [_post(1)],
        };
      final container = _container(repo);
      await container.read(circleDetailControllerProvider(1).future);

      repo.failPosts = true;
      await expectLater(
        container
            .read(circleDetailControllerProvider(1).notifier)
            .changeSort(CirclePostSort.hot),
        throwsA(isA<ApiException>()),
      );

      final state = container.read(circleDetailControllerProvider(1)).value!;
      expect(state.sort, CirclePostSort.newest);
      expect(state.posts.map((p) => p.id), [1]);
      expect(state.sortSwitching, isFalse);
    });
  });
}
