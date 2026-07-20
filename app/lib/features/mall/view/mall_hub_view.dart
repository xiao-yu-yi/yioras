import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/router/routes.dart';
import '../../growth/controller/task_center_controller.dart';

/// 首页「商城」Tab（文档 3.2 一级导航）：忧珠余额条 + 三大商城入口。
/// 忧珠计价（不可充值），余额不足去任务中心赚取。
class MallHubView extends ConsumerWidget {
  const MallHubView({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final account = ref.watch(youzhuAccountProvider);

    return RefreshIndicator(
      onRefresh: () => ref.refresh(youzhuAccountProvider.future),
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 100),
        children: [
          // 余额条（深色，与忧珠资产页同语言）
          Material(
            color: const Color(0xFF2A2F3A),
            borderRadius: BorderRadius.circular(18),
            child: InkWell(
              onTap: () => context.push(Routes.youzhu),
              borderRadius: BorderRadius.circular(18),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 14, 12, 14),
                child: Row(
                  children: [
                    const Icon(
                      Icons.brightness_7_rounded,
                      size: 20,
                      color: Color(0xFFFFD98A),
                    ),
                    const SizedBox(width: 10),
                    Text(
                      '我的忧珠',
                      style: TextStyle(
                        fontSize: 13,
                        color: Colors.white.withValues(alpha: .75),
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const Spacer(),
                    Text(
                      account.value != null ? '${account.value!.balance}' : '— —',
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                        color: Color(0xFFFFD98A),
                      ),
                    ),
                    const SizedBox(width: 4),
                    Icon(
                      Icons.chevron_right,
                      size: 18,
                      color: Colors.white.withValues(alpha: .5),
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),
          _EntryCard(
            icon: Icons.face_retouching_natural_rounded,
            gradient: const LinearGradient(
              colors: [Color(0xFFF43F5E), Color(0xFFFF7849)],
            ),
            title: '头像框装扮',
            subtitle: '兑换心仪头像框，全站头像即时生效',
            onTap: () => context.push(Routes.decorationMall),
          ),
          const SizedBox(height: 10),
          _EntryCard(
            icon: Icons.confirmation_number_outlined,
            gradient: const LinearGradient(
              colors: [Color(0xFF06B6D4), Color(0xFF3B82F6)],
            ),
            title: '靓号商城',
            subtitle: '稀有靓号先到先得，兑换立即生效',
            onTap: () => context.push(Routes.prettyNoMall),
          ),
          const SizedBox(height: 10),
          _EntryCard(
            icon: Icons.casino_outlined,
            gradient: const LinearGradient(
              colors: [Color(0xFF8B5CF6), Color(0xFFEC4899)],
            ),
            title: '积分抽奖',
            subtitle: '忧珠宝箱概率公示，大奖即抽即到账',
            onTap: () => context.push(Routes.lottery),
          ),
          const SizedBox(height: 14),
          Center(
            child: Text(
              '忧珠通过任务与签到获取，不可充值 · 兑换记录见「我的-兑换记录」',
              style: TextStyle(
                fontSize: 10.5,
                color: Theme.of(context).colorScheme.outline,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _EntryCard extends StatelessWidget {
  const _EntryCard({
    required this.icon,
    required this.gradient,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final Gradient gradient;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF1F2430).withValues(alpha: .04),
                blurRadius: 10,
                offset: const Offset(0, 3),
              ),
            ],
          ),
          child: Row(
            children: [
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  gradient: gradient,
                  borderRadius: BorderRadius.circular(15),
                ),
                child: Icon(icon, size: 26, color: Colors.white),
              ),
              const SizedBox(width: 13),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontSize: 15.5,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      subtitle,
                      style: TextStyle(fontSize: 12, color: scheme.outline),
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right, size: 20, color: scheme.outline),
            ],
          ),
        ),
      ),
    );
  }
}
