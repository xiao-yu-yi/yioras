import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/network/api_exception.dart';
import '../../../core/router/routes.dart';
import '../../../core/utils/time_format.dart';
import '../../feed/widget/post_card.dart';
import '../../report/data/report_repository.dart';
import '../../report/widget/report_sheet.dart';
import '../controller/follow_controller.dart';
import '../data/user_repository.dart';
import '../model/user_profile.dart';

/// 他人主页（文档 3.8）：封面资料 + 数据栏 4 项 + 关注/私信 + TA 的作品。
class UserProfilePage extends ConsumerWidget {
  const UserProfilePage({super.key, required this.uid});

  final int uid;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profile = ref.watch(userProfileProvider(uid));
    // 服务端初始关注状态并入全局覆盖层
    ref.listen(userProfileProvider(uid), (previous, next) {
      final value = next.value;
      if (value != null) {
        ref.read(followControllerProvider.notifier).seed(uid, value.following);
      }
    });

    return switch (profile) {
      AsyncData(:final value) => _ProfileBody(profile: value),
      AsyncError(:final error) => Scaffold(
        appBar: AppBar(title: const Text('个人主页')),
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(error is ApiException ? error.message : '加载失败，请稍后重试'),
              const SizedBox(height: 16),
              OutlinedButton(
                onPressed: () => ref.invalidate(userProfileProvider(uid)),
                child: const Text('重新加载'),
              ),
            ],
          ),
        ),
      ),
      _ => Scaffold(
        appBar: AppBar(title: const Text('个人主页')),
        body: const Center(child: CircularProgressIndicator()),
      ),
    };
  }
}

class _ProfileBody extends ConsumerWidget {
  const _ProfileBody({required this.profile});

  final UserProfile profile;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: Colors.white,
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            pinned: true,
            expandedHeight: 190,
            foregroundColor: Colors.white,
            backgroundColor: scheme.primary,
            title: Text(
              profile.nickname,
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
            ),
            actions: [
              // 举报入口（文档 3.8 他人主页）
              IconButton(
                tooltip: '举报',
                icon: const Icon(Icons.more_horiz),
                onPressed: () => showReportSheet(
                  context,
                  targetType: ReportTargetType.user,
                  targetId: profile.id,
                  targetBrief: profile.nickname,
                ),
              ),
            ],
            flexibleSpace: FlexibleSpaceBar(
              background: Stack(
                fit: StackFit.expand,
                children: [
                  if (profile.cover.isNotEmpty)
                    CachedNetworkImage(
                      imageUrl: profile.cover,
                      fit: BoxFit.cover,
                      errorWidget: (context, url, error) =>
                          Container(color: scheme.primary),
                    )
                  else
                    Container(color: scheme.primary),
                  // 顶部轻压暗保证返回键可见
                  const DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [Colors.black26, Colors.transparent],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          SliverToBoxAdapter(child: _InfoSection(profile: profile)),
          if (profile.posts.isEmpty)
            SliverFillRemaining(
              hasScrollBody: false,
              child: Center(
                child: Text(
                  '这里空空如也',
                  style: TextStyle(fontSize: 13, color: scheme.outline),
                ),
              ),
            )
          else
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(12, 4, 12, 24),
              sliver: SliverList.separated(
                itemCount: profile.posts.length,
                separatorBuilder: (context, index) =>
                    const SizedBox(height: 12),
                itemBuilder: (context, index) {
                  final post = profile.posts[index];
                  return PostCard(
                    key: ValueKey(post.id),
                    post: post,
                    onTap: () => context.push(Routes.postDetailPath(post.id)),
                  );
                },
              ),
            ),
        ],
      ),
    );
  }
}

class _InfoSection extends ConsumerWidget {
  const _InfoSection({required this.profile});

  final UserProfile profile;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final follow = ref.watch(followControllerProvider);
    final followNotifier = ref.read(followControllerProvider.notifier);
    final following = follow[profile.id] ?? profile.following;
    final busy = followNotifier.isBusy(profile.id);

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 白圈骑缝头像（与我的页同语言）
              Container(
                padding: const EdgeInsets.all(4),
                decoration: BoxDecoration(
                  color: Colors.white,
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFF1F2430).withValues(alpha: .1),
                      blurRadius: 12,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: CircleAvatar(
                  radius: 32,
                  backgroundColor: const Color(0xFFEDF1FA),
                  foregroundImage: profile.avatar.isEmpty
                      ? null
                      : CachedNetworkImageProvider(profile.avatar),
                  child: Text(
                    profile.nickname.isEmpty
                        ? '?'
                        : profile.nickname.characters.first,
                    style: TextStyle(fontSize: 22, color: scheme.primary),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            profile.nickname,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        // 深色 Lv 徽章（与我的页同款）
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 2.5,
                          ),
                          decoration: BoxDecoration(
                            color: const Color(0xFF273043),
                            borderRadius: BorderRadius.circular(999),
                          ),
                          child: Text(
                            'Lv.${profile.level}',
                            style: const TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w800,
                              color: Color(0xFFFFD666),
                              height: 1.2,
                            ),
                          ),
                        ),
                        if (profile.badge.isNotEmpty) ...[
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 7,
                              vertical: 2.5,
                            ),
                            decoration: BoxDecoration(
                              color: const Color(0xFFFFF3DC),
                              borderRadius: BorderRadius.circular(999),
                            ),
                            child: Text(
                              profile.badge,
                              style: const TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w700,
                                color: Color(0xFFA36A00),
                                height: 1.2,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 5),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 2.5,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF3F4F8),
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text(
                        profile.displayNo,
                        style: TextStyle(
                          fontSize: 10.5,
                          color: scheme.onSurfaceVariant,
                          fontWeight: FontWeight.w600,
                          height: 1.2,
                        ),
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      profile.signature.isEmpty
                          ? '这个人很懒，什么都没留下'
                          : profile.signature,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12.5,
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              _StatItem(label: '关注', value: profile.followCount),
              _StatItem(label: '粉丝', value: profile.fansCount),
              _StatItem(label: '获赞', value: profile.likeCount),
              _StatItem(label: '帖子', value: profile.postCount),
            ],
          ),
          const SizedBox(height: 14),
          // 操作区（文档 3.8 他人视角：关注 / 私信），胶囊化对齐全站按钮语言
          Row(
            children: [
              Expanded(
                child: Container(
                  decoration: BoxDecoration(
                    gradient: following
                        ? null
                        : const LinearGradient(
                            colors: [Color(0xFFF43F5E), Color(0xFFFF7849)],
                          ),
                    color: following ? const Color(0xFFF3F4F8) : null,
                    borderRadius: BorderRadius.circular(22),
                    boxShadow: following
                        ? null
                        : [
                            BoxShadow(
                              color: const Color(
                                0xFFF43F5E,
                              ).withValues(alpha: .3),
                              blurRadius: 10,
                              offset: const Offset(0, 3),
                            ),
                          ],
                  ),
                  child: FilledButton(
                    style: FilledButton.styleFrom(
                      minimumSize: const Size.fromHeight(42),
                      backgroundColor: Colors.transparent,
                      disabledBackgroundColor: Colors.transparent,
                      shadowColor: Colors.transparent,
                      foregroundColor: following
                          ? scheme.onSurfaceVariant
                          : Colors.white,
                      textStyle: const TextStyle(
                        fontSize: 14.5,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    onPressed: busy
                        ? null
                        : () async {
                            try {
                              await followNotifier.toggle(
                                profile.id,
                                currentlyFollowing: following,
                              );
                            } on ApiException catch (e) {
                              if (context.mounted) {
                                ScaffoldMessenger.of(context)
                                  ..hideCurrentSnackBar()
                                  ..showSnackBar(
                                    SnackBar(content: Text(e.message)),
                                  );
                              }
                            }
                          },
                    child: Text(following ? '已关注' : '+ 关注'),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: OutlinedButton(
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size.fromHeight(42),
                    side: const BorderSide(
                      color: Color(0xFFECEDF2),
                      width: 1.2,
                    ),
                    foregroundColor: scheme.onSurface,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(22),
                    ),
                    textStyle: const TextStyle(
                      fontSize: 14.5,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  onPressed: () => _openChat(context, ref),
                  child: const Text('私信'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          const Text(
            'TA 的作品',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
          ),
        ],
      ),
    );
  }

  Future<void> _openChat(BuildContext context, WidgetRef ref) async {
    try {
      final conversationId = await ref
          .read(userRepositoryProvider)
          .openConversation(profile.id);
      if (context.mounted) {
        context.push(Routes.chatPath(conversationId));
      }
    } on ApiException catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(SnackBar(content: Text(e.message)));
      }
    }
  }
}

class _StatItem extends StatelessWidget {
  const _StatItem({required this.label, required this.value});

  final String label;
  final int value;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Expanded(
      child: Column(
        children: [
          Text(
            formatCount(value),
            style: const TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w800,
              height: 1.2,
            ),
          ),
          const SizedBox(height: 3),
          Text(label, style: TextStyle(fontSize: 11, color: scheme.outline)),
        ],
      ),
    );
  }
}
