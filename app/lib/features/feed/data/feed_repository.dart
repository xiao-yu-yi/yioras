import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/config/app_config.dart';
import '../../../core/network/api_exception.dart';
import '../model/post.dart';
import 'feed_api.dart';

/// 推荐流仓库接口，屏蔽 HTTP/Mock 差异；统一抛 [ApiException]。
abstract interface class FeedRepository {
  Future<PostPage> fetchRecommend({String? cursor, int size});
}

class FeedRepositoryHttp implements FeedRepository {
  FeedRepositoryHttp(this._api);

  final FeedApi _api;

  @override
  Future<PostPage> fetchRecommend({String? cursor, int size = 20}) async {
    try {
      return await _api.fetchRecommend(cursor: cursor, size: size);
    } on DioException catch (e) {
      throw ApiException.fromDio(e);
    }
  }
}

/// Mock 实现：内存生成 3 页共 48 条帖子，模拟网络延迟与游标分页。
class FeedRepositoryMock implements FeedRepository {
  static final List<Post> _posts = _generate();

  static List<Post> _generate() {
    const authors = [
      ('小鱼干', 12, '开发者'),
      ('YioraBot', 20, '官方'),
      ('夜风', 6, ''),
      ('拾光者', 9, '圈主'),
      ('阿澈', 3, ''),
      ('绿萝', 15, '达人'),
    ];
    const samples = [
      (
        'Bug 反馈集中贴（长期有效）',
        '大家在内测中遇到任何问题都可以在这个帖子下面回复，附上截图和机型信息，我们会尽快排查处理。感谢每一位参与内测的小伙伴！',
        '官方公告',
        ['公告', '内测反馈'],
        true,
      ),
      (
        '安卓端夜间模式适配进度',
        '目前已经完成了首页和圈子页的深色适配，帖子详情页还在调整对比度，预计下个版本上线，敬请期待。',
        '玩机专区',
        ['夜间模式'],
        false,
      ),
      (
        '',
        '第一次用 Flutter 写长列表，滚动流畅度确实比想象中好，分享一下踩过的坑：图片一定要按列表宽度取缩略图，不然内存直接起飞……',
        '源码仓库',
        ['Flutter', '性能优化'],
        false,
      ),
      (
        '本周影视安利：值得二刷的三部片',
        '周末窝在家里把之前收藏的片单清了清，挑出三部觉得最值得二刷的，评论区聊聊你们的心头好。',
        '影视闲聊',
        ['片单'],
        false,
      ),
      (
        'Steam 夏促蹲点攻略',
        '夏促马上开始，整理了一份愿望单折扣预测表，历史低价都标出来了，需要的自取。',
        'Steam 专区',
        ['夏促', '省钱攻略'],
        false,
      ),
      ('', '今天路过江边拍到的晚霞，分享给大家，愿你们今晚都有好梦。', '闲言碎语', <String>[], false),
    ];

    return List.generate(48, (i) {
      final author = authors[i % authors.length];
      final sample = samples[i % samples.length];
      final imageCount = switch (i % 5) {
        0 => 3,
        1 => 1,
        3 => 4,
        _ => 0,
      };
      return Post(
        id: 1000 - i,
        author: PostAuthor(
          id: 100 + i % authors.length,
          nickname: author.$1,
          avatar:
              'https://picsum.photos/seed/yiora-avatar-${i % authors.length}/100/100',
          level: author.$2,
          badge: author.$3,
        ),
        title: sample.$1,
        content: sample.$2,
        circleName: sample.$3,
        images: List.generate(
          imageCount,
          (j) => 'https://picsum.photos/seed/yiora-post-$i-$j/600/400',
        ),
        topics: sample.$4,
        viewCount: 12000 - i * 173,
        likeCount: 890 - i * 11,
        commentCount: 230 - i * 4,
        isTop: sample.$5 && i < 6,
        createdAt: DateTime.now().subtract(Duration(minutes: 20 + i * 47)),
      );
    });
  }

  @override
  Future<PostPage> fetchRecommend({String? cursor, int size = 20}) async {
    await Future<void>.delayed(const Duration(milliseconds: 700));
    final offset = int.tryParse(cursor ?? '0') ?? 0;
    final end = (offset + size).clamp(0, _posts.length);
    final slice = _posts.sublist(offset.clamp(0, _posts.length), end);
    final hasMore = end < _posts.length;
    return PostPage(
      list: slice,
      nextCursor: hasMore ? '$end' : null,
      hasMore: hasMore,
    );
  }
}

final feedRepositoryProvider = Provider<FeedRepository>((ref) {
  if (AppConfig.useMock) return FeedRepositoryMock();
  return FeedRepositoryHttp(ref.watch(feedApiProvider));
});
