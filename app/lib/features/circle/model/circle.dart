/// 圈子（对齐 circle 表与文档 3.4）
class Circle {
  const Circle({
    required this.id,
    required this.name,
    this.icon = '',
    this.cover = '',
    this.intro = '',
    this.description = '',
    this.memberCount = 0,
    this.postCount = 0,
    this.isOfficial = false,
    this.pinned = false,
    this.joined = false,
  });

  final int id;
  final String name;
  final String icon;
  final String cover;

  /// 一句话简介（列表卡片展示）
  final String intro;

  /// 详细介绍（详情页展示）
  final String description;
  final int memberCount;
  final int postCount;

  /// 官方圈（官方公告/骗子举报等）
  final bool isOfficial;

  /// 发现页置顶角标
  final bool pinned;

  /// 当前用户是否已加入（服务端按登录态下发）
  final bool joined;

  Circle copyWith({int? memberCount, bool? joined}) => Circle(
    id: id,
    name: name,
    icon: icon,
    cover: cover,
    intro: intro,
    description: description,
    memberCount: memberCount ?? this.memberCount,
    postCount: postCount,
    isOfficial: isOfficial,
    pinned: pinned,
    joined: joined ?? this.joined,
  );

  factory Circle.fromJson(Map<String, dynamic> json) => Circle(
    id: (json['id'] as num).toInt(),
    name: json['name'] as String? ?? '',
    icon: json['icon'] as String? ?? '',
    cover: json['cover'] as String? ?? '',
    intro: json['intro'] as String? ?? '',
    description: json['description'] as String? ?? '',
    memberCount: (json['memberCount'] as num?)?.toInt() ?? 0,
    postCount: (json['postCount'] as num?)?.toInt() ?? 0,
    isOfficial: json['isOfficial'] as bool? ?? false,
    pinned: json['pinned'] as bool? ?? false,
    joined: json['joined'] as bool? ?? false,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'icon': icon,
    'cover': cover,
    'intro': intro,
    'description': description,
    'memberCount': memberCount,
    'postCount': postCount,
    'isOfficial': isOfficial,
    'pinned': pinned,
    'joined': joined,
  };
}

/// 发现圈子页排序（文档 3.4：最热 / 最新）
enum CircleSort {
  hot('hot', '最热'),
  newest('new', '最新');

  const CircleSort(this.value, this.label);

  /// 接口参数值
  final String value;

  /// 界面展示文案
  final String label;
}
