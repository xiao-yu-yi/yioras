import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive/hive.dart';

/// 轻量 JSON 键值缓存（SWR 本地层，文档 4.2「SWR 模式」）。
/// 存储包裹为 `{"savedAt": ISO时间, "data": {...}}`，读取时按 maxAge 判断过期。
abstract interface class KeyValueCache {
  /// 读取；不存在、损坏或超过 [maxAge] 返回 null
  Map<String, dynamic>? readJson(String key, {Duration? maxAge});

  Future<void> writeJson(String key, Map<String, dynamic> data);

  Future<void> remove(String key);

  /// 清空全部缓存（设置页「清理缓存」）
  Future<void> clear();
}

/// Hive 实现：box 于 main 中打开后注入
class HiveKeyValueCache implements KeyValueCache {
  HiveKeyValueCache(this._box);

  final Box<String> _box;

  @override
  Map<String, dynamic>? readJson(String key, {Duration? maxAge}) {
    final raw = _box.get(key);
    if (raw == null) return null;
    try {
      final wrapper = jsonDecode(raw) as Map<String, dynamic>;
      if (maxAge != null) {
        final savedAt = DateTime.tryParse(wrapper['savedAt'] as String? ?? '');
        if (savedAt == null || DateTime.now().difference(savedAt) > maxAge) {
          return null;
        }
      }
      return wrapper['data'] as Map<String, dynamic>?;
    } on FormatException {
      return null;
    }
  }

  @override
  Future<void> writeJson(String key, Map<String, dynamic> data) {
    return _box.put(
      key,
      jsonEncode({'savedAt': DateTime.now().toIso8601String(), 'data': data}),
    );
  }

  @override
  Future<void> remove(String key) => _box.delete(key);

  @override
  Future<void> clear() async {
    await _box.clear();
  }
}

/// 内存实现：单测与未初始化环境的兜底（App 存活期内有效）
class MemoryKeyValueCache implements KeyValueCache {
  final Map<String, ({DateTime savedAt, Map<String, dynamic> data})> _store =
      {};

  @override
  Map<String, dynamic>? readJson(String key, {Duration? maxAge}) {
    final entry = _store[key];
    if (entry == null) return null;
    if (maxAge != null && DateTime.now().difference(entry.savedAt) > maxAge) {
      return null;
    }
    return entry.data;
  }

  @override
  Future<void> writeJson(String key, Map<String, dynamic> data) async {
    _store[key] = (savedAt: DateTime.now(), data: data);
  }

  @override
  Future<void> remove(String key) async => _store.remove(key);

  @override
  Future<void> clear() async => _store.clear();
}

/// 生产环境由 main 用 [HiveKeyValueCache] 覆盖；默认内存实现供测试直接使用。
final cacheProvider = Provider<KeyValueCache>((ref) => MemoryKeyValueCache());
