import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/config/app_config.dart';
import '../../../core/network/api_exception.dart';
import '../model/software.dart';
import 'software_api.dart';

/// 软件库分页结果：页码分页，满页视为还有下一页。
class SoftwarePage {
  const SoftwarePage({required this.list, required this.hasMore});

  final List<SoftwareItem> list;
  final bool hasMore;
}

/// 软件库仓库接口；统一抛 [ApiException]。
abstract interface class SoftwareRepository {
  Future<SoftwarePage> fetchList({
    int type,
    int categoryId,
    SoftwareSort sort,
    int page,
    int size,
  });

  Future<SoftwareDetail> fetchDetail(int id);

  /// 下载解析：计下载数并返回真实链接与提取码
  Future<SoftwareDownload> resolveDownload(int id, {int versionId});

  Future<List<SoftwareCategory>> fetchCategories(int type);

  /// 我的发布（含审核状态：0 待审核 / 1 已上架 / 2 驳回 / 3 下架）
  Future<SoftwarePage> fetchMine({int page, int size});
}

class SoftwareRepositoryHttp implements SoftwareRepository {
  SoftwareRepositoryHttp(this._api);

  final SoftwareApi _api;

  @override
  Future<SoftwarePage> fetchList({
    int type = 0,
    int categoryId = 0,
    SoftwareSort sort = SoftwareSort.newest,
    int page = 1,
    int size = 20,
  }) => _guard(() async {
    final list = await _api.fetchList(
      type: type,
      categoryId: categoryId,
      sort: sort,
      page: page,
      size: size,
    );
    return SoftwarePage(list: list, hasMore: list.length >= size);
  });

  @override
  Future<SoftwareDetail> fetchDetail(int id) =>
      _guard(() => _api.fetchDetail(id));

  @override
  Future<SoftwareDownload> resolveDownload(int id, {int versionId = 0}) =>
      _guard(() => _api.resolveDownload(id, versionId: versionId));

  @override
  Future<List<SoftwareCategory>> fetchCategories(int type) =>
      _guard(() => _api.fetchCategories(type));

  @override
  Future<SoftwarePage> fetchMine({int page = 1, int size = 20}) =>
      _guard(() async {
        final list = await _api.fetchMine(page: page, size: size);
        return SoftwarePage(list: list, hasMore: list.length >= size);
      });

  Future<T> _guard<T>(Future<T> Function() action) async {
    try {
      return await action();
    } on DioException catch (e) {
      throw ApiException.fromDio(e);
    }
  }
}

/// Mock 实现：内存 26 款软件，支持筛选/排序/分页/详情/下载计数。
class SoftwareRepositoryMock implements SoftwareRepository {
  static const _appCategories = [
    SoftwareCategory(id: 1, name: '工具', type: 1),
    SoftwareCategory(id: 2, name: '影音', type: 1),
    SoftwareCategory(id: 3, name: '社交', type: 1),
    SoftwareCategory(id: 4, name: '学习', type: 1),
    SoftwareCategory(id: 5, name: '效率', type: 1),
    SoftwareCategory(id: 6, name: '美化', type: 1),
  ];
  static const _gameCategories = [
    SoftwareCategory(id: 11, name: '休闲', type: 2),
    SoftwareCategory(id: 12, name: '角色扮演', type: 2),
    SoftwareCategory(id: 13, name: '策略', type: 2),
    SoftwareCategory(id: 14, name: '动作', type: 2),
    SoftwareCategory(id: 15, name: '模拟经营', type: 2),
  ];

  static final List<SoftwareItem> _items = _generate();
  static final Map<int, int> _downloadDelta = {};

  static List<SoftwareItem> _generate() {
    const seeds = [
      ('极简笔记', '本地优先的 Markdown 笔记，支持双链与全文检索', 1, 1, ['免登录', '无广告'], '3.2.1', '18MB'),
      ('星尘播放器', '开源无损音乐播放器，支持均衡器与歌词秀', 1, 2, ['开源', '去广告'], '2.8.0', '32MB'),
      ('蓝鸟聊天', '轻量即时通讯，端到端加密私聊', 1, 3, ['加密'], '5.1.3', '56MB'),
      ('单词岛', '离线背单词，艾宾浩斯记忆曲线复习', 1, 4, ['离线可用'], '4.0.2', '85MB'),
      ('时间块', '极简时间管理，番茄钟 + 周视图统计', 1, 5, ['免登录'], '1.9.7', '12MB'),
      ('图标工坊', '安卓图标包生成器，一键替换全套图标', 1, 6, ['美化'], '2.3.0', '24MB'),
      ('文件蜂', '局域网高速传文件，手机电脑互传', 1, 1, ['免登录', '无广告'], '6.2.1', '20MB'),
      ('追剧日历', '自动追踪剧集更新，聚合多平台片单', 1, 2, ['聚合'], '3.5.4', '38MB'),
      ('口袋翻译', '离线翻译 60 种语言，拍照即译', 1, 4, ['离线可用'], '7.0.1', '120MB'),
      ('桌面宠物', '桌面互动宠物，支持自定义皮肤', 1, 6, ['皮肤'], '1.4.2', '45MB'),
      ('像素农场', '像素风模拟经营，离线也能收菜', 2, 15, ['离线可用'], '2.1.0', '156MB'),
      ('剑与远征团', '放置卡牌 RPG，破解内购版', 2, 12, ['GM 版'], '9.3.2', '890MB'),
      ('方块消除王', '经典三消休闲，无体力限制', 2, 11, ['无限体力'], '4.7.1', '98MB'),
      ('战棋纪元', '回合制战棋策略，兵种克制玩法硬核', 2, 13, ['汉化'], '3.0.5', '420MB'),
      ('影刃', '横版动作格斗，手感顺滑连招爽快', 2, 14, ['去广告'], '5.5.0', '650MB'),
      ('城市天际线掌机版', '掌上城市规划模拟，沙盒模式全解锁', 2, 15, ['全解锁'], '1.2.8', '1.2GB'),
      ('迷宫探险队', 'Roguelike 地牢探险，每局随机地图', 2, 12, ['汉化'], '2.6.3', '310MB'),
      ('合成大西瓜 Pro', '魔性合成休闲游戏，支持排行榜', 2, 11, ['免登录'], '1.8.0', '65MB'),
      ('净化大师', '一键清理后台与缓存，锁机白名单', 1, 1, ['无广告'], '4.4.4', '15MB'),
      ('电子书城', '全格式电子书阅读器，自定义排版', 1, 2, ['全格式'], '8.1.0', '42MB'),
      ('健身打卡', '徒手健身计划 + 动作视频示范', 1, 4, ['离线可用'], '2.2.9', '210MB'),
      ('壁纸引擎', '动态壁纸社区，创意工坊内容互通', 1, 6, ['创意工坊'], '3.3.1', '77MB'),
      ('塔防千层饼', '创新塔防策略，关卡编辑器 UGC', 2, 13, ['UGC'], '2.9.0', '380MB'),
      ('武侠浮生记', '文字武侠 RPG，多结局剧情分支', 2, 12, ['多结局'], '1.5.6', '95MB'),
      ('跑酷小恐龙', '休闲跑酷，皮肤全免费', 2, 11, ['全皮肤'], '3.1.2', '110MB'),
      ('极速录屏', '高帧率录屏 + 悬浮窗控制，无水印', 1, 5, ['无水印'], '5.0.3', '28MB'),
    ];
    return List.generate(seeds.length, (i) {
      final s = seeds[i];
      return SoftwareItem(
        id: 900 - i,
        name: s.$1,
        logo: 'https://picsum.photos/seed/yiora-soft-$i/144/144',
        intro: s.$2,
        type: s.$3,
        categoryId: s.$4,
        tags: s.$5,
        version: s.$6,
        size: s.$7,
        downloadCount: 98000 - i * 3517,
        commentCount: 640 - i * 21,
        createdAt: DateTime.now().subtract(Duration(hours: 6 + i * 26)),
      );
    });
  }

  @override
  Future<SoftwarePage> fetchList({
    int type = 0,
    int categoryId = 0,
    SoftwareSort sort = SoftwareSort.newest,
    int page = 1,
    int size = 20,
  }) async {
    await Future<void>.delayed(const Duration(milliseconds: 500));
    var list = _items
        .where((s) => type == 0 || s.type == type)
        .where((s) => categoryId == 0 || s.categoryId == categoryId)
        .toList();
    switch (sort) {
      case SoftwareSort.newest:
        list.sort((a, b) => b.createdAt.compareTo(a.createdAt));
      case SoftwareSort.hot:
        list.sort((a, b) => b.commentCount.compareTo(a.commentCount));
      case SoftwareSort.download:
        list.sort((a, b) => b.downloadCount.compareTo(a.downloadCount));
    }
    final start = ((page - 1) * size).clamp(0, list.length);
    final end = (start + size).clamp(0, list.length);
    return SoftwarePage(
      list: list.sublist(start, end),
      hasMore: end < list.length,
    );
  }

  @override
  Future<SoftwareDetail> fetchDetail(int id) async {
    await Future<void>.delayed(const Duration(milliseconds: 450));
    final item = _items.firstWhere(
      (s) => s.id == id,
      orElse: () => throw const ApiException(code: 40400, message: '软件不存在或已下架'),
    );
    final seed = 900 - id;
    // 前 1/3 的软件模拟带网盘提取码的下载链路
    final hasCode = id % 3 == 0;
    return SoftwareDetail(
      item: item,
      images: List.generate(
        4,
        (j) => 'https://picsum.photos/seed/yiora-soft-shot-$seed-$j/540/960',
      ),
      publisher: SoftwarePublisher(
        id: 100 + id % 6,
        nickname: ['小鱼干', 'YioraBot', '夜风', '拾光者', '阿澈', '绿萝'][id % 6],
        avatar: 'https://picsum.photos/seed/yiora-avatar-${id % 6}/100/100',
        level: 3 + id % 15,
      ),
      versions: [
        SoftwareVersion(
          id: id * 10 + 2,
          version: item.version,
          size: item.size,
          channel: ['自制', '搬运', '官方'][id % 3],
          downloadUrl: 'https://pan.yiora.dev/s/mock-$id-latest',
          extractCode: hasCode ? 'yr${id % 100}' : '',
          createdAt: item.createdAt,
        ),
        SoftwareVersion(
          id: id * 10 + 1,
          version: _previousVersion(item.version),
          size: item.size,
          channel: ['自制', '搬运', '官方'][id % 3],
          downloadUrl: 'https://pan.yiora.dev/s/mock-$id-old',
          extractCode: hasCode ? 'yr${id % 100}' : '',
          createdAt: item.createdAt.subtract(const Duration(days: 34)),
        ),
      ],
    );
  }

  static String _previousVersion(String version) {
    final parts = version.split('.');
    final patch = int.tryParse(parts.last) ?? 0;
    if (patch > 0) return [...parts.take(parts.length - 1), '${patch - 1}'].join('.');
    return '${parts.first}.0.0';
  }

  @override
  Future<SoftwareDownload> resolveDownload(int id, {int versionId = 0}) async {
    await Future<void>.delayed(const Duration(milliseconds: 400));
    final detail = await fetchDetail(id);
    final version = versionId == 0
        ? detail.versions.first
        : detail.versions.firstWhere(
            (v) => v.id == versionId,
            orElse: () =>
                throw const ApiException(code: 40400, message: '版本不存在'),
          );
    _downloadDelta[id] = (_downloadDelta[id] ?? 0) + 1;
    return SoftwareDownload(
      versionId: version.id,
      version: version.version,
      downloadUrl: version.downloadUrl,
      extractCode: version.extractCode,
    );
  }

  @override
  Future<List<SoftwareCategory>> fetchCategories(int type) async {
    await Future<void>.delayed(const Duration(milliseconds: 250));
    return switch (type) {
      1 => _appCategories,
      2 => _gameCategories,
      _ => [..._appCategories, ..._gameCategories],
    };
  }

  @override
  Future<SoftwarePage> fetchMine({int page = 1, int size = 20}) async {
    await Future<void>.delayed(const Duration(milliseconds: 450));
    if (page > 1) return const SoftwarePage(list: [], hasMore: false);
    // 演示各审核状态：待审核 / 已上架 / 驳回 / 下架
    final mine = [
      SoftwareItem(
        id: 9001,
        name: '云梦笔记（新提交）',
        logo: 'https://picsum.photos/seed/yiora-mine-0/144/144',
        intro: '刚提交的新软件，等待审核上架',
        type: 1,
        categoryId: 1,
        tags: const ['自制'],
        version: '1.0.0',
        size: '22MB',
        status: 0,
        createdAt: DateTime.now().subtract(const Duration(hours: 2)),
      ),
      _items.first,
      SoftwareItem(
        id: 9002,
        name: '极速抢票助手',
        logo: 'https://picsum.photos/seed/yiora-mine-1/144/144',
        intro: '因违反平台规范被驳回，可修改后重新提交',
        type: 1,
        categoryId: 5,
        tags: const [],
        version: '0.9.1',
        size: '17MB',
        status: 2,
        createdAt: DateTime.now().subtract(const Duration(days: 3)),
      ),
      SoftwareItem(
        id: 9003,
        name: '旧版影音盒子',
        logo: 'https://picsum.photos/seed/yiora-mine-2/144/144',
        intro: '因版权方投诉已下架',
        type: 1,
        categoryId: 2,
        tags: const [],
        version: '3.4.0',
        size: '48MB',
        status: 3,
        createdAt: DateTime.now().subtract(const Duration(days: 30)),
      ),
    ];
    return SoftwarePage(list: mine, hasMore: false);
  }
}

final softwareRepositoryProvider = Provider<SoftwareRepository>((ref) {
  if (AppConfig.useMock) return SoftwareRepositoryMock();
  return SoftwareRepositoryHttp(ref.watch(softwareApiProvider));
});
