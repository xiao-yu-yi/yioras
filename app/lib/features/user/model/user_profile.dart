import '../../feed/model/post.dart';

/// 他人主页资料（文档 3.8 个人主页自己/他人通用；他人不下发忧珠）
class UserProfile {
  const UserProfile({
    required this.id,
    required this.displayNo,
    required this.nickname,
    this.avatar = '',
    this.cover = '',
    this.signature = '',
    this.level = 0,
    this.badge = '',
    this.followCount = 0,
    this.fansCount = 0,
    this.likeCount = 0,
    this.postCount = 0,
    this.following = false,
    this.posts = const [],
  });

  final int id;
  final String displayNo;
  final String nickname;
  final String avatar;
  final String cover;
  final String signature;
  final int level;
  final String badge;
  final int followCount;
  final int fansCount;
  final int likeCount;
  final int postCount;

  /// 当前登录用户是否已关注 TA
  final bool following;

  /// TA 的公开帖子（发布作品 Tab）
  final List<Post> posts;

  factory UserProfile.fromJson(Map<String, dynamic> json) => UserProfile(
    id: (json['id'] as num).toInt(),
    displayNo: json['displayNo'] as String? ?? '',
    nickname: json['nickname'] as String? ?? '',
    avatar: json['avatar'] as String? ?? '',
    cover: json['cover'] as String? ?? '',
    signature: json['signature'] as String? ?? '',
    level: (json['level'] as num?)?.toInt() ?? 0,
    badge: json['badge'] as String? ?? '',
    followCount: (json['followCount'] as num?)?.toInt() ?? 0,
    fansCount: (json['fansCount'] as num?)?.toInt() ?? 0,
    likeCount: (json['likeCount'] as num?)?.toInt() ?? 0,
    postCount: (json['postCount'] as num?)?.toInt() ?? 0,
    following: json['following'] as bool? ?? false,
    posts: (json['posts'] as List<dynamic>? ?? const [])
        .map((e) => Post.fromJson(e as Map<String, dynamic>))
        .toList(),
  );
}
