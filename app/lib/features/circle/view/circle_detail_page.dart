import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/network/api_exception.dart';
import '../../../core/router/routes.dart';
import '../../../core/utils/time_format.dart';
import '../../feed/widget/post_card.dart';
import '../controller/circle_detail_controller.dart';
import '../model/circle.dart';

/// 圈子详情页（文档 3.4）：封面头图 + 简介 + 加入/退出 + 圈内帖子流（最新）。
class CircleDetailPage extends ConsumerWidget {
  const CircleDetailPage({super.key, required this.circleId});

  final int circleId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final detail = ref.watch(circleDetailControllerProvider(circleId));

    return switch (detail) {
      AsyncData(:final value) => Scaffold(
        body: _DetailBody(circleId: circleId, state: value),
      ),
      AsyncError(:final error) => _ErrorScaffold(
        message: error is ApiException ? error.message : '加载失败，请稍后重试',
        onRetry: () => ref
            .read(circleDetailControllerProvider(circleId).notifier)
            .retryFirstLoad(),
      ),
      _ => Scaffold(
        appBar: AppBar(title: const Text('圈子')),
        body: const Center(child: CircularProgressIndicator()),
      ),
    };
  }
}

class _DetailBody extends ConsumerWidget {
  const _DetailBody({required this.circleId, required this.state});

  final int circleId;
  final CircleDetailState state;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final controller = ref.read(
      circleDetailControllerProvider(circleId).notifier,
    );

    return RefreshIndicator(
      // 下沉留出 AppBar 区域，避免被封面遮挡
      edgeOffset: 220,
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
            _Header(circle: state.circle, circleId: circleId),
            if (state.posts.isEmpty)
              const SliverFillRemaining(
                hasScrollBody: false,
                child: Center(child: Text('圈子里还没有帖子，来发第一帖吧')),
              )
            else
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
                sliver: SliverList.separated(
                  itemCount: state.posts.length,
                  separatorBuilder: (context, index) =>
                      const SizedBox(height: 10),
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
              child: _FooterStatus(state: state, circleId: circleId),
            ),
          ],
        ),
      ),
    );
  }
}

/// 折叠头：封面 + 圈子信息 + 加入按钮
class _Header extends ConsumerWidget {
  const _Header({required this.circle, required this.circleId});

  final Circle circle;
  final int circleId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    return SliverAppBar(
      pinned: true,
      expandedHeight: 200,
      foregroundColor: Colors.white,
      backgroundColor: scheme.primary,
      title: Text(circle.name),
      flexibleSpace: FlexibleSpaceBar(
        background: Stack(
          fit: StackFit.expand,
          children: [
            if (circle.cover.isNotEmpty)
              CachedNetworkImage(
                imageUrl: circle.cover,
                fit: BoxFit.cover,
                errorWidget: (context, url, error) =>
                    Container(color: scheme.primary),
              )
            else
              Container(color: scheme.primary),
            // 底部渐变压暗保证文字可读
            const DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Colors.transparent, Colors.black54],
                ),
              ),
            ),
            Positioned(
              left: 16,
              right: 16,
              bottom: 14,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Row(
                          children: [
                            Flexible(
                              child: Text(
                                circle.name,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 20,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                            if (circle.isOfficial) ...[
                              const SizedBox(width: 6),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 5,
                                  vertical: 1.5,
                                ),
                                decoration: BoxDecoration(
                                  color: Colors.white.withValues(alpha: .25),
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: const Text(
                                  '官方',
                                  style: TextStyle(
                                    fontSize: 10,
                                    color: Colors.white,
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '${formatCount(circle.memberCount)} 成员 · ${formatCount(circle.postCount)} 帖子',
                          style: const TextStyle(
                            color: Colors.white70,
                            fontSize: 12,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          circle.intro,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Colors.white70,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  _JoinButton(circleId: circleId),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _JoinButton extends ConsumerWidget {
  const _JoinButton({required this.circleId});

  final int circleId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(circleDetailControllerProvider(circleId)).value;
    if (state == null) return const SizedBox.shrink();
    final joined = state.circle.joined;

    return FilledButton(
      style: FilledButton.styleFrom(
        minimumSize: const Size(88, 36),
        backgroundColor: joined
            ? Colors.white.withValues(alpha: .25)
            : Colors.white,
        foregroundColor: joined
            ? Colors.white
            : Theme.of(context).colorScheme.primary,
      ),
      onPressed: state.joinBusy
          ? null
          : () async {
              try {
                await ref
                    .read(circleDetailControllerProvider(circleId).notifier)
                    .toggleJoin();
              } on ApiException catch (e) {
                if (context.mounted) {
                  ScaffoldMessenger.of(context)
                    ..hideCurrentSnackBar()
                    ..showSnackBar(SnackBar(content: Text(e.message)));
                }
              }
            },
      child: state.joinBusy
          ? const SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : Text(joined ? '已加入' : '+ 加入'),
    );
  }
}

class _FooterStatus extends ConsumerWidget {
  const _FooterStatus({required this.state, required this.circleId});

  final CircleDetailState state;
  final int circleId;

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
            .read(circleDetailControllerProvider(circleId).notifier)
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

class _ErrorScaffold extends StatelessWidget {
  const _ErrorScaffold({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('圈子')),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.wifi_off_outlined, size: 56, color: scheme.outline),
            const SizedBox(height: 12),
            Text(message, style: TextStyle(color: scheme.onSurfaceVariant)),
            const SizedBox(height: 16),
            OutlinedButton(onPressed: onRetry, child: const Text('重新加载')),
          ],
        ),
      ),
    );
  }
}
