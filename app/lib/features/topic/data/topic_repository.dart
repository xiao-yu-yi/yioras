import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/config/app_config.dart';
import '../../../core/network/api_client.dart';
import '../../../core/network/api_exception.dart';
import '../../../core/network/api_response.dart';
import '../../feed/data/feed_repository.dart';
import '../../feed/model/post.dart';

/// 话题流排序（对齐 server GET /topics/:id/posts sort=hot|new，默认最热）
enum TopicPostSort {
  hot('hot', '最热'),
  newest('new', '最新');

  const TopicPostSort(this.value, this.label);

  final String value;
  final String label;
}

/// 话题信息（对齐 server TopicItem）
class TopicInfo {
  const TopicInfo({required this.id, required this.name, this.postCount = 0});

  final int id;
  final String name;
  final int postCount;

  factory TopicInfo.fromJson(Map<String, dynamic> json) => TopicInfo(
    id: (json['id'] as num).toInt(),
    name: json['name'] as String? ?? '',
    postCount: (json['postCount'] as num?)?.toInt() ?? 0,
  );
}

/// 话题聚合页单页结果：话题信息随帖子一并下发（页码分页，满页视为还有下一页）
class TopicPostsPage {
  const TopicPostsPage({
    required this.topic,
    required this.posts,
    required this.hasMore,
  });

  final TopicInfo topic;
  final List<Post> posts;
  final bool hasMore;
}

/// 话题仓库；统一抛 [ApiException]。
abstract interface class TopicRepository {
  Future<TopicPostsPage> fetchTopicPosts(
    int topicId, {
    TopicPostSort sort,
    int page,
    int size,
  });

  /// 按话题名解析话题（帖子卡片 chip 只有名字没有 id 时的入口解析）
  Future<TopicInfo> resolveByName(String name);
}

class TopicRepositoryHttp implements TopicRepository {
  TopicRepositoryHttp(this._dio);

  final Dio _dio;

  @override
  Future<TopicPostsPage> fetchTopicPosts(
    int topicId, {
    TopicPostSort sort = TopicPostSort.hot,
    int page = 1,
    int size = 20,
  }) async {
    try {
      final resp = await _dio.get<Map<String, dynamic>>(
        '${AppConfig.apiPrefix}/topics/$topicId/posts',
        queryParameters: {'sort': sort.value, 'page': page, 'size': size},
      );
      return ApiResponse.fromJson(resp.data!, (data) {
        final map = data as Map<String, dynamic>;
        final posts = (map['posts'] as List<dynamic>? ?? const [])
            .map((e) => Post.fromJson(e as Map<String, dynamic>))
            .toList();
        return TopicPostsPage(
          topic: TopicInfo.fromJson(map['topic'] as Map<String, dynamic>),
          posts: posts,
          hasMore: posts.length >= size,
        );
      }).unwrap();
    } on DioException catch (e) {
      throw ApiException.fromDio(e);
    }
  }

  @override
  Future<TopicInfo> resolveByName(String name) async {
    // 服务端无按名直查接口，复用话题搜索精确匹配
    try {
      final resp = await _dio.get<Map<String, dynamic>>(
        '${AppConfig.apiPrefix}/search',
        queryParameters: {'type': 'topic', 'kw': name, 'page': 1, 'size': 20},
      );
      return ApiResponse.fromJson(resp.data!, (data) {
        final list = ((data as Map<String, dynamic>)['topics']
                as List<dynamic>? ??
            const []);
        final topics = list
            .map((e) => TopicInfo.fromJson(e as Map<String, dynamic>))
            .toList();
        return topics.firstWhere(
          (t) => t.name == name,
          orElse: () =>
              throw const ApiException(code: 40400, message: '话题不存在'),
        );
      }).unwrap();
    } on DioException catch (e) {
      throw ApiException.fromDio(e);
    }
  }
}

/// Mock 实现：与搜索 Mock 的话题表一致，帖子从推荐流按话题名过滤。
class TopicRepositoryMock implements TopicRepository {
  TopicRepositoryMock({required FeedRepository feedRepository})
    : _feed = feedRepository;

  final FeedRepository _feed;

  static const topics = [
    TopicInfo(id: 1, name: '公告', postCount: 89),
    TopicInfo(id: 2, name: '内测反馈', postCount: 452),
    TopicInfo(id: 3, name: 'Flutter', postCount: 1287),
    TopicInfo(id: 4, name: '性能优化', postCount: 342),
    TopicInfo(id: 5, name: '夜间模式', postCount: 128),
    TopicInfo(id: 6, name: '片单', postCount: 986),
    TopicInfo(id: 7, name: '夏促', postCount: 1560),
    TopicInfo(id: 8, name: '省钱攻略', postCount: 764),
  ];

  @override
  Future<TopicPostsPage> fetchTopicPosts(
    int topicId, {
    TopicPostSort sort = TopicPostSort.hot,
    int page = 1,
    int size = 20,
  }) async {
    await Future<void>.delayed(const Duration(milliseconds: 450));
    final topic = topics.firstWhere(
      (t) => t.id == topicId,
      orElse: () => throw const ApiException(code: 40400, message: '话题不存在'),
    );
    final all = (await _feed.fetchRecommend(size: 100)).list
        .where((p) => p.topics.contains(topic.name))
        .toList();
    all.sort(
      (a, b) => switch (sort) {
        TopicPostSort.hot => b.likeCount.compareTo(a.likeCount),
        TopicPostSort.newest => b.createdAt.compareTo(a.createdAt),
      },
    );
    final start = ((page - 1) * size).clamp(0, all.length);
    final end = (start + size).clamp(0, all.length);
    return TopicPostsPage(
      topic: topic,
      posts: all.sublist(start, end),
      hasMore: end < all.length,
    );
  }

  @override
  Future<TopicInfo> resolveByName(String name) async {
    await Future<void>.delayed(const Duration(milliseconds: 200));
    return topics.firstWhere(
      (t) => t.name == name,
      orElse: () => throw const ApiException(code: 40400, message: '话题不存在'),
    );
  }
}

final topicRepositoryProvider = Provider<TopicRepository>((ref) {
  if (AppConfig.useMock) {
    return TopicRepositoryMock(feedRepository: ref.watch(feedRepositoryProvider));
  }
  return TopicRepositoryHttp(ref.watch(dioProvider));
});
