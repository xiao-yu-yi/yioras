import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/cache/key_value_cache.dart';
import '../model/post_draft.dart';

/// 草稿仓：取消发布时暂存并持久化（Hive），杀进程后仍可恢复。
class PublishDraftStore extends Notifier<PostDraft?> {
  static const cacheKey = 'publish_post_draft_v1';

  KeyValueCache get _cache => ref.read(cacheProvider);

  @override
  PostDraft? build() {
    final json = _cache.readJson(cacheKey);
    if (json == null) return null;
    try {
      return PostDraft.fromJson(json);
    } catch (_) {
      return null;
    }
  }

  void save(PostDraft draft) {
    state = draft;
    _cache.writeJson(cacheKey, draft.toJson());
  }

  void clear() {
    state = null;
    _cache.remove(cacheKey);
  }
}

final publishDraftProvider = NotifierProvider<PublishDraftStore, PostDraft?>(
  PublishDraftStore.new,
);
