import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/network/api_exception.dart';
import '../../../core/router/routes.dart';
import '../../../core/utils/time_format.dart';
import '../controller/task_center_controller.dart';
import '../model/growth_models.dart';

/// 忧珠资产页（文档 3.9）：余额头卡（去签到入口）+ 类型筛选 + 收支流水。
class YouzhuPage extends ConsumerWidget {
  const YouzhuPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final logs = ref.watch(youzhuLogsControllerProvider);

    return Scaffold(
      backgroundColor: const Color(0xFFF6F7F9),
      appBar: AppBar(
        title: const Text(
          '我的忧珠',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
        ),
      ),
      body: switch (logs) {
        AsyncData(:final value) => _YouzhuBody(state: value),
        AsyncError(:final error) => _ErrorView(
          message: error is ApiException ? error.message : '加载失败，请稍后重试',
          onRetry: () =>
              ref.read(youzhuLogsControllerProvider.notifier).retryFirstLoad(),
        ),
        _ => const Center(child: CircularProgressIndicator()),
      },
    );
  }
}

class _YouzhuBody extends ConsumerWidget {
  const _YouzhuBody({required this.state});

  final YouzhuLogsState state;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return NotificationListener<ScrollNotification>(
      onNotification: (notification) {
        if (notification.metrics.extentAfter < 400) {
          ref.read(youzhuLogsControllerProvider.notifier).loadMore();
        }
        return false;
      },
      child: CustomScrollView(
        slivers: [
          const SliverToBoxAdapter(child: _BalanceCard()),
          SliverToBoxAdapter(child: _FilterChips(current: state.bizType)),
          if (state.logs.isEmpty)
            const SliverFillRemaining(
              hasScrollBody: false,
              child: Center(child: Text('该类型下暂无流水')),
            )
          else
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(12, 4, 12, 0),
              sliver: SliverToBoxAdapter(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Column(
                    children: [
                      for (var i = 0; i < state.logs.length; i++) ...[
                        if (i > 0)
                          Divider(
                            height: 1,
                            thickness: .5,
                            color: Theme.of(context).colorScheme.outlineVariant
                                .withValues(alpha: .4),
                          ),
                        _LogRow(log: state.logs[i]),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          SliverToBoxAdapter(child: _FooterStatus(state: state)),
        ],
      ),
    );
  }
}

/// 深色余额头卡（对齐我的页「忧珠资产」深色胶囊语言）
class _BalanceCard extends ConsumerWidget {
  const _BalanceCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final account = ref.watch(youzhuAccountProvider);

    return Container(
      margin: const EdgeInsets.fromLTRB(12, 10, 12, 0),
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 18),
      decoration: BoxDecoration(
        color: const Color(0xFF2A2F3A),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF1F2430).withValues(alpha: .25),
            blurRadius: 14,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '忧珠余额',
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.white.withValues(alpha: .65),
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 6),
                switch (account) {
                  AsyncData(:final value) => Text(
                    '${value.balance}',
                    style: const TextStyle(
                      fontSize: 30,
                      fontWeight: FontWeight.w800,
                      color: Color(0xFFFFD98A),
                      height: 1.1,
                    ),
                  ),
                  AsyncError() => Text(
                    '— —',
                    style: TextStyle(
                      fontSize: 24,
                      color: Colors.white.withValues(alpha: .5),
                    ),
                  ),
                  _ => const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Color(0xFFFFD98A),
                    ),
                  ),
                },
                const SizedBox(height: 5),
                Text(
                  '任务与签到产出 · 兑换装扮/靓号/抽奖消耗',
                  style: TextStyle(
                    fontSize: 10.5,
                    color: Colors.white.withValues(alpha: .55),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          SizedBox(
            height: 36,
            child: FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFFFFD98A),
                foregroundColor: const Color(0xFF2A2F3A),
                padding: const EdgeInsets.symmetric(horizontal: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(18),
                ),
                textStyle: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                ),
              ),
              onPressed: () => context.push(Routes.taskCenter),
              child: Text(
                account.value?.signedToday == true ? '做任务赚忧珠' : '去签到',
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// 流水类型筛选 chips 横滑
class _FilterChips extends ConsumerWidget {
  const _FilterChips({required this.current});

  final YouzhuBizType current;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    return SizedBox(
      height: 52,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 10),
        children: [
          for (final type in YouzhuBizType.values) ...[
            GestureDetector(
              onTap: type == current
                  ? null
                  : () => ref
                        .read(youzhuLogsControllerProvider.notifier)
                        .changeBizType(type),
              child: Container(
                margin: const EdgeInsets.only(right: 8),
                padding: const EdgeInsets.symmetric(horizontal: 13),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  gradient: type == current
                      ? const LinearGradient(
                          colors: [Color(0xFFF43F5E), Color(0xFFFF7849)],
                        )
                      : null,
                  color: type == current ? null : Colors.white,
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(
                    color: type == current
                        ? Colors.transparent
                        : const Color(0xFFECEDF2),
                    width: 1.2,
                  ),
                ),
                child: Text(
                  type.label,
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: type == current
                        ? FontWeight.w700
                        : FontWeight.w500,
                    color: type == current
                        ? Colors.white
                        : scheme.onSurfaceVariant,
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _LogRow extends StatelessWidget {
  const _LogRow({required this.log});

  final YouzhuLog log;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final income = log.amount >= 0;
    final type = YouzhuBizType.fromValue(log.bizType);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: income
                  ? const Color(0xFFF43F5E).withValues(alpha: .08)
                  : const Color(0xFFF0F1F5),
              borderRadius: BorderRadius.circular(11),
            ),
            child: Icon(
              switch (type) {
                YouzhuBizType.task => Icons.task_alt,
                YouzhuBizType.signIn => Icons.event_available_outlined,
                YouzhuBizType.operation => Icons.card_giftcard_outlined,
                YouzhuBizType.exchange => Icons.redeem_outlined,
                YouzhuBizType.lottery => Icons.casino_outlined,
                YouzhuBizType.paidUnlock => Icons.lock_open_outlined,
                YouzhuBizType.all => Icons.receipt_long_outlined,
              },
              size: 18,
              color: income ? const Color(0xFFF43F5E) : scheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(width: 11),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  log.remark.isEmpty ? type.label : log.remark,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  '${formatRelativeTime(log.createdAt)} · 余额 ${log.balanceAfter}',
                  style: TextStyle(fontSize: 11, color: scheme.outline),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Text(
            income ? '+${log.amount}' : '${log.amount}',
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w800,
              color: income ? const Color(0xFFF43F5E) : scheme.onSurface,
            ),
          ),
        ],
      ),
    );
  }
}

class _FooterStatus extends ConsumerWidget {
  const _FooterStatus({required this.state});

  final YouzhuLogsState state;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final Widget child;
    if (state.loadingMore) {
      child = const SizedBox(
        width: 18,
        height: 18,
        child: CircularProgressIndicator(strokeWidth: 2),
      );
    } else if (state.loadMoreError != null) {
      child = TextButton(
        onPressed: () =>
            ref.read(youzhuLogsControllerProvider.notifier).loadMore(),
        child: Text('${state.loadMoreError}，点击重试'),
      );
    } else if (!state.hasMore && state.logs.isNotEmpty) {
      child = Text(
        '— 到底啦 —',
        style: TextStyle(fontSize: 12, color: scheme.outline),
      );
    } else {
      child = const SizedBox.shrink();
    }
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 16),
      child: Center(child: child),
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
          Icon(Icons.account_balance_wallet_outlined,
              size: 56, color: scheme.outline),
          const SizedBox(height: 12),
          Text(message, style: TextStyle(color: scheme.onSurfaceVariant)),
          const SizedBox(height: 16),
          OutlinedButton(onPressed: onRetry, child: const Text('重新加载')),
        ],
      ),
    );
  }
}
