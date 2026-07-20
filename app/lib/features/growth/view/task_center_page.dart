import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_exception.dart';
import '../controller/task_center_controller.dart';
import '../model/growth_models.dart';

/// 任务中心页（文档 3.9）：签到卡（连签天数 + 一键签到）+ 每日任务 + 新手任务。
class TaskCenterPage extends ConsumerWidget {
  const TaskCenterPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(taskCenterControllerProvider);

    return Scaffold(
      backgroundColor: const Color(0xFFF6F7F9),
      appBar: AppBar(
        title: const Text(
          '任务中心',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
        ),
      ),
      body: switch (state) {
        AsyncData(:final value) => _TaskCenterBody(center: value),
        AsyncError(:final error) => _ErrorView(
          message: error is ApiException ? error.message : '加载失败，请稍后重试',
          onRetry: () =>
              ref.read(taskCenterControllerProvider.notifier).retryFirstLoad(),
        ),
        _ => const Center(child: CircularProgressIndicator()),
      },
    );
  }
}

class _TaskCenterBody extends ConsumerWidget {
  const _TaskCenterBody({required this.center});

  final TaskCenter center;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final daily = center.tasks.where((t) => t.type == 1).toList();
    final newbie = center.tasks.where((t) => t.type == 2).toList();

    return ListView(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 24),
      children: [
        _SignInCard(center: center),
        if (daily.isNotEmpty) ...[
          const SizedBox(height: 14),
          const _SectionTitle('每日任务'),
          const SizedBox(height: 8),
          _TaskGroup(tasks: daily),
        ],
        if (newbie.isNotEmpty) ...[
          const SizedBox(height: 14),
          const _SectionTitle('新手任务'),
          const SizedBox(height: 8),
          _TaskGroup(tasks: newbie),
        ],
      ],
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 6),
      child: Text(
        text,
        style: const TextStyle(fontSize: 15.5, fontWeight: FontWeight.w800),
      ),
    );
  }
}

/// 品牌渐变签到卡：连签天数 + 下次奖励 + 签到按钮
class _SignInCard extends ConsumerStatefulWidget {
  const _SignInCard({required this.center});

  final TaskCenter center;

  @override
  ConsumerState<_SignInCard> createState() => _SignInCardState();
}

class _SignInCardState extends ConsumerState<_SignInCard> {
  bool _busy = false;

  Future<void> _signIn() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final result = await ref
          .read(taskCenterControllerProvider.notifier)
          .signIn();
      if (!mounted) return;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text(
              '签到成功 +${result.reward} 忧珠，已连签 ${result.continuous} 天',
            ),
          ),
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
    final center = widget.center;
    return Container(
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFFF43F5E), Color(0xFFFF7849)],
        ),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFFF43F5E).withValues(alpha: .3),
            blurRadius: 14,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  center.signedToday ? '今日已签到' : '每日签到',
                  style: const TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w800,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 5),
                Text(
                  center.signedToday
                      ? '已连续签到 ${center.continuous} 天，明天可得 ${center.nextReward} 忧珠'
                      : '已连签 ${center.continuous} 天，今天签到得 ${center.nextReward} 忧珠',
                  style: TextStyle(
                    fontSize: 11.5,
                    color: Colors.white.withValues(alpha: .85),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          SizedBox(
            height: 38,
            child: FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: Colors.white,
                foregroundColor: const Color(0xFFF43F5E),
                disabledBackgroundColor: Colors.white.withValues(alpha: .45),
                disabledForegroundColor: const Color(
                  0xFFF43F5E,
                ).withValues(alpha: .6),
                padding: const EdgeInsets.symmetric(horizontal: 18),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(19),
                ),
                textStyle: const TextStyle(
                  fontSize: 13.5,
                  fontWeight: FontWeight.w800,
                ),
              ),
              onPressed: center.signedToday || _busy ? null : _signIn,
              child: _busy
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Text(center.signedToday ? '已签到' : '签到'),
            ),
          ),
        ],
      ),
    );
  }
}

/// 白卡任务组
class _TaskGroup extends StatelessWidget {
  const _TaskGroup({required this.tasks});

  final List<GrowthTask> tasks;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        children: [
          for (var i = 0; i < tasks.length; i++) ...[
            if (i > 0)
              Divider(
                height: 1,
                thickness: .5,
                color: scheme.outlineVariant.withValues(alpha: .4),
              ),
            _TaskRow(task: tasks[i]),
          ],
        ],
      ),
    );
  }
}

class _TaskRow extends ConsumerStatefulWidget {
  const _TaskRow({required this.task});

  final GrowthTask task;

  @override
  ConsumerState<_TaskRow> createState() => _TaskRowState();
}

class _TaskRowState extends ConsumerState<_TaskRow> {
  bool _busy = false;

  Future<void> _claim() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final result = await ref
          .read(taskCenterControllerProvider.notifier)
          .claim(widget.task.id);
      if (!mounted) return;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text('领取成功 +${result.reward} 忧珠')));
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
    final task = widget.task;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  task.name,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    Text(
                      '+${task.rewardYouzhu} 忧珠',
                      style: const TextStyle(
                        fontSize: 11.5,
                        color: Color(0xFFF43F5E),
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    if (task.rewardExp > 0) ...[
                      const SizedBox(width: 8),
                      Text(
                        '+${task.rewardExp} 经验',
                        style: TextStyle(
                          fontSize: 11.5,
                          color: scheme.outline,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                    const SizedBox(width: 8),
                    Text(
                      '${task.progress.clamp(0, task.target)}/${task.target}',
                      style: TextStyle(fontSize: 11.5, color: scheme.outline),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          _StatusButton(task: task, busy: _busy, onClaim: _claim),
        ],
      ),
    );
  }
}

class _StatusButton extends StatelessWidget {
  const _StatusButton({
    required this.task,
    required this.busy,
    required this.onClaim,
  });

  final GrowthTask task;
  final bool busy;
  final VoidCallback onClaim;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return switch (task.status) {
      1 => SizedBox(
        height: 30,
        child: FilledButton(
          style: FilledButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: 14),
            visualDensity: VisualDensity.compact,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(15),
            ),
            textStyle: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
          onPressed: busy ? null : onClaim,
          child: busy
              ? const SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(
                    strokeWidth: 1.8,
                    color: Colors.white,
                  ),
                )
              : const Text('领取'),
        ),
      ),
      2 => Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: const Color(0xFFF0F1F5),
          borderRadius: BorderRadius.circular(15),
        ),
        child: Text(
          '已领取',
          style: TextStyle(
            fontSize: 12,
            color: scheme.outline,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
      _ => Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          border: Border.all(color: scheme.outlineVariant),
          borderRadius: BorderRadius.circular(15),
        ),
        child: Text(
          '去完成',
          style: TextStyle(
            fontSize: 12,
            color: scheme.onSurfaceVariant,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    };
  }
}

class _ErrorView extends StatelessWidget {
  const _ErrorView({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.task_alt, size: 56, color: scheme.outline),
          const SizedBox(height: 12),
          Text(message, style: TextStyle(color: scheme.onSurfaceVariant)),
          const SizedBox(height: 16),
          OutlinedButton(onPressed: onRetry, child: const Text('重新加载')),
        ],
      ),
    );
  }
}
