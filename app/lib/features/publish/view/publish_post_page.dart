import 'dart:io';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../../../core/network/api_exception.dart';
import '../../auth/controller/auth_controller.dart';
import '../../circle/model/circle.dart';
import '../controller/publish_draft_store.dart';
import '../data/publish_repository.dart';
import '../model/post_draft.dart';
import '../widget/circle_picker_sheet.dart';
import '../widget/dashed_border.dart';
import '../widget/topic_picker_sheet.dart';

/// 发动态页（文档 3.5.1，视觉对齐设计图）：
/// 用户行 / 大标题输入 / 正文 / 虚线加图 / 彩条表单行（圈子必选、话题）/ 渐变发布钮。
/// @好友、共创者、权限、付费解锁、附加卡片为 M2 后续迭代。
class PublishPostPage extends ConsumerStatefulWidget {
  const PublishPostPage({super.key});

  @override
  ConsumerState<PublishPostPage> createState() => _PublishPostPageState();
}

class _PublishPostPageState extends ConsumerState<PublishPostPage> {
  final _titleController = TextEditingController();
  final _contentController = TextEditingController();
  final _paidContentController = TextEditingController();
  final _paidPriceController = TextEditingController();
  final _picker = ImagePicker();

  final List<String> _imagePaths = [];
  Circle? _circle;
  List<String> _topics = [];
  bool _paidEnabled = false;
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
      _paidEnabled = draft.isPaid;
      if (draft.isPaid) {
        _paidPriceController.text = '${draft.paidPrice}';
        _paidContentController.text = draft.paidContent;
      }
    }
  }

  @override
  void dispose() {
    _titleController.dispose();
    _contentController.dispose();
    _paidContentController.dispose();
    _paidPriceController.dispose();
    super.dispose();
  }

  int get _paidPrice =>
      _paidEnabled ? (int.tryParse(_paidPriceController.text.trim()) ?? 0) : 0;

  PostDraft _currentDraft() => PostDraft(
    title: _titleController.text.trim(),
    content: _contentController.text.trim(),
    imagePaths: [..._imagePaths],
    circle: _circle,
    topics: [..._topics],
    paidPrice: _paidPrice,
    paidContent: _paidEnabled ? _paidContentController.text.trim() : '',
  );

  bool get _canSubmit {
    final draft = _currentDraft();
    final paidOk =
        !_paidEnabled ||
        (draft.paidPrice > 0 &&
            draft.paidPrice <= PostDraft.maxPaidPrice &&
            draft.paidContent.isNotEmpty);
    return !_submitting &&
        _circle != null &&
        paidOk &&
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
      _paidContentController.clear();
      _paidPriceController.clear();
      _imagePaths.clear();
      _circle = null;
      _topics = [];
      _paidEnabled = false;
    });
    ref.read(publishDraftProvider.notifier).clear();
  }

  void _comingSoon(String name) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text('「$name」正在开发中，敬请期待')));
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
    return PopScope(
      // 统一走取消流程，避免系统返回绕过草稿提示
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) _onCancel();
      },
      child: Scaffold(
        backgroundColor: const Color(0xFFF6F7F9),
        appBar: AppBar(
          backgroundColor: const Color(0xFFF6F7F9),
          leadingWidth: 64,
          leading: TextButton(
            onPressed: _submitting ? null : _reset,
            child: Text(
              '重置',
              style: TextStyle(
                fontSize: 14,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          title: const Text(
            '发布',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
          ),
          actions: [
            TextButton(
              onPressed: _submitting ? null : _onCancel,
              child: Text(
                '取消',
                style: TextStyle(
                  fontSize: 14,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          ],
        ),
        body: SafeArea(
          child: Column(
            children: [
              Expanded(
                child: Stack(
                  children: [
                    ListView(
                      padding: const EdgeInsets.fromLTRB(12, 10, 12, 16),
                      children: [
                        const _UserRow(),
                        const SizedBox(height: 10),
                        // 标题（独立白卡，计数内联右侧，贴设计图）
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 14),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: Row(
                            children: [
                              Expanded(
                                child: TextField(
                                  controller: _titleController,
                                  enabled: !_submitting,
                                  maxLength: PostDraft.maxTitleLength,
                                  decoration: InputDecoration(
                                    hintText: '添加标题让更多人看见',
                                    hintStyle: TextStyle(
                                      fontSize: 18,
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
                                      vertical: 15,
                                    ),
                                  ),
                                  style: const TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.w700,
                                  ),
                                  onChanged: (_) => setState(() {}),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Text(
                                '${_titleController.text.characters.length} / ${PostDraft.maxTitleLength}',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Theme.of(context).colorScheme.outline,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 10),
                        // 正文（独立白卡，贴设计图）
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 14),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: TextField(
                            controller: _contentController,
                            enabled: !_submitting,
                            minLines: 7,
                            maxLines: 12,
                            decoration: const InputDecoration(
                              hintText: '此刻的想法、见闻或故事…',
                              filled: false,
                              border: InputBorder.none,
                              enabledBorder: InputBorder.none,
                              focusedBorder: InputBorder.none,
                              disabledBorder: InputBorder.none,
                              contentPadding: EdgeInsets.symmetric(
                                vertical: 14,
                              ),
                            ),
                            style: const TextStyle(fontSize: 15, height: 1.6),
                            onChanged: (_) => setState(() {}),
                          ),
                        ),
                        const SizedBox(height: 10),
                        // 图片（白卡 + 虚线添加框）
                        Container(
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: _ImageGridEditor(
                            paths: _imagePaths,
                            enabled: !_submitting,
                            onAdd: _pickImages,
                            onRemove: (index) =>
                                setState(() => _imagePaths.removeAt(index)),
                          ),
                        ),
                        const SizedBox(height: 10),
                        // 圈子 / 话题（彩条表单行）
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 14),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: Column(
                            children: [
                              _FormRow(
                                barColor: const Color(0xFFF43F5E),
                                label: '圈子',
                                requiredTag: true,
                                value: _circle?.name,
                                hint: '选择圈子（必选）',
                                enabled: !_submitting,
                                onTap: _pickCircle,
                              ),
                              Divider(
                                height: 1,
                                thickness: .6,
                                indent: 14,
                                color: Theme.of(context)
                                    .colorScheme
                                    .outlineVariant
                                    .withValues(alpha: .4),
                              ),
                              _FormRow(
                                barColor: const Color(0xFFFFB020),
                                label: '话题',
                                value: _topics.isEmpty
                                    ? null
                                    : _topics.map((t) => '#$t').join(' '),
                                hint: '添加话题（最多 ${PostDraft.maxTopics} 个）',
                                enabled: !_submitting,
                                onTap: _pickTopics,
                              ),
                              Divider(
                                height: 1,
                                thickness: .6,
                                indent: 14,
                                color: Theme.of(context)
                                    .colorScheme
                                    .outlineVariant
                                    .withValues(alpha: .4),
                              ),
                              _FormRow(
                                barColor: const Color(0xFF22C55E),
                                label: '共创者',
                                hint: '添加共创者',
                                enabled: !_submitting,
                                onTap: () => _comingSoon('共创者'),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 14),
                        // 权限设置：忧珠付费解锁（文档 3.3/3.9）
                        Padding(
                          padding: const EdgeInsets.only(left: 6, bottom: 8),
                          child: Text(
                            '权限设置',
                            style: TextStyle(
                              fontSize: 12.5,
                              color: Theme.of(context).colorScheme.outline,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.fromLTRB(14, 12, 10, 12),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: Column(
                            children: [
                              Row(
                                children: [
                                  Container(
                                    width: 30,
                                    height: 30,
                                    decoration: BoxDecoration(
                                      color: const Color(
                                        0xFFFFB020,
                                      ).withValues(alpha: .12),
                                      borderRadius: BorderRadius.circular(9),
                                    ),
                                    child: const Icon(
                                      Icons.workspace_premium_outlined,
                                      size: 17,
                                      color: Color(0xFFB07800),
                                    ),
                                  ),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        const Text(
                                          '付费查看',
                                          style: TextStyle(
                                            fontSize: 14.5,
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                        const SizedBox(height: 1),
                                        Text(
                                          '读者消耗忧珠解锁付费段，正文作为免费摘要',
                                          style: TextStyle(
                                            fontSize: 11.5,
                                            color: Theme.of(
                                              context,
                                            ).colorScheme.outline,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  Switch(
                                    value: _paidEnabled,
                                    onChanged: _submitting
                                        ? null
                                        : (value) => setState(
                                            () => _paidEnabled = value,
                                          ),
                                  ),
                                ],
                              ),
                              if (_paidEnabled)
                                _PaidSection(
                                  priceController: _paidPriceController,
                                  contentController: _paidContentController,
                                  enabled: !_submitting,
                                  onChanged: () => setState(() {}),
                                ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    // 右侧悬浮小入口（贴设计图；外链卡片为后续迭代占位）
                    Positioned(
                      right: 0,
                      top: 300,
                      child: _SideEntry(
                        icon: Icons.link_rounded,
                        color: const Color(0xFF3B82F6),
                        label: '链接',
                        onTap: () => _comingSoon('附加链接'),
                      ),
                    ),
                  ],
                ),
              ),
              // 底部发布栏（渐变胶囊）
              Container(
                padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
                color: Colors.white,
                child: GradientSubmitButton(
                  enabled: _canSubmit,
                  submitting: _submitting,
                  label: '发布',
                  onPressed: _submit,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 渐变提交钮：可用时红橙渐变胶囊，禁用转灰（内部保留 FilledButton 便于测试）
class GradientSubmitButton extends StatelessWidget {
  const GradientSubmitButton({
    super.key,
    required this.enabled,
    required this.submitting,
    required this.label,
    required this.onPressed,
  });

  final bool enabled;
  final bool submitting;
  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        gradient: enabled
            ? const LinearGradient(
                colors: [Color(0xFFF43F5E), Color(0xFFFF7849)],
              )
            : null,
        color: enabled ? null : const Color(0xFFE7E8EE),
        borderRadius: BorderRadius.circular(26),
        boxShadow: enabled
            ? [
                BoxShadow(
                  color: const Color(0xFFF43F5E).withValues(alpha: .3),
                  blurRadius: 12,
                  offset: const Offset(0, 4),
                ),
              ]
            : null,
      ),
      child: FilledButton(
        style: FilledButton.styleFrom(
          backgroundColor: Colors.transparent,
          disabledBackgroundColor: Colors.transparent,
          disabledForegroundColor: const Color(0xFFB0B3BF),
          shadowColor: Colors.transparent,
        ),
        onPressed: enabled ? onPressed : null,
        child: submitting
            ? const SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(
                  strokeWidth: 2.5,
                  color: Colors.white,
                ),
              )
            : Text(label),
      ),
    );
  }
}

/// 付费段编辑区：忧珠价格 + 付费全文输入（开启付费查看后展开）
class _PaidSection extends StatelessWidget {
  const _PaidSection({
    required this.priceController,
    required this.contentController,
    required this.enabled,
    required this.onChanged,
  });

  final TextEditingController priceController;
  final TextEditingController contentController;
  final bool enabled;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      children: [
        Divider(
          height: 18,
          thickness: .6,
          color: scheme.outlineVariant.withValues(alpha: .4),
        ),
        Row(
          children: [
            const Text(
              '解锁价格',
              style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: TextField(
                controller: priceController,
                enabled: enabled,
                keyboardType: TextInputType.number,
                textAlign: TextAlign.right,
                maxLength: 3,
                decoration: InputDecoration(
                  hintText: '1-${PostDraft.maxPaidPrice}',
                  hintStyle: TextStyle(fontSize: 13, color: scheme.outline),
                  filled: false,
                  counterText: '',
                  border: InputBorder.none,
                  enabledBorder: InputBorder.none,
                  focusedBorder: InputBorder.none,
                  disabledBorder: InputBorder.none,
                  isDense: true,
                  contentPadding: const EdgeInsets.symmetric(vertical: 8),
                ),
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                ),
                onChanged: (_) => onChanged(),
              ),
            ),
            const SizedBox(width: 4),
            Text(
              '忧珠',
              style: TextStyle(fontSize: 12.5, color: scheme.outline),
            ),
          ],
        ),
        const SizedBox(height: 6),
        TextField(
          controller: contentController,
          enabled: enabled,
          minLines: 3,
          maxLines: 8,
          maxLength: 2000,
          decoration: InputDecoration(
            hintText: '付费全文段（读者解锁后可见，必填）',
            hintStyle: TextStyle(fontSize: 13, color: scheme.outline),
            filled: true,
            fillColor: const Color(0xFFF6F7F9),
            counterText: '',
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide.none,
            ),
            contentPadding: const EdgeInsets.all(12),
          ),
          style: const TextStyle(fontSize: 13.5, height: 1.55),
          onChanged: (_) => onChanged(),
        ),
        const SizedBox(height: 4),
      ],
    );
  }
}

/// 右侧悬浮小入口：白底半贴边 + 彩色圆形图标 + 文案（占位通道）
class _SideEntry extends StatelessWidget {
  const _SideEntry({
    required this.icon,
    required this.color,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final Color color;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 52,
        padding: const EdgeInsets.symmetric(vertical: 9),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: const BorderRadius.only(
            topLeft: Radius.circular(14),
            bottomLeft: Radius.circular(14),
          ),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFF1F2430).withValues(alpha: .08),
              blurRadius: 10,
              offset: const Offset(-2, 3),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 26,
              height: 26,
              decoration: BoxDecoration(color: color, shape: BoxShape.circle),
              child: Icon(icon, size: 15, color: Colors.white),
            ),
            const SizedBox(height: 4),
            Text(
              label,
              style: const TextStyle(
                fontSize: 10.5,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 顶部用户行：头像 + 昵称 + 「分享此刻想法」
class _UserRow extends ConsumerWidget {
  const _UserRow();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final auth = ref.watch(authControllerProvider);
    final user = auth is AuthAuthenticated ? auth.user : null;
    final nickname = user?.nickname ?? '我';
    final avatar = user?.avatar ?? '';

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Row(
        children: [
          CircleAvatar(
            radius: 17,
            backgroundColor: scheme.surfaceContainerHighest,
            foregroundImage: avatar.isEmpty
                ? null
                : CachedNetworkImageProvider(avatar),
            child: Text(
              nickname.isEmpty ? '我' : nickname.characters.first,
              style: TextStyle(fontSize: 13, color: scheme.primary),
            ),
          ),
          const SizedBox(width: 9),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                nickname,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 1),
              Text(
                '分享此刻想法',
                style: TextStyle(fontSize: 11, color: scheme.outline),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// 图片九宫格编辑器：已选图 + 虚线添加框，长按无排序（M2 后续）
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
            label: paths.isEmpty ? '添加图片' : '${paths.length}/9',
          ),
      ],
    );
  }
}

/// 彩条表单行：左侧色条 + 标签（+必选红标）+ 右侧值/提示 + 箭头
class _FormRow extends StatelessWidget {
  const _FormRow({
    required this.barColor,
    required this.label,
    required this.hint,
    required this.enabled,
    required this.onTap,
    this.value,
    this.requiredTag = false,
  });

  final Color barColor;
  final String label;
  final String? value;
  final String hint;
  final bool requiredTag;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final hasValue = value != null && value!.isNotEmpty;

    return InkWell(
      onTap: enabled ? onTap : null,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 15),
        child: Row(
          children: [
            Container(
              width: 3.5,
              height: 14,
              decoration: BoxDecoration(
                color: barColor,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(width: 9),
            Text(
              label,
              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
            ),
            if (requiredTag) ...[
              const SizedBox(width: 6),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 5,
                  vertical: 1.5,
                ),
                decoration: BoxDecoration(
                  color: const Color(0xFFF43F5E).withValues(alpha: .1),
                  borderRadius: BorderRadius.circular(5),
                ),
                child: const Text(
                  '必选',
                  style: TextStyle(
                    fontSize: 9.5,
                    color: Color(0xFFF43F5E),
                    fontWeight: FontWeight.w700,
                    height: 1.2,
                  ),
                ),
              ),
            ],
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                hasValue ? value! : hint,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.right,
                style: TextStyle(
                  fontSize: 13,
                  color: hasValue ? scheme.primary : scheme.outline,
                  fontWeight: hasValue ? FontWeight.w600 : FontWeight.w400,
                ),
              ),
            ),
            const SizedBox(width: 2),
            Icon(Icons.chevron_right, size: 18, color: scheme.outline),
          ],
        ),
      ),
    );
  }
}
