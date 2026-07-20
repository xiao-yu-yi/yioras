import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yiora/core/network/api_exception.dart';
import 'package:yiora/features/growth/controller/task_center_controller.dart';
import 'package:yiora/features/growth/data/growth_repository.dart';
import 'package:yiora/features/growth/model/growth_models.dart';

/// 可编程假仓库：签到/领奖可注入失败
class _FakeGrowthRepository implements GrowthRepository {
  bool signedToday = false;
  bool failSignIn = false;
  bool failClaim = false;
  final List<int> claimCalls = [];
  final List<YouzhuBizType> logsBizTypes = [];

  @override
  Future<TaskCenter> fetchTaskCenter() async => TaskCenter(
    signedToday: signedToday,
    continuous: 3,
    nextReward: 15,
    tasks: const [
      GrowthTask(
        id: 1,
        name: '每日签到',
        action: 'sign_in',
        target: 1,
        rewardYouzhu: 15,
      ),
      GrowthTask(
        id: 2,
        name: '点赞 3 次',
        action: 'like',
        target: 3,
        progress: 3,
        rewardYouzhu: 10,
        status: 1,
      ),
    ],
  );

  @override
  Future<SignInResult> signIn() async {
    if (failSignIn) {
      throw const ApiException(code: 42900, message: '今天已经签过到了');
    }
    signedToday = true;
    return const SignInResult(reward: 15, continuous: 4, balance: 1365);
  }

  @override
  Future<ClaimResult> claimTask(int taskId) async {
    claimCalls.add(taskId);
    if (failClaim) {
      throw const ApiException(code: 42900, message: '奖励已领取过了');
    }
    return const ClaimResult(reward: 10, balance: 1375);
  }

  @override
  Future<YouzhuAccount> fetchAccount() async =>
      const YouzhuAccount(balance: 1350, signedToday: false);

  @override
  Future<List<YouzhuLog>> fetchLogs({
    YouzhuBizType bizType = YouzhuBizType.all,
    int page = 1,
    int size = 20,
  }) async {
    logsBizTypes.add(bizType);
    return [
      YouzhuLog(
        id: page * 10,
        bizType: bizType == YouzhuBizType.all ? 1 : bizType.value,
        amount: 10,
        balanceAfter: 1000,
        createdAt: DateTime(2026, 7, 1),
      ),
    ];
  }
}

ProviderContainer _container(GrowthRepository repo) {
  final container = ProviderContainer(
    overrides: [growthRepositoryProvider.overrideWithValue(repo)],
  );
  addTearDown(container.dispose);
  return container;
}

void main() {
  group('TaskCenterController', () {
    test('签到成功：signedToday 置真且签到任务推进为可领取', () async {
      final repo = _FakeGrowthRepository();
      final container = _container(repo);
      container.listen(taskCenterControllerProvider, (_, _) {});
      await container.read(taskCenterControllerProvider.future);

      final result = await container
          .read(taskCenterControllerProvider.notifier)
          .signIn();

      expect(result.reward, 15);
      final state = container.read(taskCenterControllerProvider).value!;
      expect(state.signedToday, isTrue);
      expect(state.continuous, 4);
      final signTask = state.tasks.firstWhere((t) => t.action == 'sign_in');
      expect(signTask.status, 1, reason: '签到任务应转可领取');
    });

    test('重复签到：抛错且状态不变', () async {
      final repo = _FakeGrowthRepository()..failSignIn = true;
      final container = _container(repo);
      container.listen(taskCenterControllerProvider, (_, _) {});
      await container.read(taskCenterControllerProvider.future);

      await expectLater(
        container.read(taskCenterControllerProvider.notifier).signIn(),
        throwsA(isA<ApiException>()),
      );
      final state = container.read(taskCenterControllerProvider).value!;
      expect(state.signedToday, isFalse);
    });

    test('领奖成功：任务置已领取', () async {
      final repo = _FakeGrowthRepository();
      final container = _container(repo);
      container.listen(taskCenterControllerProvider, (_, _) {});
      await container.read(taskCenterControllerProvider.future);

      await container.read(taskCenterControllerProvider.notifier).claim(2);

      expect(repo.claimCalls, [2]);
      final state = container.read(taskCenterControllerProvider).value!;
      expect(state.tasks.firstWhere((t) => t.id == 2).status, 2);
    });
  });

  group('YouzhuLogsController', () {
    test('默认全部类型；切类型重拉并透传参数', () async {
      final repo = _FakeGrowthRepository();
      final container = _container(repo);
      container.listen(youzhuLogsControllerProvider, (_, _) {});
      await container.read(youzhuLogsControllerProvider.future);

      await container
          .read(youzhuLogsControllerProvider.notifier)
          .changeBizType(YouzhuBizType.signIn);

      expect(repo.logsBizTypes, [YouzhuBizType.all, YouzhuBizType.signIn]);
      final state = container.read(youzhuLogsControllerProvider).value!;
      expect(state.bizType, YouzhuBizType.signIn);
      expect(state.logs.single.bizType, YouzhuBizType.signIn.value);
    });
  });
}
