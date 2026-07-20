import 'package:flutter_test/flutter_test.dart';
import 'package:yiora/core/ws/ws_protocol.dart';

void main() {
  group('reconnectBackoff', () {
    test('指数递增并封顶 30s', () {
      expect(reconnectBackoff(0), const Duration(seconds: 1));
      expect(reconnectBackoff(1), const Duration(seconds: 2));
      expect(reconnectBackoff(2), const Duration(seconds: 4));
      expect(reconnectBackoff(3), const Duration(seconds: 8));
      expect(reconnectBackoff(4), const Duration(seconds: 16));
      expect(reconnectBackoff(5), const Duration(seconds: 30));
      expect(reconnectBackoff(20), const Duration(seconds: 30));
    });
  });

  group('WsFrame', () {
    test('编解码往返', () {
      const frame = WsFrame(
        type: WsFrameType.msg,
        data: {'conversationId': 1, 'text': '你好'},
      );
      final decoded = WsFrame.decode(frame.encode());
      expect(decoded, isNotNull);
      expect(decoded!.type, WsFrameType.msg);
      expect(decoded.data['text'], '你好');
    });

    test('未知类型回落 unknown', () {
      final decoded = WsFrame.decode('{"type":"whatever","data":{}}');
      expect(decoded!.type, WsFrameType.unknown);
    });

    test('非法负载返回 null', () {
      expect(WsFrame.decode('not-json'), isNull);
      expect(WsFrame.decode(123), isNull);
    });
  });
}
