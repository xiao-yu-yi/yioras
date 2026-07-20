import 'api_exception.dart';

/// 统一响应包解析，对应文档 4.3.8：`{code, msg, data, traceId}`，code==0 为成功。
class ApiResponse<T> {
  const ApiResponse({
    required this.code,
    required this.msg,
    this.data,
    this.traceId,
  });

  final int code;
  final String msg;
  final T? data;
  final String? traceId;

  bool get isSuccess => code == 0;

  static ApiResponse<T> fromJson<T>(
    Map<String, dynamic> json,
    T Function(Object? data) parseData,
  ) {
    final code = json['code'] as int? ?? -1;
    return ApiResponse<T>(
      code: code,
      msg: json['msg'] as String? ?? '',
      // 失败时 data 不可信，不做解析
      data: code == 0 ? parseData(json['data']) : null,
      traceId: json['traceId'] as String?,
    );
  }

  /// 成功返回 data，失败抛 [ApiException]；供 Repository 层统一调用。
  T unwrap() {
    if (isSuccess) return data as T;
    throw ApiException(
      code: code,
      message: msg.isEmpty ? '请求失败，请稍后重试' : msg,
      traceId: traceId,
    );
  }
}
