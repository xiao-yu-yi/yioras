/// 应用环境配置。
///
/// 通过 `--dart-define` 在构建期注入，避免把环境写死在代码里：
/// ```
/// flutter run --dart-define=API_BASE_URL=https://api.yiora.dev
/// ```
abstract final class AppConfig {
  /// REST 接口基址（默认指向本地开发网关；Android 模拟器访问宿主机用 10.0.2.2）
  static const String apiBaseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'http://10.0.2.2:8888',
  );

  /// 接口版本前缀，对应文档 4.3.8 `/api/v1/`
  static const String apiPrefix = '/api/v1';

  /// 请求超时
  static const Duration connectTimeout = Duration(seconds: 10);
  static const Duration receiveTimeout = Duration(seconds: 15);

  /// Mock 模式：骨架期后端未就绪，默认走内存假数据跑通登录与推荐流；
  /// 联调真实后端时以 `--dart-define=USE_MOCK=false` 关闭。
  static const bool useMock = bool.fromEnvironment(
    'USE_MOCK',
    defaultValue: true,
  );
}
