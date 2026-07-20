import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/network/api_exception.dart';
import '../../../core/router/routes.dart';
import '../../../core/utils/time_format.dart';
import '../../../core/ws/ws_providers.dart';
import '../data/messages_repository.dart';
import '../model/message_models.dart';

/// 消息主页（文档 3.7）：三个聚合通知入口 + AI 管家置顶 + 私信会话列表 + 合规提示。
/// 聊天页随 WS 长连接接入，当前会话点击为占位。
class MessagesPage extends ConsumerWidget {
  const MessagesPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final overview = ref.watch(messagesOverviewProvider);
    // 快照到达时校正全局会话未读角标
    ref.listen(messagesOverviewProvider, (previous, next) {
      final value = next.value;
      if (value != null) {
        ref
            .read(conversationBadgeProvider.notifier)
            .sync(value.conversationUnread);
      }
    });

    return Scaffold(
      appBar: AppBar(title: const Text('消息')),
      body: switch (overview) {
        AsyncData(:final value) => _MessagesBody(overview: value),
        AsyncError(:final error) => Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                error is ApiException ? error.message : '加载失败，请稍后重试',
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 16),
              OutlinedButton(
                onPressed: () => ref.invalidate(messagesOverviewProvider),
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

class _MessagesBody extends ConsumerWidget {
  const _MessagesBody({required this.overview});

  final MessagesOverview overview;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;

    return RefreshIndicator(
      onRefresh: () => ref.refresh(messagesOverviewProvider.future),
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        // 底部留白：悬浮导航条不遮挡合规提示
        padding: const EdgeInsets.only(bottom: 96),
        children: [
          // 聚合通知入口（固定三项）
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 6),
            child: Row(
              children: [
                _EntryItem(
                  icon: Icons.thumb_up_alt_outlined,
                  color: const Color(0xFFFF7043),
                  type: NotificationType.likeFav,
                  unread: overview.unreadByType[NotificationType.likeFav] ?? 0,
                ),
                _EntryItem(
                  icon: Icons.alternate_email,
                  color: const Color(0xFF42A5F5),
                  type: NotificationType.commentAt,
                  unread:
                      overview.unreadByType[NotificationType.commentAt] ?? 0,
                ),
                _EntryItem(
                  icon: Icons.notifications_none,
                  color: const Color(0xFF66BB6A),
                  type: NotificationType.system,
                  unread: overview.unreadByType[NotificationType.system] ?? 0,
                ),
              ],
            ),
          ),
          const Divider(height: 20, indent: 16, endIndent: 16),
          if (overview.conversations.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 48),
              child: Center(
                child: Text(
                  '暂无会话',
                  style: TextStyle(color: scheme.onSurfaceVariant),
                ),
              ),
            )
          else
            for (final conversation in overview.conversations)
              _ConversationTile(conversation: conversation),
          const SizedBox(height: 20),
          // 合规提示（文档 3.7 底部固定文案）
          Center(
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.verified_user_outlined,
                  size: 13,
                  color: scheme.outline,
                ),
                const SizedBox(width: 4),
                Text(
                  '聊天内容受平台实时监管，请文明交流',
                  style: TextStyle(fontSize: 11.5, color: scheme.outline),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _EntryItem extends StatelessWidget {
  const _EntryItem({
    required this.icon,
    required this.color,
    required this.type,
    required this.unread,
  });

  final IconData icon;
  final Color color;
  final NotificationType type;
  final int unread;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: InkWell(
        onTap: () => context.push('/notifications/${type.value}'),
        borderRadius: BorderRadius.circular(10),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Column(
            children: [
              Badge(
                isLabelVisible: unread > 0,
                label: Text('$unread'),
                child: Container(
                  width: 46,
                  height: 46,
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: .12),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(icon, color: color, size: 22),
                ),
              ),
              const SizedBox(height: 6),
              Text(type.label, style: const TextStyle(fontSize: 12.5)),
            ],
          ),
        ),
      ),
    );
  }
}

class _ConversationTile extends StatelessWidget {
  const _ConversationTile({required this.conversation});

  final ConversationSummary conversation;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ListTile(
      onTap: () => context.push(Routes.chatPath(conversation.id)),
      leading: Badge(
        isLabelVisible: conversation.unread > 0,
        label: Text('${conversation.unread}'),
        child: CircleAvatar(
          radius: 22,
          backgroundColor: conversation.isBot
              ? scheme.primaryContainer
              : scheme.surfaceContainerHighest,
          foregroundImage: conversation.peerAvatar.isEmpty
              ? null
              : CachedNetworkImageProvider(conversation.peerAvatar),
          child: conversation.isBot
              ? Icon(Icons.smart_toy_outlined, color: scheme.primary)
              : Text(
                  conversation.peerName.isEmpty
                      ? '?'
                      : conversation.peerName.characters.first,
                  style: TextStyle(color: scheme.primary),
                ),
        ),
      ),
      title: Row(
        children: [
          Flexible(
            child: Text(
              conversation.peerName,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
            ),
          ),
          if (conversation.isBot) ...[
            const SizedBox(width: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
              decoration: BoxDecoration(
                color: scheme.primary.withValues(alpha: .1),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                '官方机器人',
                style: TextStyle(fontSize: 10, color: scheme.primary),
              ),
            ),
          ],
        ],
      ),
      subtitle: Text(
        conversation.lastPreview,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(fontSize: 13, color: scheme.onSurfaceVariant),
      ),
      trailing: conversation.lastMsgAt == null
          ? null
          : Text(
              formatRelativeTime(conversation.lastMsgAt!),
              style: TextStyle(fontSize: 11.5, color: scheme.outline),
            ),
    );
  }
}
