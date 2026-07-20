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
  });

  /// 标题 ≤30 字，选填
  final String title;

  /// 正文（正文与图片至少其一）
  final String content;

  /// 本地图片路径 0-9 张
  final List<String> imagePaths;

  /// 圈子：发布必选
  final Circle? circle;

  /// 话题 ≤5 个
  final List<String> topics;

  bool get isEmpty =>
      title.isEmpty && content.isEmpty && imagePaths.isEmpty && topics.isEmpty;

  static const int maxTitleLength = 30;
  static const int maxImages = 9;
  static const int maxTopics = 5;

  /// 草稿持久化序列化（图片存本地路径，恢复时文件可能已被系统清理，UI 有兜底）
  Map<String, dynamic> toJson() => {
    'title': title,
    'content': content,
    'imagePaths': imagePaths,
    'circle': ?circle?.toJson(),
    'topics': topics,
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
  );
}
