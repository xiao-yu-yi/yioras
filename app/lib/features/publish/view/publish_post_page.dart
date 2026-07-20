import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../../../core/network/api_exception.dart';
import '../../circle/model/circle.dart';
import '../controller/publish_draft_store.dart';
import '../data/publish_repository.dart';
import '../model/post_draft.dart';
import '../widget/circle_picker_sheet.dart';
import '../widget/topic_picker_sheet.dart';

/// 发动态页（文档 3.5.1）：标题(≤30) / 正文 / 图片(0-9) / 圈子(必选) / 话题(≤5)。
/// @好友、共创者、权限、付费解锁、附加卡片为 M2 后续迭代。
class PublishPostPage extends ConsumerStatefulWidget {
  const PublishPostPage({super.key});

  @override
  ConsumerState<PublishPostPage> createState() => _PublishPostPageState();
}

class _PublishPostPageState extends ConsumerState<PublishPostPage> {
  final _titleController = TextEditingController();
  final _contentController = TextEditingController();
  final _picker = ImagePicker();

  final List<String> _imagePaths = [];
  Circle? _circle;
  List<String> _topics = [];
  bool _submitting = false;

  @override
  void initState() {
    super.initState();
    // 恢复上次「取消时保存」的草稿
    final draft = ref.read(publishDraftProvider);
    if (draft != null) {
      _titleController.text = draft.title;
      _contentController.text = draft.content;
      _imagePaths.addAll(draft.imagePaths);
      _circle = draft.circle;
      _topics = [...draft.topics];
    }
  }

  @override
  void dispose() {
    _titleController.dispose();
    _contentController.dispose();
    super.dispose();
  }

  PostDraft _currentDraft() => PostDraft(
    title: _titleController.text.trim(),
    content: _contentController.text.trim(),
    imagePaths: [..._imagePaths],
    circle: _circle,
    topics: [..._topics],
  );

  bool get _canSubmit {
    final draft = _currentDraft();
    return !_submitting &&
        _circle != null &&
        (draft.content.isNotEmpty || draft.imagePaths.isNotEmpty);
  }

  Future<void> _pickImages() async {
    final remain = PostDraft.maxImages - _imagePaths.length;
    if (remain <= 0) return;
    final files = await _picker.pickMultiImage(limit: remain);
    if (files.isEmpty || !mounted) return;
    setState(() {
      // 多选插件在部分平台不强制 limit，超出部分截断
      _imagePaths.addAll(files.take(remain).map((f) => f.path));
    });
  }

  Future<void> _pickCircle() async {
    final circle = await showCirclePickerSheet(context, selected: _circle);
    if (circle != null && mounted) setState(() => _circle = circle);
  }

  Future<void> _pickTopics() async {
    final topics = await showTopicPickerSheet(context, selected: _topics);
    if (topics != null && mounted) setState(() => _topics = topics);
  }

  void _reset() {
    setState(() {
      _titleController.clear();
      _contentController.clear();
      _imagePaths.clear();
      _circle = null;
      _topics = [];
    });
    ref.read(publishDraftProvider.notifier).clear();
  }

  /// 返回拦截：有内容时提示存草稿（文档 3.5.1 取消存草稿提示）
  Future<void> _onCancel() async {
    final draft = _currentDraft();
    if (draft.isEmpty) {
      ref.read(publishDraftProvider.notifier).clear();
      if (mounted) Navigator.of(context).pop();
      return;
    }
    final action = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('保留本次编辑？'),
        content: const Text('保存草稿后，下次进入发布页可继续编辑。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop('discard'),
            child: const Text('不保留'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop('save'),
            child: const Text('存草稿'),
          ),
        ],
      ),
    );
    if (!mounted || action == null) return;
    if (action == 'save') {
      ref.read(publishDraftProvider.notifier).save(draft);
    } else {
      ref.read(publishDraftProvider.notifier).clear();
    }
    Navigator.of(context).pop();
  }

  Future<void> _submit() async {
    if (!_canSubmit) return;
    FocusScope.of(context).unfocus();
    setState(() => _submitting = true);
    try {
      await ref.read(publishRepositoryProvider).publishPost(_currentDraft());
      ref.read(publishDraftProvider.notifier).clear();
      if (!mounted) return;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(const SnackBar(content: Text('发布成功，已提交审核')));
      Navigator.of(context).pop();
    } on ApiException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(SnackBar(content: Text('发布失败：${e.message}')));
      }
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return PopScope(
      // 统一走取消流程，避免系统返回绕过草稿提示
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) _onCancel();
      },
      child: Scaffold(
        appBar: AppBar(
          leading: IconButton(
            icon: const Icon(Icons.close),
            onPressed: _submitting ? null : _onCancel,
          ),
          title: const Text('发动态'),
          actions: [
            TextButton(
              onPressed: _submitting ? null : _reset,
              child: const Text('重置'),
            ),
          ],
        ),
        body: SafeArea(
          child: Column(
            children: [
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                  children: [
                    TextField(
                      controller: _titleController,
                      enabled: !_submitting,
                      maxLength: PostDraft.maxTitleLength,
                      decoration: const InputDecoration(
                        hintText: '标题（选填，好标题更容易被推荐）',
                      ),
                      style: const TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w600,
                      ),
                      onChanged: (_) => setState(() {}),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: _contentController,
                      enabled: !_submitting,
                      minLines: 5,
                      maxLines: 12,
                      decoration: const InputDecoration(hintText: '分享你的想法…'),
                      onChanged: (_) => setState(() {}),
                    ),
                    const SizedBox(height: 12),
                    _ImageGridEditor(
                      paths: _imagePaths,
                      enabled: !_submitting,
                      onAdd: _pickImages,
                      onRemove: (index) =>
                          setState(() => _imagePaths.removeAt(index)),
                    ),
                    const SizedBox(height: 16),
                    _PickerTile(
                      icon: Icons.workspaces_outline,
                      label: '圈子',
                      required: true,
                      value: _circle?.name,
                      hint: '选择圈子（必选）',
                      enabled: !_submitting,
                      onTap: _pickCircle,
                    ),
                    const Divider(height: 1),
                    _PickerTile(
                      icon: Icons.tag,
                      label: '话题',
                      value: _topics.isEmpty
                          ? null
                          : _topics.map((t) => '#$t').join(' '),
                      hint: '添加话题（最多 ${PostDraft.maxTopics} 个）',
                      enabled: !_submitting,
                      onTap: _pickTopics,
                    ),
                  ],
                ),
              ),
              // 底部发布栏
              Container(
                padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
                decoration: BoxDecoration(
                  color: Colors.white,
                  border: Border(
                    top: BorderSide(
                      color: scheme.outlineVariant.withValues(alpha: .5),
                    ),
                  ),
                ),
                child: FilledButton(
                  onPressed: _canSubmit ? _submit : null,
                  child: _submitting
                      ? const SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(
                            strokeWidth: 2.5,
                            color: Colors.white,
                          ),
                        )
                      : const Text('发布'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 图片九宫格编辑器：已选图 + 添加按钮，长按无排序（M2 后续）
class _ImageGridEditor extends StatelessWidget {
  const _ImageGridEditor({
    required this.paths,
    required this.enabled,
    required this.onAdd,
    required this.onRemove,
  });

  final List<String> paths;
  final bool enabled;
  final VoidCallback onAdd;
  final void Function(int index) onRemove;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final showAdd = paths.length < PostDraft.maxImages;

    return GridView.count(
      crossAxisCount: 3,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      mainAxisSpacing: 6,
      crossAxisSpacing: 6,
      children: [
        for (var i = 0; i < paths.length; i++)
          Stack(
            fit: StackFit.expand,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: Image.file(
                  File(paths[i]),
                  fit: BoxFit.cover,
                  errorBuilder: (context, error, stack) => Container(
                    color: scheme.surfaceContainerHighest,
                    child: Icon(
                      Icons.broken_image_outlined,
                      color: scheme.outline,
                    ),
                  ),
                ),
              ),
              Positioned(
                top: 4,
                right: 4,
                child: GestureDetector(
                  onTap: enabled ? () => onRemove(i) : null,
                  child: Container(
                    padding: const EdgeInsets.all(2),
                    decoration: const BoxDecoration(
                      color: Colors.black54,
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.close,
                      size: 14,
                      color: Colors.white,
                    ),
                  ),
                ),
              ),
            ],
          ),
        if (showAdd)
          InkWell(
            onTap: enabled ? onAdd : null,
            borderRadius: BorderRadius.circular(8),
            child: Container(
              decoration: BoxDecoration(
                color: scheme.surfaceContainerHighest.withValues(alpha: .6),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: scheme.outlineVariant, width: 1),
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.add_photo_alternate_outlined,
                    size: 26,
                    color: scheme.outline,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${paths.length}/${PostDraft.maxImages}',
                    style: TextStyle(fontSize: 11, color: scheme.outline),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

/// 圈子/话题选择行
class _PickerTile extends StatelessWidget {
  const _PickerTile({
    required this.icon,
    required this.label,
    required this.hint,
    required this.enabled,
    required this.onTap,
    this.value,
    this.required = false,
  });

  final IconData icon;
  final String label;
  final String? value;
  final String hint;
  final bool required;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final hasValue = value != null && value!.isNotEmpty;

    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Icon(icon, color: scheme.primary),
      title: Row(
        children: [
          Text(label, style: const TextStyle(fontSize: 15)),
          if (required) ...[
            const SizedBox(width: 2),
            Text('*', style: TextStyle(color: scheme.error)),
          ],
        ],
      ),
      subtitle: Text(
        hasValue ? value! : hint,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          fontSize: 13,
          color: hasValue ? scheme.primary : scheme.outline,
        ),
      ),
      trailing: Icon(Icons.chevron_right, color: scheme.outline),
      onTap: enabled ? onTap : null,
    );
  }
}
