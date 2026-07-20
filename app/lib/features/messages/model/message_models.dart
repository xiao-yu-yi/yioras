/// 私信会话摘要（消息主页列表项，对齐 conversation/conversation_member 表）
class ConversationSummary {
  const ConversationSummary({
    required this.id,
    required this.peerName,
    this.peerAvatar = '',
    this.lastPreview = '',
    this.lastMsgAt,
    this.unread = 0,
    this.isBot = false,
  });

  final int id;
  final String peerName;
  final String peerAvatar;
  final String lastPreview;
  final DateTime? lastMsgAt;
  final int unread;

  /// 官方 AI 管家会话（置顶 + 官方机器人标签，文档 3.7）
  final bool isBot;

  factory ConversationSummary.fromJson(Map<String, dynamic> json) =>
      ConversationSummary(
        id: (json['id'] as num).toInt(),
        peerName: json['peerName'] as String? ?? '',
        peerAvatar: json['peerAvatar'] as String? ?? '',
        lastPreview: json['lastPreview'] as String? ?? '',
        lastMsgAt: DateTime.tryParse(json['lastMsgAt'] as String? ?? ''),
        unread: (json['unread'] as num?)?.toInt() ?? 0,
        isBot: json['isBot'] as bool? ?? false,
      );
}

/// 通知类型（对齐 notification.type：1赞与收藏 2评论和@ 3系统通知）
enum NotificationType {
  likeFav(1, '赞与收藏'),
  commentAt(2, '评论和@'),
  system(3, '系统通知');

  const NotificationType(this.value, this.label);

  final int value;
  final String label;

  static NotificationType fromValue(int value) =>
      values.firstWhere((t) => t.value == value, orElse: () => system);
}

/// 通知项
class NotificationItem {
  const NotificationItem({
    required this.id,
    required this.type,
    required this.content,
    required this.createdAt,
    this.actorName = '',
    this.actorAvatar = '',
    this.isRead = false,
  });

  final int id;
  final NotificationType type;

  /// 触发者昵称（系统通知为空）
  final String actorName;
  final String actorAvatar;
  final String content;
  final DateTime createdAt;
  final bool isRead;

  factory NotificationItem.fromJson(Map<String, dynamic> json) =>
      NotificationItem(
        id: (json['id'] as num).toInt(),
        type: NotificationType.fromValue((json['type'] as num?)?.toInt() ?? 3),
        actorName: json['actorName'] as String? ?? '',
        actorAvatar: json['actorAvatar'] as String? ?? '',
        content: json['content'] as String? ?? '',
        createdAt:
            DateTime.tryParse(json['createdAt'] as String? ?? '') ??
            DateTime.now(),
        isRead: json['isRead'] as bool? ?? false,
      );
}

/// 消息主页数据：三个聚合入口未读数 + 会话列表
class MessagesOverview {
  const MessagesOverview({
    required this.unreadByType,
    required this.conversations,
  });

  /// key: NotificationType，value: 未读数
  final Map<NotificationType, int> unreadByType;
  final List<ConversationSummary> conversations;

  /// 会话未读合计（底部 Tab 角标用，M2 后续接入）
  int get conversationUnread =>
      conversations.fold(0, (sum, c) => sum + c.unread);
}
