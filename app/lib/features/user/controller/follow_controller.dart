import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_exception.dart';
import '../data/user_repository.dart';

/// 全局关注状态覆盖层：uid → 是否已关注。
/// 单一事实源：他人主页与帖子详情页的关注按钮共用本状态，
/// 各页面拉到的服务端初始值通过 [seed] 合并进来。
class FollowController extends Notifier<Map<int, bool>> {
  UserRepository get _repo => ref.read(userRepositoryProvider);

  /// 请求进行中的 uid（防重复点击）
  final Set<int> _busy = {};

  @override
  Map<int, bool> build() => const {};

  /// 是否已关注；本地无记录返回 null（由调用方用服务端初始值兜底）
  bool? statusOf(int uid) => state[uid];

  bool isBusy(int uid) => _busy.contains(uid);

  /// 合并服务端下发的初始关注状态（不覆盖本地已有操作结果）
  void seed(int uid, bool following) {
    if (state.containsKey(uid)) return;
    state = {...state, uid: following};
  }

  /// 关注/取关（乐观更新，失败回滚并 rethrow 由页面提示）
  Future<void> toggle(int uid, {required bool currentlyFollowing}) async {
    if (_busy.contains(uid)) return;
    _busy.add(uid);
    state = {...state, uid: !currentlyFollowing};
    try {
      if (currentlyFollowing) {
        await _repo.unfollow(uid);
      } else {
        await _repo.follow(uid);
      }
    } on ApiException {
      state = {...state, uid: currentlyFollowing};
      rethrow;
    } finally {
      _busy.remove(uid);
    }
  }
}

final followControllerProvider =
    NotifierProvider<FollowController, Map<int, bool>>(FollowController.new);
