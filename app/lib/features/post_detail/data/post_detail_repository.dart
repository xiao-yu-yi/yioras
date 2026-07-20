import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/config/app_config.dart';
import '../../../core/network/api_exception.dart';
import '../../feed/data/feed_repository.dart';
import '../../feed/model/post.dart';
import '../../growth/data/mock_wallet.dart';
import '../model/post_detail.dart';
import 'post_detail_api.dart';

/// 帖子详情仓库接口；统一抛 [ApiException]。
abstract interface class PostDetailRepository {
  Future<PostDetail> fetchDetail(int postId);

  Future<CommentPage> fetchComments(int postId, {String? cursor, int size});

  Future<void> setLike(int postId, {required bool like});

  Future<void> setFavorite(int postId, {required bool favorite});

  Future<void> setCommentLike(int commentId, {required bool like});

  Future<CommentPage> fetchReplies(int commentId, {String? cursor, int size});

  Future<Comment> createComment(
    int postId, {
    required String content,
    int? replyTo,
  });

  /// 忧珠解锁付费段（文档 3.9 付费帖解锁）
  Future<UnlockResult> unlockPost(int postId);
}

class PostDetailRepositoryHttp implements PostDetailRepository {
  PostDetailRepositoryHttp(this._api);

  final PostDetailApi _api;

  @override
  Future<PostDetail> fetchDetail(int postId) =>
      _guard(() => _api.fetchDetail(postId));

  @override
  Future<CommentPage> fetchComments(
    int postId, {
    String? cursor,
    int size = 20,
  }) => _guard(() => _api.fetchComments(postId, cursor: cursor, size: size));

  @override
  Future<void> setLike(int postId, {required bool like}) =>
      _guard(() => _api.setLike(postId, like: like));

  @override
  Future<void> setFavorite(int postId, {required bool favorite}) =>
      _guard(() => _api.setFavorite(postId, favorite: favorite));

  @override
  Future<void> setCommentLike(int commentId, {required bool like}) =>
      _guard(() => _api.setCommentLike(commentId, like: like));

  @override
  Future<CommentPage> fetchReplies(
    int commentId, {
    String? cursor,
    int size = 10,
  }) => _guard(() => _api.fetchReplies(commentId, cursor: cursor, size: size));

  @override
  Future<Comment> createComment(
    int postId, {
    required String content,
    int? replyTo,
  }) => _guard(
    () => _api.createComment(postId, content: content, replyTo: replyTo),
  );

  @override
  Future<UnlockResult> unlockPost(int postId) =>
      _guard(() => _api.unlockPost(postId));

  Future<T> _guard<T>(Future<T> Function() action) async {
    try {
      return await action();
    } on DioException catch (e) {
      throw ApiException.fromDio(e);
    }
  }
}

/// Mock 实现：详情复用推荐流数据；评论/点赞/收藏在内存生成与记录。
class PostDetailRepositoryMock implements PostDetailRepository {
  PostDetailRepositoryMock({required this._feedRepository});

  final FeedRepository _feedRepository;

  /// 会话内点赞/收藏状态（postId 集合）
  static final Set<int> _liked = {};
  static final Set<int> _favorited = {};

  /// 会话内评论点赞状态（commentId 集合）
  static final Set<int> _commentLiked = {};
  static int _nextCommentId = 90000;

  static const _commenters = [
    PostAuthor(id: 201, nickname: '路过的风', level: 5),
    PostAuthor(id: 202, nickname: '喵呜', level: 8, badge: '达人'),
    PostAuthor(id: 203, nickname: '深夜码农', level: 11),
    PostAuthor(id: 204, nickname: '柚子茶', level: 2),
  ];
  static const _texts = [
    '沙发！支持一下楼主',
    '写得很详细，收藏了慢慢看',
    '同款问题 +1，蹲一个后续',
    '感谢分享，正好用得上',
    '这个思路不错，学习了',
    '前排围观，顺便问下配置要求高吗？',
  ];

  @override
  Future<PostDetail> fetchDetail(int postId) async {
    await Future<void>.delayed(const Duration(milliseconds: 450));
    final page = await _feedRepository.fetchRecommend(size: 100);
    var post = page.list.where((p) => p.id == postId).firstOrNull;
    if (post == null) {
      throw const ApiException(code: 40400, message: '帖子不存在或已删除');
    }
    // 会话内已解锁的付费帖：详情下发付费全文
    if (post.isPaid && _unlocked.contains(postId)) {
      post = post.copyWith(unlocked: true, paidContent: _mockPaidContent);
    }
    return PostDetail(
      post: post,
      liked: _liked.contains(postId),
      favorited: _favorited.contains(postId),
    );
  }

  /// 首楼的楼中楼总数（前 2 条作为预览，其余展开分页拉取）
  static const int _firstFloorReplyTotal = 6;

  static const _replyTexts = [
    '楼上说得对',
    '学到了学到了',
    '插个眼，回头细看',
    '这个问题我也遇到过，重启就好了',
    '附议，希望官方看到',
    '收藏了，感谢整理',
  ];

  /// 首楼第 [index] 条楼中楼（确定性生成，点赞态读会话集合）
  Comment _firstFloorReply(int postId, int index) {
    final rootAuthor = _commenters[postId % _commenters.length];
    final id = postId * 100 + 80 + index;
    return Comment(
      id: id,
      author: _commenters[(postId + 2 + index) % _commenters.length],
      content: _replyTexts[index % _replyTexts.length],
      replyToNickname: rootAuthor.nickname,
      liked: _commentLiked.contains(id),
      createdAt: DateTime.now().subtract(Duration(minutes: 40 - index * 5)),
    );
  }

  @override
  Future<CommentPage> fetchComments(
    int postId, {
    String? cursor,
    int size = 20,
  }) async {
    await Future<void>.delayed(const Duration(milliseconds: 500));
    // 按帖子 ID 生成固定的 8 条一级评论，第 1 条带 2 条回复预览（共 6 条可展开）
    final all = List.generate(8, (i) {
      final author = _commenters[(postId + i) % _commenters.length];
      final id = postId * 100 + i;
      return Comment(
        id: id,
        author: author,
        content: _texts[(postId + i) % _texts.length],
        createdAt: DateTime.now().subtract(Duration(hours: 1 + i * 3)),
        likeCount: (17 * (i + postId)) % 90,
        liked: _commentLiked.contains(id),
        replyCount: i == 0 ? _firstFloorReplyTotal : 0,
        replies: i == 0
            ? [_firstFloorReply(postId, 0), _firstFloorReply(postId, 1)]
            : const [],
      );
    });
    final offset = int.tryParse(cursor ?? '0') ?? 0;
    final end = (offset + size).clamp(0, all.length);
    final hasMore = end < all.length;
    return CommentPage(
      list: all.sublist(offset.clamp(0, all.length), end),
      nextCursor: hasMore ? '$end' : null,
      hasMore: hasMore,
    );
  }

  @override
  Future<void> setLike(int postId, {required bool like}) async {
    await Future<void>.delayed(const Duration(milliseconds: 300));
    like ? _liked.add(postId) : _liked.remove(postId);
  }

  @override
  Future<void> setFavorite(int postId, {required bool favorite}) async {
    await Future<void>.delayed(const Duration(milliseconds: 300));
    favorite ? _favorited.add(postId) : _favorited.remove(postId);
  }

  @override
  Future<void> setCommentLike(int commentId, {required bool like}) async {
    await Future<void>.delayed(const Duration(milliseconds: 300));
    like ? _commentLiked.add(commentId) : _commentLiked.remove(commentId);
  }

  @override
  Future<CommentPage> fetchReplies(
    int commentId, {
    String? cursor,
    int size = 10,
  }) async {
    await Future<void>.delayed(const Duration(milliseconds: 450));
    // 仅首楼（id 尾数为 0）有楼中楼数据，其余楼层返回空
    if (commentId % 100 != 0) {
      return const CommentPage(list: [], nextCursor: null, hasMore: false);
    }
    final postId = commentId ~/ 100;
    final all = List.generate(
      _firstFloorReplyTotal,
      (i) => _firstFloorReply(postId, i),
    );
    final offset = int.tryParse(cursor ?? '0') ?? 0;
    final end = (offset + size).clamp(0, all.length);
    final hasMore = end < all.length;
    return CommentPage(
      list: all.sublist(offset.clamp(0, all.length), end),
      nextCursor: hasMore ? '$end' : null,
      hasMore: hasMore,
    );
  }

  @override
  Future<Comment> createComment(
    int postId, {
    required String content,
    int? replyTo,
  }) async {
    await Future<void>.delayed(const Duration(milliseconds: 500));
    return Comment(
      id: _nextCommentId++,
      author: const PostAuthor(id: 101215, nickname: '我', level: 3),
      content: content,
      createdAt: DateTime.now(),
    );
  }

  /// 会话内已解锁的付费帖
  static final Set<int> _unlocked = {};

  @override
  Future<UnlockResult> unlockPost(int postId) async {
    await Future<void>.delayed(const Duration(milliseconds: 550));
    final detail = await fetchDetail(postId);
    final post = detail.post;
    if (!post.isPaid) {
      throw const ApiException(code: 40001, message: '该帖无需解锁');
    }
    if (!_unlocked.add(postId)) {
      throw const ApiException(code: 42900, message: '已解锁过该帖');
    }
    if (MockYouzhuWallet.balance < post.paidPrice) {
      _unlocked.remove(postId);
      throw const ApiException(code: 40300, message: '忧珠余额不足，去任务中心赚一点吧');
    }
    MockYouzhuWallet.apply(
      bizType: 6,
      amount: -post.paidPrice,
      remark: '解锁付费帖「${post.title.isNotEmpty ? post.title : '无标题'}」',
    );
    return UnlockResult(
      paidContent: _mockPaidContent,
      balance: MockYouzhuWallet.balance,
    );
  }

  static const _mockPaidContent =
      '【付费段全文】这里是解锁后可见的完整干货：\n'
      '1. 完整折扣预测表（含历史低价对照与建议入手价位）；\n'
      '2. 三个只在小圈子流传的比价站与提醒机器人配置方法；\n'
      '3. 双币种支付的手续费规避技巧，实测每单省 4-7 元。\n'
      '感谢支持，有问题评论区交流～';
}

final postDetailRepositoryProvider = Provider<PostDetailRepository>((ref) {
  if (AppConfig.useMock) {
    return PostDetailRepositoryMock(
      feedRepository: ref.watch(feedRepositoryProvider),
    );
  }
  return PostDetailRepositoryHttp(ref.watch(postDetailApiProvider));
});
