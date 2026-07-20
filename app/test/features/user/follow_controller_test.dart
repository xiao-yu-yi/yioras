import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yiora/core/network/api_exception.dart';
import 'package:yiora/features/user/controller/follow_controller.dart';
import 'package:yiora/features/user/data/user_repository.dart';
import 'package:yiora/features/user/model/user_profile.dart';

class _FakeUserRepository implements UserRepository {
  bool fail = false;
  int followCalls = 0;
  int unfollowCalls = 0;

  @override
  Future<UserProfile> fetchUserProfile(int uid) async =>
      UserProfile(id: uid, displayNo: 'N$uid', nickname: '用户$uid');

  @override
  Future<void> follow(int uid) async {
    if (fail) throw const ApiException(code: -1, message: '网络超时，请稍后重试');
    followCalls++;
  }

  @override
  Future<void> unfollow(int uid) async {
    if (fail) throw const ApiException(code: -1, message: '网络超时，请稍后重试');
    unfollowCalls++;
  }

  @override
  Future<int> openConversation(int peerId) async => 99;
}

ProviderContainer _container(_FakeUserRepository repo) {
  final container = ProviderContainer(
    overrides: [userRepositoryProvider.overrideWithValue(repo)],
  );
  addTearDown(container.dispose);
  return container;
}

void main() {
  test('关注：乐观置 true 并调用接口', () async {
    final repo = _FakeUserRepository();
    final container = _container(repo);
    final notifier = container.read(followControllerProvider.notifier);

    await notifier.toggle(7, currentlyFollowing: false);

    expect(container.read(followControllerProvider)[7], isTrue);
    expect(repo.followCalls, 1);
  });

  test('取关：乐观置 false 并调用接口', () async {
    final repo = _FakeUserRepository();
    final container = _container(repo);
    final notifier = container.read(followControllerProvider.notifier);

    await notifier.toggle(7, currentlyFollowing: true);

    expect(container.read(followControllerProvider)[7], isFalse);
    expect(repo.unfollowCalls, 1);
  });

  test('关注失败：回滚状态并抛异常', () async {
    final repo = _FakeUserRepository()..fail = true;
    final container = _container(repo);
    final notifier = container.read(followControllerProvider.notifier);

    await expectLater(
      notifier.toggle(7, currentlyFollowing: false),
      throwsA(isA<ApiException>()),
    );

    expect(
      container.read(followControllerProvider)[7],
      isFalse,
      reason: '失败后回滚为原状态',
    );
  });

  test('seed 不覆盖本地已有操作结果', () async {
    final repo = _FakeUserRepository();
    final container = _container(repo);
    final notifier = container.read(followControllerProvider.notifier);

    await notifier.toggle(7, currentlyFollowing: false); // 本地已关注
    notifier.seed(7, false); // 服务端旧快照不应覆盖

    expect(container.read(followControllerProvider)[7], isTrue);

    notifier.seed(8, true); // 无本地记录时正常并入
    expect(container.read(followControllerProvider)[8], isTrue);
  });
}
