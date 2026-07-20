import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/network/api_exception.dart';
import '../controller/circle_list_controller.dart';
import '../model/circle.dart';
import '../widget/circle_card.dart';

/// 发现圈子页（文档 3.4）：最热/最新排序 + 圈子卡片列表。
class CircleDiscoverPage extends ConsumerWidget {
  const CircleDiscoverPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final list = ref.watch(circleListControllerProvider);
    final controller = ref.read(circleListControllerProvider.notifier);

    return Scaffold(
      appBar: AppBar(
        title: const Text('发现圈子'),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(44),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Align(
              alignment: Alignment.centerLeft,
              child: SegmentedButton<CircleSort>(
                segments: [
                  for (final sort in CircleSort.values)
                    ButtonSegment(value: sort, label: Text(sort.label)),
                ],
                selected: {list.value?.sort ?? CircleSort.hot},
                onSelectionChanged: (selection) =>
                    controller.changeSort(selection.first),
                showSelectedIcon: false,
                style: const ButtonStyle(visualDensity: VisualDensity.compact),
              ),
            ),
          ),
        ),
      ),
      body: switch (list) {
        AsyncData(:final value) => _CircleList(circles: value.circles),
        AsyncError(:final error) => _ErrorView(
          message: error is ApiException ? error.message : '加载失败，请稍后重试',
          onRetry: controller.retry,
        ),
        _ => const Center(child: CircularProgressIndicator()),
      },
    );
  }
}

class _CircleList extends ConsumerWidget {
  const _CircleList({required this.circles});

  final List<Circle> circles;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (circles.isEmpty) {
      return const Center(child: Text('暂无圈子'));
    }
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
      child: ListView.separated(
        physics: const AlwaysScrollableScrollPhysics(),
        // 底部留白：悬浮导航条不遮挡最后一项
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 96),
        itemCount: circles.length,
        separatorBuilder: (context, index) => const SizedBox(height: 8),
        itemBuilder: (context, index) {
          final circle = circles[index];
          return CircleCard(
            key: ValueKey(circle.id),
            circle: circle,
            onTap: () => context.push('/circles/${circle.id}'),
          );
        },
      ),
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
