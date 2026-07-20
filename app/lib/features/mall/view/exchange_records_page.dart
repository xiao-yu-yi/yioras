import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/utils/time_format.dart';
import '../data/mall_repository.dart';
import '../model/mall_models.dart';

/// 兑换记录数据源
final exchangeRecordsProvider =
    FutureProvider.autoDispose<List<ExchangeRecord>>((ref) {
      return ref.watch(mallRepositoryProvider).fetchExchangeRecords(size: 50);
    });

/// 兑换记录页（文档 3.8 抽屉：装扮/靓号/抽奖的忧珠兑换流水）。
class ExchangeRecordsPage extends ConsumerWidget {
  const ExchangeRecordsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final records = ref.watch(exchangeRecordsProvider);

    return Scaffold(
      backgroundColor: const Color(0xFFF6F7F9),
      appBar: AppBar(
        title: const Text(
          '兑换记录',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
        ),
      ),
      body: switch (records) {
        AsyncData(:final value) when value.isEmpty => const Center(
          child: Text('还没有兑换记录'),
        ),
        AsyncData(:final value) => RefreshIndicator(
          onRefresh: () => ref.refresh(exchangeRecordsProvider.future),
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 14),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Column(
                  children: [
                    for (var i = 0; i < value.length; i++) ...[
                      if (i > 0)
                        Divider(
                          height: 1,
                          thickness: .5,
                          color: Theme.of(
                            context,
                          ).colorScheme.outlineVariant.withValues(alpha: .4),
                        ),
                      _RecordRow(record: value[i]),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
        AsyncError() => Center(
          child: TextButton(
            onPressed: () => ref.invalidate(exchangeRecordsProvider),
            child: const Text('加载失败，点击重试'),
          ),
        ),
        _ => const Center(child: CircularProgressIndicator()),
      },
    );
  }
}

class _RecordRow extends StatelessWidget {
  const _RecordRow({required this.record});

  final ExchangeRecord record;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final (icon, fg, bg) = switch (record.kind) {
      2 => (
        Icons.confirmation_number_outlined,
        const Color(0xFF06B6D4),
        const Color(0xFFE5F7FB),
      ),
      3 => (
        Icons.casino_outlined,
        const Color(0xFF7C3AED),
        const Color(0xFFF1ECFD),
      ),
      _ => (
        Icons.face_retouching_natural_rounded,
        const Color(0xFFEC4899),
        const Color(0xFFFDEDF5),
      ),
    };

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: bg,
              borderRadius: BorderRadius.circular(11),
            ),
            child: Icon(icon, size: 18, color: fg),
          ),
          const SizedBox(width: 11),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  record.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  '${record.kindLabel} · ${formatRelativeTime(record.createdAt)}',
                  style: TextStyle(fontSize: 11, color: scheme.outline),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Text(
            '-${record.cost}',
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w800,
              color: scheme.onSurface,
            ),
          ),
        ],
      ),
    );
  }
}
