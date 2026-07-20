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
import '../widget/circle_icon.dart';

/// 圈子详情页（文档 3.4，视觉对齐发现页新风格）：
/// 封面头图 + 骑缝白色信息卡（圆形图标/名称/数据/加入按钮）+ 圈内帖子流（最新）。
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
      // 下沉留出封面区域，避免被遮挡
      edgeOffset: 180,
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
            _CoverBar(circle: state.circle),
            SliverToBoxAdapter(
              child: _InfoCard(circle: state.circle, circleId: circleId),
            ),
            const SliverPadding(
              padding: EdgeInsets.fromLTRB(20, 6, 20, 0),
              sliver: SliverToBoxAdapter(
                child: Text(
                  '圈内动态',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
                ),
              ),
            ),
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
              child: _FooterStatus(state: state, circleId: circleId),
            ),
          ],
        ),
      ),
    );
  }
}

/// 折叠封面条：仅封面图 + 渐变压暗，信息移入下方骑缝白卡
class _CoverBar extends StatelessWidget {
  const _CoverBar({required this.circle});

  final Circle circle;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SliverAppBar(
      pinned: true,
      expandedHeight: 176,
      foregroundColor: Colors.white,
      backgroundColor: scheme.primary,
      title: Text(
        circle.name,
        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
      ),
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
            // 顶部轻压暗保证返回键可见，底部留给白卡骑缝
            const DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Colors.black26, Colors.transparent],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 骑缝白色信息卡：圆形图标 + 名称/官方标 + 数据 + 简介 + 加入按钮
class _InfoCard extends StatelessWidget {
  const _InfoCard({required this.circle, required this.circleId});

  final Circle circle;
  final int circleId;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 12, 12, 0),
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF1F2430).withValues(alpha: .06),
            blurRadius: 14,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 白圈描边的圆形图标
              Container(
                padding: const EdgeInsets.all(2),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: const Color(0xFFECEDF2),
                    width: 1.2,
                  ),
                ),
                child: CircleIconAvatar(circle: circle, size: 52),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            circle.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 17,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                        if (circle.isOfficial) ...[
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              gradient: PostCard.brandGradient,
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: const Text(
                              '官方',
                              style: TextStyle(
                                fontSize: 9.5,
                                color: Colors.white,
                                fontWeight: FontWeight.w700,
                                height: 1.2,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 5),
                    Text(
                      '${formatCount(circle.memberCount)} 成员 · ${formatCount(circle.postCount)} 帖子',
                      style: TextStyle(
                        fontSize: 12,
                        color: scheme.outline,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              _JoinButton(circleId: circleId),
            ],
          ),
          if (circle.intro.isNotEmpty) ...[
            const SizedBox(height: 12),
            Text(
              circle.intro,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 12.5,
                height: 1.5,
                color: scheme.onSurfaceVariant.withValues(alpha: .9),
              ),
            ),
          ],
        ],
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

    Future<void> toggle() async {
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
    }

    final Widget child = state.joinBusy
        ? const SizedBox(
            width: 16,
            height: 16,
            child: CircularProgressIndicator(strokeWidth: 2),
          )
        : Text(joined ? '已加入' : '+ 加入');

    if (joined) {
      return OutlinedButton(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(78, 34),
          padding: const EdgeInsets.symmetric(horizontal: 14),
          visualDensity: VisualDensity.compact,
          foregroundColor: Theme.of(context).colorScheme.outline,
          side: BorderSide(color: Theme.of(context).colorScheme.outlineVariant),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          textStyle: const TextStyle(fontSize: 13),
        ),
        onPressed: state.joinBusy ? null : toggle,
        child: child,
      );
    }
    return FilledButton(
      style: FilledButton.styleFrom(
        minimumSize: const Size(78, 34),
        padding: const EdgeInsets.symmetric(horizontal: 16),
        visualDensity: VisualDensity.compact,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
      ),
      onPressed: state.joinBusy ? null : toggle,
      child: child,
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
