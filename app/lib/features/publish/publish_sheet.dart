import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/router/routes.dart';

/// 发布动作面板（文档 3.5）：底部导航中央 `+` 弹出，两通道——发动态 / 发软件。
/// 发动态已就绪；发软件属 M3 占位。
Future<void> showPublishSheet(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    builder: (context) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              '发布',
              textAlign: TextAlign.center,
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                _PublishAction(
                  icon: Icons.edit_note,
                  label: '发动态',
                  description: '图文帖子 · 圈子必选',
                  onTap: () {
                    Navigator.of(context).pop();
                    context.push(Routes.publishPost);
                  },
                ),
                const SizedBox(width: 12),
                _PublishAction(
                  icon: Icons.android,
                  label: '发软件',
                  description: '应用/游戏 · M3 开放',
                  onTap: () => _comingSoon(context, '发软件'),
                ),
              ],
            ),
          ],
        ),
      ),
    ),
  );
}

void _comingSoon(BuildContext context, String name) {
  Navigator.of(context).pop();
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text('「$name」正在开发中，敬请期待')));
}

class _PublishAction extends StatelessWidget {
  const _PublishAction({
    required this.icon,
    required this.label,
    required this.description,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final String description;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Expanded(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 18),
          decoration: BoxDecoration(
            color: scheme.primary.withValues(alpha: .06),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Column(
            children: [
              Icon(icon, size: 30, color: scheme.primary),
              const SizedBox(height: 8),
              Text(
                label,
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                description,
                style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
