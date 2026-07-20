import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_exception.dart';
import '../../../core/utils/time_format.dart';
import '../data/messages_repository.dart';
import '../model/message_models.dart';

/// 通知聚合列表页：赞与收藏 / 评论和@ / 系统通知（文档 3.7 三个固定入口）。
class NotificationsPage extends ConsumerWidget {
  const NotificationsPage({super.key, required this.type});

  final NotificationType type;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final items = ref.watch(notificationsProvider(type));
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(title: Text(type.label)),
      body: switch (items) {
        AsyncData(:final value) when value.isEmpty => Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.notifications_off_outlined,
                size: 56,
                color: scheme.outline,
              ),
              const SizedBox(height: 12),
              Text(
                '暂无${type.label}消息',
                style: TextStyle(color: scheme.onSurfaceVariant),
              ),
            ],
          ),
        ),
        AsyncData(:final value) => RefreshIndicator(
          onRefresh: () => ref.refresh(notificationsProvider(type).future),
          child: ListView.separated(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.symmetric(vertical: 8),
            itemCount: value.length,
            separatorBuilder: (context, index) =>
                const Divider(height: 1, indent: 72),
            itemBuilder: (context, index) =>
                _NotificationTile(item: value[index]),
          ),
        ),
        AsyncError(:final error) => Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                error is ApiException ? error.message : '加载失败，请稍后重试',
                style: TextStyle(color: scheme.onSurfaceVariant),
              ),
              const SizedBox(height: 16),
              OutlinedButton(
                onPressed: () => ref.invalidate(notificationsProvider(type)),
                child: const Text('重新加载'),
              ),
            ],
          ),
        ),
        _ => const Center(child: CircularProgressIndicator()),
      },
    );
  }
}

class _NotificationTile extends StatelessWidget {
  const _NotificationTile({required this.item});

  final NotificationItem item;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isSystem = item.type == NotificationType.system;

    return ListTile(
      leading: CircleAvatar(
        radius: 20,
        backgroundColor: isSystem
            ? scheme.primaryContainer
            : scheme.surfaceContainerHighest,
        foregroundImage: item.actorAvatar.isEmpty
            ? null
            : CachedNetworkImageProvider(item.actorAvatar),
        child: isSystem
            ? Icon(Icons.campaign_outlined, color: scheme.primary, size: 20)
            : Text(
                item.actorName.isEmpty ? '?' : item.actorName.characters.first,
                style: TextStyle(fontSize: 13, color: scheme.primary),
              ),
      ),
      title: Text(
        isSystem ? '系统通知' : item.actorName,
        style: TextStyle(
          fontSize: 14,
          fontWeight: item.isRead ? FontWeight.w400 : FontWeight.w600,
        ),
      ),
      subtitle: Text(
        item.content,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          fontSize: 13,
          color: item.isRead ? scheme.outline : scheme.onSurfaceVariant,
        ),
      ),
      trailing: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Text(
            formatRelativeTime(item.createdAt),
            style: TextStyle(fontSize: 11, color: scheme.outline),
          ),
          if (!item.isRead) ...[
            const SizedBox(height: 6),
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                color: scheme.error,
                shape: BoxShape.circle,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
