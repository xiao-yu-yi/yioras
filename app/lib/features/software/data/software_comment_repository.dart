import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/config/app_config.dart';
import '../../../core/network/api_client.dart';
import '../../../core/network/api_exception.dart';
import '../../../core/network/api_response.dart';
import '../../feed/model/post.dart';
import '../../post_detail/model/post_detail.dart';

/// 软件评论仓库（文档 3.6 软件详情评论区）。
/// 复用帖子评论的 [Comment]/[CommentPage] 模型与点赞端点，
/// 拉取/发布走 bizType=2（软件）通道。
abstract interface class SoftwareCommentRepository {
  Future<CommentPage> fetchComments(int softwareId, {String? cursor, int size});

  /// 发评论；[replyTo] 为被回复的评论 ID（null=直接评软件）
  Future<Comment> createComment(
    int softwareId, {
    required String content,
    int? replyTo,
  });

  Future<void> setCommentLike(int commentId, {required bool like});
}

class SoftwareCommentRepositoryHttp implements SoftwareCommentRepository {
  SoftwareCommentRepositoryHttp(this._dio);

  final Dio _dio;

  @override
  Future<CommentPage> fetchComments(
    int softwareId, {
    String? cursor,
    int size = 20,
  }) => _guard(() async {
    final resp = await _dio.get<Map<String, dynamic>>(
      '${AppConfig.apiPrefix}/comments',
      queryParameters: {
        'bizType': 2,
        'bizId': softwareId,
        'cursor': ?cursor,
        'size': size,
      },
    );
    return ApiResponse.fromJson(
      resp.data!,
      (data) => CommentPage.fromJson(data as Map<String, dynamic>),
    ).unwrap();
  });

  @override
  Future<Comment> createComment(
    int softwareId, {
    required String content,
    int? replyTo,
  }) => _guard(() async {
    final resp = await _dio.post<Map<String, dynamic>>(
      '${AppConfig.apiPrefix}/comments',
      data: {
        'bizType': 2,
        'bizId': softwareId,
        'content': content,
        'parentId': ?replyTo,
      },
    );
    return ApiResponse.fromJson(
      resp.data!,
      (data) => Comment.fromJson(data as Map<String, dynamic>),
    ).unwrap();
  });

  @override
  Future<void> setCommentLike(int commentId, {required bool like}) =>
      _guard(() async {
        final resp = like
            ? await _dio.post<Map<String, dynamic>>(
                '${AppConfig.apiPrefix}/comments/$commentId/like',
              )
            : await _dio.delete<Map<String, dynamic>>(
                '${AppConfig.apiPrefix}/comments/$commentId/like',
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

/// Mock 实现：按软件 ID 确定性生成 5 条评论，第 1 条带 2 条回复预览。
class SoftwareCommentRepositoryMock implements SoftwareCommentRepository {
  static final Set<int> _liked = {};
  static int _nextId = 70000;

  static const _authors = [
    PostAuthor(id: 201, nickname: '路过的风', level: 5),
    PostAuthor(id: 202, nickname: '喵呜', level: 8, badge: '达人'),
    PostAuthor(id: 203, nickname: '深夜码农', level: 11),
    PostAuthor(id: 204, nickname: '柚子茶', level: 2),
  ];
  static const _texts = [
    '用了半个月了，很稳，没广告良心',
    '这个版本比上一版流畅很多，推荐更新',
    '提取码可用，下载速度不错',
    '有没有遇到闪退的？我的机型不太兼容',
    '感谢发布者搬运，收藏了',
  ];

  @override
  Future<CommentPage> fetchComments(
    int softwareId, {
    String? cursor,
    int size = 20,
  }) async {
    await Future<void>.delayed(const Duration(milliseconds: 450));
    final all = List.generate(5, (i) {
      final id = softwareId * 100 + i;
      return Comment(
        id: id,
        author: _authors[(softwareId + i) % _authors.length],
        content: _texts[(softwareId + i) % _texts.length],
        createdAt: DateTime.now().subtract(Duration(hours: 2 + i * 7)),
        likeCount: (13 * (i + softwareId)) % 60,
        liked: _liked.contains(id),
        replyCount: i == 0 ? 2 : 0,
        replies: i == 0
            ? [
                Comment(
                  id: id * 10 + 1,
                  author: _authors[(softwareId + 2) % _authors.length],
                  content: '同感，日常主力了',
                  replyToNickname:
                      _authors[(softwareId) % _authors.length].nickname,
                  liked: _liked.contains(id * 10 + 1),
                  createdAt: DateTime.now().subtract(
                    const Duration(minutes: 50),
                  ),
                ),
                Comment(
                  id: id * 10 + 2,
                  author: _authors[(softwareId + 3) % _authors.length],
                  content: '安卓 12 亲测没问题',
                  replyToNickname:
                      _authors[(softwareId) % _authors.length].nickname,
                  liked: _liked.contains(id * 10 + 2),
                  createdAt: DateTime.now().subtract(
                    const Duration(minutes: 20),
                  ),
                ),
              ]
            : const [],
      );
    });
    final offset = int.tryParse(cursor ?? '0') ?? 0;
    final end = (offset + size).clamp(0, all.length);
    final hasMore = end < all.length;
    return CommentPage(
      list: all.sublist(offset.clamp(0, all.length), end),
      nextCursor: hasMore ? '$end' : null,
      hasMore: hasMore,
    );
  }

  @override
  Future<Comment> createComment(
    int softwareId, {
    required String content,
    int? replyTo,
  }) async {
    await Future<void>.delayed(const Duration(milliseconds: 500));
    return Comment(
      id: _nextId++,
      author: const PostAuthor(id: 101215, nickname: '我', level: 3),
      content: content,
      createdAt: DateTime.now(),
    );
  }

  @override
  Future<void> setCommentLike(int commentId, {required bool like}) async {
    await Future<void>.delayed(const Duration(milliseconds: 300));
    like ? _liked.add(commentId) : _liked.remove(commentId);
  }
}

final softwareCommentRepositoryProvider = Provider<SoftwareCommentRepository>((
  ref,
) {
  if (AppConfig.useMock) return SoftwareCommentRepositoryMock();
  return SoftwareCommentRepositoryHttp(ref.watch(dioProvider));
});
