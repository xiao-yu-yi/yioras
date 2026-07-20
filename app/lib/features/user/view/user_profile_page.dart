import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/network/api_exception.dart';
import '../../../core/router/routes.dart';
import '../../../core/utils/time_format.dart';
import '../../feed/widget/post_card.dart';
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
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            pinned: true,
            expandedHeight: 180,
            foregroundColor: Colors.white,
            backgroundColor: scheme.primary,
            title: Text(profile.nickname),
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
                  const DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [Colors.transparent, Colors.black54],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          SliverToBoxAdapter(child: _InfoSection(profile: profile)),
          if (profile.posts.isEmpty)
            const SliverFillRemaining(
              hasScrollBody: false,
              child: Center(child: Text('TA 还没有发布过内容')),
            )
          else
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(12, 4, 12, 24),
              sliver: SliverList.separated(
                itemCount: profile.posts.length,
                separatorBuilder: (context, index) =>
                    const SizedBox(height: 10),
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
              CircleAvatar(
                radius: 32,
                backgroundColor: scheme.primaryContainer,
                foregroundImage: profile.avatar.isEmpty
                    ? null
                    : CachedNetworkImageProvider(profile.avatar),
                child: Text(
                  profile.nickname.isEmpty
                      ? '?'
                      : profile.nickname.characters.first,
                  style: TextStyle(
                    fontSize: 22,
                    color: scheme.onPrimaryContainer,
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
                              fontSize: 18,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 5,
                            vertical: 1,
                          ),
                          decoration: BoxDecoration(
                            color: scheme.primaryContainer,
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            'Lv.${profile.level}',
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w700,
                              color: scheme.onPrimaryContainer,
                            ),
                          ),
                        ),
                        if (profile.badge.isNotEmpty) ...[
                          const SizedBox(width: 4),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 5,
                              vertical: 1,
                            ),
                            decoration: BoxDecoration(
                              color: const Color(
                                0xFFFFB020,
                              ).withValues(alpha: .15),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              profile.badge,
                              style: const TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w600,
                                color: Color(0xFFB07800),
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'ID: ${profile.displayNo}',
                      style: TextStyle(
                        fontSize: 12,
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 4),
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
          const SizedBox(height: 12),
          Row(
            children: [
              _StatItem(label: '关注', value: profile.followCount),
              _StatItem(label: '粉丝', value: profile.fansCount),
              _StatItem(label: '获赞', value: profile.likeCount),
              _StatItem(label: '帖子', value: profile.postCount),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: FilledButton(
                  style: FilledButton.styleFrom(
                    minimumSize: const Size.fromHeight(40),
                    backgroundColor: following
                        ? scheme.surfaceContainerHighest
                        : scheme.primary,
                    foregroundColor: following
                        ? scheme.onSurfaceVariant
                        : Colors.white,
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
              const SizedBox(width: 12),
              Expanded(
                child: OutlinedButton(
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size.fromHeight(40),
                  ),
                  onPressed: () => _openChat(context, ref),
                  child: const Text('私信'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Divider(color: scheme.outlineVariant.withValues(alpha: .5)),
          Text(
            'TA 的作品',
            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
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
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: TextStyle(fontSize: 11.5, color: scheme.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}
