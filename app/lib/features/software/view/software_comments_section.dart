import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_exception.dart';
import '../../../core/utils/time_format.dart';
import '../../post_detail/model/post_detail.dart';
import '../../report/data/report_repository.dart';
import '../../report/widget/report_sheet.dart';
import '../controller/software_comments_controller.dart';

/// 软件详情页评论分区（文档 3.6）：两级评论（回复灰盒预览）+ 点赞 +
/// 点评论回复 / 长按举报 + 分页加载 + 底部「说点什么」入口弹输入面板。
class SoftwareCommentsSection extends ConsumerWidget {
  const SoftwareCommentsSection({super.key, required this.softwareId});

  final int softwareId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(softwareCommentsControllerProvider(softwareId));

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            '评论区',
            style: TextStyle(fontSize: 14.5, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 4),
          switch (state) {
            AsyncData(:final value) => _CommentsBody(
              softwareId: softwareId,
              state: value,
            ),
            AsyncError() => Padding(
              padding: const EdgeInsets.symmetric(vertical: 20),
              child: Center(
                child: TextButton(
                  onPressed: () => ref.invalidate(
                    softwareCommentsControllerProvider(softwareId),
                  ),
                  child: const Text('评论加载失败，点击重试'),
                ),
              ),
            ),
            _ => const Padding(
              padding: EdgeInsets.symmetric(vertical: 24),
              child: Center(
                child: SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            ),
          },
          const SizedBox(height: 10),
          _CommentEntryBar(softwareId: softwareId),
        ],
      ),
    );
  }
}

class _CommentsBody extends ConsumerWidget {
  const _CommentsBody({required this.softwareId, required this.state});

  final int softwareId;
  final SoftwareCommentsState state;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    if (state.comments.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 22),
        child: Center(
          child: Text(
            '还没有评论，来说说使用体验',
            style: TextStyle(fontSize: 12.5, color: scheme.outline),
          ),
        ),
      );
    }

    Future<void> like(Comment comment) async {
      try {
        await ref
            .read(softwareCommentsControllerProvider(softwareId).notifier)
            .toggleLike(comment.id);
      } on ApiException catch (e) {
        if (context.mounted) {
          ScaffoldMessenger.of(context)
            ..hideCurrentSnackBar()
            ..showSnackBar(SnackBar(content: Text(e.message)));
        }
      }
    }

    void reply(Comment target, Comment root) {
      showSoftwareCommentInput(
        context,
        softwareId: softwareId,
        replyTo: target,
        rootId: root.id,
      );
    }

    void report(Comment target) {
      showReportSheet(
        context,
        targetType: ReportTargetType.comment,
        targetId: target.id,
        targetBrief: target.content,
      );
    }

    return Column(
      children: [
        for (var i = 0; i < state.comments.length; i++) ...[
          if (i > 0)
            Divider(
              height: 20,
              thickness: .5,
              indent: 38,
              color: scheme.outlineVariant.withValues(alpha: .4),
            ),
          _CommentTile(
            comment: state.comments[i],
            onLike: like,
            onReply: reply,
            onReport: report,
          ),
        ],
        if (state.hasMore || state.loadingMore || state.loadMoreError != null)
          Padding(
            padding: const EdgeInsets.only(top: 10),
            child: state.loadingMore
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 1.8),
                  )
                : TextButton(
                    style: TextButton.styleFrom(
                      visualDensity: VisualDensity.compact,
                      textStyle: const TextStyle(fontSize: 12.5),
                    ),
                    onPressed: () => ref
                        .read(
                          softwareCommentsControllerProvider(
                            softwareId,
                          ).notifier,
                        )
                        .loadMore(),
                    child: Text(
                      state.loadMoreError != null
                          ? '${state.loadMoreError}，点击重试'
                          : '查看更多评论',
                    ),
                  ),
          ),
      ],
    );
  }
}

/// 单条评论（含回复灰盒预览）
class _CommentTile extends StatelessWidget {
  const _CommentTile({
    required this.comment,
    required this.onLike,
    required this.onReply,
    required this.onReport,
  });

  final Comment comment;
  final void Function(Comment target) onLike;
  final void Function(Comment target, Comment root) onReply;
  final void Function(Comment target) onReport;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _CommentRow(
          comment: comment,
          onTap: () => onReply(comment, comment),
          onLike: () => onLike(comment),
          onLongPress: () => onReport(comment),
        ),
        if (comment.replies.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(left: 38, top: 8),
            child: Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: const Color(0xFFF6F7F9),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (var i = 0; i < comment.replies.length; i++) ...[
                    if (i > 0) const SizedBox(height: 8),
                    _CommentRow(
                      comment: comment.replies[i],
                      dense: true,
                      onTap: () => onReply(comment.replies[i], comment),
                      onLike: () => onLike(comment.replies[i]),
                      onLongPress: () => onReport(comment.replies[i]),
                    ),
                  ],
                ],
              ),
            ),
          ),
      ],
    );
  }
}

class _CommentRow extends StatelessWidget {
  const _CommentRow({
    required this.comment,
    this.dense = false,
    this.onTap,
    this.onLike,
    this.onLongPress,
  });

  final Comment comment;
  final bool dense;
  final VoidCallback? onTap;
  final VoidCallback? onLike;
  final VoidCallback? onLongPress;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final author = comment.author;
    final likeColor = comment.liked ? scheme.primary : scheme.outline;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        CircleAvatar(
          radius: dense ? 11 : 14,
          backgroundColor: scheme.surfaceContainerHighest,
          foregroundImage: author.avatar.isEmpty
              ? null
              : CachedNetworkImageProvider(author.avatar),
          child: Text(
            author.nickname.isEmpty ? '?' : author.nickname.characters.first,
            style: TextStyle(fontSize: dense ? 9 : 11, color: scheme.primary),
          ),
        ),
        const SizedBox(width: 9),
        Expanded(
          child: GestureDetector(
            onTap: onTap,
            onLongPress: onLongPress,
            behavior: HitTestBehavior.opaque,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        author.nickname,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: dense ? 11.5 : 12.5,
                          fontWeight: FontWeight.w600,
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                    if (comment.replyToNickname.isNotEmpty) ...[
                      const SizedBox(width: 4),
                      Text(
                        '回复 @${comment.replyToNickname}',
                        style: TextStyle(fontSize: 10.5, color: scheme.primary),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 3),
                Text(
                  comment.content,
                  style: TextStyle(fontSize: dense ? 12.5 : 14, height: 1.55),
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    Text(
                      formatRelativeTime(comment.createdAt),
                      style: TextStyle(fontSize: 10.5, color: scheme.outline),
                    ),
                    const SizedBox(width: 10),
                    Text(
                      '回复',
                      style: TextStyle(
                        fontSize: 10.5,
                        color: scheme.onSurfaceVariant,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const Spacer(),
                    GestureDetector(
                      onTap: onLike,
                      behavior: HitTestBehavior.opaque,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 2,
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              comment.liked
                                  ? Icons.favorite_rounded
                                  : Icons.favorite_border_rounded,
                              size: 13,
                              color: likeColor,
                            ),
                            const SizedBox(width: 3),
                            Text(
                              comment.likeCount > 0
                                  ? '${comment.likeCount}'
                                  : '赞',
                              style: TextStyle(
                                fontSize: 10.5,
                                color: likeColor,
                                fontWeight: comment.liked
                                    ? FontWeight.w600
                                    : FontWeight.w400,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// 「说点什么…」入口条：点击弹输入面板发一级评论
class _CommentEntryBar extends StatelessWidget {
  const _CommentEntryBar({required this.softwareId});

  final int softwareId;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return GestureDetector(
      onTap: () => showSoftwareCommentInput(context, softwareId: softwareId),
      child: Container(
        height: 40,
        padding: const EdgeInsets.symmetric(horizontal: 14),
        decoration: BoxDecoration(
          color: const Color(0xFFF3F4F8),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(
          children: [
            Icon(Icons.edit_outlined, size: 16, color: scheme.outline),
            const SizedBox(width: 8),
            Text(
              '说点什么…',
              style: TextStyle(fontSize: 13, color: scheme.outline),
            ),
          ],
        ),
      ),
    );
  }
}

/// 弹出评论输入面板（发一级评论 / 回复某条评论共用）
Future<void> showSoftwareCommentInput(
  BuildContext context, {
  required int softwareId,
  Comment? replyTo,
  int? rootId,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.white,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
    ),
    builder: (context) => Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: _CommentInputSheet(
        softwareId: softwareId,
        replyTo: replyTo,
        rootId: rootId,
      ),
    ),
  );
}

class _CommentInputSheet extends ConsumerStatefulWidget {
  const _CommentInputSheet({
    required this.softwareId,
    this.replyTo,
    this.rootId,
  });

  final int softwareId;
  final Comment? replyTo;
  final int? rootId;

  @override
  ConsumerState<_CommentInputSheet> createState() => _CommentInputSheetState();
}

class _CommentInputSheetState extends ConsumerState<_CommentInputSheet> {
  final _controller = TextEditingController();
  bool _sending = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final content = _controller.text.trim();
    if (content.isEmpty || _sending) return;
    setState(() => _sending = true);
    try {
      await ref
          .read(softwareCommentsControllerProvider(widget.softwareId).notifier)
          .send(
            content,
            replyTo: widget.replyTo?.id,
            rootId: widget.rootId,
            replyToNickname: widget.replyTo?.author.nickname ?? '',
          );
      if (!mounted) return;
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(const SnackBar(content: Text('评论已发布')));
    } on ApiException catch (e) {
      if (mounted) {
        setState(() => _sending = false);
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(SnackBar(content: Text('发布失败：${e.message}')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final replyTo = widget.replyTo;

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              replyTo == null ? '发表评论' : '回复 @${replyTo.author.nickname}',
              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _controller,
              enabled: !_sending,
              autofocus: true,
              minLines: 2,
              maxLines: 5,
              maxLength: 500,
              decoration: InputDecoration(
                hintText: replyTo == null ? '说说这款软件的使用体验…' : '回复内容…',
                hintStyle: TextStyle(fontSize: 13.5, color: scheme.outline),
                filled: true,
                fillColor: const Color(0xFFF6F7F9),
                counterText: '',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
                contentPadding: const EdgeInsets.all(12),
              ),
              style: const TextStyle(fontSize: 14, height: 1.5),
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 10),
            Align(
              alignment: Alignment.centerRight,
              child: FilledButton(
                style: FilledButton.styleFrom(
                  minimumSize: const Size(88, 38),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(19),
                  ),
                  textStyle: const TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                onPressed: _controller.text.trim().isEmpty || _sending
                    ? null
                    : _send,
                child: _sending
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Text('发布'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
