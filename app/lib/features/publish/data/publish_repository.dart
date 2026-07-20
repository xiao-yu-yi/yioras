import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/config/app_config.dart';
import '../../../core/network/api_exception.dart';
import '../model/post_draft.dart';
import 'publish_api.dart';

/// 发布仓库接口；统一抛 [ApiException]。
abstract interface class PublishRepository {
  /// 发布动态：内部完成图片上传 → 创建帖子（进入审核流）
  Future<void> publishPost(PostDraft draft);

  Future<List<String>> fetchHotTopics();
}

class PublishRepositoryHttp implements PublishRepository {
  PublishRepositoryHttp(this._api);

  final PublishApi _api;

  @override
  Future<void> publishPost(PostDraft draft) => _guard(() async {
    // 逐张上传取 URL；任一失败即中断（用户可整体重试）
    final urls = <String>[];
    for (final path in draft.imagePaths) {
      urls.add(await _api.uploadImage(path));
    }
    await _api.createPost(
      title: draft.title,
      content: draft.content,
      circleId: draft.circle!.id,
      topics: draft.topics,
      imageUrls: urls,
    );
  });

  @override
  Future<List<String>> fetchHotTopics() => _guard(_api.fetchHotTopics);

  Future<T> _guard<T>(Future<T> Function() action) async {
    try {
      return await action();
    } on DioException catch (e) {
      throw ApiException.fromDio(e);
    }
  }
}

/// Mock 实现：模拟上传与发布延迟，直接成功。
class PublishRepositoryMock implements PublishRepository {
  @override
  Future<void> publishPost(PostDraft draft) async {
    // 每张图 300ms 模拟上传 + 600ms 创建
    await Future<void>.delayed(
      Duration(milliseconds: 600 + draft.imagePaths.length * 300),
    );
  }

  @override
  Future<List<String>> fetchHotTopics() async {
    await Future<void>.delayed(const Duration(milliseconds: 300));
    return const [
      '公告',
      '内测反馈',
      'Flutter',
      '性能优化',
      '夜间模式',
      '片单',
      '夏促',
      '省钱攻略',
      '搞机日常',
      '开源推荐',
    ];
  }
}

final publishRepositoryProvider = Provider<PublishRepository>((ref) {
  if (AppConfig.useMock) return PublishRepositoryMock();
  return PublishRepositoryHttp(ref.watch(publishApiProvider));
});
