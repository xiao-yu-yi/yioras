import 'package:dio/dio.dart';

/// 统一业务/网络异常模型。
///
/// UI 层只面对 [ApiException]，不直接感知 DioException：
/// - [code] 业务错误码（网络层错误时为 -1）
/// - [message] 可直接展示给用户的文案
/// - [traceId] 服务端链路 ID，便于报障排查
class ApiException implements Exception {
  const ApiException({required this.code, required this.message, this.traceId});

  final int code;
  final String message;
  final String? traceId;

  /// 网络层错误码（区别于服务端业务码）
  static const int networkErrorCode = -1;

  /// 是否登录态失效（触发跳登录页）
  bool get isUnauthorized => code == 401;

  /// 将 Dio 异常翻译为用户可读的 [ApiException]
  factory ApiException.fromDio(DioException e) {
    // 拦截器里主动抛出的业务异常直接透传
    final inner = e.error;
    if (inner is ApiException) return inner;

    final message = switch (e.type) {
      DioExceptionType.connectionTimeout ||
      DioExceptionType.sendTimeout ||
      DioExceptionType.receiveTimeout => '网络超时，请稍后重试',
      DioExceptionType.connectionError => '网络连接失败，请检查网络设置',
      DioExceptionType.badResponse => '服务开小差了（${e.response?.statusCode}）',
      DioExceptionType.cancel => '请求已取消',
      _ => '网络异常，请稍后重试',
    };
    return ApiException(
      code: e.response?.statusCode ?? networkErrorCode,
      message: message,
    );
  }

  @override
  String toString() =>
      'ApiException(code=$code, message=$message, traceId=$traceId)';
}
