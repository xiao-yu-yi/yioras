import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/network/api_exception.dart';
import '../controller/circle_list_controller.dart';
import '../model/circle.dart';
import '../widget/circle_icon.dart';

/// 发现圈子页（文档 3.4，视觉对齐设计图）：
/// 大标题头部 + 白卡容器（推荐圈子 + 最热/最新胶囊切换 + 双列宫格卡片）。
class CircleDiscoverPage extends ConsumerWidget {
  const CircleDiscoverPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final list = ref.watch(circleListControllerProvider);
    final controller = ref.read(circleListControllerProvider.notifier);

    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: switch (list) {
          AsyncData(:final value) => _DiscoverBody(state: value),
          AsyncError(:final error) => Column(
            children: [
              const _PageHeader(),
              Expanded(
                child: _ErrorView(
                  message: error is ApiException ? error.message : '加载失败，请稍后重试',
                  onRetry: controller.retry,
                ),
              ),
            ],
          ),
          _ => const Column(
            children: [
              _PageHeader(),
              Expanded(child: Center(child: CircularProgressIndicator())),
            ],
          ),
        },
      ),
    );
  }
}

/// 大标题头部：发现圈子 + 一句话副标题
class _PageHeader extends StatelessWidget {
  const _PageHeader();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Align(
            alignment: Alignment.centerLeft,
            child: Text(
              '发现圈子',
              style: TextStyle(
                fontSize: 26,
                fontWeight: FontWeight.w800,
                height: 1.2,
              ),
            ),
          ),
          const SizedBox(height: 5),
          Text(
            '找到同频的人，加入兴趣部落',
            style: TextStyle(
              fontSize: 13,
              color: scheme.outline,
              fontWeight: FontWeight.w400,
            ),
          ),
        ],
      ),
    );
  }
}

class _DiscoverBody extends ConsumerWidget {
  const _DiscoverBody({required this.state});

  final CircleListState state;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return RefreshIndicator(
      onRefresh: () async {
        try {
          await ref.read(circleListControllerProvider.notifier).refresh();
        } on ApiException catch (e) {
          if (context.mounted) {
            ScaffoldMessenger.of(context)
              ..hideCurrentSnackBar()
              ..showSnackBar(SnackBar(content: Text('刷新失败：${e.message}')));
          }
        }
      },
      child: CustomScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: [
          const SliverToBoxAdapter(child: _PageHeader()),
          SliverToBoxAdapter(
            child: Container(
              margin: const EdgeInsets.fromLTRB(12, 16, 12, 0),
              padding: const EdgeInsets.fromLTRB(14, 14, 14, 6),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(20),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFF1F2430).withValues(alpha: .05),
                    blurRadius: 14,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Text(
                        '推荐圈子',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const Spacer(),
                      _SortSwitch(current: state.sort),
                    ],
                  ),
                  const SizedBox(height: 14),
                  if (state.circles.isEmpty)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 40),
                      child: Center(child: Text('暂无圈子')),
                    )
                  else
                    GridView.builder(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      clipBehavior: Clip.none,
                      gridDelegate:
                          const SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: 2,
                            crossAxisSpacing: 10,
                            mainAxisSpacing: 12,
                            mainAxisExtent: 74,
                          ),
                      itemCount: state.circles.length,
                      itemBuilder: (context, index) {
                        final circle = state.circles[index];
                        return _CircleGridCard(
                          key: ValueKey(circle.id),
                          circle: circle,
                          onTap: () => context.push('/circles/${circle.id}'),
                        );
                      },
                    ),
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 14),
                    child: Center(
                      child: Text(
                        '—  没有更多圈子了  —',
                        style: TextStyle(
                          fontSize: 11.5,
                          color: Color(0xFFB9BDC7),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          // 底部留白：悬浮导航条不遮挡
          const SliverToBoxAdapter(child: SizedBox(height: 100)),
        ],
      ),
    );
  }
}

/// 最热/最新胶囊切换：浅灰轨道 + 白色活动块
class _SortSwitch extends ConsumerWidget {
  const _SortSwitch({required this.current});

  final CircleSort current;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    Widget segment(CircleSort sort) {
      final active = sort == current;
      return GestureDetector(
        onTap: active
            ? null
            : () => ref
                  .read(circleListControllerProvider.notifier)
                  .changeSort(sort),
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
        children: [for (final sort in CircleSort.values) segment(sort)],
      ),
    );
  }
}

/// 双列宫格圈子卡：圆形图标 + 名称 + 一句话简介，置顶圈带角标
class _CircleGridCard extends StatelessWidget {
  const _CircleGridCard({super.key, required this.circle, required this.onTap});

  final Circle circle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Stack(
      clipBehavior: Clip.none,
      children: [
        Material(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(16),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10),
              decoration: BoxDecoration(
                border: Border.all(color: const Color(0xFFECEDF2), width: 1.2),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Row(
                children: [
                  CircleIconAvatar(circle: circle),
                  const SizedBox(width: 9),
                  Expanded(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          circle.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 14.5,
                            fontWeight: FontWeight.w700,
                            height: 1.2,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          circle.intro.isEmpty ? '快来加入我们' : circle.intro,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 11.5,
                            color: scheme.outline,
                            height: 1.2,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        // 置顶角标：骑缝在卡片右上角
        if (circle.pinned)
          Positioned(
            top: -7,
            right: -3,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2.5),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFFF43F5E), Color(0xFFFF7849)],
                ),
                borderRadius: BorderRadius.circular(8),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFFF43F5E).withValues(alpha: .35),
                    blurRadius: 6,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: const Text(
                '置顶',
                style: TextStyle(
                  fontSize: 9.5,
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                  height: 1.2,
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
