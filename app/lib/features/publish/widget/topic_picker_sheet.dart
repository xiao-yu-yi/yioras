import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/publish_repository.dart';
import '../model/post_draft.dart';

/// 热门话题数据源（选择器打开时拉取）
final hotTopicsProvider = FutureProvider.autoDispose<List<String>>((ref) {
  return ref.watch(publishRepositoryProvider).fetchHotTopics();
});

/// 话题选择器（≤5 个，文档 3.5.1）：热门话题多选 + 自定义新建，返回选中列表。
Future<List<String>?> showTopicPickerSheet(
  BuildContext context, {
  required List<String> selected,
}) {
  return showModalBottomSheet<List<String>>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (context) => Padding(
      // 输入框跟随键盘抬起
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: _TopicPickerBody(initial: selected),
    ),
  );
}

class _TopicPickerBody extends ConsumerStatefulWidget {
  const _TopicPickerBody({required this.initial});

  final List<String> initial;

  @override
  ConsumerState<_TopicPickerBody> createState() => _TopicPickerBodyState();
}

class _TopicPickerBodyState extends ConsumerState<_TopicPickerBody> {
  late final List<String> _selected = [...widget.initial];
  final _inputController = TextEditingController();

  @override
  void dispose() {
    _inputController.dispose();
    super.dispose();
  }

  void _toggle(String topic) {
    setState(() {
      if (_selected.contains(topic)) {
        _selected.remove(topic);
      } else if (_selected.length < PostDraft.maxTopics) {
        _selected.add(topic);
      } else {
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(
            const SnackBar(content: Text('最多选择 ${PostDraft.maxTopics} 个话题')),
          );
      }
    });
  }

  void _addCustom() {
    final name = _inputController.text.trim().replaceAll('#', '');
    if (name.isEmpty) return;
    if (name.length > 30) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(const SnackBar(content: Text('话题最长 30 字')));
      return;
    }
    if (!_selected.contains(name) && _selected.length >= PostDraft.maxTopics) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          const SnackBar(content: Text('最多选择 ${PostDraft.maxTopics} 个话题')),
        );
      return;
    }
    setState(() {
      if (!_selected.contains(name)) _selected.add(name);
      _inputController.clear();
    });
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final hotTopics = ref.watch(hotTopicsProvider);

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    '选择话题（${_selected.length}/${PostDraft.maxTopics}）',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                TextButton(
                  onPressed: () => Navigator.of(context).pop(_selected),
                  child: const Text('完成'),
                ),
              ],
            ),
            const SizedBox(height: 4),
            TextField(
              controller: _inputController,
              maxLength: 30,
              decoration: InputDecoration(
                hintText: '输入新话题，回车添加',
                counterText: '',
                prefixIcon: const Icon(Icons.tag),
                suffixIcon: TextButton(
                  onPressed: _addCustom,
                  child: const Text('添加'),
                ),
              ),
              onSubmitted: (_) => _addCustom(),
            ),
            const SizedBox(height: 12),
            if (_selected.isNotEmpty) ...[
              Wrap(
                spacing: 8,
                runSpacing: 6,
                children: [
                  for (final topic in _selected)
                    InputChip(
                      label: Text('#$topic'),
                      onDeleted: () => _toggle(topic),
                      visualDensity: VisualDensity.compact,
                    ),
                ],
              ),
              const SizedBox(height: 12),
            ],
            Text(
              '热门话题',
              style: TextStyle(fontSize: 13, color: scheme.onSurfaceVariant),
            ),
            const SizedBox(height: 8),
            switch (hotTopics) {
              AsyncData(:final value) => Wrap(
                spacing: 8,
                runSpacing: 6,
                children: [
                  for (final topic in value)
                    FilterChip(
                      label: Text('#$topic'),
                      selected: _selected.contains(topic),
                      onSelected: (_) => _toggle(topic),
                      visualDensity: VisualDensity.compact,
                      showCheckmark: false,
                    ),
                ],
              ),
              AsyncError() => TextButton(
                onPressed: () => ref.invalidate(hotTopicsProvider),
                child: const Text('热门话题加载失败，点击重试'),
              ),
              _ => const Padding(
                padding: EdgeInsets.symmetric(vertical: 12),
                child: Center(
                  child: SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                ),
              ),
            },
          ],
        ),
      ),
    );
  }
}
