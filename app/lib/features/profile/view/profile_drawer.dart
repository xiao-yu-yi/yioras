import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/router/routes.dart';
import '../../auth/controller/auth_controller.dart';

/// 侧边抽屉菜单（文档 3.8，视觉对齐设计图）：
/// 用户头部 + 我的设置/兑换记录 + 权益认证/头像框装扮/任务/靓号 + 更多 + 退出登录。
/// 订单/集市按 v1.1 裁剪改为兑换记录；二维码与气泡商城已按最新决策删除；
/// 各占位入口对应 M3/M4 模块。
class ProfileDrawer extends ConsumerWidget {
  const ProfileDrawer({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final auth = ref.watch(authControllerProvider);
    final user = auth is AuthAuthenticated ? auth.user : null;

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

    return Drawer(
      backgroundColor: Colors.white,
      child: SafeArea(
        child: Column(
          children: [
            // 用户头部：头像 + 昵称 + 靓号 ID（贴设计图）
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 18, 18, 14),
              child: Row(
                children: [
                  CircleAvatar(
                    radius: 24,
                    backgroundColor: const Color(0xFFEDF1FA),
                    foregroundImage: (user?.avatar.isEmpty ?? true)
                        ? null
                        : CachedNetworkImageProvider(user!.avatar),
                    child: Text(
                      (user?.nickname.isEmpty ?? true)
                          ? '我'
                          : user!.nickname.characters.first,
                      style: TextStyle(fontSize: 17, color: scheme.primary),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          user?.nickname ?? '我',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          user?.displayNo ?? '',
                          style: TextStyle(
                            fontSize: 11.5,
                            color: scheme.outline,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            Divider(
              height: 1,
              thickness: .6,
              indent: 18,
              endIndent: 18,
              color: scheme.outlineVariant.withValues(alpha: .4),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(10, 10, 10, 0),
                children: [
                  _DrawerItem(
                    icon: Icons.settings_outlined,
                    iconColor: const Color(0xFF3A4256),
                    iconBg: const Color(0xFFF3F4F8),
                    label: '我的设置',
                    onTap: () {
                      Navigator.of(context).pop();
                      context.push(Routes.settings);
                    },
                  ),
                  _DrawerItem(
                    icon: Icons.upload_file_outlined,
                    iconColor: const Color(0xFF8B5CF6),
                    iconBg: const Color(0xFFF1ECFD),
                    label: '我的发布',
                    onTap: () {
                      Navigator.of(context).pop();
                      context.push(Routes.myPublications);
                    },
                  ),
                  _DrawerItem(
                    icon: Icons.receipt_long_outlined,
                    iconColor: const Color(0xFFF43F5E),
                    iconBg: const Color(0xFFFEECEF),
                    label: '兑换记录',
                    milestone: 'M4',
                    onTap: () => comingSoon('兑换记录', 'M4'),
                  ),
                  const _SectionLabel('成长与装扮'),
                  _DrawerItem(
                    icon: Icons.verified_outlined,
                    iconColor: const Color(0xFF10B981),
                    iconBg: const Color(0xFFE7F7F0),
                    label: '权益认证',
                    onTap: () => comingSoon('权益认证'),
                  ),
                  _DrawerItem(
                    icon: Icons.face_retouching_natural_rounded,
                    iconColor: const Color(0xFFEC4899),
                    iconBg: const Color(0xFFFDEDF5),
                    label: '头像框装扮',
                    milestone: 'M4',
                    onTap: () => comingSoon('头像框装扮', 'M4'),
                  ),
                  _DrawerItem(
                    icon: Icons.task_alt_rounded,
                    iconColor: const Color(0xFFF59E0B),
                    iconBg: const Color(0xFFFEF4E2),
                    label: '任务中心',
                    onTap: () {
                      Navigator.of(context).pop();
                      context.push(Routes.taskCenter);
                    },
                  ),
                  _DrawerItem(
                    icon: Icons.confirmation_number_outlined,
                    iconColor: const Color(0xFF06B6D4),
                    iconBg: const Color(0xFFE5F7FB),
                    label: '靓号商城',
                    milestone: 'M4',
                    onTap: () => comingSoon('靓号商城', 'M4'),
                  ),
                  const _SectionLabel('更多'),
                  _DrawerItem(
                    icon: Icons.widgets_outlined,
                    iconColor: const Color(0xFF64748B),
                    iconBg: const Color(0xFFF3F4F8),
                    label: '更多功能',
                    milestone: '后台可配',
                    onTap: () => comingSoon('更多功能'),
                  ),
                ],
              ),
            ),
            Divider(
              height: 1,
              thickness: .6,
              color: scheme.outlineVariant.withValues(alpha: .4),
            ),
            // 退出登录
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 6, 10, 8),
              child: _DrawerItem(
                icon: Icons.logout_rounded,
                iconColor: scheme.error,
                iconBg: scheme.error.withValues(alpha: .08),
                label: '退出登录',
                labelColor: scheme.error,
                showChevron: false,
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
            ),
          ],
        ),
      ),
    );
  }
}

/// 分组小标题
class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 14, 10, 4),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 11.5,
          color: Theme.of(context).colorScheme.outline,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }
}

/// 抽屉菜单行：软色圆角图标 + 标签 + 里程碑标注 + 箭头
class _DrawerItem extends StatelessWidget {
  const _DrawerItem({
    required this.icon,
    required this.iconColor,
    required this.iconBg,
    required this.label,
    required this.onTap,
    this.milestone = '',
    this.labelColor,
    this.showChevron = true,
  });

  final IconData icon;
  final Color iconColor;
  final Color iconBg;
  final String label;
  final String milestone;
  final Color? labelColor;
  final bool showChevron;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 9),
        child: Row(
          children: [
            Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                color: iconBg,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, size: 18, color: iconColor),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  fontSize: 14.5,
                  fontWeight: FontWeight.w600,
                  color: labelColor,
                ),
              ),
            ),
            if (milestone.isNotEmpty) ...[
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: const Color(0xFFF3F4F8),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  milestone,
                  style: TextStyle(
                    fontSize: 10,
                    color: scheme.outline,
                    fontWeight: FontWeight.w600,
                    height: 1.2,
                  ),
                ),
              ),
              const SizedBox(width: 4),
            ],
            if (showChevron)
              Icon(Icons.chevron_right, size: 17, color: scheme.outlineVariant),
          ],
        ),
      ),
    );
  }
}
