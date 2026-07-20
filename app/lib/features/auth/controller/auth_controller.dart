import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/auth_api.dart';
import '../data/auth_repository.dart';
import '../model/auth_user.dart';

/// 登录态三态模型：路由 redirect 依赖 unknown 态避免冷启动误跳登录页。
sealed class AuthState {
  const AuthState();
}

/// 冷启动恢复中，登录态未知
class AuthUnknown extends AuthState {
  const AuthUnknown();
}

/// 未登录
class AuthUnauthenticated extends AuthState {
  const AuthUnauthenticated();
}

/// 已登录
class AuthAuthenticated extends AuthState {
  const AuthAuthenticated(this.user);

  final AuthUser user;
}

/// 全局登录态控制器。
///
/// 状态本身始终是同步值（三态之一）；登录/注册等动作的进行中与错误
/// 由页面局部管理，避免把表单态混入全局状态。
class AuthController extends Notifier<AuthState> {
  AuthRepository get _repo => ref.read(authRepositoryProvider);

  @override
  AuthState build() {
    // 构造后异步恢复登录态；期间保持 unknown，路由停在启动页
    Future.microtask(_restore);
    return const AuthUnknown();
  }

  Future<void> _restore() async {
    try {
      final user = await _repo.restoreSession();
      state = user == null
          ? const AuthUnauthenticated()
          : AuthAuthenticated(user);
    } catch (_) {
      // 弱网等原因恢复失败：降级为未登录，用户可手动重新登录
      state = const AuthUnauthenticated();
    }
  }

  /// 邮箱+密码登录；失败向上抛 [ApiException] 由登录页展示
  Future<void> login({required String email, required String password}) async {
    final user = await _repo.login(email: email, password: password);
    state = AuthAuthenticated(user);
  }

  /// 邮箱注册（成功即登录）
  Future<void> register({
    required String email,
    required String password,
    required String code,
    required String nickname,
  }) async {
    final user = await _repo.register(
      email: email,
      password: password,
      code: code,
      nickname: nickname,
    );
    state = AuthAuthenticated(user);
  }

  Future<void> sendEmailCode({
    required String email,
    required EmailCodeScene scene,
  }) => _repo.sendEmailCode(email: email, scene: scene);

  Future<void> logout() async {
    await _repo.logout();
    state = const AuthUnauthenticated();
  }

  /// 编辑资料保存成功后同步全局用户信息（服务端事实由下次 /users/me 校准）
  void applyProfile({String? nickname, String? signature, String? avatar}) {
    final current = state;
    if (current is! AuthAuthenticated) return;
    state = AuthAuthenticated(
      current.user.copyWith(
        nickname: nickname,
        signature: signature,
        avatar: avatar,
      ),
    );
  }

  /// 令牌刷新失败（拦截器回调）：本地已清理，切未登录态触发路由跳转
  void onSessionExpired() {
    if (state is! AuthUnauthenticated) {
      state = const AuthUnauthenticated();
    }
  }
}

final authControllerProvider = NotifierProvider<AuthController, AuthState>(
  AuthController.new,
);
