import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../../../core/network/api_exception.dart';
import '../../software/controller/software_list_controller.dart';
import '../../software/model/software.dart';
import '../data/publish_repository.dart';
import '../model/software_draft.dart';
import '../widget/dashed_border.dart';
import 'publish_post_page.dart' show GradientSubmitButton;

/// 发软件页（文档 3.5.2 / M3 软件库，视觉对齐设计图）：
/// Logo / 介绍图(3-6) / 名字简介 / 发布类型 / 分类 / 版本 / 大小 / 渠道 / 标签 / 下载链接。
/// 发布后进入人工审核，上架后公开可见。
class PublishSoftwarePage extends ConsumerStatefulWidget {
  const PublishSoftwarePage({super.key});

  @override
  ConsumerState<PublishSoftwarePage> createState() =>
      _PublishSoftwarePageState();
}

class _PublishSoftwarePageState extends ConsumerState<PublishSoftwarePage> {
  final _nameController = TextEditingController();
  final _introController = TextEditingController();
  final _versionController = TextEditingController();
  final _sizeController = TextEditingController();
  final _urlController = TextEditingController();
  final _extractCodeController = TextEditingController();
  final _picker = ImagePicker();

  String _logoPath = '';
  final List<String> _imagePaths = [];
  int _type = 1;
  SoftwareCategory? _category;
  String _channel = '';
  final List<String> _tags = [];
  bool _submitting = false;

  static const _channels = ['自制', '搬运', '官方'];

  @override
  void dispose() {
    _nameController.dispose();
    _introController.dispose();
    _versionController.dispose();
    _sizeController.dispose();
    _urlController.dispose();
    _extractCodeController.dispose();
    super.dispose();
  }

  SoftwareDraft _currentDraft() => SoftwareDraft(
    logoPath: _logoPath,
    imagePaths: [..._imagePaths],
    name: _nameController.text,
    intro: _introController.text,
    type: _type,
    category: _category,
    version: _versionController.text,
    size: _sizeController.text,
    channel: _channel,
    tags: [..._tags],
    downloadUrl: _urlController.text.trim(),
    extractCode: _extractCodeController.text.trim(),
  );

  bool get _canSubmit => !_submitting && _currentDraft().canSubmit;

  Future<void> _pickLogo() async {
    final file = await _picker.pickImage(source: ImageSource.gallery);
    if (file != null && mounted) setState(() => _logoPath = file.path);
  }

  Future<void> _pickImages() async {
    final remain = SoftwareDraft.maxImages - _imagePaths.length;
    if (remain <= 0) return;
    final files = await _picker.pickMultiImage(limit: remain);
    if (files.isEmpty || !mounted) return;
    setState(() {
      _imagePaths.addAll(files.take(remain).map((f) => f.path));
    });
  }

  Future<void> _pickChannel() async {
    final channel = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      backgroundColor: Colors.white,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              '选择软件渠道',
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 6),
            for (final channel in _channels)
              ListTile(
                title: Text(channel, textAlign: TextAlign.center),
                onTap: () => Navigator.of(context).pop(channel),
              ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    if (channel != null && mounted) setState(() => _channel = channel);
  }

  Future<void> _addTag() async {
    if (_tags.length >= SoftwareDraft.maxTags) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(content: Text('最多添加 ${SoftwareDraft.maxTags} 个标签')),
        );
      return;
    }
    final controller = TextEditingController();
    final tag = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('添加 APK 标签'),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLength: 8,
          decoration: const InputDecoration(hintText: '如：免登录、去广告'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(controller.text.trim()),
            child: const Text('添加'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (tag == null || tag.isEmpty || !mounted) return;
    if (_tags.contains(tag)) return;
    setState(() => _tags.add(tag));
  }

  Future<void> _submit() async {
    if (!_canSubmit) return;
    FocusScope.of(context).unfocus();
    setState(() => _submitting = true);
    try {
      await ref
          .read(publishRepositoryProvider)
          .publishSoftware(_currentDraft());
      if (!mounted) return;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(const SnackBar(content: Text('发布成功，审核上架后公开可见')));
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

    return Scaffold(
      backgroundColor: const Color(0xFFF6F7F9),
      appBar: AppBar(
        title: const Text(
          '发布软件',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
        ),
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(12, 10, 12, 16),
                children: [
                  // Logo
                  _SectionCard(
                    title: '软件 Logo',
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: SizedBox(
                        width: 92,
                        height: 92,
                        child: _logoPath.isEmpty
                            ? DashedAddBox(
                                enabled: !_submitting,
                                onTap: _pickLogo,
                                icon: Icons.add_rounded,
                                label: '上传 Logo',
                              )
                            : Stack(
                                fit: StackFit.expand,
                                children: [
                                  ClipRRect(
                                    borderRadius: BorderRadius.circular(12),
                                    child: Image.file(
                                      File(_logoPath),
                                      fit: BoxFit.cover,
                                      errorBuilder: (context, error, stack) =>
                                          Container(
                                            color:
                                                scheme.surfaceContainerHighest,
                                          ),
                                    ),
                                  ),
                                  Positioned(
                                    top: 4,
                                    right: 4,
                                    child: GestureDetector(
                                      onTap: _submitting
                                          ? null
                                          : () =>
                                                setState(() => _logoPath = ''),
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
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  // 介绍图
                  _SectionCard(
                    title: '软件介绍图（必须上传 ${SoftwareDraft.minImages} 张图，否则发布不了）',
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _IntroImagesEditor(
                          paths: _imagePaths,
                          enabled: !_submitting,
                          onAdd: _pickImages,
                          onRemove: (index) =>
                              setState(() => _imagePaths.removeAt(index)),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          '当前 ${_imagePaths.length} / ${SoftwareDraft.maxImages} 张，至少 ${SoftwareDraft.minImages} 张',
                          style: TextStyle(
                            fontSize: 11.5,
                            color: scheme.outline,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 10),
                  // 名字 + 简介
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Column(
                      children: [
                        TextField(
                          controller: _nameController,
                          enabled: !_submitting,
                          maxLength: 30,
                          decoration: InputDecoration(
                            hintText: '软件名字',
                            hintStyle: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                              color: const Color(
                                0xFF1F2430,
                              ).withValues(alpha: .25),
                            ),
                            filled: false,
                            counterText: '',
                            border: InputBorder.none,
                            enabledBorder: InputBorder.none,
                            focusedBorder: InputBorder.none,
                            disabledBorder: InputBorder.none,
                            contentPadding: const EdgeInsets.symmetric(
                              vertical: 12,
                            ),
                          ),
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                          ),
                          onChanged: (_) => setState(() {}),
                        ),
                        Divider(
                          height: 1,
                          thickness: .6,
                          color: scheme.outlineVariant.withValues(alpha: .4),
                        ),
                        TextField(
                          controller: _introController,
                          enabled: !_submitting,
                          minLines: 5,
                          maxLines: 10,
                          maxLength: SoftwareDraft.maxIntroLength,
                          decoration: const InputDecoration(
                            hintText: '软件简介',
                            filled: false,
                            border: InputBorder.none,
                            enabledBorder: InputBorder.none,
                            focusedBorder: InputBorder.none,
                            disabledBorder: InputBorder.none,
                            contentPadding: EdgeInsets.symmetric(vertical: 12),
                          ),
                          style: const TextStyle(fontSize: 14.5, height: 1.6),
                          onChanged: (_) => setState(() {}),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 10),
                  // 类型 / 分类 / 版本 / 大小 / 渠道 / 标签 / 链接
                  Container(
                    padding: const EdgeInsets.fromLTRB(14, 6, 14, 6),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Column(
                      children: [
                        _LabeledRow(
                          label: '发布类型',
                          child: _TypeChips(
                            current: _type,
                            enabled: !_submitting,
                            onChanged: (type) => setState(() {
                              _type = type;
                              _category = null;
                            }),
                          ),
                        ),
                        _rowDivider(scheme),
                        _LabeledRow(
                          label: '软件分类',
                          child: _CategoryChips(
                            type: _type,
                            current: _category,
                            enabled: !_submitting,
                            onChanged: (category) =>
                                setState(() => _category = category),
                          ),
                        ),
                        _rowDivider(scheme),
                        _InputRow(
                          label: '软件版本',
                          hint: '例如 2.3.1',
                          controller: _versionController,
                          enabled: !_submitting,
                          onChanged: () => setState(() {}),
                        ),
                        _rowDivider(scheme),
                        _InputRow(
                          label: '软件大小',
                          hint: '例如 128MB',
                          controller: _sizeController,
                          enabled: !_submitting,
                          onChanged: () => setState(() {}),
                        ),
                        _rowDivider(scheme),
                        _LabeledRow(
                          label: '软件渠道',
                          child: InkWell(
                            onTap: _submitting ? null : _pickChannel,
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  _channel.isEmpty ? '未选择' : _channel,
                                  style: TextStyle(
                                    fontSize: 13.5,
                                    color: _channel.isEmpty
                                        ? scheme.outline
                                        : scheme.primary,
                                    fontWeight: _channel.isEmpty
                                        ? FontWeight.w400
                                        : FontWeight.w600,
                                  ),
                                ),
                                Icon(
                                  Icons.chevron_right,
                                  size: 18,
                                  color: scheme.outline,
                                ),
                              ],
                            ),
                          ),
                        ),
                        _rowDivider(scheme),
                        _LabeledRow(
                          label: 'APK 标签',
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              if (_tags.isNotEmpty)
                                ConstrainedBox(
                                  constraints: const BoxConstraints(
                                    maxWidth: 200,
                                  ),
                                  child: Wrap(
                                    spacing: 6,
                                    runSpacing: 4,
                                    alignment: WrapAlignment.end,
                                    children: [
                                      for (final tag in _tags)
                                        _TagChip(
                                          tag: tag,
                                          enabled: !_submitting,
                                          onRemove: () =>
                                              setState(() => _tags.remove(tag)),
                                        ),
                                    ],
                                  ),
                                ),
                              const SizedBox(width: 8),
                              GestureDetector(
                                onTap: _submitting ? null : _addTag,
                                child: Container(
                                  width: 24,
                                  height: 24,
                                  decoration: BoxDecoration(
                                    color: const Color(
                                      0xFFF43F5E,
                                    ).withValues(alpha: .1),
                                    shape: BoxShape.circle,
                                  ),
                                  child: const Icon(
                                    Icons.add_rounded,
                                    size: 16,
                                    color: Color(0xFFF43F5E),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        _rowDivider(scheme),
                        _InputRow(
                          label: '下载链接',
                          hint: '填写 http 或 https 下载链接',
                          controller: _urlController,
                          enabled: !_submitting,
                          onChanged: () => setState(() {}),
                        ),
                        _rowDivider(scheme),
                        // 提取码（3.5.2：支持网盘链接 + 提取码）
                        _InputRow(
                          label: '提取码',
                          hint: '网盘提取码（选填）',
                          controller: _extractCodeController,
                          enabled: !_submitting,
                          onChanged: () => setState(() {}),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            // 底部发布栏（渐变胶囊，条件满足才亮起）
            Container(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
              color: Colors.white,
              child: GradientSubmitButton(
                enabled: _canSubmit,
                submitting: _submitting,
                label: '确认发布',
                onPressed: _submit,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _rowDivider(ColorScheme scheme) => Divider(
    height: 1,
    thickness: .6,
    color: scheme.outlineVariant.withValues(alpha: .4),
  );
}

/// 白卡分区：标题 + 内容
class _SectionCard extends StatelessWidget {
  const _SectionCard({required this.title, required this.child});

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 12),
          child,
        ],
      ),
    );
  }
}

/// 介绍图编辑器：3 列宫格 + 虚线添加框
class _IntroImagesEditor extends StatelessWidget {
  const _IntroImagesEditor({
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
    final showAdd = paths.length < SoftwareDraft.maxImages;

    if (paths.isEmpty) {
      return SizedBox(
        height: 104,
        width: double.infinity,
        child: DashedAddBox(
          enabled: enabled,
          onTap: onAdd,
          icon: Icons.add_rounded,
          label:
              '上传 ${SoftwareDraft.minImages}-${SoftwareDraft.maxImages} 张介绍图',
        ),
      );
    }

    return GridView.count(
      crossAxisCount: 3,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      mainAxisSpacing: 8,
      crossAxisSpacing: 8,
      children: [
        for (var i = 0; i < paths.length; i++)
          Stack(
            fit: StackFit.expand,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(10),
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
          DashedAddBox(
            enabled: enabled,
            onTap: onAdd,
            icon: Icons.add_rounded,
            label: '${paths.length}/${SoftwareDraft.maxImages}',
          ),
      ],
    );
  }
}

/// 左标签 + 右内容行
class _LabeledRow extends StatelessWidget {
  const _LabeledRow({required this.label, required this.child});

  final String label;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 11),
      child: Row(
        children: [
          Text(
            label,
            style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w600),
          ),
          const Spacer(),
          child,
        ],
      ),
    );
  }
}

/// 左标签 + 右输入行
class _InputRow extends StatelessWidget {
  const _InputRow({
    required this.label,
    required this.hint,
    required this.controller,
    required this.enabled,
    required this.onChanged,
  });

  final String label;
  final String hint;
  final TextEditingController controller;
  final bool enabled;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          Text(
            label,
            style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w600),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: TextField(
              controller: controller,
              enabled: enabled,
              textAlign: TextAlign.right,
              decoration: InputDecoration(
                hintText: hint,
                hintStyle: TextStyle(fontSize: 13.5, color: scheme.outline),
                filled: false,
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
                disabledBorder: InputBorder.none,
                contentPadding: const EdgeInsets.symmetric(vertical: 12),
                isDense: true,
              ),
              style: const TextStyle(fontSize: 13.5),
              onChanged: (_) => onChanged(),
            ),
          ),
        ],
      ),
    );
  }
}

/// 发布类型 chips：应用 / 游戏（带图标）
class _TypeChips extends StatelessWidget {
  const _TypeChips({
    required this.current,
    required this.enabled,
    required this.onChanged,
  });

  final int current;
  final bool enabled;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    Widget chip(int type, IconData icon, String label) {
      final active = current == type;
      return GestureDetector(
        onTap: enabled && !active ? () => onChanged(type) : null,
        child: Container(
          margin: const EdgeInsets.only(left: 8),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: active
                ? const Color(0xFFF43F5E).withValues(alpha: .08)
                : const Color(0xFFF3F4F8),
            borderRadius: BorderRadius.circular(999),
            border: Border.all(
              color: active
                  ? const Color(0xFFF43F5E).withValues(alpha: .5)
                  : Colors.transparent,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                icon,
                size: 14,
                color: active
                    ? const Color(0xFFF43F5E)
                    : Theme.of(context).colorScheme.onSurfaceVariant,
              ),
              const SizedBox(width: 4),
              Text(
                label,
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: active ? FontWeight.w700 : FontWeight.w500,
                  color: active
                      ? const Color(0xFFF43F5E)
                      : Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      );
    }

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        chip(1, Icons.smartphone_rounded, '应用'),
        chip(2, Icons.sports_esports_rounded, '游戏'),
      ],
    );
  }
}

/// 软件分类 chips：按发布类型从软件库仓库拉取（对齐 categoryId 契约）
class _CategoryChips extends ConsumerWidget {
  const _CategoryChips({
    required this.type,
    required this.current,
    required this.enabled,
    required this.onChanged,
  });

  final int type;
  final SoftwareCategory? current;
  final bool enabled;
  final ValueChanged<SoftwareCategory> onChanged;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final categories = ref.watch(softwareCategoryListProvider(type));
    return switch (categories) {
      AsyncData(:final value) => ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 250),
        child: Wrap(
          spacing: 6,
          runSpacing: 6,
          alignment: WrapAlignment.end,
          children: [
            for (final category in value)
              _chip(context, category, active: category.id == current?.id),
          ],
        ),
      ),
      AsyncError() => Text(
        '分类加载失败',
        style: TextStyle(
          fontSize: 12,
          color: Theme.of(context).colorScheme.outline,
        ),
      ),
      _ => const SizedBox(
        width: 14,
        height: 14,
        child: CircularProgressIndicator(strokeWidth: 1.6),
      ),
    };
  }

  Widget _chip(
    BuildContext context,
    SoftwareCategory category, {
    required bool active,
  }) {
    return GestureDetector(
      onTap: enabled && !active ? () => onChanged(category) : null,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 5),
        decoration: BoxDecoration(
          gradient: active
              ? const LinearGradient(
                  colors: [Color(0xFFF43F5E), Color(0xFFFF7849)],
                )
              : null,
          color: active ? null : const Color(0xFFF3F4F8),
          borderRadius: BorderRadius.circular(999),
        ),
        child: Text(
          category.name,
          style: TextStyle(
            fontSize: 12,
            fontWeight: active ? FontWeight.w700 : FontWeight.w500,
            color: active
                ? Colors.white
                : Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
      ),
    );
  }
}

/// APK 标签 chip（可删除）
class _TagChip extends StatelessWidget {
  const _TagChip({
    required this.tag,
    required this.enabled,
    required this.onRemove,
  });

  final String tag;
  final bool enabled;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(9, 4, 6, 4),
      decoration: BoxDecoration(
        color: const Color(0xFFF43F5E).withValues(alpha: .07),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            tag,
            style: const TextStyle(
              fontSize: 11.5,
              color: Color(0xFFF43F5E),
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(width: 3),
          GestureDetector(
            onTap: enabled ? onRemove : null,
            child: const Icon(
              Icons.close_rounded,
              size: 13,
              color: Color(0xFFF43F5E),
            ),
          ),
        ],
      ),
    );
  }
}
