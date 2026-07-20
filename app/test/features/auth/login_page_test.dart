import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yiora/features/auth/data/auth_api.dart';
import 'package:yiora/features/auth/data/auth_repository.dart';
import 'package:yiora/features/auth/model/auth_user.dart';
import 'package:yiora/features/auth/view/login_page.dart';

/// 记录调用的假仓库，避免测试触碰安全存储插件
class _FakeAuthRepository implements AuthRepository {
  String? loginEmail;
  String? loginPassword;

  static const _user = AuthUser(id: 1, displayNo: 'N1', nickname: '测试');

  @override
  Future<AuthUser?> restoreSession() async => null;

  @override
  Future<AuthUser> login({
    required String email,
    required String password,
  }) async {
    loginEmail = email;
    loginPassword = password;
    return _user;
  }

  @override
  Future<AuthUser> register({
    required String email,
    required String password,
    required String code,
    required String nickname,
  }) async => _user;

  @override
  Future<void> sendEmailCode({
    required String email,
    required EmailCodeScene scene,
  }) async {}

  @override
  Future<void> resetPassword({
    required String email,
    required String code,
    required String newPassword,
  }) async {}

  @override
  Future<void> logout() async {}
}

Future<_FakeAuthRepository> _pumpLoginPage(WidgetTester tester) async {
  final repo = _FakeAuthRepository();
  await tester.pumpWidget(
    ProviderScope(
      overrides: [authRepositoryProvider.overrideWithValue(repo)],
      child: const MaterialApp(home: LoginPage()),
    ),
  );
  return repo;
}

void main() {
  testWidgets('登录模式渲染邮箱与密码输入框', (tester) async {
    await _pumpLoginPage(tester);

    expect(find.text('Yiora'), findsOneWidget);
    expect(find.widgetWithText(TextFormField, '邮箱'), findsOneWidget);
    expect(find.widgetWithText(TextFormField, '密码'), findsOneWidget);
    // 登录模式不出现注册专属字段
    expect(find.text('邮箱验证码'), findsNothing);
    expect(find.text('昵称'), findsNothing);
  });

  testWidgets('空表单提交展示校验错误且不发请求', (tester) async {
    final repo = await _pumpLoginPage(tester);

    await tester.tap(find.widgetWithText(FilledButton, '登录'));
    await tester.pump();

    expect(find.text('请输入邮箱'), findsOneWidget);
    expect(find.text('请输入密码'), findsOneWidget);
    expect(repo.loginEmail, isNull);
  });

  testWidgets('邮箱格式错误提示', (tester) async {
    await _pumpLoginPage(tester);

    await tester.enterText(
      find.widgetWithText(TextFormField, '邮箱'),
      'not-an-email',
    );
    await tester.tap(find.widgetWithText(FilledButton, '登录'));
    await tester.pump();

    expect(find.text('邮箱格式不正确'), findsOneWidget);
  });

  testWidgets('合法输入提交调用登录', (tester) async {
    final repo = await _pumpLoginPage(tester);

    await tester.enterText(
      find.widgetWithText(TextFormField, '邮箱'),
      'demo@yiora.dev',
    );
    await tester.enterText(
      find.widgetWithText(TextFormField, '密码'),
      '12345678',
    );
    await tester.tap(find.widgetWithText(FilledButton, '登录'));
    await tester.pumpAndSettle();

    expect(repo.loginEmail, 'demo@yiora.dev');
    expect(repo.loginPassword, '12345678');
  });

  testWidgets('切到注册模式出现验证码与昵称字段', (tester) async {
    await _pumpLoginPage(tester);

    await tester.tap(find.text('注册'));
    await tester.pumpAndSettle();

    expect(find.text('邮箱验证码'), findsOneWidget);
    expect(find.text('昵称'), findsOneWidget);
    expect(find.text('获取验证码'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, '注册并登录'), findsOneWidget);
  });
}
