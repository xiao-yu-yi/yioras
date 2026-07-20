/// 首页公告 Banner（文档 3.2：轮播图文卡，后台可配跳转）
class HomeBanner {
  const HomeBanner({
    required this.id,
    required this.title,
    this.content = '',
    this.image = '',
    this.linkType = 0,
    this.linkValue = '',
  });

  final int id;
  final String title;

  /// 图文卡正文（免责声明等长文案；纯图 Banner 为空）
  final String content;
  final String image;

  /// 0 无跳转 1 帖子 2 H5 3 圈子（对齐 banner 表）
  final int linkType;
  final String linkValue;

  factory HomeBanner.fromJson(Map<String, dynamic> json) => HomeBanner(
    id: (json['id'] as num).toInt(),
    title: json['title'] as String? ?? '',
    content: json['content'] as String? ?? '',
    image: json['image'] as String? ?? '',
    linkType: (json['linkType'] as num?)?.toInt() ?? 0,
    linkValue: json['linkValue'] as String? ?? '',
  );
}

/// 置顶精选（文档 3.2：运营置顶帖横条，支持多条轮播）
class PinnedPost {
  const PinnedPost({required this.postId, required this.title});

  final int postId;
  final String title;

  factory PinnedPost.fromJson(Map<String, dynamic> json) => PinnedPost(
    postId: (json['postId'] as num).toInt(),
    title: json['title'] as String? ?? '',
  );
}

/// 首页运营配置（GET /home/config）
class HomeConfig {
  const HomeConfig({this.banners = const [], this.pinnedPosts = const []});

  final List<HomeBanner> banners;
  final List<PinnedPost> pinnedPosts;

  factory HomeConfig.fromJson(Map<String, dynamic> json) => HomeConfig(
    banners: (json['banners'] as List<dynamic>? ?? const [])
        .map((e) => HomeBanner.fromJson(e as Map<String, dynamic>))
        .toList(),
    pinnedPosts: (json['pinnedPosts'] as List<dynamic>? ?? const [])
        .map((e) => PinnedPost.fromJson(e as Map<String, dynamic>))
        .toList(),
  );
}
