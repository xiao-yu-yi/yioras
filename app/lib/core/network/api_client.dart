import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/auth/controller/auth_controller.dart';
import '../config/app_config.dart';
import '../storage/token_storage.dart';
import 'auth_interceptor.dart';

/// 全局 dio 实例：基址/超时/鉴权拦截器/调试日志统一在此组装。
final dioProvider = Provider<Dio>((ref) {
  final dio = Dio(
    BaseOptions(
      baseUrl: AppConfig.apiBaseUrl,
      connectTimeout: AppConfig.connectTimeout,
      receiveTimeout: AppConfig.receiveTimeout,
      contentType: Headers.jsonContentType,
    ),
  );

  dio.interceptors.add(
    AuthInterceptor(
      dio: dio,
      storage: ref.read(tokenStorageProvider),
      // 闭包内延迟读取，避免 dio 与 AuthController 构造期循环依赖
      onSessionExpired: () =>
          ref.read(authControllerProvider.notifier).onSessionExpired(),
    ),
  );

  if (kDebugMode) {
    // 仅调试期打日志；不打印请求头与响应体，防止令牌等敏感信息落日志
    dio.interceptors.add(
      LogInterceptor(
        requestHeader: false,
        requestBody: false,
        responseBody: false,
      ),
    );
  }
  return dio;
});
