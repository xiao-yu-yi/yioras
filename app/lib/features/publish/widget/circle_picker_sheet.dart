import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../circle/controller/circle_list_controller.dart';
import '../../circle/model/circle.dart';
import '../../circle/widget/circle_icon.dart';

/// 圈子选择器（发帖必选，文档 3.5.1）：半屏弹层，
/// 与发现圈子页同款双列宫格卡片，返回选中的圈子。
Future<Circle?> showCirclePickerSheet(
  BuildContext context, {
  Circle? selected,
}) {
  return showModalBottomSheet<Circle>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    backgroundColor: Colors.white,
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
        const SizedBox(height: 4),
        Text(
          '动态将发布到所选圈子，需经审核后展示',
          style: TextStyle(fontSize: 11.5, color: scheme.outline),
        ),
        const SizedBox(height: 10),
        Expanded(
          child: switch (list) {
            AsyncData(:final value) => GridView.builder(
              controller: controller,
              padding: const EdgeInsets.fromLTRB(14, 4, 14, 24),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2,
                crossAxisSpacing: 10,
                mainAxisSpacing: 10,
                mainAxisExtent: 70,
              ),
              itemCount: value.circles.length,
              itemBuilder: (context, index) {
                final circle = value.circles[index];
                return _PickerGridCard(
                  key: ValueKey(circle.id),
                  circle: circle,
                  isSelected: circle.id == selected?.id,
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

/// 与发现页同款宫格卡：选中态品牌色描边 + 淡红底 + 右上角对勾
class _PickerGridCard extends StatelessWidget {
  const _PickerGridCard({
    super.key,
    required this.circle,
    required this.isSelected,
    required this.onTap,
  });

  final Circle circle;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: isSelected ? scheme.primary.withValues(alpha: .05) : Colors.white,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10),
          decoration: BoxDecoration(
            border: Border.all(
              color: isSelected
                  ? scheme.primary.withValues(alpha: .6)
                  : const Color(0xFFECEDF2),
              width: isSelected ? 1.4 : 1.2,
            ),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Row(
            children: [
              CircleIconAvatar(circle: circle, size: 40),
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
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        height: 1.2,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      circle.intro.isEmpty ? '快来加入我们' : circle.intro,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 11,
                        color: scheme.outline,
                        height: 1.2,
                      ),
                    ),
                  ],
                ),
              ),
              if (isSelected) ...[
                const SizedBox(width: 4),
                Icon(
                  Icons.check_circle_rounded,
                  size: 18,
                  color: scheme.primary,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
