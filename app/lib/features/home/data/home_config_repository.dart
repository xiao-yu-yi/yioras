import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/config/app_config.dart';
import '../../../core/network/api_client.dart';
import '../../../core/network/api_exception.dart';
import '../../../core/network/api_response.dart';
import '../model/home_config.dart';

/// 首页运营配置仓库（文档 4.5：GET /home/config）。
abstract interface class HomeConfigRepository {
  Future<HomeConfig> fetchConfig();
}

class HomeConfigRepositoryHttp implements HomeConfigRepository {
  HomeConfigRepositoryHttp(this._dio);

  final Dio _dio;

  @override
  Future<HomeConfig> fetchConfig() async {
    try {
      final resp = await _dio.get<Map<String, dynamic>>(
        '${AppConfig.apiPrefix}/home/config',
      );
      return ApiResponse.fromJson(
        resp.data!,
        (data) => HomeConfig.fromJson(data as Map<String, dynamic>),
      ).unwrap();
    } on DioException catch (e) {
      throw ApiException.fromDio(e);
    }
  }
}

/// Mock：免责声明图文卡 + 活动 Banner + 置顶精选两条。
class HomeConfigRepositoryMock implements HomeConfigRepository {
  @override
  Future<HomeConfig> fetchConfig() async {
    await Future<void>.delayed(const Duration(milliseconds: 350));
    return const HomeConfig(
      banners: [
        HomeBanner(
          id: 1,
          title: '免责声明',
          content:
              '本平台资源均来自网络收集与网友提供，仅供个人学习交流、测试使用，'
              '请在下载后 24 小时内删除，禁止非法传播、不得用于任何商业盈利目的。'
              '请不要将本平台的资源用于其他用途，所产生的后果我们概不负责；'
              '如果本帖存在的内容对您和您的利益产生损害，请立即通知我们删除处理。'
              '也请大家支持、购买正版！',
          image: 'https://picsum.photos/seed/yiora-banner-notice/640/460',
        ),
        HomeBanner(
          id: 2,
          title: '新人报到季 · 完成新手任务领忧珠',
          image: 'https://picsum.photos/seed/yiora-banner-newbie/900/460',
          linkType: 1,
          linkValue: '1000',
        ),
        HomeBanner(
          id: 3,
          title: 'Steam 夏促专题 · 折扣情报汇总',
          image: 'https://picsum.photos/seed/yiora-banner-steam/900/460',
          linkType: 3,
          linkValue: '8',
        ),
      ],
      pinnedPosts: [
        PinnedPost(postId: 1000, title: 'Bug 反馈贴'),
        PinnedPost(postId: 999, title: '夜间模式适配进度公告'),
      ],
    );
  }
}

final homeConfigRepositoryProvider = Provider<HomeConfigRepository>((ref) {
  if (AppConfig.useMock) return HomeConfigRepositoryMock();
  return HomeConfigRepositoryHttp(ref.watch(dioProvider));
});

/// 首页配置数据源（下拉刷新时 invalidate 联动重拉）
final homeConfigProvider = FutureProvider.autoDispose<HomeConfig>((ref) {
  return ref.watch(homeConfigRepositoryProvider).fetchConfig();
});
