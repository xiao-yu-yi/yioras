import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_exception.dart';
import '../../../core/utils/time_format.dart';
import '../data/mall_repository.dart';
import '../model/mall_models.dart';

/// 装扮商城数据源
final decorationsProvider = FutureProvider.autoDispose<List<Decoration>>((ref) {
  return ref.watch(mallRepositoryProvider).fetchDecorations();
});

/// 我的装扮仓库数据源
final myDecorationsProvider = FutureProvider.autoDispose<List<MyDecoration>>((
  ref,
) {
  return ref.watch(mallRepositoryProvider).fetchMyDecorations();
});

/// 头像框装扮商城（文档 3.9）：商城宫格兑换 + 我的仓库佩戴/卸下。
class DecorationMallPage extends StatelessWidget {
  const DecorationMallPage({super.key});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        backgroundColor: const Color(0xFFF6F7F9),
        appBar: AppBar(
          title: const Text(
            '头像框装扮',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
          ),
          bottom: TabBar(
            labelStyle: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w700,
            ),
            unselectedLabelStyle: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w500,
            ),
            labelColor: scheme.onSurface,
            unselectedLabelColor: scheme.outline,
            indicatorColor: scheme.primary,
            indicatorSize: TabBarIndicatorSize.label,
            dividerColor: Colors.transparent,
            tabs: const [Tab(text: '商城'), Tab(text: '我的仓库')],
          ),
        ),
        body: const TabBarView(children: [_MallTab(), _WardrobeTab()]),
      ),
    );
  }
}

class _MallTab extends ConsumerWidget {
  const _MallTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final decorations = ref.watch(decorationsProvider);

    return switch (decorations) {
      AsyncData(:final value) => RefreshIndicator(
        onRefresh: () => ref.refresh(decorationsProvider.future),
        child: GridView.builder(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 2,
            crossAxisSpacing: 10,
            mainAxisSpacing: 10,
            mainAxisExtent: 216,
          ),
          itemCount: value.length,
          itemBuilder: (context, index) => _DecoCard(item: value[index]),
        ),
      ),
      AsyncError() => Center(
        child: TextButton(
          onPressed: () => ref.invalidate(decorationsProvider),
          child: const Text('加载失败，点击重试'),
        ),
      ),
      _ => const Center(child: CircularProgressIndicator()),
    };
  }
}

class _DecoCard extends ConsumerStatefulWidget {
  const _DecoCard({required this.item});

  final Decoration item;

  @override
  ConsumerState<_DecoCard> createState() => _DecoCardState();
}

class _DecoCardState extends ConsumerState<_DecoCard> {
  bool _busy = false;

  Future<void> _exchange() async {
    final item = widget.item;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('兑换「${item.name}」？'),
        content: Text(
          '将消耗 ${item.price} 忧珠，'
          '${item.durationDays > 0 ? '有效期 ${item.durationDays} 天' : '永久有效'}。',
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
      await ref.read(mallRepositoryProvider).exchangeDecoration(item.id);
      if (!mounted) return;
      ref.invalidate(decorationsProvider);
      ref.invalidate(myDecorationsProvider);
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text('兑换成功，「${item.name}」已入仓库')));
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

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        children: [
          // 预览：圆形头像框效果
          Container(
            width: 88,
            height: 88,
            padding: const EdgeInsets.all(3),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: const LinearGradient(
                colors: [Color(0xFFF43F5E), Color(0xFFFF7849)],
              ),
            ),
            child: ClipOval(
              child: item.preview.isEmpty
                  ? Container(color: scheme.surfaceContainerHighest)
                  : CachedNetworkImage(
                      imageUrl: item.preview,
                      fit: BoxFit.cover,
                      errorWidget: (context, url, error) =>
                          Container(color: scheme.surfaceContainerHighest),
                    ),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            item.name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 2),
          Text(
            item.durationDays > 0 ? '${item.durationDays} 天' : '永久',
            style: TextStyle(fontSize: 11, color: scheme.outline),
          ),
          const Spacer(),
          SizedBox(
            width: double.infinity,
            height: 32,
            child: item.owned
                ? OutlinedButton(
                    style: OutlinedButton.styleFrom(
                      visualDensity: VisualDensity.compact,
                      foregroundColor: scheme.outline,
                      side: BorderSide(color: scheme.outlineVariant),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                      textStyle: const TextStyle(fontSize: 12.5),
                    ),
                    onPressed: null,
                    child: const Text('已拥有'),
                  )
                : FilledButton(
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
                        : Text('${item.price} 忧珠兑换'),
                  ),
          ),
        ],
      ),
    );
  }
}

class _WardrobeTab extends ConsumerWidget {
  const _WardrobeTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mine = ref.watch(myDecorationsProvider);

    return switch (mine) {
      AsyncData(:final value) when value.isEmpty => const Center(
        child: Text('仓库空空的，去商城兑换一个吧'),
      ),
      AsyncData(:final value) => RefreshIndicator(
        onRefresh: () => ref.refresh(myDecorationsProvider.future),
        child: ListView.separated(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
          itemCount: value.length,
          separatorBuilder: (context, index) => const SizedBox(height: 8),
          itemBuilder: (context, index) => _WardrobeRow(item: value[index]),
        ),
      ),
      AsyncError() => Center(
        child: TextButton(
          onPressed: () => ref.invalidate(myDecorationsProvider),
          child: const Text('加载失败，点击重试'),
        ),
      ),
      _ => const Center(child: CircularProgressIndicator()),
    };
  }
}

class _WardrobeRow extends ConsumerStatefulWidget {
  const _WardrobeRow({required this.item});

  final MyDecoration item;

  @override
  ConsumerState<_WardrobeRow> createState() => _WardrobeRowState();
}

class _WardrobeRowState extends ConsumerState<_WardrobeRow> {
  bool _busy = false;

  Future<void> _toggle() async {
    final item = widget.item;
    setState(() => _busy = true);
    try {
      final repo = ref.read(mallRepositoryProvider);
      if (item.worn) {
        await repo.takeOff(item.decorationId);
      } else {
        await repo.wear(item.decorationId);
      }
      if (!mounted) return;
      ref.invalidate(myDecorationsProvider);
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(content: Text(item.worn ? '已卸下' : '佩戴成功，全站头像即时生效')),
        );
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

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            padding: const EdgeInsets.all(2),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: const LinearGradient(
                colors: [Color(0xFFF43F5E), Color(0xFFFF7849)],
              ),
            ),
            child: ClipOval(
              child: item.preview.isEmpty
                  ? Container(color: scheme.surfaceContainerHighest)
                  : CachedNetworkImage(
                      imageUrl: item.preview,
                      fit: BoxFit.cover,
                      errorWidget: (context, url, error) =>
                          Container(color: scheme.surfaceContainerHighest),
                    ),
            ),
          ),
          const SizedBox(width: 11),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        item.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 14.5,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    if (item.worn) ...[
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF43F5E).withValues(alpha: .09),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: const Text(
                          '佩戴中',
                          style: TextStyle(
                            fontSize: 10,
                            color: Color(0xFFF43F5E),
                            fontWeight: FontWeight.w700,
                            height: 1.3,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 3),
                Text(
                  item.expireAt == null
                      ? '永久有效'
                      : '有效期至 ${formatRelativeTime(item.expireAt!)}',
                  style: TextStyle(fontSize: 11.5, color: scheme.outline),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          SizedBox(
            height: 32,
            child: item.worn
                ? OutlinedButton(
                    style: OutlinedButton.styleFrom(
                      visualDensity: VisualDensity.compact,
                      foregroundColor: scheme.outline,
                      side: BorderSide(color: scheme.outlineVariant),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                      textStyle: const TextStyle(fontSize: 12.5),
                    ),
                    onPressed: _busy ? null : _toggle,
                    child: const Text('卸下'),
                  )
                : FilledButton(
                    style: FilledButton.styleFrom(
                      minimumSize: const Size(64, 32),
                      visualDensity: VisualDensity.compact,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                      textStyle: const TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    onPressed: _busy ? null : _toggle,
                    child: const Text('佩戴'),
                  ),
          ),
        ],
      ),
    );
  }
}
