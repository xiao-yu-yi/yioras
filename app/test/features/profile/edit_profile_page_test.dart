import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yiora/features/auth/controller/auth_controller.dart';
import 'package:yiora/features/auth/data/auth_api.dart';
import 'package:yiora/features/auth/data/auth_repository.dart';
import 'package:yiora/features/auth/model/auth_user.dart';
import 'package:yiora/features/profile/data/profile_repository.dart';
import 'package:yiora/features/profile/model/profile_models.dart';
import 'package:yiora/features/profile/view/edit_profile_page.dart';

/// 恢复即已登录的假认证仓库
class _FakeAuthRepository implements AuthRepository {
  static const user = AuthUser(
    id: 1,
    displayNo: 'N1',
    nickname: '旧昵称',
    signature: '旧签名',
  );

  @override
  Future<AuthUser?> restoreSession() async => user;

  @override
  Future<AuthUser> login({
    required String email,
    required String password,
  }) async => user;

  @override
  Future<AuthUser> register({
    required String email,
    required String password,
    required String code,
    required String nickname,
  }) async => user;

  @override
  Future<void> sendEmailCode({
    required String email,
    required EmailCodeScene scene,
  }) async {}

  @override
  Future<void> logout() async {}
}

class _FakeProfileRepository implements ProfileRepository {
  String? savedNickname;
  String? savedSignature;

  @override
  Future<ProfileStats> fetchStats() async => const ProfileStats();

  @override
  Future<List<MyPost>> fetchMyPosts() async => const [];

  @override
  Future<List<Footprint>> fetchFootprints() async => const [];

  @override
  Future<void> clearFootprints() async {}

  @override
  Future<String> uploadAvatar(String filePath) async => 'https://cdn/x.png';

  @override
  Future<void> updateProfile({
    required String nickname,
    required String signature,
    String? avatar,
  }) async {
    savedNickname = nickname;
    savedSignature = signature;
  }

  @override
  Future<void> deactivateAccount() async {}
}

Future<(_FakeProfileRepository, ProviderContainer)> _pump(
  WidgetTester tester,
) async {
  final repo = _FakeProfileRepository();
  final navigatorKey = GlobalKey<NavigatorState>();
  final container = ProviderContainer(
    overrides: [
      profileRepositoryProvider.overrideWithValue(repo),
      authRepositoryProvider.overrideWithValue(_FakeAuthRepository()),
    ],
  );
  addTearDown(container.dispose);

  // 先让登录态恢复为已登录
  container.read(authControllerProvider);
  await tester.runAsync(
    () => Future<void>.delayed(const Duration(milliseconds: 50)),
  );

  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        navigatorKey: navigatorKey,
        home: const Scaffold(body: SizedBox()),
      ),
    ),
  );
  navigatorKey.currentState!.push(
    MaterialPageRoute<void>(builder: (_) => const EditProfilePage()),
  );
  await tester.pumpAndSettle();
  return (repo, container);
}

void main() {
  testWidgets('回显当前昵称与签名', (tester) async {
    await _pump(tester);

    expect(find.text('旧昵称'), findsOneWidget);
    expect(find.text('旧签名'), findsOneWidget);
  });

  testWidgets('昵称清空后保存被校验拦截', (tester) async {
    final (repo, _) = await _pump(tester);

    await tester.enterText(find.widgetWithText(TextFormField, '旧昵称'), '');
    await tester.tap(find.text('保存'));
    await tester.pump();

    expect(find.text('请输入昵称'), findsOneWidget);
    expect(repo.savedNickname, isNull);
  });

  testWidgets('保存成功更新全局用户并返回', (tester) async {
    final (repo, container) = await _pump(tester);

    await tester.enterText(find.widgetWithText(TextFormField, '旧昵称'), '新昵称');
    await tester.enterText(find.widgetWithText(TextFormField, '旧签名'), '新签名');
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();

    expect(repo.savedNickname, '新昵称');
    expect(repo.savedSignature, '新签名');
    final auth = container.read(authControllerProvider) as AuthAuthenticated;
    expect(auth.user.nickname, '新昵称');
    expect(auth.user.signature, '新签名');
    expect(find.byType(EditProfilePage), findsNothing, reason: '保存成功后返回');
  });
}
