import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/router/routes.dart';
import '../../../core/utils/time_format.dart';
import '../../circle/model/circle.dart';
import '../../circle/widget/circle_icon.dart';
import '../../software/model/software.dart';
import '../controller/search_controller.dart';
import '../data/search_repository.dart';

/// 全局搜索页（文档 3.2：搜帖子/用户/圈子/话题/软件）。
/// 输入防抖 400ms 自动搜索；五类胶囊单选切换；结果点击跳对应详情。
class SearchPage extends ConsumerStatefulWidget {
  const SearchPage({super.key});

  @override
  ConsumerState<SearchPage> createState() => _SearchPageState();
}

class _SearchPageState extends ConsumerState<SearchPage> {
  final _inputController = TextEditingController();
  Timer? _debounce;

  @override
  void dispose() {
    _debounce?.cancel();
    _inputController.dispose();
    super.dispose();
  }

  void _onChanged(String text) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 400), () {
      if (mounted) {
        ref.read(searchControllerProvider.notifier).search(text);
      }
    });
  }

  void _onSubmitted(String text) {
    _debounce?.cancel();
    ref.read(searchControllerProvider.notifier).search(text);
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(searchControllerProvider);
    final controller = ref.read(searchControllerProvider.notifier);

    return Scaffold(
      backgroundColor: const Color(0xFFF6F7F9),
      appBar: AppBar(
        backgroundColor: Colors.white,
        titleSpacing: 0,
        title: Padding(
          padding: const EdgeInsets.only(right: 14),
          child: _SearchField(
            controller: _inputController,
            onChanged: _onChanged,
            onSubmitted: _onSubmitted,
          ),
        ),
      ),
      body: Column(
        children: [
          // 五类切换胶囊
          Container(
            color: Colors.white,
            padding: const EdgeInsets.fromLTRB(14, 4, 14, 10),
            child: Row(
              children: [
                for (final type in SearchType.values) ...[
                  _TypeChip(
                    type: type,
                    active: controller.currentType == type,
                    onTap: () => controller.changeType(type),
                  ),
                  if (type != SearchType.values.last) const SizedBox(width: 8),
                ],
              ],
            ),
          ),
          Expanded(
            child: switch (state) {
              SearchIdle() => const _HintView(
                icon: Icons.search_rounded,
                text: '搜帖子、用户、圈子、话题、软件',
              ),
              SearchLoading() => const Center(
                child: CircularProgressIndicator(),
              ),
              SearchError(:final message) => _ErrorView(
                message: message,
                onRetry: controller.retry,
              ),
              SearchData() && final data when data.isEmpty => const _HintView(
                icon: Icons.search_off_rounded,
                text: '没有找到相关内容，换个关键词试试',
              ),
              SearchData() && final data => _ResultList(data: data),
            },
          ),
        ],
      ),
    );
  }
}

/// 圆角搜索输入框（自动聚焦）
class _SearchField extends StatelessWidget {
  const _SearchField({
    required this.controller,
    required this.onChanged,
    required this.onSubmitted,
  });

  final TextEditingController controller;
  final ValueChanged<String> onChanged;
  final ValueChanged<String> onSubmitted;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SizedBox(
      height: 38,
      child: TextField(
        controller: controller,
        autofocus: true,
        textInputAction: TextInputAction.search,
        onChanged: onChanged,
        onSubmitted: onSubmitted,
        decoration: InputDecoration(
          hintText: '输入关键词搜索',
          hintStyle: TextStyle(fontSize: 14, color: scheme.outline),
          prefixIcon: Icon(Icons.search, size: 20, color: scheme.outline),
          filled: true,
          fillColor: const Color(0xFFF0F1F5),
          isDense: true,
          contentPadding: EdgeInsets.zero,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(999),
            borderSide: BorderSide.none,
          ),
        ),
        style: const TextStyle(fontSize: 14),
      ),
    );
  }
}

class _TypeChip extends StatelessWidget {
  const _TypeChip({
    required this.type,
    required this.active,
    required this.onTap,
  });

  final SearchType type;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return GestureDetector(
      onTap: active ? null : onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 6),
        decoration: BoxDecoration(
          gradient: active
              ? const LinearGradient(
                  colors: [Color(0xFFF43F5E), Color(0xFFFF7849)],
                )
              : null,
          color: active ? null : const Color(0xFFF0F1F5),
          borderRadius: BorderRadius.circular(999),
        ),
        child: Text(
          type.label,
          style: TextStyle(
            fontSize: 13,
            fontWeight: active ? FontWeight.w700 : FontWeight.w500,
            color: active ? Colors.white : scheme.onSurfaceVariant,
          ),
        ),
      ),
    );
  }
}

/// 结果列表：按类型渲染 + 上拉分页
class _ResultList extends ConsumerWidget {
  const _ResultList({required this.data});

  final SearchData data;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final count = data.result.countOf(data.type);

    return NotificationListener<ScrollNotification>(
      onNotification: (notification) {
        if (notification.metrics.extentAfter < 400) {
          ref.read(searchControllerProvider.notifier).loadMore();
        }
        return false;
      },
      child: ListView.separated(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 24),
        itemCount: count + 1,
        separatorBuilder: (context, index) => const SizedBox(height: 8),
        itemBuilder: (context, index) {
          if (index == count) return _Footer(data: data);
          return switch (data.type) {
            SearchType.post => _PostTile(item: data.result.posts[index]),
            SearchType.user => _UserTile(item: data.result.users[index]),
            SearchType.circle => _CircleTile(item: data.result.circles[index]),
            SearchType.topic => _TopicTile(item: data.result.topics[index]),
            SearchType.software => _SoftwareTile(
              item: data.result.software[index],
            ),
          };
        },
      ),
    );
  }
}

class _Footer extends ConsumerWidget {
  const _Footer({required this.data});

  final SearchData data;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final Widget child;
    if (data.loadingMore) {
      child = const SizedBox(
        width: 18,
        height: 18,
        child: CircularProgressIndicator(strokeWidth: 2),
      );
    } else if (data.loadMoreError != null) {
      child = TextButton(
        onPressed: () => ref.read(searchControllerProvider.notifier).loadMore(),
        child: Text('${data.loadMoreError}，点击重试'),
      );
    } else if (!data.hasMore) {
      child = Text(
        '— 到底啦 —',
        style: TextStyle(fontSize: 12, color: scheme.outline),
      );
    } else {
      child = const SizedBox.shrink();
    }
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 14),
      child: Center(child: child),
    );
  }
}

/// 白卡容器（各类型结果条目共用）
class _TileCard extends StatelessWidget {
  const _TileCard({required this.child, this.onTap});

  final Widget child;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Padding(padding: const EdgeInsets.all(12), child: child),
      ),
    );
  }
}

class _PostTile extends StatelessWidget {
  const _PostTile({required this.item});

  final SearchPostItem item;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return _TileCard(
      onTap: () => context.push(Routes.postDetailPath(item.id)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            item.title.isNotEmpty ? item.title : item.content,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w700),
          ),
          if (item.title.isNotEmpty && item.content.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              item.content,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 12.5,
                height: 1.5,
                color: scheme.onSurfaceVariant,
              ),
            ),
          ],
          const SizedBox(height: 8),
          Text(
            '${item.authorNickname} · ${formatCount(item.likeCount)} 赞 · '
            '${formatCount(item.commentCount)} 评论',
            style: TextStyle(fontSize: 11, color: scheme.outline),
          ),
        ],
      ),
    );
  }
}

class _UserTile extends StatelessWidget {
  const _UserTile({required this.item});

  final SearchUserItem item;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return _TileCard(
      onTap: () => context.push(Routes.userProfilePath(item.id)),
      child: Row(
        children: [
          CircleAvatar(
            radius: 20,
            backgroundColor: scheme.surfaceContainerHighest,
            foregroundImage: item.avatar.isEmpty
                ? null
                : CachedNetworkImageProvider(item.avatar),
            child: Text(
              item.nickname.isEmpty ? '?' : item.nickname.characters.first,
              style: TextStyle(fontSize: 14, color: scheme.primary),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        item.nickname,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 14.5,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 5,
                        vertical: 1.5,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFF2A2F3A),
                        borderRadius: BorderRadius.circular(5),
                      ),
                      child: Text(
                        'Lv.${item.level}',
                        style: const TextStyle(
                          fontSize: 9,
                          color: Color(0xFFFFD98A),
                          fontWeight: FontWeight.w800,
                          height: 1.3,
                        ),
                      ),
                    ),
                  ],
                ),
                if (item.displayNo.isNotEmpty) ...[
                  const SizedBox(height: 3),
                  Text(
                    'ID ${item.displayNo}',
                    style: TextStyle(fontSize: 11, color: scheme.outline),
                  ),
                ],
              ],
            ),
          ),
          Icon(Icons.chevron_right, size: 20, color: scheme.outline),
        ],
      ),
    );
  }
}

class _CircleTile extends StatelessWidget {
  const _CircleTile({required this.item});

  final Circle item;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return _TileCard(
      onTap: () => context.push(Routes.circleDetailPath(item.id)),
      child: Row(
        children: [
          CircleIconAvatar(circle: item, size: 44),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 14.5,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  '${formatCount(item.memberCount)} 成员 · '
                  '${formatCount(item.postCount)} 帖子',
                  style: TextStyle(fontSize: 11.5, color: scheme.outline),
                ),
              ],
            ),
          ),
          Icon(Icons.chevron_right, size: 20, color: scheme.outline),
        ],
      ),
    );
  }
}

class _TopicTile extends StatelessWidget {
  const _TopicTile({required this.item});

  final SearchTopicItem item;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return _TileCard(
      onTap: () => context.push(Routes.topicPostsPath(item.id)),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: scheme.primary.withValues(alpha: .08),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Center(
              child: Text(
                '#',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                  color: scheme.primary,
                ),
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 14.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  '${formatCount(item.postCount)} 篇讨论',
                  style: TextStyle(fontSize: 11.5, color: scheme.outline),
                ),
              ],
            ),
          ),
          Icon(Icons.chevron_right, size: 20, color: scheme.outline),
        ],
      ),
    );
  }
}

class _SoftwareTile extends StatelessWidget {
  const _SoftwareTile({required this.item});

  final SoftwareItem item;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return _TileCard(
      onTap: () => context.push(Routes.softwareDetailPath(item.id)),
      child: Row(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(11),
            child: SizedBox(
              width: 44,
              height: 44,
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
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 14.5,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  [
                    if (item.version.isNotEmpty) 'v${item.version}',
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
    );
  }
}

class _HintView extends StatelessWidget {
  const _HintView({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 52, color: scheme.outlineVariant),
          const SizedBox(height: 10),
          Text(
            text,
            style: TextStyle(fontSize: 13, color: scheme.outline),
          ),
        ],
      ),
    );
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
          Icon(Icons.wifi_off_outlined, size: 56, color: scheme.outline),
          const SizedBox(height: 12),
          Text(message, style: TextStyle(color: scheme.onSurfaceVariant)),
          const SizedBox(height: 16),
          OutlinedButton(onPressed: onRetry, child: const Text('重新加载')),
        ],
      ),
    );
  }
}
