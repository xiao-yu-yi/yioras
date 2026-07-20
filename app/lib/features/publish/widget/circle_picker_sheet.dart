import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../circle/controller/circle_list_controller.dart';
import '../../circle/model/circle.dart';

/// 圈子选择器（发帖必选，文档 3.5.1）：半屏弹层，返回选中的圈子。
Future<Circle?> showCirclePickerSheet(
  BuildContext context, {
  Circle? selected,
}) {
  return showModalBottomSheet<Circle>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (context) => DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.6,
      maxChildSize: 0.85,
      builder: (context, scrollController) =>
          _CirclePickerBody(selected: selected, controller: scrollController),
    ),
  );
}

class _CirclePickerBody extends ConsumerWidget {
  const _CirclePickerBody({required this.selected, required this.controller});

  final Circle? selected;
  final ScrollController controller;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final list = ref.watch(circleListControllerProvider);
    final scheme = Theme.of(context).colorScheme;

    return Column(
      children: [
        Text(
          '选择圈子',
          style: Theme.of(
            context,
          ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 8),
        Expanded(
          child: switch (list) {
            AsyncData(:final value) => ListView.builder(
              controller: controller,
              itemCount: value.circles.length,
              itemBuilder: (context, index) {
                final circle = value.circles[index];
                final isSelected = circle.id == selected?.id;
                return ListTile(
                  leading: ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: SizedBox(
                      width: 40,
                      height: 40,
                      child: circle.icon.isEmpty
                          ? ColoredBox(color: scheme.primaryContainer)
                          : CachedNetworkImage(
                              imageUrl: circle.icon,
                              fit: BoxFit.cover,
                              errorWidget: (context, url, error) =>
                                  ColoredBox(color: scheme.primaryContainer),
                            ),
                    ),
                  ),
                  title: Text(circle.name),
                  subtitle: Text(
                    circle.intro,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  trailing: isSelected
                      ? Icon(Icons.check_circle, color: scheme.primary)
                      : null,
                  onTap: () => Navigator.of(context).pop(circle),
                );
              },
            ),
            AsyncError() => Center(
              child: TextButton(
                onPressed: () =>
                    ref.read(circleListControllerProvider.notifier).retry(),
                child: const Text('加载失败，点击重试'),
              ),
            ),
            _ => const Center(child: CircularProgressIndicator()),
          },
        ),
      ],
    );
  }
}
