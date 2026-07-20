import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_exception.dart';
import '../../post_detail/data/post_detail_repository.dart';

/// 单帖点赞态：是否已赞 + 当前计数
class PostLikeState {
  const PostLikeState({required this.liked, required this.count});

  final bool liked;
  final int count;
}

/// 全局帖子点赞状态（postId → 覆盖层）：
/// 首页/圈内流/他人主页卡片与帖子详情页共用同一事实源，任一处操作全站同步。
/// 覆盖层缺省时各处回退展示接口下发的静态计数。
class PostLikeController extends Notifier<Map<int, PostLikeState>> {
  /// 请求中的帖子（防同一帖并发重复提交）
  final Set<int> _busy = {};

  @override
  Map<int, PostLikeState> build() => const {};

  bool isBusy(int postId) => _busy.contains(postId);

  /// 并入服务端下发的初始点赞态（详情接口）；不覆盖本地已有操作结果
  void seed(int postId, {required bool liked, required int count}) {
    if (state.containsKey(postId)) return;
    state = {...state, postId: PostLikeState(liked: liked, count: count)};
  }

  /// 点赞/取消（乐观更新，失败回滚并 rethrow 给调用方提示）。
  /// [currentLiked]/[currentCount] 为调用方当前展示值，用于覆盖层缺省时建立基线。
  Future<void> toggle(
    int postId, {
    required bool currentLiked,
    required int currentCount,
  }) async {
    if (_busy.contains(postId)) return;
    _busy.add(postId);

    final rollback = PostLikeState(liked: currentLiked, count: currentCount);
    state = {
      ...state,
      postId: PostLikeState(
        liked: !currentLiked,
        count: currentCount + (currentLiked ? -1 : 1),
      ),
    };
    try {
      await ref
          .read(postDetailRepositoryProvider)
          .setLike(postId, like: !currentLiked);
    } on ApiException {
      state = {...state, postId: rollback};
      rethrow;
    } finally {
      _busy.remove(postId);
    }
  }
}

final postLikeControllerProvider =
    NotifierProvider<PostLikeController, Map<int, PostLikeState>>(
      PostLikeController.new,
    );
