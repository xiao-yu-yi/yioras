import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/config/app_config.dart';
import '../../../core/network/api_exception.dart';
import '../../../core/storage/token_storage.dart';
import '../model/auth_user.dart';
import 'auth_api.dart';

/// 账号仓库接口：向控制器暴露领域动作，屏蔽 HTTP/Mock 差异。
/// 实现方统一抛 [ApiException]，上层不感知网络细节。
abstract interface class AuthRepository {
  /// 冷启动恢复登录态：本地无令牌返回 null；令牌失效清理后返回 null。
  Future<AuthUser?> restoreSession();

  Future<AuthUser> login({required String email, required String password});

  Future<AuthUser> register({
    required String email,
    required String password,
    required String code,
    required String nickname,
  });

  Future<void> sendEmailCode({
    required String email,
    required EmailCodeScene scene,
  });

  Future<void> logout();
}

/// 真实后端实现：组合 AuthApi 与令牌存储。
class AuthRepositoryHttp implements AuthRepository {
  AuthRepositoryHttp({required this._api, required this._storage});

  final AuthApi _api;
  final TokenStorage _storage;

  @override
  Future<AuthUser?> restoreSession() async {
    final tokens = await _storage.read();
    if (tokens == null) return null;
    try {
      return await _api.fetchMe();
    } on DioException catch (e) {
      final apiError = ApiException.fromDio(e);
      if (apiError.isUnauthorized) {
        // 令牌失效且刷新失败：清理后按未登录处理
        await _storage.clear();
        return null;
      }
      throw apiError;
    }
  }

  @override
  Future<AuthUser> login({required String email, required String password}) =>
      _guard(() async {
        final session = await _api.login(email: email, password: password);
        await _storage.save(session.tokens);
        return session.user;
      });

  @override
  Future<AuthUser> register({
    required String email,
    required String password,
    required String code,
    required String nickname,
  }) => _guard(() async {
    final session = await _api.register(
      email: email,
      password: password,
      code: code,
      nickname: nickname,
    );
    await _storage.save(session.tokens);
    return session.user;
  });

  @override
  Future<void> sendEmailCode({
    required String email,
    required EmailCodeScene scene,
  }) => _guard(() => _api.sendEmailCode(email: email, scene: scene));

  @override
  Future<void> logout() => _storage.clear();

  Future<T> _guard<T>(Future<T> Function() action) async {
    try {
      return await action();
    } on DioException catch (e) {
      throw ApiException.fromDio(e);
    }
  }
}

/// Mock 实现：无后端时跑通「注册/登录 → 首页」链路。
/// 规则：任意合法邮箱；登录密码为 12345678；验证码 6 位任意数字。
class AuthRepositoryMock implements AuthRepository {
  AuthRepositoryMock({required this._storage});

  final TokenStorage _storage;
  static const _mockPassword = '12345678';

  AuthUser _userOf(String email, [String? nickname]) => AuthUser(
    id: 101215,
    displayNo: 'N101215',
    nickname: nickname?.isNotEmpty == true ? nickname! : email.split('@').first,
    email: email,
    signature: '这个人很懒，什么都没留下',
    level: 3,
  );

  @override
  Future<AuthUser?> restoreSession() async {
    await Future<void>.delayed(const Duration(milliseconds: 400));
    final tokens = await _storage.read();
    if (tokens == null) return null;
    return _userOf('demo@yiora.dev');
  }

  @override
  Future<AuthUser> login({
    required String email,
    required String password,
  }) async {
    await Future<void>.delayed(const Duration(milliseconds: 600));
    if (password != _mockPassword) {
      throw const ApiException(code: 40001, message: 'Mock 环境请使用密码 12345678');
    }
    await _storage.save(
      const AuthTokens(
        accessToken: 'mock-access',
        refreshToken: 'mock-refresh',
      ),
    );
    return _userOf(email);
  }

  @override
  Future<AuthUser> register({
    required String email,
    required String password,
    required String code,
    required String nickname,
  }) async {
    await Future<void>.delayed(const Duration(milliseconds: 800));
    await _storage.save(
      const AuthTokens(
        accessToken: 'mock-access',
        refreshToken: 'mock-refresh',
      ),
    );
    return _userOf(email, nickname);
  }

  @override
  Future<void> sendEmailCode({
    required String email,
    required EmailCodeScene scene,
  }) => Future<void>.delayed(const Duration(milliseconds: 500));

  @override
  Future<void> logout() => _storage.clear();
}

final authRepositoryProvider = Provider<AuthRepository>((ref) {
  if (AppConfig.useMock) {
    return AuthRepositoryMock(storage: ref.watch(tokenStorageProvider));
  }
  return AuthRepositoryHttp(
    api: ref.watch(authApiProvider),
    storage: ref.watch(tokenStorageProvider),
  );
});
