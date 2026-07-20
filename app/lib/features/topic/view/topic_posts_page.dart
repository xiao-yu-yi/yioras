import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/network/api_exception.dart';
import '../../../core/router/routes.dart';
import '../../../core/utils/time_format.dart';
import '../../feed/widget/post_card.dart';
import '../controller/topic_posts_controller.dart';
import '../data/topic_repository.dart';

/// 按话题名打开聚合页：先解析话题 ID 再进页（帖子卡片 chip 只有名字）。
Future<void> openTopicByName(
  BuildContext context,
  WidgetRef ref,
  String name,
) async {
  try {
    final topic = await ref.read(topicRepositoryProvider).resolveByName(name);
    if (context.mounted) {
      context.push(Routes.topicPostsPath(topic.id));
    }
  } on ApiException catch (e) {
    if (context.mounted) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(e.message)));
    }
  }
}

/// 话题聚合页（文档 3.2 话题；对齐 server GET /topics/:id/posts）：
/// 品牌渐变头卡（#话题名 + 讨论数）+ 最热/最新胶囊 + 帖子流分页。
class TopicPostsPage extends ConsumerWidget {
  const TopicPostsPage({super.key, required this.topicId});

  final int topicId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(topicPostsControllerProvider(topicId));

    return Scaffold(
      backgroundColor: const Color(0xFFF6F7F9),
      appBar: AppBar(
        title: const Text(
          '话题',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
        ),
      ),
      body: switch (state) {
        AsyncData(:final value) => _TopicBody(topicId: topicId, state: value),
        AsyncError(:final error) => _ErrorView(
          message: error is ApiException ? error.message : '加载失败，请稍后重试',
          onRetry: () => ref
              .read(topicPostsControllerProvider(topicId).notifier)
              .retryFirstLoad(),
        ),
        _ => const Center(child: CircularProgressIndicator()),
      },
    );
  }
}

class _TopicBody extends ConsumerWidget {
  const _TopicBody({required this.topicId, required this.state});

  final int topicId;
  final TopicPostsState state;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final controller = ref.read(topicPostsControllerProvider(topicId).notifier);

    return RefreshIndicator(
      onRefresh: () async {
        try {
          await controller.refresh();
        } on ApiException catch (e) {
          if (context.mounted) {
            ScaffoldMessenger.of(context)
              ..hideCurrentSnackBar()
              ..showSnackBar(SnackBar(content: Text('刷新失败：${e.message}')));
          }
        }
      },
      child: NotificationListener<ScrollNotification>(
        onNotification: (notification) {
          if (notification.metrics.extentAfter < 600) {
            controller.loadMore();
          }
          return false;
        },
        child: CustomScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            SliverToBoxAdapter(child: _TopicHeader(topic: state.topic)),
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(20, 14, 20, 0),
              sliver: SliverToBoxAdapter(
                child: Row(
                  children: [
                    const Text(
                      '话题讨论',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const Spacer(),
                    _SortSwitch(topicId: topicId, current: state.sort),
                  ],
                ),
              ),
            ),
            if (state.sortSwitching)
              const SliverPadding(
                padding: EdgeInsets.symmetric(vertical: 56),
                sliver: SliverToBoxAdapter(
                  child: Center(
                    child: SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  ),
                ),
              )
            else if (state.posts.isEmpty)
              const SliverFillRemaining(
                hasScrollBody: false,
                child: Center(child: Text('这个话题下还没有讨论，来发第一帖吧')),
              )
            else
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
                sliver: SliverList.separated(
                  itemCount: state.posts.length,
                  separatorBuilder: (context, index) =>
                      const SizedBox(height: 12),
                  itemBuilder: (context, index) {
                    final post = state.posts[index];
                    return PostCard(
                      key: ValueKey(post.id),
                      post: post,
                      onTap: () => context.push(Routes.postDetailPath(post.id)),
                      onAuthorTap: () =>
                          context.push(Routes.userProfilePath(post.author.id)),
                    );
                  },
                ),
              ),
            SliverToBoxAdapter(
              child: _FooterStatus(topicId: topicId, state: state),
            ),
          ],
        ),
      ),
    );
  }
}

/// 品牌渐变话题头卡：大 # 符号 + 话题名 + 讨论数
class _TopicHeader extends StatelessWidget {
  const _TopicHeader({required this.topic});

  final TopicInfo topic;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 10, 12, 0),
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 18),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFFF43F5E), Color(0xFFFF7849)],
        ),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFFF43F5E).withValues(alpha: .3),
            blurRadius: 14,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: .18),
              borderRadius: BorderRadius.circular(15),
            ),
            child: const Center(
              child: Text(
                '#',
                style: TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.w800,
                  color: Colors.white,
                  height: 1,
                ),
              ),
            ),
          ),
          const SizedBox(width: 13),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  topic.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 19,
                    fontWeight: FontWeight.w800,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '${formatCount(topic.postCount)} 篇讨论 · 参与话题让更多人看见',
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.white.withValues(alpha: .85),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// 最热/最新胶囊（与圈子详情同款视觉）
class _SortSwitch extends ConsumerWidget {
  const _SortSwitch({required this.topicId, required this.current});

  final int topicId;
  final TopicPostSort current;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;

    Future<void> change(TopicPostSort sort) async {
      try {
        await ref
            .read(topicPostsControllerProvider(topicId).notifier)
            .changeSort(sort);
      } on ApiException catch (e) {
        if (context.mounted) {
          ScaffoldMessenger.of(context)
            ..hideCurrentSnackBar()
            ..showSnackBar(SnackBar(content: Text('切换失败：${e.message}')));
        }
      }
    }

    Widget segment(TopicPostSort sort) {
      final active = sort == current;
      return GestureDetector(
        onTap: active ? null : () => change(sort),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          decoration: BoxDecoration(
            color: active ? Colors.white : Colors.transparent,
            borderRadius: BorderRadius.circular(999),
            boxShadow: active
                ? [
                    BoxShadow(
                      color: const Color(0xFF1F2430).withValues(alpha: .08),
                      blurRadius: 6,
                      offset: const Offset(0, 1),
                    ),
                  ]
                : null,
          ),
          child: Text(
            sort.label,
            style: TextStyle(
              fontSize: 12.5,
              fontWeight: active ? FontWeight.w700 : FontWeight.w500,
              color: active ? scheme.onSurface : scheme.outline,
            ),
          ),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: const Color(0xFFF0F1F5),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [for (final sort in TopicPostSort.values) segment(sort)],
      ),
    );
  }
}

class _FooterStatus extends ConsumerWidget {
  const _FooterStatus({required this.topicId, required this.state});

  final int topicId;
  final TopicPostsState state;

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
            .read(topicPostsControllerProvider(topicId).notifier)
            .loadMore(),
        child: Text('${state.loadMoreError}，点击重试'),
      );
    } else if (!state.hasMore && state.posts.isNotEmpty) {
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
          Icon(Icons.tag, size: 56, color: scheme.outline),
          const SizedBox(height: 12),
          Text(message, style: TextStyle(color: scheme.onSurfaceVariant)),
          const SizedBox(height: 16),
          OutlinedButton(onPressed: onRetry, child: const Text('重新加载')),
        ],
      ),
    );
  }
}
