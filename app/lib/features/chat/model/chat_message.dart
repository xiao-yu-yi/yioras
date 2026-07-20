/// 消息发送状态（仅自己发出的消息有意义）
enum ChatSendStatus { sending, sent, failed }

/// 聊天消息（文本；图片/表情/分享卡片随 M2 后续扩展 msg_type）
class ChatMessage {
  const ChatMessage({
    required this.localId,
    this.msgId = 0,
    required this.conversationId,
    required this.text,
    required this.mine,
    required this.createdAt,
    this.status = ChatSendStatus.sent,
    this.seq = 0,
  });

  /// 客户端生成的本地 ID（乐观插入与 ack 配对；服务端消息用 msgId 字符串化）
  final String localId;

  /// 服务端消息 ID（未入库前为 0）
  final int msgId;
  final int conversationId;
  final String text;

  /// 是否自己发送
  final bool mine;
  final DateTime createdAt;
  final ChatSendStatus status;

  /// 会话内序号（排序依据，本地未确认消息为 0 排在最后）
  final int seq;

  ChatMessage copyWith({int? msgId, ChatSendStatus? status, int? seq}) =>
      ChatMessage(
        localId: localId,
        msgId: msgId ?? this.msgId,
        conversationId: conversationId,
        text: text,
        mine: mine,
        createdAt: createdAt,
        status: status ?? this.status,
        seq: seq ?? this.seq,
      );
}
