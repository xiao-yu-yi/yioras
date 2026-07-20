import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/publish_repository.dart';
import '../model/post_draft.dart';

/// 热门话题数据源（选择器打开时拉取）
final hotTopicsProvider = FutureProvider.autoDispose<List<String>>((ref) {
  return ref.watch(publishRepositoryProvider).fetchHotTopics();
});

/// 话题选择器（≤5 个，文档 3.5.1，视觉对齐发布链路新风格）：
/// 标题+副标题 + 圆角搜索输入 + 品牌色胶囊 chips，热门多选 + 自定义新建。
Future<List<String>?> showTopicPickerSheet(
  BuildContext context, {
  required List<String> selected,
}) {
  return showModalBottomSheet<List<String>>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    backgroundColor: Colors.white,
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

  static const _brand = Color(0xFFF43F5E);

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

  /// 品牌色胶囊 chip：选中红橙渐变白字，未选浅灰底
  Widget _chip(String topic, {required bool selected, VoidCallback? onTap}) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          gradient: selected
              ? const LinearGradient(
                  colors: [Color(0xFFF43F5E), Color(0xFFFF7849)],
                )
              : null,
          color: selected ? null : const Color(0xFFF3F4F8),
          borderRadius: BorderRadius.circular(999),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              '# $topic',
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                color: selected
                    ? Colors.white
                    : Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
            if (selected) ...[
              const SizedBox(width: 4),
              const Icon(Icons.close_rounded, size: 13, color: Colors.white70),
            ],
          ],
        ),
      ),
    );
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
            // 标题行 + 完成按钮（品牌色胶囊）
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '选择话题（${_selected.length}/${PostDraft.maxTopics}）',
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        '带话题的动态更容易被同好发现',
                        style: TextStyle(fontSize: 11.5, color: scheme.outline),
                      ),
                    ],
                  ),
                ),
                FilledButton(
                  style: FilledButton.styleFrom(
                    minimumSize: const Size(64, 32),
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    visualDensity: VisualDensity.compact,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(20),
                    ),
                    textStyle: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  onPressed: () => Navigator.of(context).pop(_selected),
                  child: const Text('完成'),
                ),
              ],
            ),
            const SizedBox(height: 12),
            // 新建话题输入（全圆角浅底）
            TextField(
              controller: _inputController,
              maxLength: 30,
              style: const TextStyle(fontSize: 14),
              decoration: InputDecoration(
                hintText: '输入新话题，回车添加',
                hintStyle: TextStyle(fontSize: 14, color: scheme.outline),
                counterText: '',
                isDense: true,
                prefixIcon: const Icon(Icons.tag, size: 18, color: _brand),
                suffixIcon: TextButton(
                  onPressed: _addCustom,
                  child: const Text(
                    '添加',
                    style: TextStyle(fontSize: 13, color: _brand),
                  ),
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(22),
                  borderSide: BorderSide.none,
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(22),
                  borderSide: BorderSide.none,
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(22),
                  borderSide: const BorderSide(color: _brand, width: 1.2),
                ),
              ),
              onSubmitted: (_) => _addCustom(),
            ),
            const SizedBox(height: 14),
            if (_selected.isNotEmpty) ...[
              Text(
                '已选话题',
                style: TextStyle(
                  fontSize: 12.5,
                  color: scheme.outline,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final topic in _selected)
                    _chip(topic, selected: true, onTap: () => _toggle(topic)),
                ],
              ),
              const SizedBox(height: 14),
            ],
            Text(
              '热门话题',
              style: TextStyle(
                fontSize: 12.5,
                color: scheme.outline,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: 8),
            switch (hotTopics) {
              AsyncData(:final value) => Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final topic in value)
                    _chip(
                      topic,
                      selected: _selected.contains(topic),
                      onTap: () => _toggle(topic),
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
