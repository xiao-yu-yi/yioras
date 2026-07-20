/// 软件库领域模型（文档 3.6 / M3，对齐 server types.go 软件库契约）。
library;

/// 软件分类（GET /software/categories，发布器选择器与列表筛选共用）
class SoftwareCategory {
  const SoftwareCategory({required this.id, required this.name, this.type = 1});

  final int id;
  final String name;

  /// 1 应用 / 2 游戏
  final int type;

  factory SoftwareCategory.fromJson(Map<String, dynamic> json) =>
      SoftwareCategory(
        id: (json['id'] as num).toInt(),
        name: json['name'] as String? ?? '',
        type: (json['type'] as num?)?.toInt() ?? 1,
      );
}

/// 软件列表项（GET /software，对齐 SoftwareItem）
class SoftwareItem {
  const SoftwareItem({
    required this.id,
    required this.name,
    this.logo = '',
    this.intro = '',
    this.type = 1,
    this.categoryId = 0,
    this.tags = const [],
    this.version = '',
    this.size = '',
    this.downloadCount = 0,
    this.commentCount = 0,
    this.status = 1,
    required this.createdAt,
  });

  final int id;
  final String name;
  final String logo;
  final String intro;

  /// 1 应用 / 2 游戏
  final int type;
  final int categoryId;
  final List<String> tags;

  /// 最新已发布版本号 / 大小
  final String version;
  final String size;
  final int downloadCount;
  final int commentCount;

  /// 0 待审核 1 已上架 2 驳回 3 下架
  final int status;
  final DateTime createdAt;

  factory SoftwareItem.fromJson(Map<String, dynamic> json) => SoftwareItem(
    id: (json['id'] as num).toInt(),
    name: json['name'] as String? ?? '',
    logo: json['logo'] as String? ?? '',
    intro: json['intro'] as String? ?? '',
    type: (json['type'] as num?)?.toInt() ?? 1,
    categoryId: (json['categoryId'] as num?)?.toInt() ?? 0,
    tags: (json['tags'] as List<dynamic>? ?? const [])
        .map((e) => e as String)
        .toList(),
    version: json['version'] as String? ?? '',
    size: json['size'] as String? ?? '',
    downloadCount: (json['downloadCount'] as num?)?.toInt() ?? 0,
    commentCount: (json['commentCount'] as num?)?.toInt() ?? 0,
    status: (json['status'] as num?)?.toInt() ?? 1,
    createdAt: DateTime.fromMillisecondsSinceEpoch(
      (json['createdAt'] as num?)?.toInt() ?? 0,
    ),
  );
}

/// 软件版本（详情页历史版本列表）
class SoftwareVersion {
  const SoftwareVersion({
    required this.id,
    required this.version,
    this.size = '',
    this.channel = '',
    this.downloadUrl = '',
    this.extractCode = '',
    required this.createdAt,
  });

  final int id;
  final String version;
  final String size;
  final String channel;
  final String downloadUrl;

  /// 网盘提取码，空串表示无
  final String extractCode;
  final DateTime createdAt;

  factory SoftwareVersion.fromJson(Map<String, dynamic> json) =>
      SoftwareVersion(
        id: (json['id'] as num).toInt(),
        version: json['version'] as String? ?? '',
        size: json['size'] as String? ?? '',
        channel: json['channel'] as String? ?? '',
        downloadUrl: json['downloadUrl'] as String? ?? '',
        extractCode: json['extractCode'] as String? ?? '',
        createdAt: DateTime.fromMillisecondsSinceEpoch(
          (json['createdAt'] as num?)?.toInt() ?? 0,
        ),
      );
}

/// 发布者摘要（对齐 UserBrief：键名是 userId 而非 id）
class SoftwarePublisher {
  const SoftwarePublisher({
    required this.id,
    required this.nickname,
    this.avatar = '',
    this.level = 0,
  });

  final int id;
  final String nickname;
  final String avatar;
  final int level;

  factory SoftwarePublisher.fromJson(Map<String, dynamic> json) =>
      SoftwarePublisher(
        id: (json['userId'] as num?)?.toInt() ?? 0,
        nickname: json['nickname'] as String? ?? '',
        avatar: json['avatar'] as String? ?? '',
        level: (json['level'] as num?)?.toInt() ?? 0,
      );
}

/// 软件详情（GET /software/:id）
class SoftwareDetail {
  const SoftwareDetail({
    required this.item,
    this.images = const [],
    required this.publisher,
    this.versions = const [],
  });

  final SoftwareItem item;
  final List<String> images;
  final SoftwarePublisher publisher;
  final List<SoftwareVersion> versions;

  factory SoftwareDetail.fromJson(Map<String, dynamic> json) => SoftwareDetail(
    item: SoftwareItem.fromJson(json),
    images: (json['images'] as List<dynamic>? ?? const [])
        .map((e) => e as String)
        .toList(),
    publisher: SoftwarePublisher.fromJson(
      json['publisher'] as Map<String, dynamic>? ?? const {},
    ),
    versions: (json['versions'] as List<dynamic>? ?? const [])
        .map((e) => SoftwareVersion.fromJson(e as Map<String, dynamic>))
        .toList(),
  );
}

/// 下载解析结果（POST /software/:id/download）
class SoftwareDownload {
  const SoftwareDownload({
    required this.versionId,
    required this.version,
    required this.downloadUrl,
    this.extractCode = '',
  });

  final int versionId;
  final String version;
  final String downloadUrl;
  final String extractCode;

  factory SoftwareDownload.fromJson(Map<String, dynamic> json) =>
      SoftwareDownload(
        versionId: (json['versionId'] as num?)?.toInt() ?? 0,
        version: json['version'] as String? ?? '',
        downloadUrl: json['downloadUrl'] as String? ?? '',
        extractCode: json['extractCode'] as String? ?? '',
      );
}

/// 软件列表排序（对齐 server sort=new|hot|download）
enum SoftwareSort {
  newest('new', '最新'),
  hot('hot', '最热'),
  download('download', '下载最多');

  const SoftwareSort(this.value, this.label);

  final String value;
  final String label;
}
