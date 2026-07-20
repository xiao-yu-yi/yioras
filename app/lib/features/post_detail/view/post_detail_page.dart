import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/network/api_exception.dart';
import '../../../core/router/routes.dart';
import '../../../core/utils/time_format.dart';
import '../../feed/controller/post_like_controller.dart';
import '../../feed/model/post.dart';
import '../../feed/widget/post_card.dart' show PostCard;
import '../../report/data/report_repository.dart';
import '../../report/widget/report_sheet.dart';
import '../../user/controller/follow_controller.dart';
import '../controller/post_detail_controller.dart';
import '../model/post_detail.dart';
import 'image_gallery_viewer.dart';

/// 帖子详情页（文档 3.3）：作者卡片 / 全文 / 图片九宫格大图预览 / 两级评论 / 底部互动栏。
/// 视觉语言与首页卡片统一：白底正文区 + 灰色分段带 + 爱心点赞/浏览量互动语言。
/// 付费解锁、@解析、外链卡片、分享/举报为后续迭代。
class PostDetailPage extends ConsumerWidget {
  const PostDetailPage({super.key, required this.postId});

  final int postId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final detail = ref.watch(postDetailControllerProvider(postId));

    // 详情接口下发的点赞初始态并入全局点赞层（列表卡片同步展示，不覆盖本地操作）
    ref.listen(postDetailControllerProvider(postId), (previous, next) {
      final value = next.value;
      if (value != null) {
        ref
            .read(postLikeControllerProvider.notifier)
            .seed(postId, liked: value.detail.liked, count: value.likeCount);
      }
    });

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: const Text(
          '帖子详情',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
        ),
        actions: [
          // 举报入口（文档 3.3 帖子互动）
          if (detail.value != null)
            IconButton(
              tooltip: '举报',
              icon: const Icon(Icons.more_horiz),
              onPressed: () {
                final post = detail.value!.detail.post;
                showReportSheet(
                  context,
                  targetType: ReportTargetType.post,
                  targetId: postId,
                  targetBrief: post.title.isNotEmpty ? post.title : post.content,
                );
              },
            ),
        ],
      ),
      body: switch (detail) {
        AsyncData(:final value) => _DetailBody(postId: postId, state: value),
        AsyncError(:final error) => _ErrorView(
          message: error is ApiException ? error.message : '加载失败，请稍后重试',
          onRetry: () => ref
              .read(postDetailControllerProvider(postId).notifier)
              .retryFirstLoad(),
        ),
        _ => const Center(child: CircularProgressIndicator()),
      },
    );
  }
}

class _DetailBody extends ConsumerStatefulWidget {
  const _DetailBody({required this.postId, required this.state});

  final int postId;
  final PostDetailState state;

  @override
  ConsumerState<_DetailBody> createState() => _DetailBodyState();
}

class _DetailBodyState extends ConsumerState<_DetailBody> {
  /// 当前回复对象；null 表示直接回帖
  CommentReplyTarget? _replyTarget;

  /// 点评论 → 输入框切换为「回复 @昵称」；再点右侧 X 取消
  void _pickReply(Comment target, {required Comment root}) {
    setState(() {
      _replyTarget = CommentReplyTarget(
        commentId: target.id,
        rootId: root.id,
        nickname: target.author.nickname,
      );
    });
  }

  Future<void> _toggleCommentLike(Comment comment) async {
    try {
      await ref
          .read(postDetailControllerProvider(widget.postId).notifier)
          .toggleCommentLike(comment.id);
    } on ApiException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(SnackBar(content: Text(e.message)));
      }
    }
  }

  /// 长按评论 → 举报该评论
  void _reportComment(Comment comment) {
    showReportSheet(
      context,
      targetType: ReportTargetType.comment,
      targetId: comment.id,
      targetBrief: comment.content,
    );
  }

  @override
  Widget build(BuildContext context) {
    final postId = widget.postId;
    final state = widget.state;
    final post = state.detail.post;

    return Column(
      children: [
        Expanded(
          child: NotificationListener<ScrollNotification>(
            onNotification: (notification) {
              if (notification.metrics.extentAfter < 400) {
                ref
                    .read(postDetailControllerProvider(postId).notifier)
                    .loadMoreComments();
              }
              return false;
            },
            child: CustomScrollView(
              slivers: [
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
                  sliver: SliverList.list(
                    children: [
                      _AuthorCard(post: post),
                      const SizedBox(height: 16),
                      if (post.title.isNotEmpty) ...[
                        Text(
                          post.title,
                          style: const TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.w800,
                            height: 1.4,
                            letterSpacing: .1,
                          ),
                        ),
                        const SizedBox(height: 10),
                      ],
                      Text(
                        post.content,
                        style: TextStyle(
                          fontSize: 15.5,
                          height: 1.7,
                          color: Theme.of(
                            context,
                          ).colorScheme.onSurface.withValues(alpha: .88),
                        ),
                      ),
                      if (post.images.isNotEmpty) ...[
                        const SizedBox(height: 14),
                        _ImageGrid(images: post.images),
                      ],
                      if (post.topics.isNotEmpty) ...[
                        const SizedBox(height: 14),
                        Wrap(
                          spacing: 8,
                          runSpacing: 6,
                          children: [
                            for (final topic in post.topics)
                              _TopicChip(name: topic),
                          ],
                        ),
                      ],
                      const SizedBox(height: 14),
                      _MetaRow(post: post),
                      const SizedBox(height: 14),
                      Divider(
                        height: 1,
                        thickness: .6,
                        color: Theme.of(
                          context,
                        ).colorScheme.outlineVariant.withValues(alpha: .4),
                      ),
                      _InteractionRow(postId: postId, state: state),
                      const SizedBox(height: 6),
                    ],
                  ),
                ),
                // 灰色分段带：正文区与评论区的视觉分层
                SliverToBoxAdapter(
                  child: Container(height: 8, color: const Color(0xFFF6F7F9)),
                ),
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
                  sliver: SliverToBoxAdapter(
                    child: Row(
                      children: [
                        const Text(
                          '评论',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          formatCount(post.commentCount),
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: Theme.of(context).colorScheme.outline,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                if (state.comments.isEmpty)
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 44),
                      child: Column(
                        children: [
                          Icon(
                            Icons.maps_ugc_outlined,
                            size: 40,
                            color: Theme.of(context).colorScheme.outlineVariant,
                          ),
                          const SizedBox(height: 8),
                          Text(
                            '还没有评论，抢个沙发',
                            style: TextStyle(
                              fontSize: 13,
                              color: Theme.of(context).colorScheme.outline,
                            ),
                          ),
                        ],
                      ),
                    ),
                  )
                else
                  SliverPadding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    sliver: SliverList.separated(
                      itemCount: state.comments.length,
                      separatorBuilder: (context, index) => Divider(
                        height: 24,
                        thickness: .5,
                        indent: 42,
                        color: Theme.of(
                          context,
                        ).colorScheme.outlineVariant.withValues(alpha: .4),
                      ),
                      itemBuilder: (context, index) {
                        final comment = state.comments[index];
                        return _CommentTile(
                          key: ValueKey(comment.id),
                          comment: comment,
                          thread: state.replyThreads[comment.id],
                          onReply: _pickReply,
                          onLike: _toggleCommentLike,
                          onReport: _reportComment,
                          onToggleReplies: () => ref
                              .read(
                                postDetailControllerProvider(postId).notifier,
                              )
                              .toggleReplies(comment.id),
                          onLoadMoreReplies: () => ref
                              .read(
                                postDetailControllerProvider(postId).notifier,
                              )
                              .loadMoreReplies(comment.id),
                        );
                      },
                    ),
                  ),
                SliverToBoxAdapter(
                  child: _CommentsFooter(postId: postId, state: state),
                ),
              ],
            ),
          ),
        ),
        _BottomBar(
          postId: postId,
          state: state,
          replyTarget: _replyTarget,
          onCancelReply: () => setState(() => _replyTarget = null),
          onSent: () => setState(() => _replyTarget = null),
        ),
      ],
    );
  }
}

class _AuthorCard extends ConsumerWidget {
  const _AuthorCard({required this.post});

  final Post post;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final author = post.author;
    return Row(
      children: [
        GestureDetector(
          onTap: () => context.push(Routes.userProfilePath(author.id)),
          child: Container(
            padding: const EdgeInsets.all(1.5),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(
                color: scheme.outlineVariant.withValues(alpha: .55),
                width: 1,
              ),
            ),
            child: CircleAvatar(
              radius: 21,
              backgroundColor: scheme.surfaceContainerHighest,
              foregroundImage: author.avatar.isEmpty
                  ? null
                  : CachedNetworkImageProvider(author.avatar),
              child: Text(
                author.nickname.isEmpty
                    ? '?'
                    : author.nickname.characters.first,
                style: TextStyle(color: scheme.primary),
              ),
            ),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: GestureDetector(
            onTap: () => context.push(Routes.userProfilePath(author.id)),
            behavior: HitTestBehavior.opaque,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        author.nickname,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 15.5,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 5,
                        vertical: 1.5,
                      ),
                      decoration: BoxDecoration(
                        gradient: PostCard.brandGradient,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        'Lv.${author.level}',
                        style: const TextStyle(
                          fontSize: 9,
                          fontWeight: FontWeight.w800,
                          color: Colors.white,
                          height: 1.2,
                        ),
                      ),
                    ),
                    if (author.badge.isNotEmpty) ...[
                      const SizedBox(width: 4),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 5,
                          vertical: 1.5,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(0xFFFFF3DC),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          author.badge,
                          style: const TextStyle(
                            fontSize: 9,
                            fontWeight: FontWeight.w700,
                            color: Color(0xFFA36A00),
                            height: 1.2,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 3),
                Text(
                  formatRelativeTime(post.createdAt),
                  style: TextStyle(
                    fontSize: 12,
                    color: scheme.onSurfaceVariant.withValues(alpha: .9),
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(width: 8),
        _FollowButton(uid: post.author.id),
      ],
    );
  }
}

/// 详情页关注按钮：与他人主页共用全局关注状态（乐观更新失败回滚）。
/// 未关注为品牌色实心胶囊，已关注转灰描边。
class _FollowButton extends ConsumerWidget {
  const _FollowButton({required this.uid});

  final int uid;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // 详情接口不下发 following 初始态，未知时按未关注展示
    final following = ref.watch(followControllerProvider)[uid] ?? false;
    final notifier = ref.read(followControllerProvider.notifier);
    final scheme = Theme.of(context).colorScheme;

    Future<void> toggle() async {
      try {
        await notifier.toggle(uid, currentlyFollowing: following);
      } on ApiException catch (e) {
        if (context.mounted) {
          ScaffoldMessenger.of(context)
            ..hideCurrentSnackBar()
            ..showSnackBar(SnackBar(content: Text(e.message)));
        }
      }
    }

    if (following) {
      return OutlinedButton(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(72, 32),
          padding: const EdgeInsets.symmetric(horizontal: 14),
          visualDensity: VisualDensity.compact,
          foregroundColor: scheme.outline,
          side: BorderSide(color: scheme.outlineVariant),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          textStyle: const TextStyle(fontSize: 13),
        ),
        onPressed: notifier.isBusy(uid) ? null : toggle,
        child: const Text('已关注'),
      );
    }
    return FilledButton(
      style: FilledButton.styleFrom(
        minimumSize: const Size(72, 32),
        padding: const EdgeInsets.symmetric(horizontal: 16),
        visualDensity: VisualDensity.compact,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
      ),
      onPressed: notifier.isBusy(uid) ? null : toggle,
      child: const Text('+ 关注'),
    );
  }
}

/// 详情页九宫格：全部展示，点击进入大图预览
class _ImageGrid extends StatelessWidget {
  const _ImageGrid({required this.images});

  final List<String> images;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final placeholderColor = scheme.surfaceContainerHighest.withValues(
      alpha: .6,
    );

    if (images.length == 1) {
      return GestureDetector(
        onTap: () => showImageGallery(context, images: images),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: AspectRatio(
            aspectRatio: 16 / 9,
            child: CachedNetworkImage(
              imageUrl: images.first,
              fit: BoxFit.cover,
              fadeInDuration: const Duration(milliseconds: 200),
              placeholder: (context, url) => Container(color: placeholderColor),
              errorWidget: (context, url, error) =>
                  Container(color: placeholderColor),
            ),
          ),
        ),
      );
    }

    return GridView.count(
      crossAxisCount: 3,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      mainAxisSpacing: 6,
      crossAxisSpacing: 6,
      children: [
        for (var i = 0; i < images.length; i++)
          GestureDetector(
            onTap: () =>
                showImageGallery(context, images: images, initialIndex: i),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: CachedNetworkImage(
                imageUrl: images[i],
                fit: BoxFit.cover,
                fadeInDuration: const Duration(milliseconds: 200),
                placeholder: (context, url) =>
                    Container(color: placeholderColor),
                errorWidget: (context, url, error) =>
                    Container(color: placeholderColor),
              ),
            ),
          ),
      ],
    );
  }
}

class _TopicChip extends StatelessWidget {
  const _TopicChip({required this.name});

  final String name;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: scheme.primary.withValues(alpha: .07),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text.rich(
        TextSpan(
          children: [
            TextSpan(
              text: '# ',
              style: TextStyle(
                fontWeight: FontWeight.w800,
                color: scheme.primary.withValues(alpha: .8),
              ),
            ),
            TextSpan(text: name),
          ],
        ),
        style: TextStyle(
          fontSize: 12,
          color: scheme.primary,
          fontWeight: FontWeight.w500,
          height: 1.2,
        ),
      ),
    );
  }
}

/// 正文尾行：来自圈子标签
class _MetaRow extends StatelessWidget {
  const _MetaRow({required this.post});

  final Post post;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    if (post.circleName.isEmpty) return const SizedBox.shrink();
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: scheme.primary.withValues(alpha: .06),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.workspaces_outline, size: 13, color: scheme.primary),
            const SizedBox(width: 4),
            Text(
              post.circleName,
              style: TextStyle(
                fontSize: 12,
                color: scheme.primary,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 帖子底部互动行（评论区上方）：浏览量 + 爱心点赞 + 收藏，
/// 与首页卡片同一互动语言；点赞走全局 PostLikeController（列表卡片同步），
/// 收藏走详情控制器；均为乐观更新失败回滚提示。
class _InteractionRow extends ConsumerWidget {
  const _InteractionRow({required this.postId, required this.state});

  final int postId;
  final PostDetailState state;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final post = state.detail.post;
    final controller = ref.read(postDetailControllerProvider(postId).notifier);
    // 全局点赞覆盖层缺省时回退详情接口下发的初始值
    final likeOverlay = ref.watch(postLikeControllerProvider)[postId];
    final liked = likeOverlay?.liked ?? state.detail.liked;
    final likeCount = likeOverlay?.count ?? state.likeCount;

    Future<void> run(Future<void> Function() action) async {
      try {
        await action();
      } on ApiException catch (e) {
        if (context.mounted) {
          ScaffoldMessenger.of(context)
            ..hideCurrentSnackBar()
            ..showSnackBar(SnackBar(content: Text(e.message)));
        }
      }
    }

    Widget item(
      IconData icon,
      String label, {
      bool active = false,
      VoidCallback? onTap,
    }) {
      final color = active
          ? scheme.primary
          : (onTap == null ? scheme.outline : scheme.onSurfaceVariant);
      return GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 10),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 18, color: color),
              const SizedBox(width: 5),
              Text(
                label,
                style: TextStyle(
                  fontSize: 12.5,
                  color: color,
                  fontWeight: active ? FontWeight.w600 : FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      );
    }

    return Row(
      children: [
        item(
          Icons.remove_red_eye_outlined,
          '${formatCount(post.viewCount)} 浏览',
        ),
        const Spacer(),
        item(
          liked ? Icons.favorite_rounded : Icons.favorite_border_rounded,
          formatCount(likeCount),
          active: liked,
          onTap: () => run(
            () => ref
                .read(postLikeControllerProvider.notifier)
                .toggle(postId, currentLiked: liked, currentCount: likeCount),
          ),
        ),
        const SizedBox(width: 14),
        item(
          state.detail.favorited
              ? Icons.star_rounded
              : Icons.star_outline_rounded,
          state.detail.favorited ? '已收藏' : '收藏',
          active: state.detail.favorited,
          onTap: () => run(controller.toggleFavorite),
        ),
      ],
    );
  }
}

/// 两级评论：一级评论 + 缩进的回复区。
/// 点评论内容切换回复对象；点爱心点赞（两级均支持）；长按举报；
/// 「共 N 条回复」可展开全量分页拉取，展开后可继续加载或收起。
class _CommentTile extends StatelessWidget {
  const _CommentTile({
    super.key,
    required this.comment,
    required this.thread,
    required this.onReply,
    required this.onLike,
    required this.onReport,
    required this.onToggleReplies,
    required this.onLoadMoreReplies,
  });

  final Comment comment;
  final ReplyThreadState? thread;
  final void Function(Comment target, {required Comment root}) onReply;
  final void Function(Comment target) onLike;
  final void Function(Comment target) onReport;
  final VoidCallback onToggleReplies;
  final VoidCallback onLoadMoreReplies;

  @override
  Widget build(BuildContext context) {
    // 收起态（已加载过全量）只显示预览条数，展开态显示全部
    final t = thread;
    final visibleReplies = (t != null && t.loaded && !t.expanded)
        ? comment.replies.take(t.previewCount).toList()
        : comment.replies;
    final showBox = visibleReplies.isNotEmpty || comment.replyCount > 0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _CommentRow(
          comment: comment,
          onTap: () => onReply(comment, root: comment),
          onLike: () => onLike(comment),
          onLongPress: () => onReport(comment),
        ),
        if (showBox)
          Padding(
            padding: const EdgeInsets.only(left: 42, top: 8),
            child: Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: const Color(0xFFF6F7F9),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (var i = 0; i < visibleReplies.length; i++) ...[
                    if (i > 0) const SizedBox(height: 8),
                    _CommentRow(
                      comment: visibleReplies[i],
                      dense: true,
                      onTap: () => onReply(visibleReplies[i], root: comment),
                      onLike: () => onLike(visibleReplies[i]),
                      onLongPress: () => onReport(visibleReplies[i]),
                    ),
                  ],
                  _ReplyThreadFooter(
                    comment: comment,
                    thread: thread,
                    visibleCount: visibleReplies.length,
                    onToggle: onToggleReplies,
                    onLoadMore: onLoadMoreReplies,
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

/// 回复框尾部多态：共 N 条展开 / 加载中 / 展开更多+收起 / 收起 / 失败重试
class _ReplyThreadFooter extends StatelessWidget {
  const _ReplyThreadFooter({
    required this.comment,
    required this.thread,
    required this.visibleCount,
    required this.onToggle,
    required this.onLoadMore,
  });

  final Comment comment;
  final ReplyThreadState? thread;
  final int visibleCount;
  final VoidCallback onToggle;
  final VoidCallback onLoadMore;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final t = thread ?? const ReplyThreadState();

    TextStyle linkStyle = TextStyle(
      fontSize: 12,
      color: scheme.primary,
      fontWeight: FontWeight.w600,
    );
    Widget link(String text, VoidCallback onTap) => GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Padding(
        padding: const EdgeInsets.only(top: 8),
        child: Text(text, style: linkStyle),
      ),
    );

    if (t.loading) {
      return Padding(
        padding: const EdgeInsets.only(top: 10),
        child: Row(
          children: [
            const SizedBox(
              width: 12,
              height: 12,
              child: CircularProgressIndicator(strokeWidth: 1.6),
            ),
            const SizedBox(width: 6),
            Text(
              '加载回复中…',
              style: TextStyle(fontSize: 12, color: scheme.outline),
            ),
          ],
        ),
      );
    }
    if (t.error != null) {
      // 首页失败重试重新展开；分页失败重试继续拉下一页
      return link('${t.error}，点击重试', t.loaded ? onLoadMore : onToggle);
    }
    if (t.expanded) {
      if (t.hasMore) {
        return Row(
          children: [
            link('展开更多回复', onLoadMore),
            const SizedBox(width: 16),
            link('收起', onToggle),
          ],
        );
      }
      return link('收起回复', onToggle);
    }
    // 收起态：还有未展示的回复才给展开入口
    if (comment.replyCount > visibleCount) {
      return link('共 ${comment.replyCount} 条回复 >', onToggle);
    }
    return const SizedBox.shrink();
  }
}

class _CommentRow extends StatelessWidget {
  const _CommentRow({
    required this.comment,
    this.dense = false,
    this.onTap,
    this.onLike,
    this.onLongPress,
  });

  final Comment comment;
  final bool dense;

  /// 点内容区：切换回复对象
  final VoidCallback? onTap;

  /// 点爱心：点赞/取消
  final VoidCallback? onLike;

  /// 长按内容区：举报评论
  final VoidCallback? onLongPress;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final author = comment.author;
    final likeColor = comment.liked ? scheme.primary : scheme.outline;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        CircleAvatar(
          radius: dense ? 12 : 16,
          backgroundColor: scheme.surfaceContainerHighest,
          foregroundImage: author.avatar.isEmpty
              ? null
              : CachedNetworkImageProvider(author.avatar),
          child: Text(
            author.nickname.isEmpty ? '?' : author.nickname.characters.first,
            style: TextStyle(fontSize: dense ? 10 : 12, color: scheme.primary),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: GestureDetector(
            onTap: onTap,
            onLongPress: onLongPress,
            behavior: HitTestBehavior.opaque,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        author.nickname,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: dense ? 12 : 13,
                          fontWeight: FontWeight.w600,
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                    if (comment.replyToNickname.isNotEmpty) ...[
                      const SizedBox(width: 4),
                      Text(
                        '回复 @${comment.replyToNickname}',
                        style: TextStyle(fontSize: 11, color: scheme.primary),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 3),
                Text(
                  comment.content,
                  style: TextStyle(fontSize: dense ? 13 : 14.5, height: 1.55),
                ),
                const SizedBox(height: 5),
                Row(
                  children: [
                    Text(
                      formatRelativeTime(comment.createdAt),
                      style: TextStyle(fontSize: 11, color: scheme.outline),
                    ),
                    const SizedBox(width: 10),
                    Text(
                      '回复',
                      style: TextStyle(
                        fontSize: 11,
                        color: scheme.onSurfaceVariant,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const Spacer(),
                    // 爱心独立热区，避免与「点内容回复」冲突
                    GestureDetector(
                      onTap: onLike,
                      behavior: HitTestBehavior.opaque,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 2,
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              comment.liked
                                  ? Icons.favorite_rounded
                                  : Icons.favorite_border_rounded,
                              size: 14,
                              color: likeColor,
                            ),
                            const SizedBox(width: 3),
                            Text(
                              comment.likeCount > 0
                                  ? '${comment.likeCount}'
                                  : '赞',
                              style: TextStyle(
                                fontSize: 11,
                                color: likeColor,
                                fontWeight: comment.liked
                                    ? FontWeight.w600
                                    : FontWeight.w400,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _CommentsFooter extends ConsumerWidget {
  const _CommentsFooter({required this.postId, required this.state});

  final int postId;
  final PostDetailState state;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final Widget child;
    if (state.loadingMore) {
      child = const SizedBox(
        width: 20,
        height: 20,
        child: CircularProgressIndicator(strokeWidth: 2),
      );
    } else if (state.loadMoreError != null) {
      child = TextButton(
        onPressed: () => ref
            .read(postDetailControllerProvider(postId).notifier)
            .loadMoreComments(),
        child: Text('${state.loadMoreError}，点击重试'),
      );
    } else if (!state.hasMore && state.comments.isNotEmpty) {
      child = Text(
        '— 到底啦 —',
        style: TextStyle(fontSize: 12, color: scheme.outline),
      );
    } else {
      child = const SizedBox.shrink();
    }
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 16),
      child: Center(child: child),
    );
  }
}

/// 底部评论输入栏（浏览/点赞/收藏已移至正文底部互动行）。
/// 有回复对象时顶部显示「正在回复 @xxx」可取消条。
class _BottomBar extends ConsumerStatefulWidget {
  const _BottomBar({
    required this.postId,
    required this.state,
    required this.replyTarget,
    required this.onCancelReply,
    required this.onSent,
  });

  final int postId;
  final PostDetailState state;
  final CommentReplyTarget? replyTarget;
  final VoidCallback onCancelReply;
  final VoidCallback onSent;

  @override
  ConsumerState<_BottomBar> createState() => _BottomBarState();
}

class _BottomBarState extends ConsumerState<_BottomBar> {
  final _inputController = TextEditingController();
  final _inputFocus = FocusNode();

  @override
  void didUpdateWidget(covariant _BottomBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    // 新选回复对象时自动拉起键盘聚焦输入框
    if (widget.replyTarget != null &&
        widget.replyTarget?.commentId != oldWidget.replyTarget?.commentId) {
      _inputFocus.requestFocus();
    }
  }

  @override
  void dispose() {
    _inputController.dispose();
    _inputFocus.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final content = _inputController.text.trim();
    if (content.isEmpty || widget.state.sendingComment) return;
    try {
      await ref
          .read(postDetailControllerProvider(widget.postId).notifier)
          .sendComment(content, replyTo: widget.replyTarget);
      if (!mounted) return;
      _inputController.clear();
      widget.onSent();
      FocusScope.of(context).unfocus();
    } on ApiException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(SnackBar(content: Text('评论失败：${e.message}')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final state = widget.state;
    final replyTarget = widget.replyTarget;

    return Container(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border(
          top: BorderSide(
            color: scheme.outlineVariant.withValues(alpha: .4),
            width: .6,
          ),
        ),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF1F2430).withValues(alpha: .04),
            blurRadius: 12,
            offset: const Offset(0, -3),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // 回复对象提示条：正在回复 @xxx + 取消
            if (replyTarget != null)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Row(
                  children: [
                    Icon(
                      Icons.subdirectory_arrow_right_rounded,
                      size: 14,
                      color: scheme.primary,
                    ),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Text(
                        '正在回复 @${replyTarget.nickname}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 12,
                          color: scheme.primary,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                    GestureDetector(
                      onTap: widget.onCancelReply,
                      behavior: HitTestBehavior.opaque,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 2,
                        ),
                        child: Icon(
                          Icons.close_rounded,
                          size: 16,
                          color: scheme.outline,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            const SizedBox(height: 8),
            _buildInputRow(scheme, state, replyTarget),
          ],
        ),
      ),
    );
  }

  Widget _buildInputRow(
    ColorScheme scheme,
    PostDetailState state,
    CommentReplyTarget? replyTarget,
  ) {
    return Row(
      children: [
        Expanded(
          child: TextField(
            controller: _inputController,
            focusNode: _inputFocus,
            enabled: !state.sendingComment,
            maxLength: 1000,
            maxLines: 1,
            textInputAction: TextInputAction.send,
            onSubmitted: (_) => _send(),
            style: const TextStyle(fontSize: 14),
            decoration: InputDecoration(
              hintText: replyTarget == null
                  ? '说点什么…'
                  : '回复 @${replyTarget.nickname}…',
              hintStyle: TextStyle(fontSize: 14, color: scheme.outline),
              counterText: '',
              isDense: true,
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 16,
                vertical: 9,
              ),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(22),
                borderSide: BorderSide.none,
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(22),
                borderSide: BorderSide.none,
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(22),
                borderSide: BorderSide(color: scheme.primary, width: 1.2),
              ),
              suffixIcon: state.sendingComment
                  ? const Padding(
                      padding: EdgeInsets.all(10),
                      child: SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    )
                  : IconButton(
                      icon: Icon(
                        Icons.send_rounded,
                        size: 20,
                        color: scheme.primary,
                      ),
                      onPressed: _send,
                    ),
            ),
          ),
        ),
      ],
    );
  }
}

class _ErrorView extends StatelessWidget {
  const _ErrorView({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.description_outlined, size: 56, color: scheme.outline),
          const SizedBox(height: 12),
          Text(message, style: TextStyle(color: scheme.onSurfaceVariant)),
          const SizedBox(height: 16),
          OutlinedButton(onPressed: onRetry, child: const Text('重新加载')),
        ],
      ),
    );
  }
}
