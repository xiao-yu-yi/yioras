import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/config/app_config.dart';
import '../../../core/network/api_client.dart';
import '../../../core/network/api_exception.dart';
import '../../../core/network/api_response.dart';
import '../../feed/data/feed_repository.dart';
import '../model/profile_models.dart';

/// 个人中心仓库接口；统一抛 [ApiException]。
/// M2 骨架期作品/足迹一次拉取（≤50 条），分页随数据量增长再加。
abstract interface class ProfileRepository {
  Future<ProfileStats> fetchStats();

  Future<List<MyPost>> fetchMyPosts();

  Future<List<Footprint>> fetchFootprints();

  Future<void> clearFootprints();

  /// 上传头像，返回可访问 URL
  Future<String> uploadAvatar(String filePath);

  /// 更新资料（性别/生日随编辑页扩展再加）
  Future<void> updateProfile({
    required String nickname,
    required String signature,
    String? avatar,
  });

  /// 注销账号（文档 3.1 应用商店合规必备；服务端置 status=已注销）
  Future<void> deactivateAccount();
}

class ProfileRepositoryHttp implements ProfileRepository {
  ProfileRepositoryHttp(this._dio);

  final Dio _dio;

  @override
  Future<ProfileStats> fetchStats() => _guard(() async {
    final resp = await _dio.get<Map<String, dynamic>>(
      '${AppConfig.apiPrefix}/users/me/stats',
    );
    return ApiResponse.fromJson(
      resp.data!,
      (data) => ProfileStats.fromJson(data as Map<String, dynamic>),
    ).unwrap();
  });

  @override
  Future<List<MyPost>> fetchMyPosts() => _guard(() async {
    final resp = await _dio.get<Map<String, dynamic>>(
      '${AppConfig.apiPrefix}/users/me/posts',
    );
    return ApiResponse.fromJson(
      resp.data!,
      (data) => ((data as Map<String, dynamic>)['list'] as List<dynamic>)
          .map((e) => MyPost.fromJson(e as Map<String, dynamic>))
          .toList(),
    ).unwrap();
  });

  @override
  Future<List<Footprint>> fetchFootprints() => _guard(() async {
    final resp = await _dio.get<Map<String, dynamic>>(
      '${AppConfig.apiPrefix}/users/me/footprints',
    );
    return ApiResponse.fromJson(
      resp.data!,
      (data) => ((data as Map<String, dynamic>)['list'] as List<dynamic>)
          .map((e) => Footprint.fromJson(e as Map<String, dynamic>))
          .toList(),
    ).unwrap();
  });

  @override
  Future<void> clearFootprints() => _guard(() async {
    final resp = await _dio.delete<Map<String, dynamic>>(
      '${AppConfig.apiPrefix}/users/me/footprints',
    );
    ApiResponse.fromJson(resp.data!, (_) => null).unwrap();
  });

  @override
  Future<String> uploadAvatar(String filePath) => _guard(() async {
    final form = FormData.fromMap({
      'file': await MultipartFile.fromFile(filePath),
    });
    final resp = await _dio.post<Map<String, dynamic>>(
      '${AppConfig.apiPrefix}/upload/image',
      data: form,
    );
    return ApiResponse.fromJson(
      resp.data!,
      (data) => (data as Map<String, dynamic>)['url'] as String,
    ).unwrap();
  });

  @override
  Future<void> updateProfile({
    required String nickname,
    required String signature,
    String? avatar,
  }) => _guard(() async {
    final resp = await _dio.put<Map<String, dynamic>>(
      '${AppConfig.apiPrefix}/users/me',
      data: {'nickname': nickname, 'signature': signature, 'avatar': ?avatar},
    );
    ApiResponse.fromJson(resp.data!, (_) => null).unwrap();
  });

  @override
  Future<void> deactivateAccount() => _guard(() async {
    final resp = await _dio.post<Map<String, dynamic>>(
      '${AppConfig.apiPrefix}/users/me/deactivate',
    );
    ApiResponse.fromJson(resp.data!, (_) => null).unwrap();
  });

  Future<T> _guard<T>(Future<T> Function() action) async {
    try {
      return await action();
    } on DioException catch (e) {
      throw ApiException.fromDio(e);
    }
  }
}

/// Mock 实现：作品复用推荐流前几条并混入审核状态；足迹取中段并可清空。
class ProfileRepositoryMock implements ProfileRepository {
  ProfileRepositoryMock({required this._feedRepository});

  final FeedRepository _feedRepository;

  /// 会话内清空足迹的标记
  static bool _footprintsCleared = false;

  @override
  Future<ProfileStats> fetchStats() async {
    await Future<void>.delayed(const Duration(milliseconds: 400));
    return const ProfileStats(
      followCount: 128,
      fansCount: 2049,
      likeCount: 8321,
      postCount: 46,
      youzhu: 1350,
    );
  }

  @override
  Future<List<MyPost>> fetchMyPosts() async {
    final page = await _feedRepository.fetchRecommend(size: 8);
    return [
      for (var i = 0; i < page.list.length; i++)
        MyPost(
          post: page.list[i],
          auditStatus: switch (i) {
            0 => PostAuditStatus.pending,
            3 => PostAuditStatus.rejected,
            _ => PostAuditStatus.published,
          },
        ),
    ];
  }

  @override
  Future<List<Footprint>> fetchFootprints() async {
    if (_footprintsCleared) return const [];
    final page = await _feedRepository.fetchRecommend(size: 40);
    final slice = page.list.skip(10).take(12).toList();
    return [
      for (var i = 0; i < slice.length; i++)
        Footprint(
          post: slice[i],
          viewedAt: DateTime.now().subtract(Duration(hours: 2 + i * 7)),
        ),
    ];
  }

  @override
  Future<void> clearFootprints() async {
    await Future<void>.delayed(const Duration(milliseconds: 300));
    _footprintsCleared = true;
  }

  @override
  Future<String> uploadAvatar(String filePath) async {
    // 模拟上传耗时并返回随机新头像 URL
    await Future<void>.delayed(const Duration(milliseconds: 800));
    final seed = DateTime.now().millisecondsSinceEpoch % 1000;
    return 'https://picsum.photos/seed/yiora-new-avatar-$seed/200/200';
  }

  @override
  Future<void> updateProfile({
    required String nickname,
    required String signature,
    String? avatar,
  }) => Future<void>.delayed(const Duration(milliseconds: 500));

  @override
  Future<void> deactivateAccount() =>
      Future<void>.delayed(const Duration(milliseconds: 800));
}

final profileRepositoryProvider = Provider<ProfileRepository>((ref) {
  if (AppConfig.useMock) {
    return ProfileRepositoryMock(
      feedRepository: ref.watch(feedRepositoryProvider),
    );
  }
  return ProfileRepositoryHttp(ref.watch(dioProvider));
});

final profileStatsProvider = FutureProvider.autoDispose<ProfileStats>((ref) {
  return ref.watch(profileRepositoryProvider).fetchStats();
});

final myPostsProvider = FutureProvider.autoDispose<List<MyPost>>((ref) {
  return ref.watch(profileRepositoryProvider).fetchMyPosts();
});

final footprintsProvider = FutureProvider.autoDispose<List<Footprint>>((ref) {
  return ref.watch(profileRepositoryProvider).fetchFootprints();
});
