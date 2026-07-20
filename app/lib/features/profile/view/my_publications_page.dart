import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/router/routes.dart';
import '../../../core/utils/time_format.dart';
import '../../software/data/software_repository.dart';
import '../../software/model/software.dart';
import '../data/profile_repository.dart';
import '../model/profile_models.dart';

/// 我发布的软件数据源（GET /software/mine，含审核状态）
final mySoftwareProvider = FutureProvider.autoDispose<List<SoftwareItem>>((
  ref,
) async {
  final page = await ref.watch(softwareRepositoryProvider).fetchMine(size: 50);
  return page.list;
});

/// 我的发布页（文档 3.5.2 审核流：作者可在「我的发布」查看审核状态）：
/// 动态 / 软件双 Tab，待审核/驳回/下架均带状态角标。
class MyPublicationsPage extends StatelessWidget {
  const MyPublicationsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        backgroundColor: const Color(0xFFF6F7F9),
        appBar: AppBar(
          title: const Text(
            '我的发布',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
          ),
          bottom: TabBar(
            labelStyle: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w700,
            ),
            unselectedLabelStyle: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w500,
            ),
            labelColor: scheme.onSurface,
            unselectedLabelColor: scheme.outline,
            indicatorColor: scheme.primary,
            indicatorSize: TabBarIndicatorSize.label,
            dividerColor: Colors.transparent,
            tabs: const [Tab(text: '动态'), Tab(text: '软件')],
          ),
        ),
        body: const TabBarView(children: [_MyPostsTab(), _MySoftwareTab()]),
      ),
    );
  }
}

class _MyPostsTab extends ConsumerWidget {
  const _MyPostsTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final posts = ref.watch(myPostsProvider);

    return switch (posts) {
      AsyncData(:final value) when value.isEmpty => const Center(
        child: Text('还没有发布过动态'),
      ),
      AsyncData(:final value) => RefreshIndicator(
        onRefresh: () => ref.refresh(myPostsProvider.future),
        child: ListView.separated(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
          itemCount: value.length,
          separatorBuilder: (context, index) => const SizedBox(height: 8),
          itemBuilder: (context, index) => _MyPostRow(item: value[index]),
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

class _MyPostRow extends StatelessWidget {
  const _MyPostRow({required this.item});

  final MyPost item;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final post = item.post;

    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: () => context.push(Routes.postDetailPath(post.id)),
        borderRadius: BorderRadius.circular(14),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      post.title.isNotEmpty ? post.title : post.content,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 14.5,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  _StatusBadge(
                    label: item.auditStatus.label,
                    color: switch (item.auditStatus) {
                      PostAuditStatus.pending => const Color(0xFFF59E0B),
                      PostAuditStatus.rejected => scheme.error,
                      _ => scheme.outline,
                    },
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                '${formatRelativeTime(post.createdAt)} · '
                '${formatCount(post.viewCount)} 浏览 · '
                '${formatCount(post.likeCount)} 赞',
                style: TextStyle(fontSize: 11.5, color: scheme.outline),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MySoftwareTab extends ConsumerWidget {
  const _MySoftwareTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final software = ref.watch(mySoftwareProvider);

    return switch (software) {
      AsyncData(:final value) when value.isEmpty => const Center(
        child: Text('还没有发布过软件'),
      ),
      AsyncData(:final value) => RefreshIndicator(
        onRefresh: () => ref.refresh(mySoftwareProvider.future),
        child: ListView.separated(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
          itemCount: value.length,
          separatorBuilder: (context, index) => const SizedBox(height: 8),
          itemBuilder: (context, index) => _MySoftwareRow(item: value[index]),
        ),
      ),
      AsyncError() => Center(
        child: TextButton(
          onPressed: () => ref.invalidate(mySoftwareProvider),
          child: const Text('加载失败，点击重试'),
        ),
      ),
      _ => const Center(child: CircularProgressIndicator()),
    };
  }
}

/// 软件审核状态角标语义（对齐 server software.status）
({String label, bool blocking}) _softwareStatus(int status) => switch (status) {
  0 => (label: '待审核', blocking: false),
  2 => (label: '已驳回', blocking: true),
  3 => (label: '已下架', blocking: true),
  _ => (label: '', blocking: false),
};

class _MySoftwareRow extends StatelessWidget {
  const _MySoftwareRow({required this.item});

  final SoftwareItem item;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final status = _softwareStatus(item.status);

    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: () => context.push(Routes.softwareDetailPath(item.id)),
        borderRadius: BorderRadius.circular(14),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(11),
                child: SizedBox(
                  width: 46,
                  height: 46,
                  child: item.logo.isEmpty
                      ? Container(
                          color: scheme.surfaceContainerHighest,
                          child: Icon(Icons.android, color: scheme.outline),
                        )
                      : CachedNetworkImage(
                          imageUrl: item.logo,
                          fit: BoxFit.cover,
                          errorWidget: (context, url, error) =>
                              Container(color: scheme.surfaceContainerHighest),
                        ),
                ),
              ),
              const SizedBox(width: 11),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            item.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 14.5,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        _StatusBadge(
                          label: status.label,
                          color: switch (item.status) {
                            0 => const Color(0xFFF59E0B),
                            2 => scheme.error,
                            3 => scheme.outline,
                            _ => scheme.outline,
                          },
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      [
                        if (item.version.isNotEmpty) 'v${item.version}',
                        formatRelativeTime(item.createdAt),
                        if (item.status == 1)
                          '${formatCount(item.downloadCount)} 次下载',
                      ].join(' · '),
                      style: TextStyle(fontSize: 11.5, color: scheme.outline),
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right, size: 20, color: scheme.outline),
            ],
          ),
        ),
      ),
    );
  }
}

class _StatusBadge extends StatelessWidget {
  const _StatusBadge({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    if (label.isEmpty) return const SizedBox.shrink();
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: .1),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 11,
          color: color,
          fontWeight: FontWeight.w600,
          height: 1.3,
        ),
      ),
    );
  }
}
