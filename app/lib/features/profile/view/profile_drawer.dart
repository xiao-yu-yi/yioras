import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/router/routes.dart';
import '../../auth/controller/auth_controller.dart';

/// 侧边抽屉菜单（文档 3.8）：设置/二维码/兑换记录/认证/装扮/任务/靓号入口 + 退出登录。
/// 各入口对应 M2 后续与 M3/M4 模块，当前为占位提示。
class ProfileDrawer extends ConsumerWidget {
  const ProfileDrawer({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;

    void comingSoon(String name, [String milestone = '']) {
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text(
              milestone.isEmpty
                  ? '「$name」正在开发中，敬请期待'
                  : '「$name」将在 $milestone 开放',
            ),
          ),
        );
    }

    Widget item(
      IconData icon,
      String label, {
      String milestone = '',
      VoidCallback? onTap,
    }) => ListTile(
      leading: Icon(icon, color: scheme.onSurfaceVariant),
      title: Text(label, style: const TextStyle(fontSize: 14.5)),
      trailing: milestone.isEmpty
          ? null
          : Text(
              milestone,
              style: TextStyle(fontSize: 11, color: scheme.outline),
            ),
      dense: true,
      onTap: onTap ?? () => comingSoon(label, milestone),
    );

    return Drawer(
      child: SafeArea(
        child: Column(
          children: [
            const SizedBox(height: 8),
            Expanded(
              child: ListView(
                children: [
                  item(
                    Icons.settings_outlined,
                    '我的设置',
                    onTap: () {
                      Navigator.of(context).pop();
                      context.push(Routes.settings);
                    },
                  ),
                  item(Icons.qr_code_2, '我的二维码'),
                  item(Icons.receipt_long_outlined, '兑换记录', milestone: 'M4'),
                  const Divider(indent: 16, endIndent: 16),
                  item(Icons.verified_outlined, '权益认证'),
                  item(Icons.face_retouching_natural, '头像框装扮', milestone: 'M4'),
                  item(Icons.chat_bubble_outline, '气泡商城', milestone: 'M4'),
                  item(Icons.task_alt, '任务中心', milestone: 'M3'),
                  item(
                    Icons.confirmation_number_outlined,
                    '靓号商城',
                    milestone: 'M4',
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            ListTile(
              leading: Icon(Icons.logout, color: scheme.error),
              title: Text(
                '退出登录',
                style: TextStyle(fontSize: 14.5, color: scheme.error),
              ),
              dense: true,
              onTap: () async {
                final confirmed = await showDialog<bool>(
                  context: context,
                  builder: (context) => AlertDialog(
                    title: const Text('退出登录？'),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.of(context).pop(false),
                        child: const Text('取消'),
                      ),
                      FilledButton(
                        onPressed: () => Navigator.of(context).pop(true),
                        child: const Text('退出'),
                      ),
                    ],
                  ),
                );
                if (confirmed == true) {
                  // 登录态切换后由路由 redirect 自动回登录页
                  await ref.read(authControllerProvider.notifier).logout();
                }
              },
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}
