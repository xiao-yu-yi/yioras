import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/config/app_config.dart';
import '../../../core/network/api_client.dart';
import '../../../core/network/api_response.dart';
import '../model/post_detail.dart';

/// 帖子详情域 API（文档 4.5：GET /posts/{id}、POST /posts/{id}/like、POST /comments）。
class PostDetailApi {
  PostDetailApi(this._dio);

  final Dio _dio;

  Future<PostDetail> fetchDetail(int postId) async {
    final resp = await _dio.get<Map<String, dynamic>>(
      '${AppConfig.apiPrefix}/posts/$postId',
    );
    return ApiResponse.fromJson(
      resp.data!,
      (data) => PostDetail.fromJson(data as Map<String, dynamic>),
    ).unwrap();
  }

  Future<CommentPage> fetchComments(
    int postId, {
    String? cursor,
    int size = 20,
  }) async {
    final resp = await _dio.get<Map<String, dynamic>>(
      '${AppConfig.apiPrefix}/posts/$postId/comments',
      queryParameters: {'cursor': ?cursor, 'size': size},
    );
    return ApiResponse.fromJson(
      resp.data!,
      (data) => CommentPage.fromJson(data as Map<String, dynamic>),
    ).unwrap();
  }

  /// like=true 点赞，false 取消（服务端幂等）
  Future<void> setLike(int postId, {required bool like}) async {
    final resp = await _dio.post<Map<String, dynamic>>(
      '${AppConfig.apiPrefix}/posts/$postId/like',
      data: {'like': like},
    );
    ApiResponse.fromJson(resp.data!, (_) => null).unwrap();
  }

  Future<void> setFavorite(int postId, {required bool favorite}) async {
    final resp = await _dio.post<Map<String, dynamic>>(
      '${AppConfig.apiPrefix}/posts/$postId/favorite',
      data: {'favorite': favorite},
    );
    ApiResponse.fromJson(resp.data!, (_) => null).unwrap();
  }

  /// 评论点赞/取消（对齐帖子点赞语义，服务端幂等）
  Future<void> setCommentLike(int commentId, {required bool like}) async {
    final resp = await _dio.post<Map<String, dynamic>>(
      '${AppConfig.apiPrefix}/comments/$commentId/like',
      data: {'like': like},
    );
    ApiResponse.fromJson(resp.data!, (_) => null).unwrap();
  }

  /// 楼层回复全量分页（楼中楼），返回按时间正序的回复列表
  Future<CommentPage> fetchReplies(
    int commentId, {
    String? cursor,
    int size = 10,
  }) async {
    final resp = await _dio.get<Map<String, dynamic>>(
      '${AppConfig.apiPrefix}/comments/$commentId/replies',
      queryParameters: {'cursor': ?cursor, 'size': size},
    );
    return ApiResponse.fromJson(
      resp.data!,
      (data) => CommentPage.fromJson(data as Map<String, dynamic>),
    ).unwrap();
  }

  /// 发评论；replyTo 为被回复的评论 ID（0/null 表示直接回帖），返回新评论
  Future<Comment> createComment(
    int postId, {
    required String content,
    int? replyTo,
  }) async {
    final resp = await _dio.post<Map<String, dynamic>>(
      '${AppConfig.apiPrefix}/comments',
      data: {'postId': postId, 'content': content, 'replyTo': ?replyTo},
    );
    return ApiResponse.fromJson(
      resp.data!,
      (data) => Comment.fromJson(data as Map<String, dynamic>),
    ).unwrap();
  }
}

final postDetailApiProvider = Provider<PostDetailApi>((ref) {
  return PostDetailApi(ref.watch(dioProvider));
});
