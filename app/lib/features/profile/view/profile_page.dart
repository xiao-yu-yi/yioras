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
      backgroundColor: Colors.white,
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
                  unselectedLabelColor: Theme.of(context).colorScheme.outline,
                  labelStyle: const TextStyle(
                    fontSize: 14.5,
                    fontWeight: FontWeight.w800,
                  ),
                  unselectedLabelStyle: const TextStyle(
                    fontSize: 14.5,
                    fontWeight: FontWeight.w500,
                  ),
                  indicatorSize: TabBarIndicatorSize.label,
                  indicatorWeight: 3,
                  dividerColor: const Color(0xFFF0F1F5),
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

/// 大封面 + 悬浮胶囊操作钮 + 骑缝头像 + 资料区 + 数据栏（视觉对齐设计图）
class _ProfileHeader extends ConsumerWidget {
  const _ProfileHeader({required this.user});

  final AuthUser user;

  void _comingSoon(BuildContext context, String name, {String? suffix}) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(content: Text('「$name」${suffix ?? '正在开发中，敬请期待'}')),
      );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final stats = ref.watch(profileStatsProvider);

    return Column(
      children: [
        // 大封面区（浅色底 + 品牌水印占位，封面素材就绪后换图）+ 骑缝头像
        Stack(
          clipBehavior: Clip.none,
          children: [
            Container(
              height: 300,
              width: double.infinity,
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Color(0xFFEDF1FA), Color(0xFFFDFDFF)],
                ),
              ),
              // 蓝紫渐变星形占位画（贴设计图的插画氛围，素材就绪后换图）
              child: Stack(
                alignment: Alignment.center,
                children: [
                  Positioned(top: 74, child: _GradientStar(size: 128)),
                  Positioned(
                    top: 60,
                    right: 118,
                    child: _GradientStar(size: 38),
                  ),
                  Positioned(
                    top: 190,
                    left: 128,
                    child: _GradientStar(size: 24),
                  ),
                ],
              ),
            ),
            // 封面顶部淡昵称水印（贴设计图）
            Positioned(
              top: MediaQuery.paddingOf(context).top + 12,
              left: 0,
              right: 0,
              child: Center(
                child: Text(
                  user.nickname,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: const Color(0xFF1F2430).withValues(alpha: .16),
                  ),
                ),
              ),
            ),
            Positioned(
              top: MediaQuery.paddingOf(context).top + 6,
              left: 12,
              child: _FrostedCircleButton(
                icon: Icons.qr_code_scanner_rounded,
                onTap: () => _comingSoon(context, '扫一扫'),
              ),
            ),
            Positioned(
              top: MediaQuery.paddingOf(context).top + 6,
              right: 12,
              child: Row(
                children: [
                  _FrostedCircleButton(
                    icon: Icons.person_add_alt_rounded,
                    onTap: () => _comingSoon(context, '添加好友'),
                  ),
                  const SizedBox(width: 8),
                  Builder(
                    builder: (context) => _FrostedCircleButton(
                      icon: Icons.menu_rounded,
                      onTap: () => Scaffold.of(context).openEndDrawer(),
                    ),
                  ),
                ],
              ),
            ),
            Positioned(
              left: 16,
              bottom: -40,
              child: Container(
                padding: const EdgeInsets.all(5),
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
                  radius: 38,
                  backgroundColor: const Color(0xFFEDF1FA),
                  foregroundImage: user.avatar.isEmpty
                      ? null
                      : CachedNetworkImageProvider(user.avatar),
                  child: Text(
                    user.nickname.isEmpty
                        ? '?'
                        : user.nickname.characters.first,
                    style: TextStyle(fontSize: 28, color: scheme.primary),
                  ),
                ),
              ),
            ),
          ],
        ),
        // 操作区（文档 3.8：编辑资料 / 更换封面 / 忧珠资产，VIP 已裁剪不做）
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              _PillButton(
                label: '更换封面',
                background: Colors.white,
                foreground: const Color(0xFF3A4256),
                bordered: true,
                onTap: () => _comingSoon(context, '更换封面'),
              ),
              const SizedBox(width: 8),
              _PillButton(
                label: '忧珠资产',
                background: const Color(0xFF273043),
                foreground: Colors.white,
                onTap: () => _comingSoon(context, '忧珠资产', suffix: '将在 M3 开放'),
              ),
              const SizedBox(width: 8),
              _PillButton(
                label: '编辑资料',
                gradient: const LinearGradient(
                  colors: [Color(0xFFF43F5E), Color(0xFFFF7849)],
                ),
                foreground: Colors.white,
                onTap: () => context.push(Routes.editProfile),
              ),
            ],
          ),
        ),
        // 资料区：昵称 + Lv + 靓号 ID + 签名
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
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
                        fontSize: 22,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  // 深色 Lv 徽章（贴设计图）
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
                      'Lv.${user.level}',
                      style: const TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w800,
                        color: Color(0xFFFFD666),
                        height: 1.2,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
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
                      user.displayNo,
                      style: TextStyle(
                        fontSize: 10.5,
                        color: scheme.onSurfaceVariant,
                        fontWeight: FontWeight.w600,
                        height: 1.2,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 9),
              GestureDetector(
                onTap: () => context.push(Routes.editProfile),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Flexible(
                      child: Text(
                        user.signature.isEmpty
                            ? '填写个性签名，让大家认识你…'
                            : user.signature,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 13,
                          color: user.signature.isEmpty
                              ? scheme.outline
                              : scheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                    const SizedBox(width: 4),
                    Icon(Icons.edit_outlined, size: 13, color: scheme.outline),
                  ],
                ),
              ),
            ],
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

/// 蓝紫渐变四角星（封面占位插画元素）
class _GradientStar extends StatelessWidget {
  const _GradientStar({required this.size});

  final double size;

  @override
  Widget build(BuildContext context) {
    return ShaderMask(
      shaderCallback: (bounds) => const LinearGradient(
        begin: Alignment.topRight,
        end: Alignment.bottomLeft,
        colors: [Color(0xFF2E5BFF), Color(0xFF8A5CFF)],
      ).createShader(bounds),
      child: Icon(Icons.auto_awesome_rounded, size: size, color: Colors.white),
    );
  }
}

/// 封面上的磨砂圆形小按钮（扫一扫/加好友/菜单）
class _FrostedCircleButton extends StatelessWidget {
  const _FrostedCircleButton({required this.icon, required this.onTap});

  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 32,
        height: 32,
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: .7),
          shape: BoxShape.circle,
          boxShadow: [
            BoxShadow(
              color: const Color(0xFF1F2430).withValues(alpha: .08),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Icon(icon, size: 16, color: const Color(0xFF3A4256)),
      ),
    );
  }
}

/// 悬浮小胶囊按钮（更换封面/编辑资料/我的资产）
class _PillButton extends StatelessWidget {
  const _PillButton({
    required this.label,
    required this.foreground,
    required this.onTap,
    this.background,
    this.gradient,
    this.bordered = false,
  });

  final String label;
  final Color foreground;
  final Color? background;
  final Gradient? gradient;
  final bool bordered;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
        decoration: BoxDecoration(
          color: gradient == null ? background : null,
          gradient: gradient,
          borderRadius: BorderRadius.circular(999),
          border: bordered
              ? Border.all(color: const Color(0xFFECEDF2), width: 1.2)
              : null,
          boxShadow: [
            BoxShadow(
              color: const Color(0xFF1F2430).withValues(alpha: .08),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w700,
            color: foreground,
            height: 1.2,
          ),
        ),
      ),
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
                  fontSize: 17,
                  fontWeight: FontWeight.w800,
                  color: highlight ? scheme.primary : scheme.onSurface,
                  height: 1.2,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                label,
                style: TextStyle(fontSize: 11, color: scheme.outline),
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
      AsyncData(:final value) when value.isEmpty => Center(
        child: Text(
          '这里空空如也',
          style: TextStyle(
            fontSize: 13,
            color: Theme.of(context).colorScheme.outline,
          ),
        ),
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
