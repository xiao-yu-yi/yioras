import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yiora/core/cache/key_value_cache.dart';
import 'package:yiora/features/circle/model/circle.dart';
import 'package:yiora/features/publish/controller/publish_draft_store.dart';
import 'package:yiora/features/publish/model/post_draft.dart';

ProviderContainer _container(KeyValueCache cache) {
  final container = ProviderContainer(
    overrides: [cacheProvider.overrideWithValue(cache)],
  );
  addTearDown(container.dispose);
  return container;
}

void main() {
  test('保存草稿后新会话可恢复（含圈子与话题）', () {
    final cache = MemoryKeyValueCache();
    final first = _container(cache);

    first
        .read(publishDraftProvider.notifier)
        .save(
          const PostDraft(
            title: '草稿标题',
            content: '草稿正文',
            imagePaths: ['/tmp/a.jpg'],
            circle: Circle(id: 2, name: '闲言碎语'),
            topics: ['Flutter'],
          ),
        );

    // 模拟重启：同一缓存、新容器
    final second = _container(cache);
    final restored = second.read(publishDraftProvider);

    expect(restored, isNotNull);
    expect(restored!.title, '草稿标题');
    expect(restored.content, '草稿正文');
    expect(restored.imagePaths, ['/tmp/a.jpg']);
    expect(restored.circle?.id, 2);
    expect(restored.topics, ['Flutter']);
  });

  test('清除草稿后不再恢复', () {
    final cache = MemoryKeyValueCache();
    final first = _container(cache);
    first
        .read(publishDraftProvider.notifier)
        .save(const PostDraft(content: '要被清掉的'));
    first.read(publishDraftProvider.notifier).clear();

    final second = _container(cache);
    expect(second.read(publishDraftProvider), isNull);
  });
}
