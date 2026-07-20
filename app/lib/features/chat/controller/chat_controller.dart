import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/ws/ws_protocol.dart';
import '../../../core/ws/ws_providers.dart';
import '../../messages/model/message_models.dart';
import '../data/chat_repository.dart';
import '../model/chat_message.dart';

/// 聊天页状态：会话信息 + 消息列表（时间升序，新消息在尾部）。
class ChatState {
  const ChatState({required this.peer, required this.messages});

  final ConversationSummary peer;
  final List<ChatMessage> messages;

  ChatState copyWith({List<ChatMessage>? messages}) =>
      ChatState(peer: peer, messages: messages ?? this.messages);
}

/// 聊天控制器（family：conversationId）。
/// 发送走乐观插入：sending → ack 置 sent；超时/未连接置 failed 可重发。
class ChatController extends AsyncNotifier<ChatState> {
  ChatController(this.conversationId);

  final int conversationId;

  /// ack 等待超时：超过后标记发送失败
  static const ackTimeout = Duration(seconds: 10);

  ChatRepository get _repo => ref.read(chatRepositoryProvider);

  final Map<String, Timer> _ackTimers = {};
  int _localSeq = 0;

  @override
  Future<ChatState> build() async {
    // 订阅下行帧（先订阅再拉历史，避免间隙丢消息；Mock 场景足够）
    final sub = ref.watch(wsClientProvider).frames.listen(_onFrame);
    ref.onDispose(() {
      sub.cancel();
      for (final timer in _ackTimers.values) {
        timer.cancel();
      }
      _ackTimers.clear();
    });

    final peer = await _repo.fetchConversation(conversationId);
    final history = await _repo.fetchHistory(conversationId);
    return ChatState(peer: peer, messages: history);
  }

  Future<void> retryFirstLoad() async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(build);
  }

  void _onFrame(WsFrame frame) {
    final current = state.value;
    if (current == null) return;
    if ((frame.data['conversationId'] as num?)?.toInt() != conversationId) {
      return;
    }

    switch (frame.type) {
      case WsFrameType.msg:
        // 对方新消息追加到尾部
        final message = ChatMessage(
          localId: 'srv-${frame.data['msgId']}',
          msgId: (frame.data['msgId'] as num?)?.toInt() ?? 0,
          conversationId: conversationId,
          text: frame.data['text'] as String? ?? '',
          mine: false,
          createdAt:
              DateTime.tryParse(frame.data['createdAt'] as String? ?? '') ??
              DateTime.now(),
          seq: (frame.data['seq'] as num?)?.toInt() ?? 0,
        );
        state = AsyncData(
          current.copyWith(messages: [...current.messages, message]),
        );
        // 正在聊天页，收到即视为已读，回冲全局角标
        ref.read(conversationBadgeProvider.notifier).consume(1);
      case WsFrameType.ack:
        final localId = frame.data['localId'] as String? ?? '';
        _ackTimers.remove(localId)?.cancel();
        _updateMessage(
          localId,
          (m) => m.copyWith(
            status: ChatSendStatus.sent,
            msgId: (frame.data['msgId'] as num?)?.toInt() ?? m.msgId,
            seq: (frame.data['seq'] as num?)?.toInt() ?? m.seq,
          ),
        );
      default:
        break;
    }
  }

  void _updateMessage(String localId, ChatMessage Function(ChatMessage) fn) {
    final current = state.value;
    if (current == null) return;
    state = AsyncData(
      current.copyWith(
        messages: [
          for (final message in current.messages)
            if (message.localId == localId) fn(message) else message,
        ],
      ),
    );
  }

  /// 发送文本消息（乐观插入）
  void send(String text) {
    final content = text.trim();
    final current = state.value;
    if (content.isEmpty || current == null) return;

    final localId =
        'loc-${DateTime.now().microsecondsSinceEpoch}-${_localSeq++}';
    final message = ChatMessage(
      localId: localId,
      conversationId: conversationId,
      text: content,
      mine: true,
      createdAt: DateTime.now(),
      status: ChatSendStatus.sending,
    );
    state = AsyncData(
      current.copyWith(messages: [...current.messages, message]),
    );
    _dispatch(localId, content);
  }

  /// 失败消息点击重发
  void resend(String localId) {
    final current = state.value;
    final message = current?.messages
        .where((m) => m.localId == localId)
        .firstOrNull;
    if (message == null || message.status != ChatSendStatus.failed) return;
    _updateMessage(localId, (m) => m.copyWith(status: ChatSendStatus.sending));
    _dispatch(localId, message.text);
  }

  void _dispatch(String localId, String text) {
    try {
      ref
          .read(wsClientProvider)
          .send(
            WsFrame(
              type: WsFrameType.msg,
              data: {
                'localId': localId,
                'conversationId': conversationId,
                'text': text,
              },
            ),
          );
      // 超时未 ack 判发送失败
      _ackTimers[localId]?.cancel();
      _ackTimers[localId] = Timer(ackTimeout, () {
        _ackTimers.remove(localId);
        _updateMessage(
          localId,
          (m) => m.status == ChatSendStatus.sending
              ? m.copyWith(status: ChatSendStatus.failed)
              : m,
        );
      });
    } on StateError {
      // WS 未连接：直接标记失败
      _updateMessage(localId, (m) => m.copyWith(status: ChatSendStatus.failed));
    }
  }
}

final chatControllerProvider = AsyncNotifierProvider.family
    .autoDispose<ChatController, ChatState, int>(ChatController.new);
