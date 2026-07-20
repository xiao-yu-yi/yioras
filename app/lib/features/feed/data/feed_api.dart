import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/config/app_config.dart';
import '../../../core/network/api_client.dart';
import '../../../core/network/api_response.dart';
import '../model/post.dart';

/// 内容域 API：GET /posts?tab=recommend 推荐信息流分页（文档 4.5）。
class FeedApi {
  FeedApi(this._dio);

  final Dio _dio;

  Future<PostPage> fetchRecommend({String? cursor, int size = 20}) async {
    final resp = await _dio.get<Map<String, dynamic>>(
      '${AppConfig.apiPrefix}/posts',
      queryParameters: {'tab': 'recommend', 'cursor': ?cursor, 'size': size},
    );
    return ApiResponse.fromJson(
      resp.data!,
      (data) => PostPage.fromJson(data as Map<String, dynamic>),
    ).unwrap();
  }
}

final feedApiProvider = Provider<FeedApi>((ref) {
  return FeedApi(ref.watch(dioProvider));
});
