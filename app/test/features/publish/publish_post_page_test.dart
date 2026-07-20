import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yiora/features/circle/data/circle_repository.dart';
import 'package:yiora/features/circle/model/circle.dart';
import 'package:yiora/features/feed/model/post.dart';
import 'package:yiora/features/publish/data/publish_repository.dart';
import 'package:yiora/features/publish/model/post_draft.dart';
import 'package:yiora/features/publish/model/software_draft.dart';
import 'package:yiora/features/publish/view/publish_post_page.dart';

class _FakePublishRepository implements PublishRepository {
  PostDraft? published;

  @override
  Future<void> publishPost(PostDraft draft) async => published = draft;

  @override
  Future<List<String>> fetchHotTopics() async => const ['话题A', '话题B'];

  @override
  Future<void> publishSoftware(SoftwareDraft draft) async {}

  @override
  Future<List<String>> fetchSoftwareCategories(int type) async => const ['工具'];
}

class _FakeCircleRepository implements CircleRepository {
  static const _circle = Circle(id: 1, name: '闲言碎语', intro: '无聊就来此聊聊');

  @override
  Future<List<Circle>> fetchCircles({required CircleSort sort}) async => const [
    _circle,
  ];

  @override
  Future<Circle> fetchCircleDetail(int id) async => _circle;

  @override
  Future<void> joinCircle(int id) async {}

  @override
  Future<void> quitCircle(int id) async {}

  @override
  Future<PostPage> fetchCirclePosts(
    int circleId, {
    CirclePostSort sort = CirclePostSort.newest,
    String? cursor,
    int size = 20,
  }) async => const PostPage(list: [], nextCursor: null, hasMore: false);
}

Future<_FakePublishRepository> _pumpPage(WidgetTester tester) async {
  // 放大测试画布，保证表单全部可见、不被底部发布栏遮挡
  await tester.binding.setSurfaceSize(const Size(800, 1400));
  addTearDown(() => tester.binding.setSurfaceSize(null));

  final publishRepo = _FakePublishRepository();
  final navigatorKey = GlobalKey<NavigatorState>();
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        publishRepositoryProvider.overrideWithValue(publishRepo),
        circleRepositoryProvider.overrideWithValue(_FakeCircleRepository()),
      ],
      child: MaterialApp(
        navigatorKey: navigatorKey,
        home: const Scaffold(body: SizedBox()),
      ),
    ),
  );
  // 以 push 方式进入，保证页面内 Navigator.pop 可用
  unawaited(
    navigatorKey.currentState!.push(
      MaterialPageRoute<void>(builder: (_) => const PublishPostPage()),
    ),
  );
  await tester.pumpAndSettle();
  return publishRepo;
}

/// 打开圈子选择器 → 选中假圈子
Future<void> _selectCircle(WidgetTester tester) async {
  await tester.tap(find.text('选择圈子（必选）'));
  await tester.pumpAndSettle();
  await tester.tap(find.text('闲言碎语').last);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('初始状态发布按钮禁用', (tester) async {
    await _pumpPage(tester);

    final button = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, '发布'),
    );
    expect(button.onPressed, isNull);
  });

  testWidgets('仅填正文未选圈子仍禁用；选圈子后启用', (tester) async {
    await _pumpPage(tester);

    await tester.enterText(
      find.widgetWithText(TextField, '此刻的想法、见闻或故事…'),
      '这是一条测试动态',
    );
    await tester.pump();
    var button = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, '发布'),
    );
    expect(button.onPressed, isNull, reason: '圈子必选，未选不可发布');

    await _selectCircle(tester);

    button = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, '发布'),
    );
    expect(button.onPressed, isNotNull);
  });

  testWidgets('发布成功提交草稿内容并返回', (tester) async {
    final repo = await _pumpPage(tester);

    await tester.enterText(
      find.widgetWithText(TextField, '添加标题让更多人看见'),
      '测试标题',
    );
    await tester.enterText(
      find.widgetWithText(TextField, '此刻的想法、见闻或故事…'),
      '这是一条测试动态',
    );
    await _selectCircle(tester);

    await tester.tap(find.widgetWithText(FilledButton, '发布'));
    await tester.pumpAndSettle();

    expect(repo.published, isNotNull);
    expect(repo.published!.title, '测试标题');
    expect(repo.published!.content, '这是一条测试动态');
    expect(repo.published!.circle?.id, 1);
    // 发布成功后返回上一页
    expect(find.byType(PublishPostPage), findsNothing);
  });

  testWidgets('重置清空所有输入', (tester) async {
    await _pumpPage(tester);

    await tester.enterText(
      find.widgetWithText(TextField, '此刻的想法、见闻或故事…'),
      '要被重置的内容',
    );
    await tester.pump();

    await tester.tap(find.text('重置'));
    await tester.pump();

    expect(find.text('要被重置的内容'), findsNothing);
    final button = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, '发布'),
    );
    expect(button.onPressed, isNull);
  });

  testWidgets('有内容点取消弹出存草稿确认', (tester) async {
    await _pumpPage(tester);

    await tester.enterText(
      find.widgetWithText(TextField, '此刻的想法、见闻或故事…'),
      '未完成的草稿',
    );
    await tester.pump();

    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();

    expect(find.text('保留本次编辑？'), findsOneWidget);
    expect(find.text('存草稿'), findsOneWidget);

    // 选择存草稿后页面关闭
    await tester.tap(find.text('存草稿'));
    await tester.pumpAndSettle();
    expect(find.byType(PublishPostPage), findsNothing);
  });
}
