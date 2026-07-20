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
  int joinCalls = 0;
  int quitCalls = 0;
  bool failJoin = false;

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
    String? cursor,
    int size = 20,
  }) async => const PostPage(list: [], nextCursor: null, hasMore: false);
}

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
}
