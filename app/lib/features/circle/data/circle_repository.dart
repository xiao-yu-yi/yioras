import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/config/app_config.dart';
import '../../../core/network/api_exception.dart';
import '../../feed/data/feed_repository.dart';
import '../../feed/model/post.dart';
import '../model/circle.dart';
import 'circle_api.dart';

/// 圈子仓库接口，屏蔽 HTTP/Mock 差异；统一抛 [ApiException]。
abstract interface class CircleRepository {
  Future<List<Circle>> fetchCircles({required CircleSort sort});

  Future<Circle> fetchCircleDetail(int id);

  Future<void> joinCircle(int id);

  Future<void> quitCircle(int id);

  Future<PostPage> fetchCirclePosts(
    int circleId, {
    CirclePostSort sort,
    String? cursor,
    int size,
  });
}

class CircleRepositoryHttp implements CircleRepository {
  CircleRepositoryHttp(this._api);

  final CircleApi _api;

  @override
  Future<List<Circle>> fetchCircles({required CircleSort sort}) =>
      _guard(() => _api.fetchCircles(sort: sort));

  @override
  Future<Circle> fetchCircleDetail(int id) =>
      _guard(() => _api.fetchCircleDetail(id));

  @override
  Future<void> joinCircle(int id) => _guard(() => _api.joinCircle(id));

  @override
  Future<void> quitCircle(int id) => _guard(() => _api.quitCircle(id));

  @override
  Future<PostPage> fetchCirclePosts(
    int circleId, {
    CirclePostSort sort = CirclePostSort.newest,
    String? cursor,
    int size = 20,
  }) => _guard(
    () =>
        _api.fetchCirclePosts(circleId, sort: sort, cursor: cursor, size: size),
  );

  Future<T> _guard<T>(Future<T> Function() action) async {
    try {
      return await action();
    } on DioException catch (e) {
      throw ApiException.fromDio(e);
    }
  }
}

/// Mock 实现：内存圈子列表 + 加入/退出状态即时生效。
class CircleRepositoryMock implements CircleRepository {
  CircleRepositoryMock({required this._feedRepository});

  /// 复用推荐流 Mock 数据充当圈内帖子流
  final FeedRepository _feedRepository;

  static Circle _c(
    int id,
    String name,
    String intro, {
    bool official = false,
    bool pinned = false,
    bool joined = false,
    int members = 0,
    int posts = 0,
  }) => Circle(
    id: id,
    name: name,
    icon: 'https://picsum.photos/seed/yiora-circle-$id/120/120',
    cover: 'https://picsum.photos/seed/yiora-circle-cover-$id/800/360',
    intro: intro,
    description: '$intro。这里是「$name」圈子，欢迎遵守社区规范，友善交流。',
    memberCount: members,
    postCount: posts,
    isOfficial: official,
    pinned: pinned,
    joined: joined,
  );

  /// 有状态：加入/退出会修改 joined 与 memberCount
  static final List<Circle> _circles = [
    _c(
      1,
      '官方公告',
      '社区最新通知,仅官方可发',
      official: true,
      pinned: true,
      members: 128934,
      posts: 89,
    ),
    _c(2, '闲言碎语', '无聊就来此聊聊', joined: true, members: 88213, posts: 15672),
    _c(3, '骗子举报', '曝光各类诈骗,强化审核', official: true, members: 45201, posts: 2310),
    _c(4, '玩机专区', '刷机搞机技术交流', members: 67432, posts: 9821),
    _c(5, '绿色软件', '纯净好用的软件分享', joined: true, members: 59870, posts: 7654),
    _c(6, '源码仓库', '代码与开源项目交流', members: 32109, posts: 4321),
    _c(7, 'GM 游戏', '变态版手游快乐玩', members: 28764, posts: 3456),
    _c(8, 'Steam 专区', '喜加一与游戏折扣情报', members: 51234, posts: 6789),
    _c(9, '影视闲聊', '剧集电影观后交流', members: 40987, posts: 5123),
  ];

  @override
  Future<List<Circle>> fetchCircles({required CircleSort sort}) async {
    await Future<void>.delayed(const Duration(milliseconds: 500));
    final list = [..._circles];
    switch (sort) {
      case CircleSort.hot:
        // 置顶圈优先，其余按成员数
        list.sort((a, b) {
          if (a.pinned != b.pinned) return a.pinned ? -1 : 1;
          return b.memberCount.compareTo(a.memberCount);
        });
      case CircleSort.newest:
        list.sort((a, b) => b.id.compareTo(a.id));
    }
    return list;
  }

  @override
  Future<Circle> fetchCircleDetail(int id) async {
    await Future<void>.delayed(const Duration(milliseconds: 400));
    return _circles.firstWhere(
      (c) => c.id == id,
      orElse: () => throw const ApiException(code: 40400, message: '圈子不存在或已解散'),
    );
  }

  @override
  Future<void> joinCircle(int id) async {
    await Future<void>.delayed(const Duration(milliseconds: 400));
    final index = _circles.indexWhere((c) => c.id == id);
    if (index < 0) {
      throw const ApiException(code: 40400, message: '圈子不存在或已解散');
    }
    final circle = _circles[index];
    if (!circle.joined) {
      _circles[index] = circle.copyWith(
        joined: true,
        memberCount: circle.memberCount + 1,
      );
    }
  }

  @override
  Future<void> quitCircle(int id) async {
    await Future<void>.delayed(const Duration(milliseconds: 400));
    final index = _circles.indexWhere((c) => c.id == id);
    if (index < 0) {
      throw const ApiException(code: 40400, message: '圈子不存在或已解散');
    }
    final circle = _circles[index];
    if (circle.joined) {
      _circles[index] = circle.copyWith(
        joined: false,
        memberCount: circle.memberCount - 1,
      );
    }
  }

  @override
  Future<PostPage> fetchCirclePosts(
    int circleId, {
    CirclePostSort sort = CirclePostSort.newest,
    String? cursor,
    int size = 20,
  }) async {
    // 复用推荐流数据按圈名过滤，模拟圈内流；置顶帖恒前置（对齐 circle_top 语义）
    final detail = await fetchCircleDetail(circleId);
    final page = await _feedRepository.fetchRecommend(size: 100);
    final filtered = page.list
        .where((p) => p.circleName == detail.name)
        .toList();
    filtered.sort((a, b) {
      if (a.isTop != b.isTop) return a.isTop ? -1 : 1;
      return switch (sort) {
        CirclePostSort.newest => b.createdAt.compareTo(a.createdAt),
        CirclePostSort.hot => b.likeCount.compareTo(a.likeCount),
      };
    });
    final offset = int.tryParse(cursor ?? '0') ?? 0;
    final end = (offset + size).clamp(0, filtered.length);
    final hasMore = end < filtered.length;
    return PostPage(
      list: filtered.sublist(offset.clamp(0, filtered.length), end),
      nextCursor: hasMore ? '$end' : null,
      hasMore: hasMore,
    );
  }
}

final circleRepositoryProvider = Provider<CircleRepository>((ref) {
  if (AppConfig.useMock) {
    return CircleRepositoryMock(
      feedRepository: ref.watch(feedRepositoryProvider),
    );
  }
  return CircleRepositoryHttp(ref.watch(circleApiProvider));
});
