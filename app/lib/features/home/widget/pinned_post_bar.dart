import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/router/routes.dart';
import '../model/home_config.dart';

/// 置顶精选横条（文档 3.2）：喇叭徽章 + 渐变栏目字 + 标题垂直跑马灯。
class PinnedPostBar extends StatefulWidget {
  const PinnedPostBar({super.key, required this.pinnedPosts});

  final List<PinnedPost> pinnedPosts;

  @override
  State<PinnedPostBar> createState() => _PinnedPostBarState();
}

class _PinnedPostBarState extends State<PinnedPostBar> {
  Timer? _rotateTimer;
  int _current = 0;

  @override
  void initState() {
    super.initState();
    if (widget.pinnedPosts.length > 1) {
      _rotateTimer = Timer.periodic(const Duration(seconds: 4), (_) {
        if (!mounted) return;
        setState(() => _current = (_current + 1) % widget.pinnedPosts.length);
      });
    }
  }

  @override
  void dispose() {
    _rotateTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.pinnedPosts.isEmpty) return const SizedBox.shrink();
    final scheme = Theme.of(context).colorScheme;
    final pinned = widget.pinnedPosts[_current];
    final accent = Color.lerp(scheme.primary, const Color(0xFFFF7A45), .5)!;

    return Container(
      margin: const EdgeInsets.fromLTRB(12, 8, 12, 4),
      height: 48,
      decoration: BoxDecoration(
        // 柔和暖色渐变底，与白色帖子卡区分层次
        gradient: LinearGradient(
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
          colors: [
            const Color(0xFFFFF1F2),
            const Color(0xFFFFF8F6),
            Colors.white,
          ],
        ),
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
            color: scheme.primary.withValues(alpha: .07),
            blurRadius: 12,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: () => context.push(Routes.postDetailPath(pinned.postId)),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 11),
            child: Row(
              children: [
                // 渐变喇叭徽章
                Container(
                  width: 27,
                  height: 27,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [scheme.primary, accent],
                    ),
                    borderRadius: BorderRadius.circular(9),
                    boxShadow: [
                      BoxShadow(
                        color: scheme.primary.withValues(alpha: .35),
                        blurRadius: 6,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: const Icon(
                    Icons.campaign_rounded,
                    size: 17,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(width: 9),
                // 渐变栏目字
                ShaderMask(
                  shaderCallback: (bounds) => LinearGradient(
                    colors: [scheme.primary, accent],
                  ).createShader(bounds),
                  child: const Text(
                    '精选推荐',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w900,
                      color: Colors.white,
                      letterSpacing: .2,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                // 标题垂直跑马灯：旧的向上出、新的自下入
                Expanded(
                  child: ClipRect(
                    child: AnimatedSwitcher(
                      duration: const Duration(milliseconds: 350),
                      switchInCurve: Curves.easeOutCubic,
                      switchOutCurve: Curves.easeInCubic,
                      transitionBuilder: (child, animation) {
                        final incoming =
                            child.key == ValueKey<int>(pinned.postId);
                        final slide = Tween<Offset>(
                          begin: incoming
                              ? const Offset(0, 1)
                              : const Offset(0, -1),
                          end: Offset.zero,
                        ).animate(animation);
                        return FadeTransition(
                          opacity: animation,
                          child: SlideTransition(position: slide, child: child),
                        );
                      },
                      layoutBuilder: (currentChild, previousChildren) => Stack(
                        alignment: Alignment.centerLeft,
                        children: [...previousChildren, ?currentChild],
                      ),
                      child: Align(
                        key: ValueKey<int>(pinned.postId),
                        alignment: Alignment.centerLeft,
                        child: Text(
                          pinned.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 13.5,
                            fontWeight: FontWeight.w500,
                            color: scheme.onSurface.withValues(alpha: .82),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                // 多条时的迷你页码点
                if (widget.pinnedPosts.length > 1) ...[
                  Row(
                    children: [
                      for (var i = 0; i < widget.pinnedPosts.length; i++)
                        AnimatedContainer(
                          duration: const Duration(milliseconds: 250),
                          margin: const EdgeInsets.symmetric(horizontal: 2),
                          width: i == _current ? 10 : 4,
                          height: 4,
                          decoration: BoxDecoration(
                            color: i == _current
                                ? scheme.primary
                                : scheme.primary.withValues(alpha: .22),
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(width: 6),
                ],
                Icon(
                  Icons.arrow_forward_ios_rounded,
                  size: 12,
                  color: scheme.primary.withValues(alpha: .75),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
