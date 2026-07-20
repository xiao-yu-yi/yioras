import '../../circle/model/circle.dart';

/// 发动态草稿（文档 3.5.1）。
/// M2 骨架期草稿保存在内存（App 存活期内有效），本地持久化随缓存层引入。
class PostDraft {
  const PostDraft({
    this.title = '',
    this.content = '',
    this.imagePaths = const [],
    this.circle,
    this.topics = const [],
    this.paidPrice = 0,
    this.paidContent = '',
  });

  /// 标题 ≤30 字，选填
  final String title;

  /// 正文（正文与图片至少其一；付费帖时为免费摘要段）
  final String content;

  /// 本地图片路径 0-9 张
  final List<String> imagePaths;

  /// 圈子：发布必选
  final Circle? circle;

  /// 话题 ≤5 个
  final List<String> topics;

  /// 忧珠付费解锁价格，>0 开启付费查看
  final int paidPrice;

  /// 付费全文段（paidPrice>0 时必填）
  final String paidContent;

  bool get isPaid => paidPrice > 0;

  bool get isEmpty =>
      title.isEmpty &&
      content.isEmpty &&
      imagePaths.isEmpty &&
      topics.isEmpty &&
      paidContent.isEmpty;

  static const int maxTitleLength = 30;
  static const int maxImages = 9;
  static const int maxTopics = 5;
  static const int maxPaidPrice = 999;

  /// 草稿持久化序列化（图片存本地路径，恢复时文件可能已被系统清理，UI 有兜底）
  Map<String, dynamic> toJson() => {
    'title': title,
    'content': content,
    'imagePaths': imagePaths,
    'circle': ?circle?.toJson(),
    'topics': topics,
    'paidPrice': paidPrice,
    'paidContent': paidContent,
  };

  factory PostDraft.fromJson(Map<String, dynamic> json) => PostDraft(
    title: json['title'] as String? ?? '',
    content: json['content'] as String? ?? '',
    imagePaths: (json['imagePaths'] as List<dynamic>? ?? const [])
        .map((e) => e as String)
        .toList(),
    circle: json['circle'] == null
        ? null
        : Circle.fromJson(json['circle'] as Map<String, dynamic>),
    topics: (json['topics'] as List<dynamic>? ?? const [])
        .map((e) => e as String)
        .toList(),
    paidPrice: (json['paidPrice'] as num?)?.toInt() ?? 0,
    paidContent: json['paidContent'] as String? ?? '',
  );
}
