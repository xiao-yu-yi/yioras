import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yiora/core/network/api_exception.dart';
import 'package:yiora/features/feed/model/post.dart';
import 'package:yiora/features/post_detail/controller/post_detail_controller.dart';
import 'package:yiora/features/post_detail/data/post_detail_repository.dart';
import 'package:yiora/features/post_detail/model/post_detail.dart';

/// 可编程假仓库：记录调用，可让点赞/评论/回复分页失败
class _FakePostDetailRepository implements PostDetailRepository {
  bool failLike = false;
  bool failComment = false;
  bool failCommentLike = false;
  bool failReplies = false;
  final List<bool> likeCalls = [];
  final List<(int, bool)> commentLikeCalls = [];
  final List<int?> commentReplyTos = [];
  final List<String?> commentCursors = [];
  final List<String?> replyCursors = [];

  static Post _post(int id) => Post(
    id: id,
    author: const PostAuthor(id: 1, nickname: '作者'),
    content: '正文',
    likeCount: 10,
    createdAt: DateTime(2026, 7, 20),
  );

  static Comment _comment(int id) => Comment(
    id: id,
    author: const PostAuthor(id: 2, nickname: '评论者'),
    content: '评论 $id',
    createdAt: DateTime(2026, 7, 20),
  );

  @override
  Future<PostDetail> fetchDetail(int postId) async =>
      PostDetail(post: _post(postId));

  @override
  Future<CommentPage> fetchComments(
    int postId, {
    String? cursor,
    int size = 20,
  }) async {
    commentCursors.add(cursor);
    if (cursor == null) {
      // 第 1 条一级评论挂 1 条预览回复（共 6 条可展开），覆盖两级点赞/回复场景
      final root = Comment(
        id: 1,
        author: const PostAuthor(id: 2, nickname: '评论者'),
        content: '评论 1',
        createdAt: DateTime(2026, 7, 20),
        likeCount: 5,
        replyCount: 6,
        replies: [_reply(11)],
      );
      return CommentPage(
        list: [root, _comment(2)],
        nextCursor: '2',
        hasMore: true,
      );
    }
    return CommentPage(list: [_comment(3)], nextCursor: null, hasMore: false);
  }

  static Comment _reply(int id) => Comment(
    id: id,
    author: const PostAuthor(id: 3, nickname: '回复者'),
    content: '回复 $id',
    replyToNickname: '评论者',
    createdAt: DateTime(2026, 7, 20),
    likeCount: 2,
  );

  @override
  Future<CommentPage> fetchReplies(
    int commentId, {
    String? cursor,
    int size = 10,
  }) async {
    replyCursors.add(cursor);
    if (failReplies) {
      throw const ApiException(code: -1, message: '网络超时，请稍后重试');
    }
    // 楼层 1 的全量回复：11..16 共 6 条
    final all = [for (var i = 11; i <= 16; i++) _reply(i)];
    final offset = int.tryParse(cursor ?? '0') ?? 0;
    final end = (offset + size).clamp(0, all.length);
    final hasMore = end < all.length;
    return CommentPage(
      list: all.sublist(offset, end),
      nextCursor: hasMore ? '$end' : null,
      hasMore: hasMore,
    );
  }

  @override
  Future<void> setLike(int postId, {required bool like}) async {
    likeCalls.add(like);
    if (failLike) {
      throw const ApiException(code: -1, message: '网络超时，请稍后重试');
    }
  }

  @override
  Future<void> setFavorite(int postId, {required bool favorite}) async {}

  @override
  Future<void> setCommentLike(int commentId, {required bool like}) async {
    commentLikeCalls.add((commentId, like));
    if (failCommentLike) {
      throw const ApiException(code: -1, message: '网络超时，请稍后重试');
    }
  }

  @override
  Future<Comment> createComment(
    int postId, {
    required String content,
    int? replyTo,
  }) async {
    commentReplyTos.add(replyTo);
    if (failComment) {
      throw const ApiException(code: 500, message: '评论发送失败');
    }
    return Comment(
      id: 999,
      author: const PostAuthor(id: 9, nickname: '我'),
      content: content,
      createdAt: DateTime(2026, 7, 20),
    );
  }
}

ProviderContainer _container(PostDetailRepository repo) {
  final container = ProviderContainer(
    overrides: [postDetailRepositoryProvider.overrideWithValue(repo)],
  );
  addTearDown(container.dispose);
  return container;
}

void main() {
  test('首屏加载详情与第一页评论', () async {
    final repo = _FakePostDetailRepository();
    final container = _container(repo);

    final state = await container.read(postDetailControllerProvider(7).future);

    expect(state.detail.post.id, 7);
    expect(state.likeCount, 10);
    expect(state.comments.length, 2);
    expect(state.hasMore, isTrue);
  });

  test('评论分页追加并透传游标', () async {
    final repo = _FakePostDetailRepository();
    final container = _container(repo);
    await container.read(postDetailControllerProvider(7).future);

    await container
        .read(postDetailControllerProvider(7).notifier)
        .loadMoreComments();

    final state = container.read(postDetailControllerProvider(7)).value!;
    expect(state.comments.map((c) => c.id), [1, 2, 3]);
    expect(state.hasMore, isFalse);
    expect(repo.commentCursors, [null, '2']);
  });

  test('发评论成功插入列表顶部', () async {
    final repo = _FakePostDetailRepository();
    final container = _container(repo);
    await container.read(postDetailControllerProvider(7).future);

    await container
        .read(postDetailControllerProvider(7).notifier)
        .sendComment('新评论');

    final state = container.read(postDetailControllerProvider(7)).value!;
    expect(state.comments.first.id, 999);
    expect(state.comments.first.content, '新评论');
    expect(state.sendingComment, isFalse);
  });

  test('发评论失败：列表不变并抛异常', () async {
    final repo = _FakePostDetailRepository()..failComment = true;
    final container = _container(repo);
    await container.read(postDetailControllerProvider(7).future);

    await expectLater(
      container
          .read(postDetailControllerProvider(7).notifier)
          .sendComment('会失败的评论'),
      throwsA(isA<ApiException>()),
    );

    final state = container.read(postDetailControllerProvider(7)).value!;
    expect(state.comments.length, 2);
    expect(state.sendingComment, isFalse);
  });

  test('回复评论：透传 replyTo 并追加到对应楼层回复列表', () async {
    final repo = _FakePostDetailRepository();
    final container = _container(repo);
    await container.read(postDetailControllerProvider(7).future);

    await container
        .read(postDetailControllerProvider(7).notifier)
        .sendComment(
          '这是回复',
          replyTo: const CommentReplyTarget(
            commentId: 11,
            rootId: 1,
            nickname: '回复者',
          ),
        );

    final state = container.read(postDetailControllerProvider(7)).value!;
    expect(repo.commentReplyTos, [11], reason: '接口透传被回复评论 ID');
    final root = state.comments.first;
    expect(root.id, 1, reason: '楼层位置不变，不插到列表顶部');
    expect(root.replies.length, 2);
    expect(root.replies.last.content, '这是回复');
    expect(root.replies.last.replyToNickname, '回复者');
    expect(root.replyCount, 7, reason: '回复总数 +1');
  });

  test('评论点赞乐观更新：一级评论立即翻转并 +1', () async {
    final repo = _FakePostDetailRepository();
    final container = _container(repo);
    await container.read(postDetailControllerProvider(7).future);

    await container
        .read(postDetailControllerProvider(7).notifier)
        .toggleCommentLike(1);

    final state = container.read(postDetailControllerProvider(7)).value!;
    expect(state.comments.first.liked, isTrue);
    expect(state.comments.first.likeCount, 6);
    expect(repo.commentLikeCalls, [(1, true)]);
  });

  test('回复点赞乐观更新：嵌套回复同样生效', () async {
    final repo = _FakePostDetailRepository();
    final container = _container(repo);
    await container.read(postDetailControllerProvider(7).future);

    await container
        .read(postDetailControllerProvider(7).notifier)
        .toggleCommentLike(11);

    final state = container.read(postDetailControllerProvider(7)).value!;
    final reply = state.comments.first.replies.first;
    expect(reply.liked, isTrue);
    expect(reply.likeCount, 3);
    expect(repo.commentLikeCalls, [(11, true)]);
  });

  test('评论点赞失败：回滚状态并抛异常', () async {
    final repo = _FakePostDetailRepository()..failCommentLike = true;
    final container = _container(repo);
    await container.read(postDetailControllerProvider(7).future);

    await expectLater(
      container
          .read(postDetailControllerProvider(7).notifier)
          .toggleCommentLike(1),
      throwsA(isA<ApiException>()),
    );

    final state = container.read(postDetailControllerProvider(7)).value!;
    expect(state.comments.first.liked, isFalse, reason: '失败后回滚');
    expect(state.comments.first.likeCount, 5);
  });

  test('展开楼层回复：首页去重合并且预览条数被记录', () async {
    final repo = _FakePostDetailRepository();
    final container = _container(repo);
    await container.read(postDetailControllerProvider(7).future);

    await container
        .read(postDetailControllerProvider(7).notifier)
        .toggleReplies(1);

    final state = container.read(postDetailControllerProvider(7)).value!;
    final root = state.comments.first;
    final thread = state.replyThreads[1]!;
    expect(repo.replyCursors, [null], reason: '首页无游标');
    // 首页 4 条（11-14），预览 11 与服务端去重不重复
    expect(root.replies.map((r) => r.id), [11, 12, 13, 14]);
    expect(thread.expanded, isTrue);
    expect(thread.loaded, isTrue);
    expect(thread.hasMore, isTrue);
    expect(thread.previewCount, 1, reason: '展开前预览 1 条');
  });

  test('展开更多回复：透传游标追加下一页到底', () async {
    final repo = _FakePostDetailRepository();
    final container = _container(repo);
    final notifier = container.read(postDetailControllerProvider(7).notifier);
    await container.read(postDetailControllerProvider(7).future);

    await notifier.toggleReplies(1);
    await notifier.loadMoreReplies(1);

    final state = container.read(postDetailControllerProvider(7)).value!;
    expect(repo.replyCursors, [null, '4']);
    expect(state.comments.first.replies.map((r) => r.id), [
      11, 12, 13, 14, 15, 16, //
    ]);
    expect(state.replyThreads[1]!.hasMore, isFalse);
  });

  test('收起后再展开：直接复用已加载数据不重复请求', () async {
    final repo = _FakePostDetailRepository();
    final container = _container(repo);
    final notifier = container.read(postDetailControllerProvider(7).notifier);
    await container.read(postDetailControllerProvider(7).future);

    await notifier.toggleReplies(1); // 展开（请求首页）
    await notifier.toggleReplies(1); // 收起
    var state = container.read(postDetailControllerProvider(7)).value!;
    expect(state.replyThreads[1]!.expanded, isFalse);
    expect(state.comments.first.replies.length, 4, reason: '数据保留，收起仅影响展示');

    await notifier.toggleReplies(1); // 再展开
    state = container.read(postDetailControllerProvider(7)).value!;
    expect(state.replyThreads[1]!.expanded, isTrue);
    expect(repo.replyCursors, [null], reason: '未重复请求首页');
  });

  test('展开回复失败：记录错误并停止加载，可重试', () async {
    final repo = _FakePostDetailRepository()..failReplies = true;
    final container = _container(repo);
    final notifier = container.read(postDetailControllerProvider(7).notifier);
    await container.read(postDetailControllerProvider(7).future);

    await notifier.toggleReplies(1);

    var thread = container
        .read(postDetailControllerProvider(7))
        .value!
        .replyThreads[1]!;
    expect(thread.loading, isFalse);
    expect(thread.loaded, isFalse);
    expect(thread.error, isNotNull);

    // 恢复后重试成功
    repo.failReplies = false;
    await notifier.toggleReplies(1);
    thread = container
        .read(postDetailControllerProvider(7))
        .value!
        .replyThreads[1]!;
    expect(thread.loaded, isTrue);
    expect(thread.error, isNull);
  });
}
