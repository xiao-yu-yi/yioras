import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';

import 'app.dart';
import 'core/cache/key_value_cache.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // 本地缓存（SWR 层 + 草稿持久化）
  await Hive.initFlutter();
  final cacheBox = await Hive.openBox<String>('yiora_kv_cache');

  runApp(
    ProviderScope(
      overrides: [cacheProvider.overrideWithValue(HiveKeyValueCache(cacheBox))],
      child: const YioraApp(),
    ),
  );
}
