import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_exception.dart';
import '../model/post_detail.dart';
import '../data/post_detail_repository.dart';

/// 回复目标：点某条评论后，输入框切换为「回复 @nickname」。
/// [rootId] 为其所属一级评论 ID（点一级评论时等于 [commentId]），
/// 用于把新回复插到对应楼层的回复列表里。
class CommentReplyTarget {
  const CommentReplyTarget({
    required this.commentId,
    required this.rootId,
    required this.nickname,
  });

  final int commentId;
  final int rootId;
  final String nickname;
}

/// 单个楼层的回复展开状态（rootId → 本状态）。
/// [loaded] 表示已拉取过首页全量回复；收起后再展开直接复用不重复请求。
class ReplyThreadState {
  const ReplyThreadState({
    this.expanded = false,
    this.loading = false,
    this.loaded = false,
    this.previewCount = 0,
    this.nextCursor,
    this.hasMore = false,
    this.error,
  });

  final bool expanded;
  final bool loading;
  final bool loaded;

  /// 展开前的预览条数：收起时恢复只显示前 N 条
  final int previewCount;
  final String? nextCursor;
  final bool hasMore;
  final String? error;

  ReplyThreadState copyWith({
    bool? expanded,
    bool? loading,
    bool? loaded,
    int? previewCount,
    String? Function()? nextCursor,
    bool? hasMore,
    String? Function()? error,
  }) {
    return ReplyThreadState(
      expanded: expanded ?? this.expanded,
      loading: loading ?? this.loading,
      loaded: loaded ?? this.loaded,
      previewCount: previewCount ?? this.previewCount,
      nextCursor: nextCursor != null ? nextCursor() : this.nextCursor,
      hasMore: hasMore ?? this.hasMore,
      error: error != null ? error() : this.error,
    );
  }
}

/// 帖子详情页状态：详情 + 互动态 + 两级评论分页。
class PostDetailState {
  const PostDetailState({
    required this.detail,
    required this.comments,
    required this.nextCursor,
    required this.hasMore,
    this.loadingMore = false,
    this.loadMoreError,
    this.likeCount = 0,
    this.sendingComment = false,
    this.replyThreads = const {},
  });

  final PostDetail detail;
  final List<Comment> comments;
  final String? nextCursor;
  final bool hasMore;
  final bool loadingMore;
  final String? loadMoreError;

  /// 服务端下发的初始点赞数（全局点赞覆盖层缺省时的回退展示值）
  final int likeCount;

  /// 评论发送中（输入栏防重复提交）
  final bool sendingComment;

  /// 楼层回复展开状态（key 为一级评论 ID）
  final Map<int, ReplyThreadState> replyThreads;

  PostDetailState copyWith({
    PostDetail? detail,
    List<Comment>? comments,
    String? nextCursor,
    bool? hasMore,
    bool? loadingMore,
    String? Function()? loadMoreError,
    int? likeCount,
    bool? sendingComment,
    Map<int, ReplyThreadState>? replyThreads,
  }) {
    return PostDetailState(
      detail: detail ?? this.detail,
      comments: comments ?? this.comments,
      nextCursor: nextCursor ?? this.nextCursor,
      hasMore: hasMore ?? this.hasMore,
      loadingMore: loadingMore ?? this.loadingMore,
      loadMoreError: loadMoreError != null
          ? loadMoreError()
          : this.loadMoreError,
      likeCount: likeCount ?? this.likeCount,
      sendingComment: sendingComment ?? this.sendingComment,
      replyThreads: replyThreads ?? this.replyThreads,
    );
  }
}

/// 帖子详情控制器（family：postId）。
/// 点赞/收藏采用乐观更新：先翻转 UI，请求失败回滚并抛异常给页面提示。
class PostDetailController extends AsyncNotifier<PostDetailState> {
  PostDetailController(this.postId);

  final int postId;

  static const int pageSize = 20;

  PostDetailRepository get _repo => ref.read(postDetailRepositoryProvider);

  @override
  Future<PostDetailState> build() async {
    final detail = await _repo.fetchDetail(postId);
    final page = await _repo.fetchComments(postId, size: pageSize);
    return PostDetailState(
      detail: detail,
      comments: page.list,
      nextCursor: page.nextCursor,
      hasMore: page.hasMore,
      likeCount: detail.post.likeCount,
    );
  }

  Future<void> retryFirstLoad() async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(build);
  }

  Future<void> loadMoreComments() async {
    final current = state.value;
    if (current == null || current.loadingMore || !current.hasMore) return;

    state = AsyncData(
      current.copyWith(loadingMore: true, loadMoreError: () => null),
    );
    try {
      final page = await _repo.fetchComments(
        postId,
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

  // 帖子点赞已迁移至全局 PostLikeController（feed/controller/post_like_controller.dart），
  // 卡片与详情页共用同一事实源；本控制器仅保留初始 liked/likeCount 供覆盖层缺省时回退。

  /// 收藏/取消收藏（乐观更新，失败回滚并 rethrow）
  Future<void> toggleFavorite() async {
    final current = state.value;
    if (current == null) return;
    final favorited = current.detail.favorited;

    state = AsyncData(
      current.copyWith(
        detail: PostDetail(
          post: current.detail.post,
          liked: current.detail.liked,
          favorited: !favorited,
        ),
      ),
    );
    try {
      await _repo.setFavorite(postId, favorite: !favorited);
    } on ApiException {
      final latest = state.value;
      if (latest != null) {
        state = AsyncData(
          latest.copyWith(
            detail: PostDetail(
              post: latest.detail.post,
              liked: latest.detail.liked,
              favorited: favorited,
            ),
          ),
        );
      }
      rethrow;
    }
  }

  /// 发评论：直接回帖插入列表顶部；带 [replyTo] 时追加到对应楼层的回复列表。
  /// 失败 rethrow 由输入栏提示（不清输入内容、不清回复对象）。
  Future<void> sendComment(
    String content, {
    CommentReplyTarget? replyTo,
  }) async {
    final current = state.value;
    if (current == null || current.sendingComment) return;

    state = AsyncData(current.copyWith(sendingComment: true));
    try {
      final comment = await _repo.createComment(
        postId,
        content: content,
        replyTo: replyTo?.commentId,
      );
      final latest = state.value ?? current;
      if (replyTo == null) {
        state = AsyncData(
          latest.copyWith(
            comments: [comment, ...latest.comments],
            sendingComment: false,
          ),
        );
        return;
      }
      // 回复：挂到所属一级评论的回复列表并 +1 回复数
      final reply = comment.copyWith(replyToNickname: replyTo.nickname);
      final rootIndex = latest.comments.indexWhere(
        (c) => c.id == replyTo.rootId,
      );
      if (rootIndex < 0) {
        // 楼层已不在当前列表（极端情况），退化为顶部插入保证可见
        state = AsyncData(
          latest.copyWith(
            comments: [reply, ...latest.comments],
            sendingComment: false,
          ),
        );
        return;
      }
      final root = latest.comments[rootIndex];
      final thread = latest.replyThreads[replyTo.rootId];
      // 收起态（已加载全量）插到预览区末尾保证可见；其余场景追加到尾部
      final collapsedInsert =
          thread != null && thread.loaded && !thread.expanded;
      final insertAt = collapsedInsert
          ? thread.previewCount.clamp(0, root.replies.length)
          : root.replies.length;
      final updatedRoot = root.copyWith(
        replies: [...root.replies]..insert(insertAt, reply),
        replyCount: root.replyCount + 1,
      );
      state = AsyncData(
        latest.copyWith(
          comments: [
            for (final c in latest.comments)
              if (c.id == root.id) updatedRoot else c,
          ],
          replyThreads: collapsedInsert
              ? {
                  ...latest.replyThreads,
                  replyTo.rootId: thread.copyWith(
                    previewCount: thread.previewCount + 1,
                  ),
                }
              : latest.replyThreads,
          sendingComment: false,
        ),
      );
    } on ApiException {
      final latest = state.value ?? current;
      state = AsyncData(latest.copyWith(sendingComment: false));
      rethrow;
    }
  }

  /// 请求中的评论点赞（防同一条并发重复提交）
  final Set<int> _likingComments = {};

  /// 评论点赞/取消（乐观更新，失败回滚并 rethrow）；一级评论与回复均可点。
  Future<void> toggleCommentLike(int commentId) async {
    final current = state.value;
    if (current == null || _likingComments.contains(commentId)) return;
    final target = _findComment(current.comments, commentId);
    if (target == null) return;

    final liked = target.liked;
    _likingComments.add(commentId);
    _applyCommentPatch(commentId, liked: !liked, delta: liked ? -1 : 1);
    try {
      await _repo.setCommentLike(commentId, like: !liked);
    } on ApiException {
      // 回滚到操作前
      _applyCommentPatch(commentId, liked: liked, delta: liked ? 1 : -1);
      rethrow;
    } finally {
      _likingComments.remove(commentId);
    }
  }

  /// 楼中楼分页大小（Mock 首楼共 6 条 → 展开首页 4 条 + 更多 2 条）
  static const int replyPageSize = 4;

  /// 展开/收起某楼层的全量回复。
  /// 首次展开拉取第一页；已加载过则直接切换展开态不重复请求；
  /// 首页拉取失败后（expanded 但未 loaded）再次调用视为重试。
  Future<void> toggleReplies(int rootId) async {
    final current = state.value;
    if (current == null) return;
    final thread = current.replyThreads[rootId] ?? const ReplyThreadState();
    if (thread.loading) return;

    if (thread.loaded) {
      _setThread(
        rootId,
        thread.copyWith(expanded: !thread.expanded, error: () => null),
      );
      return;
    }
    await _fetchReplies(rootId, firstPage: true);
  }

  /// 已展开楼层继续拉下一页回复
  Future<void> loadMoreReplies(int rootId) async {
    final current = state.value;
    if (current == null) return;
    final thread = current.replyThreads[rootId];
    if (thread == null || thread.loading || !thread.hasMore) return;
    await _fetchReplies(rootId, firstPage: false);
  }

  Future<void> _fetchReplies(int rootId, {required bool firstPage}) async {
    final current = state.value;
    if (current == null) return;
    final root = _rootOf(current.comments, rootId);
    if (root == null) return;
    final thread = current.replyThreads[rootId] ?? const ReplyThreadState();

    _setThread(
      rootId,
      thread.copyWith(
        loading: true,
        expanded: true,
        error: () => null,
        // 首次拉取记录预览条数，供收起时恢复
        previewCount: thread.loaded ? null : root.replies.length,
      ),
    );
    try {
      final page = await _repo.fetchReplies(
        rootId,
        cursor: firstPage ? null : thread.nextCursor,
        size: replyPageSize,
      );
      final latest = state.value;
      if (latest == null) return;
      final latestRoot = _rootOf(latest.comments, rootId);
      final latestThread =
          latest.replyThreads[rootId] ?? const ReplyThreadState();
      if (latestRoot == null) return;

      // 合并去重：服务端分页在前，本地新增（不在服务端列表内）保留在尾部
      final List<Comment> merged;
      if (firstPage) {
        final serverIds = page.list.map((e) => e.id).toSet();
        merged = [
          ...page.list,
          ...latestRoot.replies.where((r) => !serverIds.contains(r.id)),
        ];
      } else {
        final existingIds = latestRoot.replies.map((e) => e.id).toSet();
        merged = [
          ...latestRoot.replies,
          ...page.list.where((r) => !existingIds.contains(r.id)),
        ];
      }
      state = AsyncData(
        latest.copyWith(
          comments: [
            for (final c in latest.comments)
              if (c.id == rootId) c.copyWith(replies: merged) else c,
          ],
          replyThreads: {
            ...latest.replyThreads,
            rootId: latestThread.copyWith(
              loading: false,
              loaded: true,
              expanded: true,
              nextCursor: () => page.nextCursor,
              hasMore: page.hasMore,
              error: () => null,
            ),
          },
        ),
      );
    } on ApiException catch (e) {
      final latest = state.value;
      if (latest == null) return;
      final latestThread =
          latest.replyThreads[rootId] ?? const ReplyThreadState();
      _setThread(
        rootId,
        latestThread.copyWith(loading: false, error: () => e.message),
      );
    }
  }

  Comment? _rootOf(List<Comment> comments, int rootId) {
    for (final c in comments) {
      if (c.id == rootId) return c;
    }
    return null;
  }

  void _setThread(int rootId, ReplyThreadState thread) {
    final latest = state.value;
    if (latest == null) return;
    state = AsyncData(
      latest.copyWith(replyThreads: {...latest.replyThreads, rootId: thread}),
    );
  }

  Comment? _findComment(List<Comment> comments, int commentId) {
    for (final c in comments) {
      if (c.id == commentId) return c;
      for (final r in c.replies) {
        if (r.id == commentId) return r;
      }
    }
    return null;
  }

  /// 在两级评论树中就地更新目标评论的点赞态
  void _applyCommentPatch(
    int commentId, {
    required bool liked,
    required int delta,
  }) {
    final latest = state.value;
    if (latest == null) return;
    Comment patch(Comment c) =>
        c.copyWith(liked: liked, likeCount: c.likeCount + delta);

    state = AsyncData(
      latest.copyWith(
        comments: [
          for (final c in latest.comments)
            if (c.id == commentId)
              patch(c)
            else if (c.replies.any((r) => r.id == commentId))
              c.copyWith(
                replies: [
                  for (final r in c.replies)
                    if (r.id == commentId) patch(r) else r,
                ],
              )
            else
              c,
        ],
      ),
    );
  }
}

final postDetailControllerProvider = AsyncNotifierProvider.family
    .autoDispose<PostDetailController, PostDetailState, int>(
      PostDetailController.new,
    );
