import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/network/api_exception.dart';
import '../../../core/router/routes.dart';
import '../../home/data/home_config_repository.dart';
import '../../home/widget/home_banner_carousel.dart';
import '../../home/widget/pinned_post_bar.dart';
import '../../mall/view/mall_hub_view.dart';
import '../../software/view/software_library_view.dart';
import '../controller/feed_controller.dart';
import '../widget/post_card.dart';

/// 首页（文档 3.2）：顶部一级 Tab「首页 / 应用 / 商城」+ 全局搜索入口。
/// 首页 Tab：公告 Banner + 置顶精选 + 推荐信息流；应用 Tab：社区软件库（M3）；
/// 商城 Tab：忧珠商城聚合入口（M4）。
class FeedPage extends ConsumerStatefulWidget {
  const FeedPage({super.key});

  @override
  ConsumerState<FeedPage> createState() => _FeedPageState();
}

class _FeedPageState extends ConsumerState<FeedPage> {
  /// 0 首页 / 1 应用 / 2 商城
  int _tab = 0;

  /// 已进入过的 Tab（懒加载：未访问不发请求）
  final Set<int> _visited = {0};

  void _switchTab(int index) {
    if (index == _tab) return;
    setState(() {
      _tab = index;
      _visited.add(index);
    });
  }

  @override
  Widget build(BuildContext context) {
    final feed = ref.watch(feedControllerProvider);

    return Scaffold(
      appBar: AppBar(
        titleSpacing: 0,
        title: _TopTabs(current: _tab, onChanged: _switchTab),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: _SearchButton(onTap: () => context.push(Routes.search)),
          ),
        ],
      ),
      // IndexedStack 保活各 Tab 的滚动位置；应用/商城懒加载
      body: IndexedStack(
        index: _tab,
        children: [
          switch (feed) {
            AsyncData(:final value) => _FeedList(state: value),
            AsyncError(:final error) => _FirstLoadError(
              message: error is ApiException ? error.message : '加载失败，请稍后重试',
              onRetry: () =>
                  ref.read(feedControllerProvider.notifier).retryFirstLoad(),
            ),
            _ => const _FeedSkeleton(),
          },
          if (_visited.contains(1))
            const SoftwareLibraryView()
          else
            const SizedBox.shrink(),
          if (_visited.contains(2))
            const MallHubView()
          else
            const SizedBox.shrink(),
        ],
      ),
    );
  }
}

/// 顶部一级导航：首页 / 应用 / 商城，选中项加粗 + 品牌色下划线
class _TopTabs extends StatelessWidget {
  const _TopTabs({required this.current, required this.onChanged});

  final int current;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    Widget tab(String label, {bool active = false, VoidCallback? onTap}) =>
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: InkWell(
            borderRadius: BorderRadius.circular(6),
            onTap: active ? null : onTap,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    fontSize: active ? 18 : 15.5,
                    fontWeight: active ? FontWeight.w800 : FontWeight.w500,
                    color: active ? scheme.onSurface : scheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 3),
                Container(
                  width: 18,
                  height: 3,
                  decoration: BoxDecoration(
                    color: active ? scheme.primary : Colors.transparent,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ],
            ),
          ),
        );

    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        tab('首页', active: current == 0, onTap: () => onChanged(0)),
        tab('应用', active: current == 1, onTap: () => onChanged(1)),
        tab('商城', active: current == 2, onTap: () => onChanged(2)),
      ],
    );
  }
}

/// 圆底搜索按钮（贴原型的浅色圆形按钮）
class _SearchButton extends StatelessWidget {
  const _SearchButton({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return InkWell(
      customBorder: const CircleBorder(),
      onTap: onTap,
      child: Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          color: scheme.surfaceContainerHighest.withValues(alpha: .7),
          shape: BoxShape.circle,
        ),
        child: Icon(Icons.search, size: 20, color: scheme.onSurfaceVariant),
      ),
    );
  }
}

class _FeedList extends ConsumerStatefulWidget {
  const _FeedList({required this.state});

  final FeedState state;

  @override
  ConsumerState<_FeedList> createState() => _FeedListState();
}

class _FeedListState extends ConsumerState<_FeedList> {
  Future<void> _onRefresh() async {
    // Banner/置顶配置随信息流一并刷新
    ref.invalidate(homeConfigProvider);
    try {
      await ref.read(feedControllerProvider.notifier).refresh();
    } on ApiException catch (e) {
      // 刷新失败保留旧列表，仅提示
      if (mounted) {
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(SnackBar(content: Text('刷新失败：${e.message}')));
      }
    }
  }

  bool _onScroll(ScrollNotification notification) {
    // 距底部两屏内预加载下一页
    if (notification.metrics.extentAfter < 600) {
      ref.read(feedControllerProvider.notifier).loadMore();
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    final state = widget.state;
    final homeConfig = ref.watch(homeConfigProvider).value;

    if (state.posts.isEmpty) {
      return _EmptyView(onRefresh: _onRefresh);
    }

    return RefreshIndicator(
      onRefresh: _onRefresh,
      child: NotificationListener<ScrollNotification>(
        onNotification: _onScroll,
        child: CustomScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            // 公告 Banner + 置顶精选（配置加载中/失败时静默隐藏，不阻塞信息流）
            if (homeConfig != null && homeConfig.banners.isNotEmpty)
              SliverToBoxAdapter(
                child: HomeBannerCarousel(banners: homeConfig.banners),
              ),
            if (homeConfig != null && homeConfig.pinnedPosts.isNotEmpty)
              SliverToBoxAdapter(
                child: PinnedPostBar(pinnedPosts: homeConfig.pinnedPosts),
              ),
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
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
            SliverToBoxAdapter(child: _FooterStatus(state: state)),
          ],
        ),
      ),
    );
  }
}

/// 列表底部：加载中 / 加载失败重试 / 已到底
class _FooterStatus extends ConsumerWidget {
  const _FooterStatus({required this.state});

  final FeedState state;

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
        onPressed: () => ref.read(feedControllerProvider.notifier).loadMore(),
        child: Text('${state.loadMoreError}，点击重试'),
      );
    } else if (!state.hasMore) {
      child = Text(
        '— 到底啦 —',
        style: TextStyle(fontSize: 12, color: scheme.outline),
      );
    } else {
      child = const SizedBox.shrink();
    }
    // 底部额外留白：悬浮导航条不遮挡尾部内容
    return Padding(
      padding: const EdgeInsets.fromLTRB(0, 16, 0, 92),
      child: Center(child: child),
    );
  }
}

/// 首屏骨架屏：静态占位块，避免额外动效依赖
class _FeedSkeleton extends StatelessWidget {
  const _FeedSkeleton();

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.surfaceContainerHighest;
    Widget block(double height, {double? width, double radius = 6}) =>
        Container(
          height: height,
          width: width,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(radius),
          ),
        );

    return ListView.separated(
      physics: const NeverScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
      itemCount: 4,
      separatorBuilder: (context, index) => const SizedBox(height: 12),
      itemBuilder: (context, index) => Container(
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
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 38,
                    height: 38,
                    decoration: BoxDecoration(
                      color: color,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      block(12, width: 90),
                      const SizedBox(height: 6),
                      block(10, width: 140),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 12),
              block(14, width: 220),
              const SizedBox(height: 8),
              block(12),
              const SizedBox(height: 6),
              block(12, width: 240),
            ],
          ),
        ),
      ),
    );
  }
}

class _EmptyView extends StatelessWidget {
  const _EmptyView({required this.onRefresh});

  final Future<void> Function() onRefresh;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    // 用可滚动结构包裹以支持空态下拉刷新
    return RefreshIndicator(
      onRefresh: onRefresh,
      child: LayoutBuilder(
        builder: (context, constraints) => SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          child: SizedBox(
            height: constraints.maxHeight,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.forum_outlined, size: 56, color: scheme.outline),
                const SizedBox(height: 12),
                Text(
                  '还没有内容，下拉刷新看看',
                  style: TextStyle(color: scheme.onSurfaceVariant),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _FirstLoadError extends StatelessWidget {
  const _FirstLoadError({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Center(
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
    );
  }
}
