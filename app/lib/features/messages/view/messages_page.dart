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

/// 消息主页（文档 3.7，视觉对齐设计图）：
/// 大标题 + 私信/群聊胶囊切换 + 互动入口卡 + 系统通知/AI 管家/私信会话卡 + 合规提示。
/// 群聊为后续能力占位；聊天页已随 WS 长连接接入。
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
      body: SafeArea(
        bottom: false,
        child: switch (overview) {
          AsyncData(:final value) => _MessagesBody(overview: value),
          AsyncError(:final error) => Column(
            children: [
              const _PageTitle(),
              Expanded(
                child: Center(
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
                        onPressed: () =>
                            ref.invalidate(messagesOverviewProvider),
                        child: const Text('重新加载'),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
          _ => const Column(
            children: [
              _PageTitle(),
              Expanded(child: Center(child: CircularProgressIndicator())),
            ],
          ),
        },
      ),
    );
  }
}

class _PageTitle extends StatelessWidget {
  const _PageTitle();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.fromLTRB(20, 16, 20, 0),
      child: Align(
        alignment: Alignment.centerLeft,
        child: Text(
          '消息',
          style: TextStyle(fontSize: 26, fontWeight: FontWeight.w800),
        ),
      ),
    );
  }
}

class _MessagesBody extends ConsumerWidget {
  const _MessagesBody({required this.overview});

  final MessagesOverview overview;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final bots = overview.conversations.where((c) => c.isBot).toList();
    final humans = overview.conversations.where((c) => !c.isBot).toList();

    return RefreshIndicator(
      onRefresh: () => ref.refresh(messagesOverviewProvider.future),
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        // 底部留白：悬浮导航条不遮挡合规提示
        padding: const EdgeInsets.only(bottom: 96),
        children: [
          const _PageTitle(),
          const SizedBox(height: 14),
          // 互动通知入口卡：赞与收藏 / 评论和@
          Container(
            margin: const EdgeInsets.symmetric(horizontal: 12),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFF1F2430).withValues(alpha: .04),
                  blurRadius: 12,
                  offset: const Offset(0, 3),
                ),
              ],
            ),
            child: Column(
              children: [
                _EntryRow(
                  icon: Icons.favorite_rounded,
                  color: const Color(0xFFF43F5E),
                  type: NotificationType.likeFav,
                  unread: overview.unreadByType[NotificationType.likeFav] ?? 0,
                ),
                Divider(
                  height: 1,
                  thickness: .6,
                  indent: 56,
                  color: scheme.outlineVariant.withValues(alpha: .4),
                ),
                _EntryRow(
                  icon: Icons.alternate_email_rounded,
                  color: const Color(0xFF3B82F6),
                  type: NotificationType.commentAt,
                  unread:
                      overview.unreadByType[NotificationType.commentAt] ?? 0,
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          // 系统通知 + AI 管家 + 私信会话
          Container(
            margin: const EdgeInsets.symmetric(horizontal: 12),
            clipBehavior: Clip.antiAlias,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFF1F2430).withValues(alpha: .04),
                  blurRadius: 12,
                  offset: const Offset(0, 3),
                ),
              ],
            ),
            child: Column(
              children: [
                _SystemNotifyRow(
                  unread: overview.unreadByType[NotificationType.system] ?? 0,
                ),
                for (final bot in bots) _BotConversationRow(conversation: bot),
                if (humans.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 44),
                    child: Center(
                      child: Text(
                        '暂无私信',
                        style: TextStyle(fontSize: 13, color: scheme.outline),
                      ),
                    ),
                  )
                else
                  for (final conversation in humans)
                    _ConversationTile(conversation: conversation),
              ],
            ),
          ),
          const SizedBox(height: 18),
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

/// 互动通知入口行：软色圆角图标 + 标签 + 未读角标 + 箭头
class _EntryRow extends StatelessWidget {
  const _EntryRow({
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
    final scheme = Theme.of(context).colorScheme;
    return InkWell(
      onTap: () => context.push('/notifications/${type.value}'),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 12, 12),
        child: Row(
          children: [
            Badge(
              isLabelVisible: unread > 0,
              label: Text('$unread'),
              child: Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: .1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, color: color, size: 18),
              ),
            ),
            const SizedBox(width: 11),
            Expanded(
              child: Text(
                type.label,
                style: const TextStyle(
                  fontSize: 14.5,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            Icon(Icons.chevron_right, size: 18, color: scheme.outline),
          ],
        ),
      ),
    );
  }
}

/// 系统通知行：深色方块图标 + 最新提示
class _SystemNotifyRow extends StatelessWidget {
  const _SystemNotifyRow({required this.unread});

  final int unread;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return InkWell(
      onTap: () =>
          context.push('/notifications/${NotificationType.system.value}'),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 12, 12),
        child: Row(
          children: [
            Badge(
              isLabelVisible: unread > 0,
              label: Text('$unread'),
              child: Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: const Color(0xFF1F2430),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(
                  Icons.campaign_rounded,
                  color: Colors.white,
                  size: 22,
                ),
              ),
            ),
            const SizedBox(width: 11),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    '系统通知',
                    style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    unread > 0 ? '$unread 条新通知' : '暂无新通知',
                    style: TextStyle(
                      fontSize: 12.5,
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            Icon(Icons.chevron_right, size: 18, color: scheme.outline),
          ],
        ),
      ),
    );
  }
}

/// AI 管家高亮行：淡紫底 + 紫色左条 + 紫名 + 官方机器人标
class _BotConversationRow extends StatelessWidget {
  const _BotConversationRow({required this.conversation});

  final ConversationSummary conversation;

  static const _purple = Color(0xFF7C4DFF);

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () => context.push(Routes.chatPath(conversation.id)),
      child: Container(
        decoration: const BoxDecoration(
          color: Color(0xFFF3EEFF),
          border: Border(left: BorderSide(color: _purple, width: 3)),
        ),
        padding: const EdgeInsets.fromLTRB(11, 12, 12, 12),
        child: Row(
          children: [
            Badge(
              isLabelVisible: conversation.unread > 0,
              label: Text('${conversation.unread}'),
              child: CircleAvatar(
                radius: 22,
                backgroundColor: _purple.withValues(alpha: .12),
                foregroundImage: conversation.peerAvatar.isEmpty
                    ? null
                    : CachedNetworkImageProvider(conversation.peerAvatar),
                child: const Icon(
                  Icons.smart_toy_outlined,
                  color: _purple,
                  size: 22,
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
                          conversation.peerName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                            color: _purple,
                          ),
                        ),
                      ),
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: _purple.withValues(alpha: .14),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: const Text(
                          '官方机器人',
                          style: TextStyle(
                            fontSize: 9.5,
                            color: _purple,
                            fontWeight: FontWeight.w700,
                            height: 1.2,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 3),
                  Text(
                    conversation.lastPreview,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 12.5,
                      color: const Color(0xFF1F2430).withValues(alpha: .55),
                    ),
                  ),
                ],
              ),
            ),
            if (conversation.lastMsgAt != null) ...[
              const SizedBox(width: 8),
              Text(
                formatRelativeTime(conversation.lastMsgAt!),
                style: TextStyle(
                  fontSize: 11,
                  color: Theme.of(context).colorScheme.outline,
                ),
              ),
            ],
          ],
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
          backgroundColor: scheme.surfaceContainerHighest,
          foregroundImage: conversation.peerAvatar.isEmpty
              ? null
              : CachedNetworkImageProvider(conversation.peerAvatar),
          child: Text(
            conversation.peerName.isEmpty
                ? '?'
                : conversation.peerName.characters.first,
            style: TextStyle(color: scheme.primary),
          ),
        ),
      ),
      title: Text(
        conversation.peerName,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
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
