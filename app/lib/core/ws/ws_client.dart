import 'dart:async';

import 'package:web_socket_channel/web_socket_channel.dart';

import '../config/app_config.dart';
import '../storage/token_storage.dart';
import 'ws_protocol.dart';

/// IM 长连接客户端抽象：聊天/角标等业务只依赖本接口。
abstract interface class YioraWsClient {
  /// 下行帧流（广播流，可多订阅）
  Stream<WsFrame> get frames;

  /// 连接状态流
  Stream<WsStatus> get statusStream;

  WsStatus get status;

  /// 建立连接（幂等；断线后自动重连由实现负责）
  Future<void> connect();

  /// 主动断开（登出时调用，不再自动重连）
  Future<void> disconnect();

  /// 发送一帧；未连接时抛 [StateError]
  void send(WsFrame frame);
}

/// 真实实现：`WSS /ws?token=` + 心跳保活 + 指数退避重连（文档 3.7 技术要求）。
/// 尚未与真实网关联调，协议细节以服务端实现为准微调。
class WsClientImpl implements YioraWsClient {
  WsClientImpl({
    required this._storage,
    WebSocketChannel Function(Uri uri)? channelFactory,
  }) : _channelFactory = channelFactory ?? WebSocketChannel.connect;

  final TokenStorage _storage;
  final WebSocketChannel Function(Uri uri) _channelFactory;

  final _frameController = StreamController<WsFrame>.broadcast();
  final _statusController = StreamController<WsStatus>.broadcast();

  WebSocketChannel? _channel;
  StreamSubscription<dynamic>? _channelSub;
  Timer? _heartbeatTimer;
  Timer? _pongTimeoutTimer;
  Timer? _reconnectTimer;
  int _reconnectAttempt = 0;
  bool _manuallyClosed = false;
  WsStatus _status = WsStatus.disconnected;

  static const _heartbeatInterval = Duration(seconds: 30);
  static const _pongTimeout = Duration(seconds: 10);

  @override
  Stream<WsFrame> get frames => _frameController.stream;

  @override
  Stream<WsStatus> get statusStream => _statusController.stream;

  @override
  WsStatus get status => _status;

  void _setStatus(WsStatus value) {
    if (_status == value) return;
    _status = value;
    _statusController.add(value);
  }

  @override
  Future<void> connect() async {
    if (_status != WsStatus.disconnected) return;
    _manuallyClosed = false;
    await _open();
  }

  Future<void> _open() async {
    final tokens = await _storage.read();
    if (tokens == null) return; // 未登录不建连

    _setStatus(WsStatus.connecting);
    try {
      final wsBase = AppConfig.apiBaseUrl
          .replaceFirst('https://', 'wss://')
          .replaceFirst('http://', 'ws://');
      final channel = _channelFactory(
        Uri.parse(
          '$wsBase/ws?token=${Uri.encodeComponent(tokens.accessToken)}',
        ),
      );
      await channel.ready;
      _channel = channel;
      _reconnectAttempt = 0;
      _setStatus(WsStatus.connected);

      _channelSub = channel.stream.listen(
        _onData,
        onError: (Object _) => _onConnectionLost(),
        onDone: _onConnectionLost,
        cancelOnError: true,
      );
      _startHeartbeat();
    } catch (_) {
      _onConnectionLost();
    }
  }

  void _onData(dynamic raw) {
    final frame = WsFrame.decode(raw);
    if (frame == null) return;
    if (frame.type == WsFrameType.pong) {
      _pongTimeoutTimer?.cancel();
      return;
    }
    _frameController.add(frame);
  }

  void _startHeartbeat() {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = Timer.periodic(_heartbeatInterval, (_) {
      if (_status != WsStatus.connected) return;
      _channel?.sink.add(const WsFrame(type: WsFrameType.ping).encode());
      // 超时未收到 pong 判定假死，主动断开触发重连
      _pongTimeoutTimer?.cancel();
      _pongTimeoutTimer = Timer(_pongTimeout, _onConnectionLost);
    });
  }

  void _onConnectionLost() {
    _cleanupChannel();
    _setStatus(WsStatus.disconnected);
    if (_manuallyClosed) return;
    // 指数退避重连
    _reconnectTimer?.cancel();
    _reconnectTimer = Timer(reconnectBackoff(_reconnectAttempt), () {
      _reconnectAttempt++;
      _open();
    });
  }

  void _cleanupChannel() {
    _heartbeatTimer?.cancel();
    _pongTimeoutTimer?.cancel();
    _channelSub?.cancel();
    _channelSub = null;
    _channel?.sink.close();
    _channel = null;
  }

  @override
  Future<void> disconnect() async {
    _manuallyClosed = true;
    _reconnectTimer?.cancel();
    _cleanupChannel();
    _setStatus(WsStatus.disconnected);
  }

  @override
  void send(WsFrame frame) {
    final channel = _channel;
    if (_status != WsStatus.connected || channel == null) {
      throw StateError('WS 未连接');
    }
    channel.sink.add(frame.encode());
  }
}
