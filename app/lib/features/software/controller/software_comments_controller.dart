import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_exception.dart';
import '../../post_detail/model/post_detail.dart';
import '../data/software_comment_repository.dart';

/// 软件评论区状态：两级评论 + 游标分页。
class SoftwareCommentsState {
  const SoftwareCommentsState({
    required this.comments,
    required this.nextCursor,
    required this.hasMore,
    this.loadingMore = false,
    this.loadMoreError,
  });

  final List<Comment> comments;
  final String? nextCursor;
  final bool hasMore;
  final bool loadingMore;
  final String? loadMoreError;

  SoftwareCommentsState copyWith({
    List<Comment>? comments,
    String? nextCursor,
    bool? hasMore,
    bool? loadingMore,
    String? Function()? loadMoreError,
  }) {
    return SoftwareCommentsState(
      comments: comments ?? this.comments,
      nextCursor: nextCursor ?? this.nextCursor,
      hasMore: hasMore ?? this.hasMore,
      loadingMore: loadingMore ?? this.loadingMore,
      loadMoreError: loadMoreError != null
          ? loadMoreError()
          : this.loadMoreError,
    );
  }
}

/// 软件评论控制器（family：软件 ID）：分页 / 发评论（含回复）/ 两级点赞乐观更新。
class SoftwareCommentsController extends AsyncNotifier<SoftwareCommentsState> {
  SoftwareCommentsController(this.softwareId);

  final int softwareId;

  static const int pageSize = 20;

  SoftwareCommentRepository get _repo =>
      ref.read(softwareCommentRepositoryProvider);

  @override
  Future<SoftwareCommentsState> build() async {
    final page = await _repo.fetchComments(softwareId, size: pageSize);
    return SoftwareCommentsState(
      comments: page.list,
      nextCursor: page.nextCursor,
      hasMore: page.hasMore,
    );
  }

  Future<void> loadMore() async {
    final current = state.value;
    if (current == null || current.loadingMore || !current.hasMore) return;

    state = AsyncData(
      current.copyWith(loadingMore: true, loadMoreError: () => null),
    );
    try {
      final page = await _repo.fetchComments(
        softwareId,
        cursor: current.nextCursor,
        size: pageSize,
      );
      state = AsyncData(
        current.copyWith(
          comments: [...current.comments, ...page.list],
          nextCursor: page.nextCursor,
          hasMore: page.hasMore,
          loadingMore: false,
        ),
      );
    } on ApiException catch (e) {
      state = AsyncData(
        current.copyWith(loadingMore: false, loadMoreError: () => e.message),
      );
    }
  }

  /// 发评论：null 回复对象=评软件（插列表头）；否则插入根评论回复区尾部。
  /// 失败抛 [ApiException] 由输入面板提示。
  Future<void> send(
    String content, {
    int? replyTo,
    int? rootId,
    String replyToNickname = '',
  }) async {
    final created = await _repo.createComment(
      softwareId,
      content: content,
      replyTo: replyTo,
    );
    final current = state.value;
    if (current == null) return;

    if (replyTo == null || rootId == null) {
      state = AsyncData(
        current.copyWith(comments: [created, ...current.comments]),
      );
      return;
    }
    final stamped = created.copyWith(replyToNickname: replyToNickname);
    state = AsyncData(
      current.copyWith(
        comments: [
          for (final c in current.comments)
            if (c.id == rootId)
              c.copyWith(
                replyCount: c.replyCount + 1,
                replies: [...c.replies, stamped],
              )
            else
              c,
        ],
      ),
    );
  }

  /// 两级评论点赞：乐观翻转，失败回滚并抛 [ApiException]。
  Future<void> toggleLike(int commentId) async {
    final current = state.value;
    if (current == null) return;

    Comment? target;
    for (final c in current.comments) {
      if (c.id == commentId) target = c;
      for (final r in c.replies) {
        if (r.id == commentId) target = r;
      }
    }
    if (target == null) return;
    final nextLiked = !target.liked;

    List<Comment> apply(List<Comment> list, bool liked) => [
      for (final c in list)
        if (c.id == commentId)
          c.copyWith(
            liked: liked,
            likeCount: (c.likeCount + (liked ? 1 : -1)).clamp(0, 1 << 31),
          )
        else
          c.copyWith(replies: [
            for (final r in c.replies)
              if (r.id == commentId)
                r.copyWith(
                  liked: liked,
                  likeCount: (r.likeCount + (liked ? 1 : -1)).clamp(0, 1 << 31),
                )
              else
                r,
          ]),
    ];

    state = AsyncData(
      current.copyWith(comments: apply(current.comments, nextLiked)),
    );
    try {
      await _repo.setCommentLike(commentId, like: nextLiked);
    } on ApiException {
      final latest = state.value;
      if (latest != null) {
        state = AsyncData(
          latest.copyWith(comments: apply(latest.comments, !nextLiked)),
        );
      }
      rethrow;
    }
  }
}

final softwareCommentsControllerProvider = AsyncNotifierProvider.family
    .autoDispose<SoftwareCommentsController, SoftwareCommentsState, int>(
      SoftwareCommentsController.new,
    );
