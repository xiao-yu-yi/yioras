import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_exception.dart';
import '../data/report_repository.dart';

/// 弹出通用举报面板（帖子/评论/用户共用）。
/// [targetBrief] 为被举报对象摘要（标题/内容/昵称），帮助用户确认对象。
Future<void> showReportSheet(
  BuildContext context, {
  required ReportTargetType targetType,
  required int targetId,
  String targetBrief = '',
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    backgroundColor: Colors.white,
    builder: (context) => Padding(
      // 键盘弹起时上推，保证补充说明输入框可见
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: _ReportSheet(
        targetType: targetType,
        targetId: targetId,
        targetBrief: targetBrief,
      ),
    ),
  );
}

class _ReportSheet extends ConsumerStatefulWidget {
  const _ReportSheet({
    required this.targetType,
    required this.targetId,
    required this.targetBrief,
  });

  final ReportTargetType targetType;
  final int targetId;
  final String targetBrief;

  @override
  ConsumerState<_ReportSheet> createState() => _ReportSheetState();
}

class _ReportSheetState extends ConsumerState<_ReportSheet> {
  final _reasonController = TextEditingController();
  ReportCategory? _category;
  bool _submitting = false;

  @override
  void dispose() {
    _reasonController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final category = _category;
    if (category == null || _submitting) return;
    setState(() => _submitting = true);
    try {
      await ref
          .read(reportRepositoryProvider)
          .submit(
            targetType: widget.targetType,
            targetId: widget.targetId,
            category: category,
            reason: _reasonController.text,
          );
      if (!mounted) return;
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(const SnackBar(content: Text('举报已提交，平台会尽快核实处理')));
    } on ApiException catch (e) {
      if (mounted) {
        setState(() => _submitting = false);
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(SnackBar(content: Text(e.message)));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '举报${widget.targetType.label}',
              style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 4),
            Text(
              widget.targetBrief.isEmpty
                  ? '请选择举报原因，恶意举报将被追责'
                  : '对象：${widget.targetBrief}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 12.5, color: scheme.outline),
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final category in ReportCategory.values)
                  _CategoryChip(
                    category: category,
                    active: category == _category,
                    enabled: !_submitting,
                    onTap: () => setState(() => _category = category),
                  ),
              ],
            ),
            const SizedBox(height: 14),
            TextField(
              controller: _reasonController,
              enabled: !_submitting,
              minLines: 2,
              maxLines: 4,
              maxLength: 200,
              decoration: InputDecoration(
                hintText: '补充说明（选填，帮助平台更快核实）',
                hintStyle: TextStyle(fontSize: 13, color: scheme.outline),
                filled: true,
                fillColor: const Color(0xFFF6F7F9),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
                contentPadding: const EdgeInsets.all(12),
              ),
              style: const TextStyle(fontSize: 13.5, height: 1.5),
            ),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              height: 46,
              child: FilledButton(
                style: FilledButton.styleFrom(
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(23),
                  ),
                  textStyle: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                onPressed: _category == null || _submitting ? null : _submit,
                child: _submitting
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2.2,
                          color: Colors.white,
                        ),
                      )
                    : const Text('提交举报'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CategoryChip extends StatelessWidget {
  const _CategoryChip({
    required this.category,
    required this.active,
    required this.enabled,
    required this.onTap,
  });

  final ReportCategory category;
  final bool active;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return GestureDetector(
      onTap: enabled && !active ? onTap : null,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: active
              ? const Color(0xFFF43F5E).withValues(alpha: .08)
              : const Color(0xFFF3F4F8),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
            color: active
                ? const Color(0xFFF43F5E).withValues(alpha: .55)
                : Colors.transparent,
          ),
        ),
        child: Text(
          category.label,
          style: TextStyle(
            fontSize: 13,
            fontWeight: active ? FontWeight.w700 : FontWeight.w500,
            color: active ? const Color(0xFFF43F5E) : scheme.onSurfaceVariant,
          ),
        ),
      ),
    );
  }
}
