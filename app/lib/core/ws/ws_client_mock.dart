import 'dart:async';
import 'dart:math';

import 'ws_client.dart';
import 'ws_protocol.dart';

/// Mock 长连接：本地模拟服务端行为，跑通聊天与角标链路。
/// - 上行 msg：800ms 后回 ack；若发给 AI 管家会话再回一条机器人消息
/// - 周期性行为不模拟（无随机插入消息，保证测试可预期）
class WsClientMock implements YioraWsClient {
  final _frameController = StreamController<WsFrame>.broadcast();
  final _statusController = StreamController<WsStatus>.broadcast();
  final _random = Random();

  WsStatus _status = WsStatus.disconnected;
  int _seq = 1000;

  /// AI 管家会话 ID（与 MessagesRepositoryMock 的会话数据对齐）
  static const int botConversationId = 1;

  static const _botReplies = [
    '收到啦～我是 Yo酱，你的专属社区管家',
    '这个问题我记下来了，你也可以在「任务中心」看看新手任务哦',
    '试试下拉刷新首页，说不定有新内容',
    '记得文明交流哦，祝你在 Yiora 玩得开心～',
  ];

  @override
  Stream<WsFrame> get frames => _frameController.stream;

  @override
  Stream<WsStatus> get statusStream => _statusController.stream;

  @override
  WsStatus get status => _status;

  void _setStatus(WsStatus value) {
    _status = value;
    _statusController.add(value);
  }

  @override
  Future<void> connect() async {
    if (_status == WsStatus.connected) return;
    _setStatus(WsStatus.connecting);
    await Future<void>.delayed(const Duration(milliseconds: 300));
    _setStatus(WsStatus.connected);
  }

  @override
  Future<void> disconnect() async => _setStatus(WsStatus.disconnected);

  @override
  void send(WsFrame frame) {
    if (_status != WsStatus.connected) throw StateError('WS 未连接');
    if (frame.type != WsFrameType.msg) return;

    final conversationId = frame.data['conversationId'] as int? ?? 0;
    final localId = frame.data['localId'] as String? ?? '';

    // 模拟服务端 ack
    Timer(const Duration(milliseconds: 600), () {
      if (_status != WsStatus.connected) return;
      _frameController.add(
        WsFrame(
          type: WsFrameType.ack,
          data: {
            'localId': localId,
            'conversationId': conversationId,
            'seq': ++_seq,
            'msgId': _seq,
          },
        ),
      );
    });

    // AI 管家自动回复
    if (conversationId == botConversationId) {
      Timer(const Duration(milliseconds: 1500), () {
        if (_status != WsStatus.connected) return;
        _frameController.add(
          WsFrame(
            type: WsFrameType.msg,
            data: {
              'msgId': ++_seq,
              'conversationId': conversationId,
              'senderId': -1,
              'text': _botReplies[_random.nextInt(_botReplies.length)],
              'seq': _seq,
              'createdAt': DateTime.now().toIso8601String(),
            },
          ),
        );
      });
    }
  }
}
