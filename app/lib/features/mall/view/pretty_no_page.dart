import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_exception.dart';
import '../data/mall_repository.dart';
import '../model/mall_models.dart';

/// 靓号在售数据源
final prettyNosProvider = FutureProvider.autoDispose<List<PrettyNo>>((ref) {
  return ref.watch(mallRepositoryProvider).fetchPrettyNos();
});

/// 靓号商城（文档 3.9）：稀有度分档在售列表 + 兑换确认。
/// 兑换成功后新靓号立即生效（替换展示 ID）。
class PrettyNoPage extends ConsumerWidget {
  const PrettyNoPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final nos = ref.watch(prettyNosProvider);

    return Scaffold(
      backgroundColor: const Color(0xFFF6F7F9),
      appBar: AppBar(
        title: const Text(
          '靓号商城',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
        ),
      ),
      body: switch (nos) {
        AsyncData(:final value) when value.isEmpty => const Center(
          child: Text('靓号已被兑换一空，晚点再来看看'),
        ),
        AsyncData(:final value) => RefreshIndicator(
          onRefresh: () => ref.refresh(prettyNosProvider.future),
          child: ListView.separated(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
            itemCount: value.length,
            separatorBuilder: (context, index) => const SizedBox(height: 8),
            itemBuilder: (context, index) => _PrettyNoRow(item: value[index]),
          ),
        ),
        AsyncError() => Center(
          child: TextButton(
            onPressed: () => ref.invalidate(prettyNosProvider),
            child: const Text('加载失败，点击重试'),
          ),
        ),
        _ => const Center(child: CircularProgressIndicator()),
      },
    );
  }
}

class _PrettyNoRow extends ConsumerStatefulWidget {
  const _PrettyNoRow({required this.item});

  final PrettyNo item;

  @override
  ConsumerState<_PrettyNoRow> createState() => _PrettyNoRowState();
}

class _PrettyNoRowState extends ConsumerState<_PrettyNoRow> {
  bool _busy = false;

  (Color, Color) get _rarityColors => switch (widget.item.rarity) {
    3 => (const Color(0xFFB45309), const Color(0xFFFEF3C7)),
    2 => (const Color(0xFF7C3AED), const Color(0xFFF1ECFD)),
    _ => (const Color(0xFF64748B), const Color(0xFFF3F4F8)),
  };

  Future<void> _exchange() async {
    final item = widget.item;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('兑换靓号 ${item.no}？'),
        content: Text(
          '将消耗 ${item.price} 忧珠，兑换后立即替换你的展示 ID，原 ID 不可找回。',
          style: const TextStyle(fontSize: 13.5, height: 1.6),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('确认兑换'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _busy = true);
    try {
      final no = await ref
          .read(mallRepositoryProvider)
          .exchangePrettyNo(item.id);
      if (!mounted) return;
      ref.invalidate(prettyNosProvider);
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text('兑换成功，新靓号 $no 已生效')));
    } on ApiException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(SnackBar(content: Text(e.message)));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final item = widget.item;
    final (fg, bg) = _rarityColors;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: bg,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(Icons.confirmation_number_outlined, size: 20, color: fg),
          ),
          const SizedBox(width: 11),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      item.no,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                        letterSpacing: .5,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: bg,
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        item.rarityLabel,
                        style: TextStyle(
                          fontSize: 10.5,
                          color: fg,
                          fontWeight: FontWeight.w700,
                          height: 1.3,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 3),
                Text(
                  '兑换后立即生效，全站展示',
                  style: TextStyle(fontSize: 11.5, color: scheme.outline),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          SizedBox(
            height: 32,
            child: FilledButton(
              style: FilledButton.styleFrom(
                minimumSize: const Size(0, 32),
                visualDensity: VisualDensity.compact,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
                textStyle: const TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w700,
                ),
              ),
              onPressed: _busy ? null : _exchange,
              child: _busy
                  ? const SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(
                        strokeWidth: 1.8,
                        color: Colors.white,
                      ),
                    )
                  : Text('${item.price} 忧珠'),
            ),
          ),
        ],
      ),
    );
  }
}
