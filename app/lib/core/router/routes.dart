/// 路由路径常量，统一维护避免散落魔法字符串。
abstract final class Routes {
  static const splash = '/splash';
  static const login = '/login';
  static const resetPassword = '/reset-password';

  // 主壳四个 Tab 分支（发布为弹层不占路由）
  static const home = '/home';
  static const circles = '/circles';
  static const messages = '/messages';
  static const profile = '/profile';

  // 全屏页
  static const circleDetail = '/circles/:id';
  static const publishPost = '/publish/post';
  static const publishSoftware = '/publish/software';
  static const postDetail = '/posts/:id';
  static const notifications = '/notifications/:type';
  static const chat = '/chat/:id';
  static const userProfile = '/users/:id';
  static const settings = '/settings';
  static const editProfile = '/settings/profile';

  static String circleDetailPath(int id) => '/circles/$id';

  static String postDetailPath(int id) => '/posts/$id';

  static String chatPath(int conversationId) => '/chat/$conversationId';

  static String userProfilePath(int uid) => '/users/$uid';
}
