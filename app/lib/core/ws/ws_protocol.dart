import 'dart:convert';

/// WS 帧类型（与服务端约定，文档 3.7/4.3.3）。
enum WsFrameType {
  /// 心跳
  ping('ping'),
  pong('pong'),

  /// 私信消息（双向：上行发送 / 下行推送）
  msg('msg'),

  /// 服务端确认上行消息已入库（携带 localId 与最终 seq）
  ack('ack'),

  /// 未读角标推送（会话未读总数）
  badge('badge'),

  /// 未知帧（协议前向兼容）
  unknown('unknown');

  const WsFrameType(this.value);

  final String value;

  static WsFrameType fromValue(String? value) => values.firstWhere(
    (t) => t.value == value,
    orElse: () => WsFrameType.unknown,
  );
}

/// WS 帧：`{"type": "...", "data": {...}}`
class WsFrame {
  const WsFrame({required this.type, this.data = const {}});

  final WsFrameType type;
  final Map<String, dynamic> data;

  String encode() => jsonEncode({'type': type.value, 'data': data});

  static WsFrame? decode(dynamic raw) {
    if (raw is! String) return null;
    try {
      final json = jsonDecode(raw);
      if (json is! Map<String, dynamic>) return null;
      return WsFrame(
        type: WsFrameType.fromValue(json['type'] as String?),
        data: (json['data'] as Map<String, dynamic>?) ?? const {},
      );
    } on FormatException {
      return null;
    }
  }
}

/// 连接状态
enum WsStatus { disconnected, connecting, connected }

/// 重连退避策略：1s 起指数翻倍，封顶 30s。
/// 纯函数便于单测；attempt 从 0 开始计。
Duration reconnectBackoff(int attempt) {
  const maxSeconds = 30;
  final seconds = 1 << attempt.clamp(0, 5);
  return Duration(seconds: seconds > maxSeconds ? maxSeconds : seconds);
}
