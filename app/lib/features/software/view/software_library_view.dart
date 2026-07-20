import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/network/api_exception.dart';
import '../../../core/router/routes.dart';
import '../../../core/utils/time_format.dart';
import '../controller/software_list_controller.dart';
import '../model/software.dart';

/// 应用中心 / 社区软件库（文档 3.6，嵌入首页「应用」Tab）：
/// 类型 + 二级分类筛选、最新/最热/下载最多排序、白卡列表 + 分页。
class SoftwareLibraryView extends ConsumerWidget {
  const SoftwareLibraryView({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final list = ref.watch(softwareListControllerProvider);

    return switch (list) {
      AsyncData(:final value) => _LibraryBody(state: value),
      AsyncError(:final error) => _ErrorView(
        message: error is ApiException ? error.message : '加载失败，请稍后重试',
        onRetry: () =>
            ref.read(softwareListControllerProvider.notifier).retryFirstLoad(),
      ),
      _ => const Center(child: CircularProgressIndicator()),
    };
  }
}

class _LibraryBody extends ConsumerWidget {
  const _LibraryBody({required this.state});

  final SoftwareListState state;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final controller = ref.read(softwareListControllerProvider.notifier);

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
            SliverToBoxAdapter(child: _FilterBar(state: state)),
            if (state.items.isEmpty)
              const SliverFillRemaining(
                hasScrollBody: false,
                child: Center(child: Text('该分类下暂无软件，换个筛选看看')),
              )
            else
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(12, 4, 12, 0),
                sliver: SliverList.separated(
                  itemCount: state.items.length,
                  separatorBuilder: (context, index) =>
                      const SizedBox(height: 10),
                  itemBuilder: (context, index) {
                    final item = state.items[index];
                    return _SoftwareCard(
                      key: ValueKey(item.id),
                      item: item,
                      onTap: () =>
                          context.push(Routes.softwareDetailPath(item.id)),
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

/// 筛选区：类型 chips + 分类横滑 chips + 排序胶囊
class _FilterBar extends ConsumerWidget {
  const _FilterBar({required this.state});

  final SoftwareListState state;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final controller = ref.read(softwareListControllerProvider.notifier);
    final categories = ref.watch(softwareCategoryListProvider(state.type));

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _TypeChip(
                label: '全部',
                active: state.type == 0,
                onTap: () => controller.applyFilter(type: 0),
              ),
              const SizedBox(width: 8),
              _TypeChip(
                label: '应用',
                icon: Icons.smartphone_rounded,
                active: state.type == 1,
                onTap: () => controller.applyFilter(type: 1),
              ),
              const SizedBox(width: 8),
              _TypeChip(
                label: '游戏',
                icon: Icons.sports_esports_rounded,
                active: state.type == 2,
                onTap: () => controller.applyFilter(type: 2),
              ),
              const Spacer(),
              _SortSwitch(current: state.sort),
            ],
          ),
          // 二级分类横滑（类型选定后展示该类型下分类）
          if (state.type != 0)
            if (categories case AsyncData(:final value))
              Padding(
                padding: const EdgeInsets.only(top: 10),
                child: SizedBox(
                  height: 30,
                  child: ListView(
                    scrollDirection: Axis.horizontal,
                    children: [
                      _CategoryChip(
                        label: '全部分类',
                        active: state.categoryId == 0,
                        onTap: () => controller.applyFilter(categoryId: 0),
                      ),
                      for (final category in value) ...[
                        const SizedBox(width: 8),
                        _CategoryChip(
                          label: category.name,
                          active: state.categoryId == category.id,
                          onTap: () =>
                              controller.applyFilter(categoryId: category.id),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
        ],
      ),
    );
  }
}

class _TypeChip extends StatelessWidget {
  const _TypeChip({
    required this.label,
    this.icon,
    required this.active,
    required this.onTap,
  });

  final String label;
  final IconData? icon;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return GestureDetector(
      onTap: active ? null : onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 7),
        decoration: BoxDecoration(
          gradient: active
              ? const LinearGradient(
                  colors: [Color(0xFFF43F5E), Color(0xFFFF7849)],
                )
              : null,
          color: active ? null : Colors.white,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
            color: active ? Colors.transparent : const Color(0xFFECEDF2),
            width: 1.2,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              Icon(
                icon,
                size: 14,
                color: active ? Colors.white : scheme.onSurfaceVariant,
              ),
              const SizedBox(width: 4),
            ],
            Text(
              label,
              style: TextStyle(
                fontSize: 13,
                fontWeight: active ? FontWeight.w700 : FontWeight.w500,
                color: active ? Colors.white : scheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CategoryChip extends StatelessWidget {
  const _CategoryChip({
    required this.label,
    required this.active,
    required this.onTap,
  });

  final String label;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return GestureDetector(
      onTap: active ? null : onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
        decoration: BoxDecoration(
          color: active
              ? const Color(0xFFF43F5E).withValues(alpha: .08)
              : const Color(0xFFF0F1F5),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
            color: active
                ? const Color(0xFFF43F5E).withValues(alpha: .5)
                : Colors.transparent,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: active ? FontWeight.w700 : FontWeight.w500,
            color: active ? const Color(0xFFF43F5E) : scheme.onSurfaceVariant,
            height: 1.4,
          ),
        ),
      ),
    );
  }
}

/// 排序切换：点击循环 最新 → 最热 → 下载最多
class _SortSwitch extends ConsumerWidget {
  const _SortSwitch({required this.current});

  final SoftwareSort current;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    return GestureDetector(
      onTap: () {
        final values = SoftwareSort.values;
        final next = values[(values.indexOf(current) + 1) % values.length];
        ref.read(softwareListControllerProvider.notifier).applyFilter(
          sort: next,
        );
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 6),
        decoration: BoxDecoration(
          color: const Color(0xFFF0F1F5),
          borderRadius: BorderRadius.circular(999),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.swap_vert_rounded, size: 15, color: scheme.onSurface),
            const SizedBox(width: 3),
            Text(
              current.label,
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
                color: scheme.onSurface,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 软件白卡：Logo + 名称/版本 + 简介 + 标签 + 下载/评论数
class _SoftwareCard extends StatelessWidget {
  const _SoftwareCard({super.key, required this.item, required this.onTap});

  final SoftwareItem item;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF1F2430).withValues(alpha: .04),
                blurRadius: 10,
                offset: const Offset(0, 3),
              ),
            ],
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(13),
                child: SizedBox(
                  width: 56,
                  height: 56,
                  child: item.logo.isEmpty
                      ? Container(
                          color: scheme.surfaceContainerHighest,
                          child: Icon(Icons.android, color: scheme.outline),
                        )
                      : CachedNetworkImage(
                          imageUrl: item.logo,
                          fit: BoxFit.cover,
                          errorWidget: (context, url, error) =>
                              Container(color: scheme.surfaceContainerHighest),
                        ),
                ),
              ),
              const SizedBox(width: 11),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            item.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        if (item.version.isNotEmpty) ...[
                          const SizedBox(width: 6),
                          Text(
                            'v${item.version}',
                            style: TextStyle(
                              fontSize: 11,
                              color: scheme.outline,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 3),
                    Text(
                      item.intro,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12,
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        for (final tag in item.tags.take(3)) ...[
                          Container(
                            margin: const EdgeInsets.only(right: 5),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: const Color(
                                0xFFF43F5E,
                              ).withValues(alpha: .07),
                              borderRadius: BorderRadius.circular(5),
                            ),
                            child: Text(
                              tag,
                              style: const TextStyle(
                                fontSize: 9.5,
                                color: Color(0xFFF43F5E),
                                fontWeight: FontWeight.w600,
                                height: 1.3,
                              ),
                            ),
                          ),
                        ],
                        const Spacer(),
                        Icon(
                          Icons.download_outlined,
                          size: 13,
                          color: scheme.outline,
                        ),
                        const SizedBox(width: 2),
                        Text(
                          formatCount(item.downloadCount),
                          style: TextStyle(
                            fontSize: 11,
                            color: scheme.outline,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Icon(
                          Icons.chat_bubble_outline_rounded,
                          size: 12,
                          color: scheme.outline,
                        ),
                        const SizedBox(width: 2),
                        Text(
                          formatCount(item.commentCount),
                          style: TextStyle(
                            fontSize: 11,
                            color: scheme.outline,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              // 品牌色「查看」小胶囊
              Container(
                margin: const EdgeInsets.only(top: 12),
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 5,
                ),
                decoration: BoxDecoration(
                  color: const Color(0xFFF43F5E).withValues(alpha: .09),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: const Text(
                  '查看',
                  style: TextStyle(
                    fontSize: 12,
                    color: Color(0xFFF43F5E),
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _FooterStatus extends ConsumerWidget {
  const _FooterStatus({required this.state});

  final SoftwareListState state;

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
        onPressed: () =>
            ref.read(softwareListControllerProvider.notifier).loadMore(),
        child: Text('${state.loadMoreError}，点击重试'),
      );
    } else if (!state.hasMore && state.items.isNotEmpty) {
      child = Text(
        '— 到底啦 —',
        style: TextStyle(fontSize: 12, color: scheme.outline),
      );
    } else {
      child = const SizedBox.shrink();
    }
    // 底部留白：悬浮导航条不遮挡
    return Padding(
      padding: const EdgeInsets.fromLTRB(0, 16, 0, 92),
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
