import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/config/app_config.dart';
import '../../../core/network/api_client.dart';
import '../../../core/network/api_response.dart';
import '../../feed/model/post.dart';
import '../model/circle.dart';

/// 圈子域 API（文档 4.5：GET /circles?sort=hot、POST /circles/{id}/join）。
class CircleApi {
  CircleApi(this._dio);

  final Dio _dio;

  Future<List<Circle>> fetchCircles({required CircleSort sort}) async {
    final resp = await _dio.get<Map<String, dynamic>>(
      '${AppConfig.apiPrefix}/circles',
      queryParameters: {'sort': sort.value},
    );
    return ApiResponse.fromJson(
      resp.data!,
      (data) => ((data as Map<String, dynamic>)['list'] as List<dynamic>)
          .map((e) => Circle.fromJson(e as Map<String, dynamic>))
          .toList(),
    ).unwrap();
  }

  Future<Circle> fetchCircleDetail(int id) async {
    final resp = await _dio.get<Map<String, dynamic>>(
      '${AppConfig.apiPrefix}/circles/$id',
    );
    return ApiResponse.fromJson(
      resp.data!,
      (data) => Circle.fromJson(data as Map<String, dynamic>),
    ).unwrap();
  }

  Future<void> joinCircle(int id) async {
    final resp = await _dio.post<Map<String, dynamic>>(
      '${AppConfig.apiPrefix}/circles/$id/join',
    );
    ApiResponse.fromJson(resp.data!, (_) => null).unwrap();
  }

  Future<void> quitCircle(int id) async {
    final resp = await _dio.post<Map<String, dynamic>>(
      '${AppConfig.apiPrefix}/circles/$id/quit',
    );
    ApiResponse.fromJson(resp.data!, (_) => null).unwrap();
  }

  /// 圈内帖子流（双 Tab：最新/最热，游标分页）
  Future<PostPage> fetchCirclePosts(
    int circleId, {
    CirclePostSort sort = CirclePostSort.newest,
    String? cursor,
    int size = 20,
  }) async {
    final resp = await _dio.get<Map<String, dynamic>>(
      '${AppConfig.apiPrefix}/circles/$circleId/posts',
      queryParameters: {'sort': sort.value, 'cursor': ?cursor, 'size': size},
    );
    return ApiResponse.fromJson(
      resp.data!,
      (data) => PostPage.fromJson(data as Map<String, dynamic>),
    ).unwrap();
  }
}

final circleApiProvider = Provider<CircleApi>((ref) {
  return CircleApi(ref.watch(dioProvider));
});
