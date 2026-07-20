import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/router/routes.dart';
import '../../../core/utils/time_format.dart';
import '../../auth/controller/auth_controller.dart';
import '../../auth/model/auth_user.dart';
import '../data/profile_repository.dart';
import '../model/profile_models.dart';
import 'profile_drawer.dart';

/// 个人中心主页（文档 3.8）：封面 + 资料头 + 数据栏 5 项 + 作品/足迹双 Tab + 侧边抽屉。
class ProfilePage extends ConsumerWidget {
  const ProfilePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final auth = ref.watch(authControllerProvider);
    // 路由 redirect 保证进入本页时已登录
    final user = auth is AuthAuthenticated ? auth.user : null;
    if (user == null) return const SizedBox.shrink();

    return Scaffold(
      endDrawer: const ProfileDrawer(),
      body: DefaultTabController(
        length: 2,
        child: NestedScrollView(
          headerSliverBuilder: (context, innerBoxIsScrolled) => [
            SliverToBoxAdapter(child: _ProfileHeader(user: user)),
            SliverPersistentHeader(
              pinned: true,
              delegate: _TabBarDelegate(
                TabBar(
                  tabs: const [
                    Tab(text: '发布作品'),
                    Tab(text: '我的足迹'),
                  ],
                  labelColor: Theme.of(context).colorScheme.primary,
                  indicatorSize: TabBarIndicatorSize.label,
                ),
              ),
            ),
          ],
          body: const TabBarView(children: [_MyPostsTab(), _FootprintsTab()]),
        ),
      ),
    );
  }
}

/// 封面 + 头像资料 + 数据栏
class _ProfileHeader extends ConsumerWidget {
  const _ProfileHeader({required this.user});

  final AuthUser user;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final stats = ref.watch(profileStatsProvider);

    return Column(
      children: [
        // 封面区（更换封面随编辑资料一起接入）
        Stack(
          clipBehavior: Clip.none,
          children: [
            Container(
              height: 150,
              width: double.infinity,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [scheme.primary, scheme.tertiary],
                ),
              ),
            ),
            Positioned(
              top: MediaQuery.paddingOf(context).top + 4,
              right: 8,
              child: Builder(
                builder: (context) => IconButton(
                  icon: const Icon(Icons.menu, color: Colors.white),
                  tooltip: '菜单',
                  onPressed: () => Scaffold.of(context).openEndDrawer(),
                ),
              ),
            ),
            Positioned(
              left: 16,
              bottom: -32,
              child: CircleAvatar(
                radius: 36,
                backgroundColor: Colors.white,
                child: CircleAvatar(
                  radius: 33,
                  backgroundColor: scheme.primaryContainer,
                  foregroundImage: user.avatar.isEmpty
                      ? null
                      : CachedNetworkImageProvider(user.avatar),
                  child: Text(
                    user.nickname.isEmpty
                        ? '?'
                        : user.nickname.characters.first,
                    style: TextStyle(
                      fontSize: 24,
                      color: scheme.onPrimaryContainer,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
        // 资料行
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 6, 16, 0),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(width: 88),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            user.nickname,
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
                            'Lv.${user.level}',
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w700,
                              color: scheme.onPrimaryContainer,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'ID: ${user.displayNo}',
                      style: TextStyle(
                        fontSize: 12,
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              OutlinedButton(
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size(76, 32),
                  visualDensity: VisualDensity.compact,
                ),
                onPressed: () => context.push(Routes.editProfile),
                child: const Text('编辑资料'),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
          child: Align(
            alignment: Alignment.centerLeft,
            child: Text(
              user.signature.isEmpty ? '这个人很懒，什么都没留下' : user.signature,
              style: TextStyle(fontSize: 13, color: scheme.onSurfaceVariant),
            ),
          ),
        ),
        // 数据栏 5 项（文档 3.8：关注/粉丝/获赞/帖子/忧珠）
        Padding(
          padding: const EdgeInsets.fromLTRB(8, 14, 8, 6),
          child: switch (stats) {
            AsyncData(:final value) => Row(
              children: [
                _StatItem(label: '关注', value: value.followCount),
                _StatItem(label: '粉丝', value: value.fansCount),
                _StatItem(label: '获赞', value: value.likeCount),
                _StatItem(label: '帖子', value: value.postCount),
                _StatItem(label: '忧珠', value: value.youzhu, highlight: true),
              ],
            ),
            AsyncError() => SizedBox(
              height: 48,
              child: Center(
                child: TextButton(
                  onPressed: () => ref.invalidate(profileStatsProvider),
                  child: const Text('数据加载失败，点击重试'),
                ),
              ),
            ),
            _ => const SizedBox(
              height: 48,
              child: Center(
                child: SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            ),
          },
        ),
      ],
    );
  }
}

class _StatItem extends StatelessWidget {
  const _StatItem({
    required this.label,
    required this.value,
    this.highlight = false,
  });

  final String label;
  final int value;
  final bool highlight;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Expanded(
      child: InkWell(
        onTap: highlight
            ? () {
                // 忧珠资产页属 M3（忧珠账户与流水）
                ScaffoldMessenger.of(context)
                  ..hideCurrentSnackBar()
                  ..showSnackBar(
                    const SnackBar(content: Text('「忧珠资产」将在 M3 开放')),
                  );
              }
            : null,
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Column(
            children: [
              Text(
                formatCount(value),
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: highlight ? scheme.primary : scheme.onSurface,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                label,
                style: TextStyle(
                  fontSize: 11.5,
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 发布作品 Tab：含审核状态角标（仅自己可见）
class _MyPostsTab extends ConsumerWidget {
  const _MyPostsTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final posts = ref.watch(myPostsProvider);

    return switch (posts) {
      AsyncData(:final value) when value.isEmpty => const Center(
        child: Text('还没有发布过内容'),
      ),
      AsyncData(:final value) => RefreshIndicator(
        onRefresh: () => ref.refresh(myPostsProvider.future),
        child: ListView.separated(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 96),
          itemCount: value.length,
          separatorBuilder: (context, index) => const SizedBox(height: 8),
          itemBuilder: (context, index) => _MyPostTile(item: value[index]),
        ),
      ),
      AsyncError() => Center(
        child: TextButton(
          onPressed: () => ref.invalidate(myPostsProvider),
          child: const Text('加载失败，点击重试'),
        ),
      ),
      _ => const Center(child: CircularProgressIndicator()),
    };
  }
}

class _MyPostTile extends StatelessWidget {
  const _MyPostTile({required this.item});

  final MyPost item;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final post = item.post;
    final statusColor = switch (item.auditStatus) {
      PostAuditStatus.pending => const Color(0xFFF59E0B),
      PostAuditStatus.rejected => scheme.error,
      _ => scheme.outline,
    };

    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => context.push('/posts/${post.id}'),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      post.title.isEmpty ? post.content : post.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  if (item.auditStatus.label.isNotEmpty) ...[
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: statusColor.withValues(alpha: .1),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        item.auditStatus.label,
                        style: TextStyle(fontSize: 11, color: statusColor),
                      ),
                    ),
                  ],
                ],
              ),
              const SizedBox(height: 6),
              Text(
                '${formatRelativeTime(post.createdAt)} · ${post.circleName} · ${formatCount(post.viewCount)} 浏览 · ${formatCount(post.likeCount)} 赞',
                style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 我的足迹 Tab：浏览历史（仅自己可见，可清空）
class _FootprintsTab extends ConsumerWidget {
  const _FootprintsTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final footprints = ref.watch(footprintsProvider);
    final scheme = Theme.of(context).colorScheme;

    return switch (footprints) {
      AsyncData(:final value) when value.isEmpty => const Center(
        child: Text('暂无浏览记录'),
      ),
      AsyncData(:final value) => Column(
        children: [
          Align(
            alignment: Alignment.centerRight,
            child: TextButton.icon(
              onPressed: () async {
                final confirmed = await showDialog<bool>(
                  context: context,
                  builder: (context) => AlertDialog(
                    title: const Text('清空足迹？'),
                    content: const Text('清空后浏览记录不可恢复。'),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.of(context).pop(false),
                        child: const Text('取消'),
                      ),
                      FilledButton(
                        onPressed: () => Navigator.of(context).pop(true),
                        child: const Text('清空'),
                      ),
                    ],
                  ),
                );
                if (confirmed != true) return;
                await ref.read(profileRepositoryProvider).clearFootprints();
                ref.invalidate(footprintsProvider);
              },
              icon: Icon(Icons.delete_outline, size: 16, color: scheme.outline),
              label: Text(
                '清空',
                style: TextStyle(fontSize: 12.5, color: scheme.outline),
              ),
            ),
          ),
          Expanded(
            child: RefreshIndicator(
              onRefresh: () => ref.refresh(footprintsProvider.future),
              child: ListView.separated(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 96),
                itemCount: value.length,
                separatorBuilder: (context, index) => const SizedBox(height: 8),
                itemBuilder: (context, index) {
                  final footprint = value[index];
                  return Card(
                    clipBehavior: Clip.antiAlias,
                    child: ListTile(
                      onTap: () => context.push('/posts/${footprint.post.id}'),
                      title: Text(
                        footprint.post.title.isEmpty
                            ? footprint.post.content
                            : footprint.post.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 14.5),
                      ),
                      subtitle: Text(
                        '${footprint.post.author.nickname} · ${formatRelativeTime(footprint.viewedAt)}浏览',
                        style: TextStyle(
                          fontSize: 12,
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
        ],
      ),
      AsyncError() => Center(
        child: TextButton(
          onPressed: () => ref.invalidate(footprintsProvider),
          child: const Text('加载失败，点击重试'),
        ),
      ),
      _ => const Center(child: CircularProgressIndicator()),
    };
  }
}

/// 吸顶 TabBar
class _TabBarDelegate extends SliverPersistentHeaderDelegate {
  const _TabBarDelegate(this.tabBar);

  final TabBar tabBar;

  @override
  double get minExtent => tabBar.preferredSize.height;

  @override
  double get maxExtent => tabBar.preferredSize.height;

  @override
  Widget build(
    BuildContext context,
    double shrinkOffset,
    bool overlapsContent,
  ) {
    return ColoredBox(
      color: Theme.of(context).scaffoldBackgroundColor,
      child: tabBar,
    );
  }

  @override
  bool shouldRebuild(covariant _TabBarDelegate oldDelegate) =>
      oldDelegate.tabBar != tabBar;
}
