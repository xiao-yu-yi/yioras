import 'package:dio/dio.dart';

import '../config/app_config.dart';
import '../storage/token_storage.dart';

/// 鉴权拦截器：请求注入 Access Token；401 时用 Refresh Token 换新并重放。
///
/// 继承 [QueuedInterceptor]：dio 会将本拦截器的回调串行化，
/// 并发多个 401 只会触发一次真实刷新（后续请求发现令牌已更新则直接重放）。
class AuthInterceptor extends QueuedInterceptor {
  AuthInterceptor({
    required this._dio,
    required this._storage,
    required this._onSessionExpired,
  });

  /// 主 dio 实例，重放请求时复用（会重新走一遍拦截器注入新令牌）
  final Dio _dio;
  final TokenStorage _storage;

  /// 刷新失败（登录态彻底失效）时通知上层切到未登录态
  final void Function() _onSessionExpired;

  /// 标记无需鉴权的开放接口（登录/注册/验证码等）
  static const String kNoAuth = 'noAuth';

  /// 标记该请求已因 401 重放过一次，防止无限循环
  static const String _kRetried = 'authRetried';

  @override
  Future<void> onRequest(
    RequestOptions options,
    RequestInterceptorHandler handler,
  ) async {
    if (options.extra[kNoAuth] == true) {
      return handler.next(options);
    }
    final tokens = await _storage.read();
    if (tokens != null) {
      options.headers['Authorization'] = 'Bearer ${tokens.accessToken}';
    }
    handler.next(options);
  }

  @override
  Future<void> onError(
    DioException err,
    ErrorInterceptorHandler handler,
  ) async {
    final options = err.requestOptions;
    final is401 = err.response?.statusCode == 401;
    // 开放接口的 401 是业务错误（如密码错误），不走刷新
    if (!is401 || options.extra[kNoAuth] == true) {
      return handler.next(err);
    }
    // 已重放过仍 401：登录态确实失效
    if (options.extra[_kRetried] == true) {
      await _expire();
      return handler.next(err);
    }

    final current = await _storage.read();
    if (current == null) {
      await _expire();
      return handler.next(err);
    }

    // 若失败请求所带令牌已不是当前令牌，说明队列前面的请求刚刷新过，直接重放
    final usedToken = (options.headers['Authorization'] as String?)
        ?.replaceFirst('Bearer ', '');
    if (usedToken == current.accessToken) {
      final refreshed = await _refresh(current.refreshToken);
      if (!refreshed) {
        await _expire();
        return handler.next(err);
      }
    }

    // 用新令牌重放原请求（重新过 onRequest 注入头）
    try {
      options.extra[_kRetried] = true;
      options.headers.remove('Authorization');
      final response = await _dio.fetch<dynamic>(options);
      handler.resolve(response);
    } on DioException catch (e) {
      handler.next(e);
    }
  }

  /// 用独立裸 dio 调刷新接口，避免递归进入本拦截器
  Future<bool> _refresh(String refreshToken) async {
    try {
      final bare = Dio(
        BaseOptions(
          baseUrl: AppConfig.apiBaseUrl,
          connectTimeout: AppConfig.connectTimeout,
          receiveTimeout: AppConfig.receiveTimeout,
        ),
      );
      final resp = await bare.post<Map<String, dynamic>>(
        '${AppConfig.apiPrefix}/auth/refresh',
        data: {'refreshToken': refreshToken},
      );
      final body = resp.data;
      if (body == null || body['code'] != 0) return false;
      final data = body['data'] as Map<String, dynamic>;
      await _storage.save(AuthTokens.fromJson(data));
      return true;
    } on DioException {
      return false;
    }
  }

  Future<void> _expire() async {
    await _storage.clear();
    _onSessionExpired();
  }
}
