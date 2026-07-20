import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/auth/controller/auth_controller.dart';
import '../config/app_config.dart';
import '../storage/token_storage.dart';
import 'ws_client.dart';
import 'ws_client_mock.dart';
import 'ws_protocol.dart';

/// 全局 WS 客户端：登录后自动建连，登出/登录失效自动断开。
final wsClientProvider = Provider<YioraWsClient>((ref) {
  final client = AppConfig.useMock
      ? WsClientMock()
      : WsClientImpl(storage: ref.watch(tokenStorageProvider));

  // 跟随登录态开合连接
  ref.listen(authControllerProvider, (previous, next) {
    switch (next) {
      case AuthAuthenticated():
        client.connect();
      case AuthUnauthenticated():
        client.disconnect();
      case AuthUnknown():
        break;
    }
  }, fireImmediately: true);

  ref.onDispose(client.disconnect);
  return client;
});

/// 会话未读总数（底部消息 Tab 角标）。
/// 快照来自消息主页接口，增量来自 WS badge 帧与新消息帧。
class ConversationBadgeController extends Notifier<int> {
  @override
  int build() {
    final client = ref.watch(wsClientProvider);
    final sub = client.frames.listen((frame) {
      switch (frame.type) {
        case WsFrameType.badge:
          state = (frame.data['conversationUnread'] as num?)?.toInt() ?? state;
        case WsFrameType.msg:
          // 简化：收到任意下行消息角标 +1；进入聊天页/消息页由快照校正
          state = state + 1;
        default:
          break;
      }
    });
    ref.onDispose(sub.cancel);
    return 0;
  }

  /// 消息主页拉到快照后校正
  void sync(int unread) => state = unread;

  /// 进入会话把该会话未读记为已读（骨架期粗粒度递减）
  void consume(int count) => state = (state - count).clamp(0, 1 << 31);
}

final conversationBadgeProvider =
    NotifierProvider<ConversationBadgeController, int>(
      ConversationBadgeController.new,
    );
