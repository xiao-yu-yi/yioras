import '../../feed/model/post.dart';

/// 帖子详情（文档 3.3）：完整正文 + 当前用户互动状态。
class PostDetail {
  const PostDetail({
    required this.post,
    this.liked = false,
    this.favorited = false,
  });

  final Post post;

  /// 当前用户是否已点赞/收藏（服务端按登录态下发）
  final bool liked;
  final bool favorited;

  factory PostDetail.fromJson(Map<String, dynamic> json) => PostDetail(
    post: Post.fromJson(json),
    liked: json['liked'] as bool? ?? false,
    favorited: json['favorited'] as bool? ?? false,
  );

  PostDetail copyWith({Post? post, bool? favorited}) => PostDetail(
    post: post ?? this.post,
    liked: liked,
    favorited: favorited ?? this.favorited,
  );
}

/// 付费解锁结果（对齐 server UnlockResp）
class UnlockResult {
  const UnlockResult({required this.paidContent, required this.balance});

  final String paidContent;
  final int balance;

  factory UnlockResult.fromJson(Map<String, dynamic> json) => UnlockResult(
    paidContent: json['paidContent'] as String? ?? '',
    balance: (json['balance'] as num?)?.toInt() ?? 0,
  );
}

/// 评论（两级，对齐 comment 表）：一级评论可挂回复列表。
class Comment {
  const Comment({
    required this.id,
    required this.author,
    required this.content,
    required this.createdAt,
    this.likeCount = 0,
    this.liked = false,
    this.replyCount = 0,
    this.replyToNickname = '',
    this.replies = const [],
  });

  final int id;
  final PostAuthor author;
  final String content;
  final DateTime createdAt;
  final int likeCount;

  /// 当前用户是否已点赞（服务端按登录态下发）
  final bool liked;

  /// 仅一级评论维护：回复总数（用于「共 N 条回复」）
  final int replyCount;

  /// 回复目标昵称（二级评论「回复@xx」展示，空串表示直接回帖）
  final String replyToNickname;

  /// 一级评论附带的回复预览（服务端下发前几条）
  final List<Comment> replies;

  factory Comment.fromJson(Map<String, dynamic> json) => Comment(
    id: (json['id'] as num).toInt(),
    author: PostAuthor.fromJson(json['author'] as Map<String, dynamic>),
    content: json['content'] as String? ?? '',
    createdAt:
        DateTime.tryParse(json['createdAt'] as String? ?? '') ?? DateTime.now(),
    likeCount: (json['likeCount'] as num?)?.toInt() ?? 0,
    liked: json['liked'] as bool? ?? false,
    replyCount: (json['replyCount'] as num?)?.toInt() ?? 0,
    replyToNickname: json['replyToNickname'] as String? ?? '',
    replies: (json['replies'] as List<dynamic>? ?? const [])
        .map((e) => Comment.fromJson(e as Map<String, dynamic>))
        .toList(),
  );

  /// 乐观更新用：仅覆盖互动/回复相关字段
  Comment copyWith({
    int? likeCount,
    bool? liked,
    int? replyCount,
    String? replyToNickname,
    List<Comment>? replies,
  }) => Comment(
    id: id,
    author: author,
    content: content,
    createdAt: createdAt,
    likeCount: likeCount ?? this.likeCount,
    liked: liked ?? this.liked,
    replyCount: replyCount ?? this.replyCount,
    replyToNickname: replyToNickname ?? this.replyToNickname,
    replies: replies ?? this.replies,
  );
}

/// 评论游标分页
class CommentPage {
  const CommentPage({
    required this.list,
    required this.nextCursor,
    required this.hasMore,
  });

  final List<Comment> list;
  final String? nextCursor;
  final bool hasMore;

  factory CommentPage.fromJson(Map<String, dynamic> json) => CommentPage(
    list: (json['list'] as List<dynamic>? ?? const [])
        .map((e) => Comment.fromJson(e as Map<String, dynamic>))
        .toList(),
    nextCursor: json['nextCursor'] as String?,
    hasMore: json['hasMore'] as bool? ?? false,
  );
}
