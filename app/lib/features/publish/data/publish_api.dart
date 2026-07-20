import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/config/app_config.dart';
import '../../../core/network/api_client.dart';
import '../../../core/network/api_response.dart';

/// 发布域 API（文档 4.5：POST /posts；图片先传 OSS 网关拿 URL）。
class PublishApi {
  PublishApi(this._dio);

  final Dio _dio;

  /// POST /upload/image 表单上传单张图片，返回可访问 URL。
  /// 后端就绪后可切换为 OSS 直传 + 签名 URL，这里保持接口不变。
  Future<String> uploadImage(String filePath) async {
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
  }

  /// POST /posts 发动态（发布后进入审核流，状态=待审核）
  Future<void> createPost({
    required String title,
    required String content,
    required int circleId,
    required List<String> topics,
    required List<String> imageUrls,
  }) async {
    final resp = await _dio.post<Map<String, dynamic>>(
      '${AppConfig.apiPrefix}/posts',
      data: {
        'title': title,
        'content': content,
        'circleId': circleId,
        'topics': topics,
        'images': imageUrls,
      },
    );
    ApiResponse.fromJson(resp.data!, (_) => null).unwrap();
  }

  /// GET /topics/hot 热门话题（话题选择器数据源）
  Future<List<String>> fetchHotTopics() async {
    final resp = await _dio.get<Map<String, dynamic>>(
      '${AppConfig.apiPrefix}/topics/hot',
    );
    return ApiResponse.fromJson(
      resp.data!,
      (data) => ((data as Map<String, dynamic>)['list'] as List<dynamic>)
          .map((e) => e as String)
          .toList(),
    ).unwrap();
  }
}

final publishApiProvider = Provider<PublishApi>((ref) {
  return PublishApi(ref.watch(dioProvider));
});
