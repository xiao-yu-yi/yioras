import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/config/app_config.dart';
import '../../../core/network/api_client.dart';
import '../../../core/network/api_exception.dart';
import '../../../core/network/api_response.dart';
import '../../circle/data/circle_repository.dart';
import '../../circle/model/circle.dart';
import '../../feed/data/feed_repository.dart';
import '../../software/data/software_repository.dart';
import '../../software/model/software.dart';

/// 搜索类型（对齐 server GET /search type=post|user|circle|software|topic）
enum SearchType {
  post('post', '帖子'),
  user('user', '用户'),
  circle('circle', '圈子'),
  topic('topic', '话题'),
  software('software', '软件');

  const SearchType(this.value, this.label);

  final String value;
  final String label;
}

/// 帖子搜索结果条目（服务端 PostItem 的展示子集，字段防御式解析）
class SearchPostItem {
  const SearchPostItem({
    required this.id,
    this.title = '',
    this.content = '',
    this.authorNickname = '',
    this.likeCount = 0,
    this.commentCount = 0,
  });

  final int id;
  final String title;
  final String content;
  final String authorNickname;
  final int likeCount;
  final int commentCount;

  factory SearchPostItem.fromJson(Map<String, dynamic> json) {
    final author = json['author'] as Map<String, dynamic>? ?? const {};
    return SearchPostItem(
      id: (json['id'] as num).toInt(),
      title: json['title'] as String? ?? '',
      content: json['content'] as String? ?? '',
      authorNickname: author['nickname'] as String? ?? '',
      likeCount: (json['likeCount'] as num?)?.toInt() ?? 0,
      commentCount: (json['commentCount'] as num?)?.toInt() ?? 0,
    );
  }
}

/// 用户搜索结果条目（服务端 RelationUserItem：UserBrief + followed）
class SearchUserItem {
  const SearchUserItem({
    required this.id,
    required this.nickname,
    this.avatar = '',
    this.level = 0,
    this.displayNo = '',
  });

  final int id;
  final String nickname;
  final String avatar;
  final int level;
  final String displayNo;

  factory SearchUserItem.fromJson(Map<String, dynamic> json) => SearchUserItem(
    id: (json['userId'] as num?)?.toInt() ?? (json['id'] as num?)?.toInt() ?? 0,
    nickname: json['nickname'] as String? ?? '',
    avatar: json['avatar'] as String? ?? '',
    level: (json['level'] as num?)?.toInt() ?? 0,
    displayNo: json['displayNo'] as String? ?? '',
  );
}

/// 话题搜索结果条目
class SearchTopicItem {
  const SearchTopicItem({
    required this.id,
    required this.name,
    this.postCount = 0,
  });

  final int id;
  final String name;
  final int postCount;

  factory SearchTopicItem.fromJson(Map<String, dynamic> json) =>
      SearchTopicItem(
        id: (json['id'] as num).toInt(),
        name: json['name'] as String? ?? '',
        postCount: (json['postCount'] as num?)?.toInt() ?? 0,
      );
}

/// 单类搜索结果页（页码分页，满页视为还有下一页）
class SearchResultPage {
  const SearchResultPage({
    this.posts = const [],
    this.users = const [],
    this.circles = const [],
    this.topics = const [],
    this.software = const [],
    required this.hasMore,
  });

  final List<SearchPostItem> posts;
  final List<SearchUserItem> users;
  final List<Circle> circles;
  final List<SearchTopicItem> topics;
  final List<SoftwareItem> software;
  final bool hasMore;

  /// 当前类型的结果条数（分页判断用）
  int countOf(SearchType type) => switch (type) {
    SearchType.post => posts.length,
    SearchType.user => users.length,
    SearchType.circle => circles.length,
    SearchType.topic => topics.length,
    SearchType.software => software.length,
  };
}

/// 全局搜索仓库；统一抛 [ApiException]。
abstract interface class SearchRepository {
  Future<SearchResultPage> search({
    required SearchType type,
    required String kw,
    int page,
    int size,
  });
}

class SearchRepositoryHttp implements SearchRepository {
  SearchRepositoryHttp(this._dio);

  final Dio _dio;

  @override
  Future<SearchResultPage> search({
    required SearchType type,
    required String kw,
    int page = 1,
    int size = 20,
  }) async {
    try {
      final resp = await _dio.get<Map<String, dynamic>>(
        '${AppConfig.apiPrefix}/search',
        queryParameters: {
          'type': type.value,
          'kw': kw,
          'page': page,
          'size': size,
        },
      );
      final result = ApiResponse.fromJson(resp.data!, (data) {
        final map = data as Map<String, dynamic>;
        List<T> parse<T>(String key, T Function(Map<String, dynamic>) from) =>
            (map[key] as List<dynamic>? ?? const [])
                .map((e) => from(e as Map<String, dynamic>))
                .toList();
        final page = SearchResultPage(
          posts: parse('posts', SearchPostItem.fromJson),
          users: parse('users', SearchUserItem.fromJson),
          circles: parse('circles', Circle.fromJson),
          topics: parse('topics', SearchTopicItem.fromJson),
          software: parse('software', SoftwareItem.fromJson),
          hasMore: false,
        );
        return page;
      }).unwrap();
      return SearchResultPage(
        posts: result.posts,
        users: result.users,
        circles: result.circles,
        topics: result.topics,
        software: result.software,
        hasMore: result.countOf(type) >= size,
      );
    } on DioException catch (e) {
      throw ApiException.fromDio(e);
    }
  }
}

/// Mock 实现：基于各域 Mock 数据做关键字过滤，模拟五类搜索。
class SearchRepositoryMock implements SearchRepository {
  SearchRepositoryMock({
    required FeedRepository feedRepository,
    required CircleRepository circleRepository,
    required SoftwareRepository softwareRepository,
  }) : _feed = feedRepository,
       _circle = circleRepository,
       _software = softwareRepository;

  final FeedRepository _feed;
  final CircleRepository _circle;
  final SoftwareRepository _software;

  static const _mockUsers = [
    SearchUserItem(
      id: 100,
      nickname: '小鱼干',
      avatar: 'https://picsum.photos/seed/yiora-avatar-0/100/100',
      level: 12,
      displayNo: 'N100100',
    ),
    SearchUserItem(
      id: 101,
      nickname: 'YioraBot',
      avatar: 'https://picsum.photos/seed/yiora-avatar-1/100/100',
      level: 20,
      displayNo: 'N100101',
    ),
    SearchUserItem(
      id: 102,
      nickname: '夜风',
      avatar: 'https://picsum.photos/seed/yiora-avatar-2/100/100',
      level: 6,
      displayNo: 'N100102',
    ),
    SearchUserItem(
      id: 103,
      nickname: '拾光者',
      avatar: 'https://picsum.photos/seed/yiora-avatar-3/100/100',
      level: 9,
      displayNo: 'N100103',
    ),
    SearchUserItem(
      id: 104,
      nickname: '阿澈',
      avatar: 'https://picsum.photos/seed/yiora-avatar-4/100/100',
      level: 3,
      displayNo: 'N100104',
    ),
    SearchUserItem(
      id: 105,
      nickname: '绿萝',
      avatar: 'https://picsum.photos/seed/yiora-avatar-5/100/100',
      level: 15,
      displayNo: 'N100105',
    ),
  ];

  static const _mockTopics = [
    SearchTopicItem(id: 1, name: '公告', postCount: 89),
    SearchTopicItem(id: 2, name: '内测反馈', postCount: 452),
    SearchTopicItem(id: 3, name: 'Flutter', postCount: 1287),
    SearchTopicItem(id: 4, name: '性能优化', postCount: 342),
    SearchTopicItem(id: 5, name: '夜间模式', postCount: 128),
    SearchTopicItem(id: 6, name: '片单', postCount: 986),
    SearchTopicItem(id: 7, name: '夏促', postCount: 1560),
    SearchTopicItem(id: 8, name: '省钱攻略', postCount: 764),
  ];

  @override
  Future<SearchResultPage> search({
    required SearchType type,
    required String kw,
    int page = 1,
    int size = 20,
  }) async {
    await Future<void>.delayed(const Duration(milliseconds: 450));
    final keyword = kw.trim().toLowerCase();
    bool hit(String text) => text.toLowerCase().contains(keyword);

    List<T> paginate<T>(List<T> list) {
      final start = ((page - 1) * size).clamp(0, list.length);
      final end = (start + size).clamp(0, list.length);
      return list.sublist(start, end);
    }

    switch (type) {
      case SearchType.post:
        final all = (await _feed.fetchRecommend(size: 100)).list
            .where((p) => hit(p.title) || hit(p.content))
            .map(
              (p) => SearchPostItem(
                id: p.id,
                title: p.title,
                content: p.content,
                authorNickname: p.author.nickname,
                likeCount: p.likeCount,
                commentCount: p.commentCount,
              ),
            )
            .toList();
        final slice = paginate(all);
        return SearchResultPage(
          posts: slice,
          hasMore: page * size < all.length,
        );
      case SearchType.user:
        final all = _mockUsers.where((u) => hit(u.nickname)).toList();
        return SearchResultPage(users: paginate(all), hasMore: false);
      case SearchType.circle:
        final all = (await _circle.fetchCircles(sort: CircleSort.hot))
            .where((c) => hit(c.name) || hit(c.intro))
            .toList();
        return SearchResultPage(circles: paginate(all), hasMore: false);
      case SearchType.topic:
        final all = _mockTopics.where((t) => hit(t.name)).toList();
        return SearchResultPage(topics: paginate(all), hasMore: false);
      case SearchType.software:
        final all = <SoftwareItem>[];
        var p = 1;
        while (true) {
          final chunk = await _software.fetchList(page: p, size: 50);
          all.addAll(chunk.list);
          if (!chunk.hasMore) break;
          p++;
        }
        final filtered = all
            .where((s) => hit(s.name) || hit(s.intro))
            .toList();
        return SearchResultPage(
          software: paginate(filtered),
          hasMore: page * size < filtered.length,
        );
    }
  }
}

final searchRepositoryProvider = Provider<SearchRepository>((ref) {
  if (AppConfig.useMock) {
    return SearchRepositoryMock(
      feedRepository: ref.watch(feedRepositoryProvider),
      circleRepository: ref.watch(circleRepositoryProvider),
      softwareRepository: ref.watch(softwareRepositoryProvider),
    );
  }
  return SearchRepositoryHttp(ref.watch(dioProvider));
});
