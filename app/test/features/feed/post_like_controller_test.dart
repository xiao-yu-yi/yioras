import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yiora/core/network/api_exception.dart';
import 'package:yiora/features/feed/controller/post_like_controller.dart';
import 'package:yiora/features/post_detail/data/post_detail_repository.dart';
import 'package:yiora/features/post_detail/model/post_detail.dart';

/// 只关心 setLike 的假仓库，其余接口不会被调用
class _FakeLikeRepository implements PostDetailRepository {
  bool failLike = false;
  final List<(int, bool)> likeCalls = [];

  @override
  Future<void> setLike(int postId, {required bool like}) async {
    likeCalls.add((postId, like));
    if (failLike) {
      throw const ApiException(code: -1, message: '网络超时，请稍后重试');
    }
  }

  @override
  Future<PostDetail> fetchDetail(int postId) => throw UnimplementedError();

  @override
  Future<CommentPage> fetchComments(
    int postId, {
    String? cursor,
    int size = 20,
  }) => throw UnimplementedError();

  @override
  Future<void> setFavorite(int postId, {required bool favorite}) =>
      throw UnimplementedError();

  @override
  Future<void> setCommentLike(int commentId, {required bool like}) =>
      throw UnimplementedError();

  @override
  Future<CommentPage> fetchReplies(
    int commentId, {
    String? cursor,
    int size = 10,
  }) => throw UnimplementedError();

  @override
  Future<Comment> createComment(
    int postId, {
    required String content,
    int? replyTo,
  }) => throw UnimplementedError();
}

ProviderContainer _container(PostDetailRepository repo) {
  final container = ProviderContainer(
    overrides: [postDetailRepositoryProvider.overrideWithValue(repo)],
  );
  addTearDown(container.dispose);
  return container;
}

void main() {
  test('点赞乐观更新：立即翻转 +1 并透传接口参数', () async {
    final repo = _FakeLikeRepository();
    final container = _container(repo);

    await container
        .read(postLikeControllerProvider.notifier)
        .toggle(5, currentLiked: false, currentCount: 890);

    final overlay = container.read(postLikeControllerProvider)[5]!;
    expect(overlay.liked, isTrue);
    expect(overlay.count, 891);
    expect(repo.likeCalls, [(5, true)]);
  });

  test('取消点赞：翻转 -1', () async {
    final repo = _FakeLikeRepository();
    final container = _container(repo);

    await container
        .read(postLikeControllerProvider.notifier)
        .toggle(5, currentLiked: true, currentCount: 891);

    final overlay = container.read(postLikeControllerProvider)[5]!;
    expect(overlay.liked, isFalse);
    expect(overlay.count, 890);
    expect(repo.likeCalls, [(5, false)]);
  });

  test('点赞失败：回滚到调用前基线并抛异常', () async {
    final repo = _FakeLikeRepository()..failLike = true;
    final container = _container(repo);

    await expectLater(
      container
          .read(postLikeControllerProvider.notifier)
          .toggle(5, currentLiked: false, currentCount: 890),
      throwsA(isA<ApiException>()),
    );

    final overlay = container.read(postLikeControllerProvider)[5]!;
    expect(overlay.liked, isFalse, reason: '失败后回滚');
    expect(overlay.count, 890);
  });

  test('seed 并入服务端初始态且不覆盖已有操作', () async {
    final repo = _FakeLikeRepository();
    final container = _container(repo);
    final notifier = container.read(postLikeControllerProvider.notifier);

    notifier.seed(5, liked: true, count: 100);
    expect(container.read(postLikeControllerProvider)[5]!.liked, isTrue);

    // 用户操作后 seed 不得回写覆盖
    await notifier.toggle(5, currentLiked: true, currentCount: 100);
    notifier.seed(5, liked: true, count: 100);
    final overlay = container.read(postLikeControllerProvider)[5]!;
    expect(overlay.liked, isFalse);
    expect(overlay.count, 99);
  });
}
