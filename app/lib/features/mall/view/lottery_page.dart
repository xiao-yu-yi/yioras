import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_exception.dart';
import '../data/mall_repository.dart';
import '../model/mall_models.dart';

/// 奖池数据源
final lotteryPoolProvider = FutureProvider.autoDispose<LotteryPool>((ref) {
  return ref.watch(mallRepositoryProvider).fetchLotteryPool();
});

/// 积分抽奖页（文档 3.9）：宝箱奖池 + 概率公示（合规）+ 抽奖与中奖弹窗。
class LotteryPage extends ConsumerWidget {
  const LotteryPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pool = ref.watch(lotteryPoolProvider);

    return Scaffold(
      backgroundColor: const Color(0xFFF6F7F9),
      appBar: AppBar(
        title: const Text(
          '积分抽奖',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
        ),
      ),
      body: switch (pool) {
        AsyncData(:final value) => _LotteryBody(pool: value),
        AsyncError() => Center(
          child: TextButton(
            onPressed: () => ref.invalidate(lotteryPoolProvider),
            child: const Text('奖池加载失败，点击重试'),
          ),
        ),
        _ => const Center(child: CircularProgressIndicator()),
      },
    );
  }
}

class _LotteryBody extends ConsumerStatefulWidget {
  const _LotteryBody({required this.pool});

  final LotteryPool pool;

  @override
  ConsumerState<_LotteryBody> createState() => _LotteryBodyState();
}

class _LotteryBodyState extends ConsumerState<_LotteryBody> {
  bool _drawing = false;

  Future<void> _draw() async {
    if (_drawing) return;
    setState(() => _drawing = true);
    try {
      final result = await ref.read(mallRepositoryProvider).draw();
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (context) => _PrizeDialog(result: result),
      );
    } on ApiException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(SnackBar(content: Text(e.message)));
      }
    } finally {
      if (mounted) setState(() => _drawing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final pool = widget.pool;
    final totalWeight = pool.prizes.fold<int>(0, (sum, p) => sum + p.weight);

    return ListView(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 24),
      children: [
        // 宝箱主卡
        Container(
          padding: const EdgeInsets.fromLTRB(18, 22, 18, 22),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xFFF43F5E), Color(0xFFFF7849)],
            ),
            borderRadius: BorderRadius.circular(20),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFFF43F5E).withValues(alpha: .3),
                blurRadius: 14,
                offset: const Offset(0, 5),
              ),
            ],
          ),
          child: Column(
            children: [
              Container(
                width: 76,
                height: 76,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: .18),
                  borderRadius: BorderRadius.circular(22),
                ),
                child: const Icon(
                  Icons.card_giftcard_rounded,
                  size: 40,
                  color: Colors.white,
                ),
              ),
              const SizedBox(height: 12),
              const Text(
                '忧珠宝箱',
                style: TextStyle(
                  fontSize: 19,
                  fontWeight: FontWeight.w800,
                  color: Colors.white,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                '单次消耗 ${pool.cost} 忧珠，奖池概率公示见下方',
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.white.withValues(alpha: .85),
                ),
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: 180,
                height: 44,
                child: FilledButton(
                  style: FilledButton.styleFrom(
                    minimumSize: const Size(0, 44),
                    backgroundColor: Colors.white,
                    foregroundColor: const Color(0xFFF43F5E),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(22),
                    ),
                    textStyle: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  onPressed: _drawing ? null : _draw,
                  child: _drawing
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('抽一次'),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        // 概率公示（合规要求）
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                '奖池与概率公示',
                style: TextStyle(fontSize: 14.5, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 10),
              for (var i = 0; i < pool.prizes.length; i++) ...[
                if (i > 0)
                  Divider(
                    height: 16,
                    thickness: .5,
                    color: Theme.of(
                      context,
                    ).colorScheme.outlineVariant.withValues(alpha: .4),
                  ),
                _PrizeRow(
                  prize: pool.prizes[i],
                  probability: totalWeight > 0
                      ? pool.prizes[i].weight / totalWeight
                      : 0,
                ),
              ],
              const SizedBox(height: 10),
              Text(
                '概率=权重/总权重，实时公示；奖励即抽即到账，抽奖消耗不予退还。',
                style: TextStyle(
                  fontSize: 10.5,
                  height: 1.6,
                  color: Theme.of(context).colorScheme.outline,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _PrizeRow extends StatelessWidget {
  const _PrizeRow({required this.prize, required this.probability});

  final LotteryPrize prize;
  final double probability;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Row(
      children: [
        Container(
          width: 34,
          height: 34,
          decoration: BoxDecoration(
            color: prize.kind == 2
                ? const Color(0xFFF1ECFD)
                : const Color(0xFFFEF4E2),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(
            prize.kind == 2
                ? Icons.face_retouching_natural_rounded
                : Icons.brightness_7_rounded,
            size: 17,
            color: prize.kind == 2
                ? const Color(0xFF7C3AED)
                : const Color(0xFFF59E0B),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            prize.name,
            style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600),
          ),
        ),
        Text(
          '${(probability * 100).toStringAsFixed(1)}%',
          style: TextStyle(
            fontSize: 12.5,
            color: scheme.outline,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}

/// 中奖弹窗
class _PrizeDialog extends StatelessWidget {
  const _PrizeDialog({required this.result});

  final DrawResult result;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('恭喜中奖！'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFFF43F5E), Color(0xFFFF7849)],
              ),
              borderRadius: BorderRadius.circular(18),
            ),
            child: const Icon(
              Icons.celebration_rounded,
              size: 32,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            result.prize.name,
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 4),
          Text(
            '已发放到账 · 当前余额 ${result.balance} 忧珠',
            style: TextStyle(
              fontSize: 12,
              color: Theme.of(context).colorScheme.outline,
            ),
          ),
        ],
      ),
      actions: [
        FilledButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('收下奖励'),
        ),
      ],
    );
  }
}
