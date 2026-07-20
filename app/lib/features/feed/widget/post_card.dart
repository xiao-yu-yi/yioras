import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_exception.dart';
import '../../../core/utils/time_format.dart';
import '../../topic/view/topic_posts_page.dart' show openTopicByName;
import '../controller/post_like_controller.dart';
import '../model/post.dart';

/// 推荐流帖子卡片（文档 3.2）：作者行 / 标题 / 摘要 / 图片宫格 / 话题 / 互动栏。
/// 视觉语言：白卡 + 柔投影，品牌红橙渐变仅用于 Lv 徽章与置顶胶囊（与置顶精选条呼应）。
class PostCard extends StatelessWidget {
  const PostCard({super.key, required this.post, this.onTap, this.onAuthorTap});

  final Post post;
  final VoidCallback? onTap;

  /// 点击作者头像/昵称（进入他人主页）
  final VoidCallback? onAuthorTap;

  /// 品牌红橙渐变（与首页置顶精选条同语言）
  static const Gradient brandGradient = LinearGradient(
    colors: [Color(0xFFF43F5E), Color(0xFFFF7849)],
  );

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF1F2430).withValues(alpha: .05),
            blurRadius: 14,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Material(
        type: MaterialType.transparency,
        borderRadius: BorderRadius.circular(16),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 14, 14, 4),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _AuthorRow(post: post, onAuthorTap: onAuthorTap),
                if (post.title.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  _TitleLine(post: post),
                ],
                if (post.content.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Text(
                    post.content,
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 14.5,
                      height: 1.6,
                      color: scheme.onSurface.withValues(alpha: .74),
                    ),
                  ),
                ],
                if (post.images.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  _ImageGrid(images: post.images),
                ],
                if (post.topics.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    runSpacing: 6,
                    children: [
                      for (final topic in post.topics) _TopicChip(name: topic),
                    ],
                  ),
                ],
                const SizedBox(height: 12),
                Divider(
                  height: 1,
                  thickness: .6,
                  color: scheme.outlineVariant.withValues(alpha: .45),
                ),
                _ActionBar(post: post),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _AuthorRow extends StatelessWidget {
  const _AuthorRow({required this.post, this.onAuthorTap});

  final VoidCallback? onAuthorTap;

  final Post post;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final author = post.author;
    return Row(
      children: [
        // 头像与昵称区域可点进他人主页
        GestureDetector(
          onTap: onAuthorTap,
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
              radius: 18,
              backgroundColor: scheme.surfaceContainerHighest,
              foregroundImage: author.avatar.isEmpty
                  ? null
                  : CachedNetworkImageProvider(author.avatar),
              child: Text(
                author.nickname.isEmpty
                    ? '?'
                    : author.nickname.characters.first,
                style: TextStyle(fontSize: 14, color: scheme.primary),
              ),
            ),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: GestureDetector(
            onTap: onAuthorTap,
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
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                    _LevelBadge(level: author.level),
                    if (author.badge.isNotEmpty) ...[
                      const SizedBox(width: 4),
                      _TitleBadge(text: author.badge),
                    ],
                  ],
                ),
                const SizedBox(height: 3),
                Text.rich(
                  TextSpan(
                    children: [
                      TextSpan(text: formatRelativeTime(post.createdAt)),
                      if (post.circleName.isNotEmpty) ...[
                        const TextSpan(text: '  ·  '),
                        TextSpan(
                          text: post.circleName,
                          style: TextStyle(
                            color: scheme.primary.withValues(alpha: .85),
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ],
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 11.5,
                    color: scheme.onSurfaceVariant.withValues(alpha: .9),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _TitleLine extends StatelessWidget {
  const _TitleLine({required this.post});

  final Post post;

  @override
  Widget build(BuildContext context) {
    // 运营置顶帖标题红色高亮（文档 3.2），色值对齐品牌红
    final titleColor = post.isTop
        ? const Color(0xFFE2374B)
        : Theme.of(context).colorScheme.onSurface;
    return Text.rich(
      TextSpan(
        children: [
          if (post.isTop)
            WidgetSpan(
              alignment: PlaceholderAlignment.middle,
              child: Container(
                margin: const EdgeInsets.only(right: 6),
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  gradient: PostCard.brandGradient,
                  borderRadius: BorderRadius.circular(5),
                ),
                child: const Text(
                  '置顶',
                  style: TextStyle(
                    fontSize: 10,
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                    height: 1.2,
                  ),
                ),
              ),
            ),
          TextSpan(text: post.title),
        ],
      ),
      maxLines: 2,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(
        fontSize: 16.5,
        fontWeight: FontWeight.w700,
        height: 1.4,
        letterSpacing: .1,
        color: titleColor,
      ),
    );
  }
}

class _LevelBadge extends StatelessWidget {
  const _LevelBadge({required this.level});

  final int level;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
      decoration: BoxDecoration(
        gradient: PostCard.brandGradient,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        'Lv.$level',
        style: const TextStyle(
          fontSize: 9,
          fontWeight: FontWeight.w800,
          color: Colors.white,
          height: 1.2,
        ),
      ),
    );
  }
}

class _TitleBadge extends StatelessWidget {
  const _TitleBadge({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF3DC),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        text,
        style: const TextStyle(
          fontSize: 9,
          fontWeight: FontWeight.w700,
          color: Color(0xFFA36A00),
          height: 1.2,
        ),
      ),
    );
  }
}

/// 图片宫格：1 张大图；2/3 张一行；≥4 张取 3 张 + 「+N」蒙层
class _ImageGrid extends StatelessWidget {
  const _ImageGrid({required this.images});

  final List<String> images;

  @override
  Widget build(BuildContext context) {
    if (images.length == 1) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: AspectRatio(
          aspectRatio: 16 / 9,
          child: _NetImage(url: images.first),
        ),
      );
    }

    final visible = images.take(3).toList();
    final more = images.length - 3;
    return Row(
      children: [
        for (var i = 0; i < visible.length; i++) ...[
          if (i > 0) const SizedBox(width: 6),
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: AspectRatio(
                aspectRatio: 1,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    _NetImage(url: visible[i]),
                    // 最后一格显示剩余张数
                    if (i == 2 && more > 0)
                      Container(
                        color: Colors.black.withValues(alpha: .4),
                        alignment: Alignment.center,
                        child: Text(
                          '+$more',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 17,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ],
    );
  }
}

class _NetImage extends StatelessWidget {
  const _NetImage({required this.url});

  final String url;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return CachedNetworkImage(
      imageUrl: url,
      fit: BoxFit.cover,
      fadeInDuration: const Duration(milliseconds: 200),
      placeholder: (context, url) => Container(
        color: scheme.surfaceContainerHighest.withValues(alpha: .6),
      ),
      errorWidget: (context, url, error) => Container(
        color: scheme.surfaceContainerHighest.withValues(alpha: .6),
        child: Icon(Icons.broken_image_outlined, color: scheme.outline),
      ),
    );
  }
}

/// 话题胶囊：点按进话题聚合页（按名解析 ID）
class _TopicChip extends ConsumerWidget {
  const _TopicChip({required this.name});

  final String name;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    return GestureDetector(
      onTap: () => openTopicByName(context, ref, name),
      child: Container(
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
      ),
    );
  }
}

/// 底部互动栏：左侧浏览量（弱灰），右侧 评论 + 爱心点赞。
/// 点赞走全局 PostLikeController（与帖子详情页状态同步），
/// 乐观更新失败回滚提示；独立热区不触发整卡跳转。
class _ActionBar extends ConsumerWidget {
  const _ActionBar({required this.post});

  final Post post;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    // 覆盖层缺省回退列表接口下发的静态计数
    final overlay = ref.watch(postLikeControllerProvider)[post.id];
    final liked = overlay?.liked ?? false;
    final likeCount = overlay?.count ?? post.likeCount;

    Widget item(
      IconData icon,
      String label, {
      Color? color,
      FontWeight? weight,
    }) => Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 17, color: color ?? scheme.onSurfaceVariant),
        const SizedBox(width: 5),
        Text(
          label,
          style: TextStyle(
            fontSize: 12.5,
            color: color ?? scheme.onSurfaceVariant,
            fontWeight: weight ?? FontWeight.w500,
          ),
        ),
      ],
    );

    Future<void> toggleLike() async {
      try {
        await ref
            .read(postLikeControllerProvider.notifier)
            .toggle(post.id, currentLiked: liked, currentCount: likeCount);
      } on ApiException catch (e) {
        if (context.mounted) {
          ScaffoldMessenger.of(context)
            ..hideCurrentSnackBar()
            ..showSnackBar(SnackBar(content: Text(e.message)));
        }
      }
    }

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: item(
              Icons.remove_red_eye_outlined,
              '${formatCount(post.viewCount)} 浏览',
              color: scheme.outline,
            ),
          ),
          const Spacer(),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: item(
              Icons.chat_bubble_outline_rounded,
              formatCount(post.commentCount),
            ),
          ),
          const SizedBox(width: 10),
          // 爱心独立热区：吸收点击不触发整卡跳详情
          GestureDetector(
            onTap: toggleLike,
            behavior: HitTestBehavior.opaque,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
              child: item(
                liked ? Icons.favorite_rounded : Icons.favorite_border_rounded,
                formatCount(likeCount),
                color: liked ? scheme.primary : null,
                weight: liked ? FontWeight.w600 : null,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
