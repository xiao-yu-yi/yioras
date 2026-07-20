import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/config/app_config.dart';
import '../../../core/network/api_client.dart';
import '../../../core/network/api_response.dart';
import '../../../core/network/auth_interceptor.dart';
import '../../../core/storage/token_storage.dart';
import '../model/auth_user.dart';

/// 邮箱验证码使用场景（与服务端约定的枚举值）
enum EmailCodeScene {
  register('register'),
  resetPassword('reset_password');

  const EmailCodeScene(this.value);
  final String value;
}

/// 登录/注册成功后的凭证 + 用户信息
class AuthSession {
  const AuthSession({required this.tokens, required this.user});

  final AuthTokens tokens;
  final AuthUser user;

  factory AuthSession.fromJson(Map<String, dynamic> json) => AuthSession(
    tokens: AuthTokens.fromJson(json),
    user: AuthUser.fromJson(json['user'] as Map<String, dynamic>),
  );
}

/// 账号域 API，对应文档 4.5 的 auth 接口组。
class AuthApi {
  AuthApi(this._dio);

  final Dio _dio;

  /// 开放接口标记：不注入令牌，401 视为业务错误
  static const _noAuth = {AuthInterceptor.kNoAuth: true};

  /// POST /auth/email-code 发送邮箱验证码（注册/找回）
  Future<void> sendEmailCode({
    required String email,
    required EmailCodeScene scene,
  }) async {
    final resp = await _dio.post<Map<String, dynamic>>(
      '${AppConfig.apiPrefix}/auth/email-code',
      data: {'email': email, 'scene': scene.value},
      options: Options(extra: _noAuth),
    );
    ApiResponse.fromJson(resp.data!, (_) => null).unwrap();
  }

  /// POST /auth/register 邮箱注册（注册成功即登录）
  Future<AuthSession> register({
    required String email,
    required String password,
    required String code,
    required String nickname,
  }) async {
    final resp = await _dio.post<Map<String, dynamic>>(
      '${AppConfig.apiPrefix}/auth/register',
      data: {
        'email': email,
        'password': password,
        'code': code,
        'nickname': nickname,
      },
      options: Options(extra: _noAuth),
    );
    return ApiResponse.fromJson(
      resp.data!,
      (data) => AuthSession.fromJson(data as Map<String, dynamic>),
    ).unwrap();
  }

  /// POST /auth/login 邮箱+密码登录
  Future<AuthSession> login({
    required String email,
    required String password,
  }) async {
    final resp = await _dio.post<Map<String, dynamic>>(
      '${AppConfig.apiPrefix}/auth/login',
      data: {'email': email, 'password': password},
      options: Options(extra: _noAuth),
    );
    return ApiResponse.fromJson(
      resp.data!,
      (data) => AuthSession.fromJson(data as Map<String, dynamic>),
    ).unwrap();
  }

  /// POST /auth/reset-password 邮箱验证码重置密码
  Future<void> resetPassword({
    required String email,
    required String code,
    required String newPassword,
  }) async {
    final resp = await _dio.post<Map<String, dynamic>>(
      '${AppConfig.apiPrefix}/auth/reset-password',
      data: {'email': email, 'code': code, 'newPassword': newPassword},
      options: Options(extra: _noAuth),
    );
    ApiResponse.fromJson(resp.data!, (_) => null).unwrap();
  }

  /// GET /users/me 拉取当前用户（冷启动恢复登录态时校验令牌有效性）
  Future<AuthUser> fetchMe() async {
    final resp = await _dio.get<Map<String, dynamic>>(
      '${AppConfig.apiPrefix}/users/me',
    );
    return ApiResponse.fromJson(
      resp.data!,
      (data) => AuthUser.fromJson(data as Map<String, dynamic>),
    ).unwrap();
  }
}

final authApiProvider = Provider<AuthApi>((ref) {
  return AuthApi(ref.watch(dioProvider));
});
