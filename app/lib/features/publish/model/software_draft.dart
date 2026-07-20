import '../../software/model/software.dart';

/// 发软件表单草稿（对齐 server POST /software 契约，文档 3.5.2 / M3 软件库）
class SoftwareDraft {
  const SoftwareDraft({
    this.logoPath = '',
    this.imagePaths = const [],
    this.name = '',
    this.intro = '',
    this.type = 1,
    this.category,
    this.version = '',
    this.size = '',
    this.channel = '',
    this.tags = const [],
    this.downloadUrl = '',
    this.extractCode = '',
  });

  /// 本地 Logo 图路径（提交时上传换 URL）
  final String logoPath;

  /// 本地介绍图路径（3-6 张）
  final List<String> imagePaths;
  final String name;
  final String intro;

  /// 发布类型：1 应用 / 2 游戏
  final int type;

  /// 软件分类（后台配置的二级分类，服务端校验 categoryId 必须存在）
  final SoftwareCategory? category;
  final String version;
  final String size;

  /// 渠道：自制 / 搬运 / 官方
  final String channel;
  final List<String> tags;
  final String downloadUrl;

  /// 网盘提取码（选填，随下载链接下发给下载者）
  final String extractCode;

  static const int minImages = 3;
  static const int maxImages = 6;
  static const int maxTags = 5;
  static const int maxIntroLength = 1000;

  /// 必填齐全才可发布：Logo、介绍图 >=3、名字、简介、分类、版本、合法下载链接
  bool get canSubmit =>
      logoPath.isNotEmpty &&
      imagePaths.length >= minImages &&
      name.trim().isNotEmpty &&
      intro.trim().isNotEmpty &&
      category != null &&
      version.trim().isNotEmpty &&
      (downloadUrl.startsWith('http://') || downloadUrl.startsWith('https://'));
}
