import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:yiora/main.dart' as app;

/// M2 全链路冒烟（Mock 模式，真机/模拟器执行）：
/// 冷启动 → 邮箱登录 → 推荐流 → 发动态（圈子必选）→ 私信（Yo酱收发）→ 设置页。
///
/// 运行：`flutter test integration_test/smoke_test.dart -d deviceId`
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('登录→发帖→聊天→设置 全链路冒烟', (tester) async {
    await app.main();
    await tester.pump(const Duration(seconds: 1));

    // ── 1/2. 冷启动：无令牌走登录，有残留令牌直接进首页（重复执行幂等）──
    final landed = await _pumpUntilAny(tester, [
      find.widgetWithText(FilledButton, '登录'),
      find.textContaining('Bug 反馈集中贴'),
    ]);
    if (landed == 0) {
      await tester.enterText(
        find.widgetWithText(TextFormField, '邮箱'),
        'demo@yiora.dev',
      );
      await tester.enterText(
        find.widgetWithText(TextFormField, '密码'),
        '12345678',
      );
      await tester.tap(find.widgetWithText(FilledButton, '登录'));
    }

    // ── 3. 首页推荐流出现帖子（Mock 置顶帖标题）────────────────
    await _pumpUntil(tester, find.textContaining('Bug 反馈集中贴'));

    // ── 4. 发动态：中央 + → 发动态 → 正文 → 圈子必选 → 发布 ──
    await tester.tap(find.byIcon(Icons.add));
    await _pumpUntil(tester, find.text('发动态'));
    await tester.tap(find.text('发动态'));
    await _pumpUntil(tester, find.text('此刻的想法、见闻或故事…'));

    await tester.enterText(
      find.widgetWithText(TextField, '此刻的想法、见闻或故事…'),
      '冒烟测试动态内容',
    );
    await tester.pump();

    // 圈子行可能在视口外，先滚动露出
    await tester.scrollUntilVisible(
      find.text('选择圈子（必选）'),
      160,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pump(const Duration(milliseconds: 200));
    await tester.tap(find.text('选择圈子（必选）'), warnIfMissed: false);
    await _pumpUntil(tester, find.text('选择圈子'));
    await _pumpUntil(tester, find.text('闲言碎语'));
    await tester.tap(find.text('闲言碎语').last);
    await tester.pump(const Duration(milliseconds: 400));

    await tester.tap(find.widgetWithText(FilledButton, '发布'));
    await _pumpUntil(tester, find.text('发布成功，已提交审核'));

    // 回到首页；等 SnackBar 展示期结束，避免悬浮层遮挡后续点击
    await _pumpUntil(tester, find.textContaining('Bug 反馈集中贴'));
    await tester.pump(const Duration(seconds: 5));

    // ── 5. 私信：消息 Tab → Yo酱 → 发消息 → ack + 机器人回复 ──
    await tester.tap(find.text('消息'));
    await _pumpUntil(tester, find.text('Yo酱'));
    await tester.tap(find.text('Yo酱'));
    await _pumpUntil(tester, find.text('文明交流，理性发言…'));

    await tester.enterText(
      find.widgetWithText(TextField, '文明交流，理性发言…'),
      '冒烟测试消息',
    );
    await tester.pump(const Duration(milliseconds: 200));
    await tester.tap(find.byIcon(Icons.send_rounded));
    await _pumpUntil(tester, find.text('冒烟测试消息'));

    // 等 ack（600ms）与机器人回复（1.5s）
    await tester.pump(const Duration(milliseconds: 2500));
    await tester.pump();
    final botReplied = [
      '收到啦',
      '这个问题我记下来了',
      '试试下拉刷新',
      '记得文明交流',
    ].any((text) => find.textContaining(text).evaluate().isNotEmpty);
    expect(botReplied, isTrue, reason: 'Yo酱应自动回复');

    // ── 6. 设置：我的 Tab → 抽屉 → 我的设置 ─────────────────
    await tester.pageBack();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.tap(find.text('我的'));
    await _pumpUntil(tester, find.text('编辑资料'));

    await tester.tap(find.byIcon(Icons.menu));
    await _pumpUntil(tester, find.text('我的设置'));
    await tester.tap(find.text('我的设置'));
    await _pumpUntil(tester, find.text('清理缓存'));
    expect(find.text('注销账号'), findsOneWidget);
    // 栈下层个人主页抽屉里也有一个「退出登录」，故不断言唯一
    expect(find.text('退出登录'), findsWidgets);
  });
}

/// 轮询等待目标控件出现（Mock 网络延迟 + 无限动画下不能用 pumpAndSettle）
Future<void> _pumpUntil(
  WidgetTester tester,
  Finder finder, {
  Duration timeout = const Duration(seconds: 20),
}) async {
  final end = DateTime.now().add(timeout);
  while (DateTime.now().isBefore(end)) {
    await tester.pump(const Duration(milliseconds: 200));
    if (finder.evaluate().isNotEmpty) return;
  }
  throw TestFailure('等待超时：未找到 $finder');
}

/// 轮询等待多个候选之一出现，返回命中的下标
Future<int> _pumpUntilAny(
  WidgetTester tester,
  List<Finder> finders, {
  Duration timeout = const Duration(seconds: 20),
}) async {
  final end = DateTime.now().add(timeout);
  while (DateTime.now().isBefore(end)) {
    await tester.pump(const Duration(milliseconds: 200));
    for (var i = 0; i < finders.length; i++) {
      if (finders[i].evaluate().isNotEmpty) return i;
    }
  }
  throw TestFailure('等待超时：候选均未出现 $finders');
}
