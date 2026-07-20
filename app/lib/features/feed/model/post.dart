/// 帖子作者摘要（信息流卡片所需字段，对齐 user 表）
class PostAuthor {
  const PostAuthor({
    required this.id,
    required this.nickname,
    this.avatar = '',
    this.level = 0,
    this.badge = '',
  });

  final int id;
  final String nickname;
  final String avatar;
  final int level;

  /// 头衔徽章文案（官方/开发者/圈主等），空串表示无
  final String badge;

  factory PostAuthor.fromJson(Map<String, dynamic> json) => PostAuthor(
    id: (json['id'] as num).toInt(),
    nickname: json['nickname'] as String? ?? '',
    avatar: json['avatar'] as String? ?? '',
    level: (json['level'] as num?)?.toInt() ?? 0,
    badge: json['badge'] as String? ?? '',
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'nickname': nickname,
    'avatar': avatar,
    'level': level,
    'badge': badge,
  };
}

/// 推荐流帖子（对齐 post 表 + 文档 3.2 帖子卡片字段）
class Post {
  const Post({
    required this.id,
    required this.author,
    required this.content,
    this.title = '',
    this.circleName = '',
    this.images = const [],
    this.topics = const [],
    this.viewCount = 0,
    this.likeCount = 0,
    this.commentCount = 0,
    this.isTop = false,
    required this.createdAt,
  });

  final int id;
  final PostAuthor author;
  final String title;
  final String content;
  final String circleName;
  final List<String> images;
  final List<String> topics;
  final int viewCount;
  final int likeCount;
  final int commentCount;

  /// 运营置顶精选
  final bool isTop;
  final DateTime createdAt;

  factory Post.fromJson(Map<String, dynamic> json) => Post(
    id: (json['id'] as num).toInt(),
    author: PostAuthor.fromJson(json['author'] as Map<String, dynamic>),
    title: json['title'] as String? ?? '',
    content: json['content'] as String? ?? '',
    circleName: json['circleName'] as String? ?? '',
    images: (json['images'] as List<dynamic>? ?? const [])
        .map((e) => e as String)
        .toList(),
    topics: (json['topics'] as List<dynamic>? ?? const [])
        .map((e) => e as String)
        .toList(),
    viewCount: (json['viewCount'] as num?)?.toInt() ?? 0,
    likeCount: (json['likeCount'] as num?)?.toInt() ?? 0,
    commentCount: (json['commentCount'] as num?)?.toInt() ?? 0,
    isTop: json['isTop'] as bool? ?? false,
    createdAt:
        DateTime.tryParse(json['createdAt'] as String? ?? '') ?? DateTime.now(),
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'author': author.toJson(),
    'title': title,
    'content': content,
    'circleName': circleName,
    'images': images,
    'topics': topics,
    'viewCount': viewCount,
    'likeCount': likeCount,
    'commentCount': commentCount,
    'isTop': isTop,
    'createdAt': createdAt.toIso8601String(),
  };
}

/// 游标分页响应：`{list, nextCursor, hasMore}`
class PostPage {
  const PostPage({
    required this.list,
    required this.nextCursor,
    required this.hasMore,
  });

  final List<Post> list;
  final String? nextCursor;
  final bool hasMore;

  factory PostPage.fromJson(Map<String, dynamic> json) => PostPage(
    list: (json['list'] as List<dynamic>? ?? const [])
        .map((e) => Post.fromJson(e as Map<String, dynamic>))
        .toList(),
    nextCursor: json['nextCursor'] as String?,
    hasMore: json['hasMore'] as bool? ?? false,
  );
}
