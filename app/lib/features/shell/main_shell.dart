import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/ws/ws_providers.dart';
import '../publish/publish_sheet.dart';

/// 主壳：底部 5 Tab（首页/圈子/发布/消息/我的）。
/// 中央「发布」不是路由分支，点击弹出发布面板；其余四项映射 shell 分支。
class MainShell extends ConsumerWidget {
  const MainShell({super.key, required this.navigationShell});

  final StatefulNavigationShell navigationShell;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final unread = ref.watch(conversationBadgeProvider);

    return Scaffold(
      // 悬浮胶囊导航条：内容延伸到条后
      extendBody: true,
      body: navigationShell,
      bottomNavigationBar: SafeArea(
        top: false,
        child: Container(
          margin: const EdgeInsets.fromLTRB(14, 0, 14, 10),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(30),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: .08),
                blurRadius: 18,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: SizedBox(
            height: 60,
            child: Row(
              children: [
                _TabItem(
                  icon: Icons.home_outlined,
                  activeIcon: Icons.home,
                  label: '首页',
                  active: navigationShell.currentIndex == 0,
                  onTap: () => _goBranch(0),
                ),
                _TabItem(
                  icon: Icons.workspaces_outline,
                  activeIcon: Icons.workspaces,
                  label: '圈子',
                  active: navigationShell.currentIndex == 1,
                  onTap: () => _goBranch(1),
                ),
                _PublishButton(onTap: () => showPublishSheet(context)),
                _TabItem(
                  icon: Icons.chat_bubble_outline,
                  activeIcon: Icons.chat_bubble,
                  label: '消息',
                  active: navigationShell.currentIndex == 2,
                  badgeCount: unread,
                  onTap: () => _goBranch(2),
                ),
                _TabItem(
                  icon: Icons.person_outline,
                  activeIcon: Icons.person,
                  label: '我的',
                  active: navigationShell.currentIndex == 3,
                  onTap: () => _goBranch(3),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _goBranch(int index) {
    navigationShell.goBranch(
      index,
      // 重复点击当前 Tab 回到该分支初始位置（如列表回顶）
      initialLocation: index == navigationShell.currentIndex,
    );
  }
}

class _TabItem extends StatelessWidget {
  const _TabItem({
    required this.icon,
    required this.activeIcon,
    required this.label,
    required this.active,
    required this.onTap,
    this.badgeCount = 0,
  });

  final IconData icon;
  final IconData activeIcon;
  final String label;
  final bool active;
  final VoidCallback onTap;

  /// 未读角标数，0 不显示
  final int badgeCount;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final color = active ? scheme.primary : scheme.onSurfaceVariant;
    return Expanded(
      child: InkWell(
        onTap: onTap,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Badge(
              isLabelVisible: badgeCount > 0,
              label: Text(badgeCount > 99 ? '99+' : '$badgeCount'),
              child: Icon(active ? activeIcon : icon, size: 24, color: color),
            ),
            const SizedBox(height: 2),
            Text(
              label,
              style: TextStyle(
                fontSize: 10.5,
                color: color,
                fontWeight: active ? FontWeight.w600 : FontWeight.w400,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 中央发布按钮：品牌红渐变圆钮 `+`（贴原型）
class _PublishButton extends StatelessWidget {
  const _PublishButton({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Expanded(
      child: Center(
        child: InkWell(
          onTap: onTap,
          customBorder: const CircleBorder(),
          child: Container(
            width: 46,
            height: 46,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  scheme.primary,
                  Color.lerp(scheme.primary, const Color(0xFFFF7A45), .45)!,
                ],
              ),
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: scheme.primary.withValues(alpha: .35),
                  blurRadius: 10,
                  offset: const Offset(0, 3),
                ),
              ],
            ),
            child: const Icon(Icons.add, color: Colors.white, size: 26),
          ),
        ),
      ),
    );
  }
}
