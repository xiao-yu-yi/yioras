import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../features/auth/controller/auth_controller.dart';
import '../../features/auth/view/login_page.dart';
import '../../features/chat/view/chat_page.dart';
import '../../features/circle/view/circle_detail_page.dart';
import '../../features/circle/view/circle_discover_page.dart';
import '../../features/feed/view/feed_page.dart';
import '../../features/messages/model/message_models.dart';
import '../../features/messages/view/messages_page.dart';
import '../../features/messages/view/notifications_page.dart';
import '../../features/post_detail/view/post_detail_page.dart';
import '../../features/profile/view/edit_profile_page.dart';
import '../../features/profile/view/profile_page.dart';
import '../../features/profile/view/settings_page.dart';
import '../../features/publish/view/publish_post_page.dart';
import '../../features/publish/view/publish_software_page.dart';
import '../../features/shell/main_shell.dart';
import '../../features/user/view/user_profile_page.dart';
import 'routes.dart';

/// 全局路由。
///
/// 登录态三态 redirect：
/// - unknown        → 停留启动页，等待恢复结果（避免闪跳登录页）
/// - unauthenticated → 一律去登录页
/// - authenticated  → 启动页/登录页自动进首页
final routerProvider = Provider<GoRouter>((ref) {
  // 登录态变化时触发路由重新执行 redirect
  final refresh = ValueNotifier(0);
  ref.onDispose(refresh.dispose);
  ref.listen(authControllerProvider, (_, _) => refresh.value++);

  final router = GoRouter(
    initialLocation: Routes.splash,
    refreshListenable: refresh,
    debugLogDiagnostics: kDebugMode,
    redirect: (context, state) {
      final auth = ref.read(authControllerProvider);
      final location = state.matchedLocation;
      final atSplash = location == Routes.splash;
      final atLogin = location == Routes.login;

      return switch (auth) {
        AuthUnknown() => atSplash ? null : Routes.splash,
        AuthUnauthenticated() => atLogin ? null : Routes.login,
        AuthAuthenticated() => (atSplash || atLogin) ? Routes.home : null,
      };
    },
    routes: [
      GoRoute(
        path: Routes.splash,
        builder: (context, state) => const _SplashPage(),
      ),
      GoRoute(
        path: Routes.login,
        builder: (context, state) => const LoginPage(),
      ),
      // 全屏页（脱离底部 Tab 壳）
      GoRoute(
        path: Routes.circleDetail,
        builder: (context, state) =>
            CircleDetailPage(circleId: int.parse(state.pathParameters['id']!)),
      ),
      GoRoute(
        path: Routes.publishPost,
        builder: (context, state) => const PublishPostPage(),
      ),
      GoRoute(
        path: Routes.publishSoftware,
        builder: (context, state) => const PublishSoftwarePage(),
      ),
      GoRoute(
        path: Routes.postDetail,
        builder: (context, state) =>
            PostDetailPage(postId: int.parse(state.pathParameters['id']!)),
      ),
      GoRoute(
        path: Routes.notifications,
        builder: (context, state) => NotificationsPage(
          type: NotificationType.fromValue(
            int.parse(state.pathParameters['type']!),
          ),
        ),
      ),
      GoRoute(
        path: Routes.chat,
        builder: (context, state) =>
            ChatPage(conversationId: int.parse(state.pathParameters['id']!)),
      ),
      GoRoute(
        path: Routes.userProfile,
        builder: (context, state) =>
            UserProfilePage(uid: int.parse(state.pathParameters['id']!)),
      ),
      GoRoute(
        path: Routes.editProfile,
        builder: (context, state) => const EditProfilePage(),
      ),
      GoRoute(
        path: Routes.settings,
        builder: (context, state) => const SettingsPage(),
      ),
      // 底部 Tab 主壳：IndexedStack 保活各分支浏览位置
      StatefulShellRoute.indexedStack(
        builder: (context, state, navigationShell) =>
            MainShell(navigationShell: navigationShell),
        branches: [
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: Routes.home,
                builder: (context, state) => const FeedPage(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: Routes.circles,
                builder: (context, state) => const CircleDiscoverPage(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: Routes.messages,
                builder: (context, state) => const MessagesPage(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: Routes.profile,
                builder: (context, state) => const ProfilePage(),
              ),
            ],
          ),
        ],
      ),
    ],
  );
  ref.onDispose(router.dispose);
  return router;
});

/// 启动页：登录态恢复期间的品牌过渡页
class _SplashPage extends StatelessWidget {
  const _SplashPage();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Yiora',
              style: Theme.of(context).textTheme.displaySmall?.copyWith(
                color: scheme.primary,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 24),
            const SizedBox(
              width: 24,
              height: 24,
              child: CircularProgressIndicator(strokeWidth: 2.5),
            ),
          ],
        ),
      ),
    );
  }
}
