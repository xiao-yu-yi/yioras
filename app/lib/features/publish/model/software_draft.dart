/// 发软件表单草稿（对齐 server POST /software 契约，文档 3.5.2 / M3 软件库）
class SoftwareDraft {
  const SoftwareDraft({
    this.logoPath = '',
    this.imagePaths = const [],
    this.name = '',
    this.intro = '',
    this.type = 1,
    this.category = '',
    this.version = '',
    this.size = '',
    this.channel = '',
    this.tags = const [],
    this.downloadUrl = '',
  });

  /// 本地 Logo 图路径（提交时上传换 URL）
  final String logoPath;

  /// 本地介绍图路径（3-6 张）
  final List<String> imagePaths;
  final String name;
  final String intro;

  /// 发布类型：1 应用 / 2 游戏
  final int type;

  /// 软件分类（分类名，服务端映射 categoryId）
  final String category;
  final String version;
  final String size;

  /// 渠道：自制 / 搬运 / 官方
  final String channel;
  final List<String> tags;
  final String downloadUrl;

  static const int minImages = 3;
  static const int maxImages = 6;
  static const int maxTags = 5;
  static const int maxIntroLength = 1000;

  /// 必填齐全才可发布：Logo、介绍图 >=3、名字、版本、合法下载链接
  bool get canSubmit =>
      logoPath.isNotEmpty &&
      imagePaths.length >= minImages &&
      name.trim().isNotEmpty &&
      version.trim().isNotEmpty &&
      (downloadUrl.startsWith('http://') || downloadUrl.startsWith('https://'));
}
