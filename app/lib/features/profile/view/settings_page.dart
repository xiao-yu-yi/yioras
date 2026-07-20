import 'package:flutter/material.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/cache/key_value_cache.dart';
import '../../../core/network/api_exception.dart';
import '../../../core/router/routes.dart';
import '../../auth/controller/auth_controller.dart';
import '../data/profile_repository.dart';

/// 我的设置（文档 3.8 侧边抽屉「我的设置」）：
/// 编辑资料 / 清理缓存 / 关于 / 注销账号 / 退出登录；
/// 账号安全与通知开关待后端能力就绪后接入。
class SettingsPage extends ConsumerStatefulWidget {
  const SettingsPage({super.key});

  @override
  ConsumerState<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends ConsumerState<SettingsPage> {
  bool _clearingCache = false;
  bool _deactivating = false;

  void _comingSoon(String name) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text('「$name」正在开发中，敬请期待')));
  }

  Future<void> _clearCache() async {
    if (_clearingCache) return;
    setState(() => _clearingCache = true);
    try {
      // 业务 JSON 缓存（推荐流 SWR 等）+ 图片磁盘缓存
      await ref.read(cacheProvider).clear();
      await DefaultCacheManager().emptyCache();
      if (mounted) {
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(const SnackBar(content: Text('缓存已清理')));
      }
    } finally {
      if (mounted) setState(() => _clearingCache = false);
    }
  }

  Future<void> _deactivateAccount() async {
    if (_deactivating) return;
    // 双重确认：注销不可恢复
    final firstConfirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('注销账号？'),
        content: const Text('注销后账号数据将被删除且不可恢复，包括帖子、评论、忧珠资产与关注关系。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('继续'),
          ),
        ],
      ),
    );
    if (firstConfirm != true || !mounted) return;

    final secondConfirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('最后确认'),
        content: const Text('确定要永久注销当前账号吗？此操作无法撤销。'),
        actions: [
          FilledButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('我再想想'),
          ),
          TextButton(
            style: TextButton.styleFrom(
              foregroundColor: Theme.of(context).colorScheme.error,
            ),
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('确认注销'),
          ),
        ],
      ),
    );
    if (secondConfirm != true || !mounted) return;

    setState(() => _deactivating = true);
    try {
      await ref.read(profileRepositoryProvider).deactivateAccount();
      // 注销成功按登出处理，路由自动回登录页
      await ref.read(authControllerProvider.notifier).logout();
    } on ApiException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(SnackBar(content: Text('注销失败：${e.message}')));
      }
    } finally {
      if (mounted) setState(() => _deactivating = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    Widget group(String title, List<Widget> children) {
      final items = <Widget>[];
      for (var i = 0; i < children.length; i++) {
        if (i > 0) {
          items.add(
            Divider(
              height: 1,
              thickness: .6,
              indent: 56,
              color: scheme.outlineVariant.withValues(alpha: .4),
            ),
          );
        }
        items.add(children[i]);
      }
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(22, 16, 22, 6),
            child: Text(
              title,
              style: TextStyle(
                fontSize: 11.5,
                color: scheme.outline,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          Container(
            margin: const EdgeInsets.symmetric(horizontal: 12),
            clipBehavior: Clip.antiAlias,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Column(children: items),
          ),
        ],
      );
    }

    Widget item(
      IconData icon,
      String label, {
      required Color iconColor,
      required Color iconBg,
      VoidCallback? onTap,
      Widget? trailing,
      Color? color,
    }) => InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 11, 12, 11),
        child: Row(
          children: [
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: iconBg,
                borderRadius: BorderRadius.circular(9),
              ),
              child: Icon(icon, size: 17, color: iconColor),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  fontSize: 14.5,
                  fontWeight: FontWeight.w600,
                  color: color,
                ),
              ),
            ),
            trailing ??
                Icon(
                  Icons.chevron_right,
                  size: 18,
                  color: scheme.outlineVariant,
                ),
          ],
        ),
      ),
    );

    Widget spinner() => const SizedBox(
      width: 16,
      height: 16,
      child: CircularProgressIndicator(strokeWidth: 2),
    );

    return Scaffold(
      backgroundColor: const Color(0xFFF6F7F9),
      appBar: AppBar(
        backgroundColor: const Color(0xFFF6F7F9),
        title: const Text(
          '我的设置',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 24),
        children: [
          group('账号', [
            item(
              Icons.person_outline,
              '编辑资料',
              iconColor: const Color(0xFFF43F5E),
              iconBg: const Color(0xFFFEECEF),
              onTap: () => context.push(Routes.editProfile),
            ),
            item(
              Icons.security_outlined,
              '账号安全',
              iconColor: const Color(0xFF3B82F6),
              iconBg: const Color(0xFFEAF2FE),
              onTap: () => _comingSoon('账号安全'),
            ),
            item(
              Icons.notifications_none_rounded,
              '通知设置',
              iconColor: const Color(0xFFF59E0B),
              iconBg: const Color(0xFFFEF4E2),
              onTap: () => _comingSoon('通知设置'),
            ),
          ]),
          group('通用', [
            item(
              Icons.cleaning_services_outlined,
              '清理缓存',
              iconColor: const Color(0xFF10B981),
              iconBg: const Color(0xFFE7F7F0),
              trailing: _clearingCache ? spinner() : null,
              onTap: _clearCache,
            ),
            item(
              Icons.info_outline_rounded,
              '关于 Yiora',
              iconColor: const Color(0xFF64748B),
              iconBg: const Color(0xFFF3F4F8),
              onTap: () => showAboutDialog(
                context: context,
                applicationName: 'Yiora',
                applicationVersion: 'v1.0.0 (M2 内测)',
                applicationLegalese: '兴趣圈子 · 有趣灵魂的聚集地',
              ),
            ),
          ]),
          group('账号操作', [
            item(
              Icons.person_off_outlined,
              '注销账号',
              iconColor: scheme.error,
              iconBg: scheme.error.withValues(alpha: .08),
              color: scheme.error,
              trailing: _deactivating ? spinner() : null,
              onTap: _deactivateAccount,
            ),
          ]),
          const SizedBox(height: 24),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: OutlinedButton(
              style: OutlinedButton.styleFrom(
                minimumSize: const Size.fromHeight(48),
                foregroundColor: scheme.error,
                backgroundColor: Colors.white,
                side: BorderSide(color: scheme.error.withValues(alpha: .3)),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(24),
                ),
                textStyle: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                ),
              ),
              onPressed: () async {
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
                  await ref.read(authControllerProvider.notifier).logout();
                }
              },
              child: const Text('退出登录'),
            ),
          ),
        ],
      ),
    );
  }
}
