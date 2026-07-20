import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yiora/core/ws/ws_client_mock.dart';
import 'package:yiora/core/ws/ws_providers.dart';
import 'package:yiora/features/chat/controller/chat_controller.dart';
import 'package:yiora/features/chat/data/chat_repository.dart';
import 'package:yiora/features/chat/model/chat_message.dart';
import 'package:yiora/features/messages/model/message_models.dart';

class _FakeChatRepository implements ChatRepository {
  @override
  Future<ConversationSummary> fetchConversation(int conversationId) async =>
      ConversationSummary(
        id: conversationId,
        peerName: conversationId == WsClientMock.botConversationId
            ? 'Yo酱'
            : '测试用户',
        isBot: conversationId == WsClientMock.botConversationId,
      );

  @override
  Future<List<ChatMessage>> fetchHistory(int conversationId) async => [
    ChatMessage(
      localId: 'srv-1',
      msgId: 1,
      conversationId: conversationId,
      text: '历史消息',
      mine: false,
      createdAt: DateTime(2026, 7, 20, 10),
      seq: 1,
    ),
  ];
}

ProviderContainer _container(WsClientMock ws) {
  final container = ProviderContainer(
    overrides: [
      wsClientProvider.overrideWithValue(ws),
      chatRepositoryProvider.overrideWithValue(_FakeChatRepository()),
    ],
  );
  addTearDown(container.dispose);
  return container;
}

void main() {
  test('首屏加载会话信息与历史消息', () async {
    final ws = WsClientMock();
    await ws.connect();
    final container = _container(ws);

    final state = await container.read(chatControllerProvider(2).future);

    expect(state.peer.peerName, '测试用户');
    expect(state.messages.single.text, '历史消息');
  });

  test('发送：乐观插入 sending，收到 ack 变 sent', () async {
    final ws = WsClientMock();
    await ws.connect();
    final container = _container(ws);
    // 保持订阅防止 autoDispose 提前销毁
    final sub = container.listen(chatControllerProvider(2), (_, _) {});
    addTearDown(sub.close);
    await container.read(chatControllerProvider(2).future);

    container.read(chatControllerProvider(2).notifier).send('新消息');

    var state = container.read(chatControllerProvider(2)).value!;
    expect(state.messages.last.text, '新消息');
    expect(state.messages.last.status, ChatSendStatus.sending);

    // WsClientMock 600ms 后回 ack
    await Future<void>.delayed(const Duration(milliseconds: 900));
    state = container.read(chatControllerProvider(2)).value!;
    expect(state.messages.last.status, ChatSendStatus.sent);
    expect(state.messages.last.msgId, greaterThan(0));
  });

  test('WS 未连接发送直接标记失败，重连后重发成功', () async {
    final ws = WsClientMock(); // 不 connect
    final container = _container(ws);
    final sub = container.listen(chatControllerProvider(2), (_, _) {});
    addTearDown(sub.close);
    await container.read(chatControllerProvider(2).future);

    container.read(chatControllerProvider(2).notifier).send('会失败');
    var state = container.read(chatControllerProvider(2)).value!;
    final failed = state.messages.last;
    expect(failed.status, ChatSendStatus.failed);

    // 连上后重发
    await ws.connect();
    container.read(chatControllerProvider(2).notifier).resend(failed.localId);
    state = container.read(chatControllerProvider(2)).value!;
    expect(state.messages.last.status, ChatSendStatus.sending);

    await Future<void>.delayed(const Duration(milliseconds: 900));
    state = container.read(chatControllerProvider(2)).value!;
    expect(state.messages.last.status, ChatSendStatus.sent);
  });

  test('AI 管家会话收到自动回复', () async {
    final ws = WsClientMock();
    await ws.connect();
    final container = _container(ws);
    final sub = container.listen(
      chatControllerProvider(WsClientMock.botConversationId),
      (_, _) {},
    );
    addTearDown(sub.close);
    await container.read(
      chatControllerProvider(WsClientMock.botConversationId).future,
    );

    container
        .read(chatControllerProvider(WsClientMock.botConversationId).notifier)
        .send('你好');

    // 机器人 1.5s 后回复
    await Future<void>.delayed(const Duration(milliseconds: 2000));
    final state = container
        .read(chatControllerProvider(WsClientMock.botConversationId))
        .value!;
    final lastMessage = state.messages.last;
    expect(lastMessage.mine, isFalse, reason: '最后一条应为机器人回复');
    expect(lastMessage.text, isNotEmpty);
  });
}
