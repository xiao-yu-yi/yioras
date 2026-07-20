import '../../feed/model/post.dart';

/// 个人主页数据栏（文档 3.8：5 项，无余额/曝光）
class ProfileStats {
  const ProfileStats({
    this.followCount = 0,
    this.fansCount = 0,
    this.likeCount = 0,
    this.postCount = 0,
    this.youzhu = 0,
  });

  final int followCount;
  final int fansCount;
  final int likeCount;
  final int postCount;

  /// 忧珠（积分）余额，仅自己可见明细入口
  final int youzhu;

  factory ProfileStats.fromJson(Map<String, dynamic> json) => ProfileStats(
    followCount: (json['followCount'] as num?)?.toInt() ?? 0,
    fansCount: (json['fansCount'] as num?)?.toInt() ?? 0,
    likeCount: (json['likeCount'] as num?)?.toInt() ?? 0,
    postCount: (json['postCount'] as num?)?.toInt() ?? 0,
    youzhu: (json['youzhu'] as num?)?.toInt() ?? 0,
  );
}

/// 帖子审核状态（对齐 post.status，仅自己可见，文档 3.8）
enum PostAuditStatus {
  pending(0, '待审核'),
  published(1, ''),
  rejected(2, '已驳回'),
  removed(3, '已下架');

  const PostAuditStatus(this.value, this.label);

  final int value;

  /// 角标文案；已发布不显示角标
  final String label;

  static PostAuditStatus fromValue(int value) => values.firstWhere(
    (s) => s.value == value,
    orElse: () => PostAuditStatus.published,
  );
}

/// 我发布的帖子（含审核状态标记）
class MyPost {
  const MyPost({required this.post, required this.auditStatus});

  final Post post;
  final PostAuditStatus auditStatus;

  factory MyPost.fromJson(Map<String, dynamic> json) => MyPost(
    post: Post.fromJson(json),
    auditStatus: PostAuditStatus.fromValue(
      (json['auditStatus'] as num?)?.toInt() ?? 1,
    ),
  );
}

/// 足迹项：浏览过的帖子 + 浏览时间
class Footprint {
  const Footprint({required this.post, required this.viewedAt});

  final Post post;
  final DateTime viewedAt;

  factory Footprint.fromJson(Map<String, dynamic> json) => Footprint(
    post: Post.fromJson(json),
    viewedAt:
        DateTime.tryParse(json['viewedAt'] as String? ?? '') ?? DateTime.now(),
  );
}
