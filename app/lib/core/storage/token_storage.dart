import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// 登录令牌对。access 短效走请求头，refresh 长效仅用于刷新。
class AuthTokens {
  const AuthTokens({required this.accessToken, required this.refreshToken});

  final String accessToken;
  final String refreshToken;

  factory AuthTokens.fromJson(Map<String, dynamic> json) => AuthTokens(
    accessToken: json['accessToken'] as String,
    refreshToken: json['refreshToken'] as String,
  );
}

/// 令牌安全存储：Android Keystore / iOS Keychain，不落明文盘。
class TokenStorage {
  TokenStorage(this._storage);

  static const _kAccessToken = 'yiora_access_token';
  static const _kRefreshToken = 'yiora_refresh_token';

  final FlutterSecureStorage _storage;

  /// 内存缓存，避免每个请求都读 Keychain
  AuthTokens? _cached;
  bool _loaded = false;

  /// 读取令牌（首次从安全存储恢复，之后走内存）
  Future<AuthTokens?> read() async {
    if (_loaded) return _cached;
    final access = await _storage.read(key: _kAccessToken);
    final refresh = await _storage.read(key: _kRefreshToken);
    _cached = (access != null && refresh != null)
        ? AuthTokens(accessToken: access, refreshToken: refresh)
        : null;
    _loaded = true;
    return _cached;
  }

  Future<void> save(AuthTokens tokens) async {
    _cached = tokens;
    _loaded = true;
    await _storage.write(key: _kAccessToken, value: tokens.accessToken);
    await _storage.write(key: _kRefreshToken, value: tokens.refreshToken);
  }

  /// 登出/刷新失败时清理
  Future<void> clear() async {
    _cached = null;
    _loaded = true;
    await _storage.delete(key: _kAccessToken);
    await _storage.delete(key: _kRefreshToken);
  }
}

final tokenStorageProvider = Provider<TokenStorage>((ref) {
  return TokenStorage(const FlutterSecureStorage());
});
