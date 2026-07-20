import 'dart:math';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/config/app_config.dart';
import '../../../core/network/api_client.dart';
import '../../../core/network/api_exception.dart';
import '../../../core/network/api_response.dart';
import '../../growth/data/mock_wallet.dart';
import '../model/mall_models.dart';

/// 忧珠商城仓库（装扮/靓号/抽奖/兑换记录）；统一抛 [ApiException]。
abstract interface class MallRepository {
  /// GET /mall/decorations 装扮商城（登录态带 owned）
  Future<List<Decoration>> fetchDecorations();

  /// POST /mall/decorations/:id/exchange 兑换装扮
  Future<void> exchangeDecoration(int id);

  /// GET /mall/decorations/mine 我的仓库
  Future<List<MyDecoration>> fetchMyDecorations();

  /// POST /mall/decorations/:id/wear 佩戴（同类互斥由服务端保证）
  Future<void> wear(int id);

  /// POST /mall/decorations/:id/take-off 卸下
  Future<void> takeOff(int id);

  /// GET /mall/pretty-no 靓号在售列表
  Future<List<PrettyNo>> fetchPrettyNos({int page, int size});

  /// POST /mall/pretty-no/:id/exchange 兑换靓号，返回新靓号
  Future<String> exchangePrettyNo(int id);

  /// GET /lottery/pools 奖池（含单次消耗与概率公示）
  Future<LotteryPool> fetchLotteryPool();

  /// POST /lottery/draw 抽一次
  Future<DrawResult> draw();

  /// GET /exchange/records 兑换记录
  Future<List<ExchangeRecord>> fetchExchangeRecords({int page, int size});
}

class MallRepositoryHttp implements MallRepository {
  MallRepositoryHttp(this._dio);

  final Dio _dio;

  @override
  Future<List<Decoration>> fetchDecorations() => _guard(() async {
    final resp = await _dio.get<Map<String, dynamic>>(
      '${AppConfig.apiPrefix}/mall/decorations',
      queryParameters: {'kind': 1},
    );
    return ApiResponse.fromJson(
      resp.data!,
      (data) => (data as List<dynamic>? ?? const [])
          .map((e) => Decoration.fromJson(e as Map<String, dynamic>))
          .toList(),
    ).unwrap();
  });

  @override
  Future<void> exchangeDecoration(int id) => _guard(() async {
    final resp = await _dio.post<Map<String, dynamic>>(
      '${AppConfig.apiPrefix}/mall/decorations/$id/exchange',
    );
    ApiResponse.fromJson(resp.data!, (_) => null).unwrap();
  });

  @override
  Future<List<MyDecoration>> fetchMyDecorations() => _guard(() async {
    final resp = await _dio.get<Map<String, dynamic>>(
      '${AppConfig.apiPrefix}/mall/decorations/mine',
    );
    return ApiResponse.fromJson(
      resp.data!,
      (data) => (data as List<dynamic>? ?? const [])
          .map((e) => MyDecoration.fromJson(e as Map<String, dynamic>))
          .toList(),
    ).unwrap();
  });

  @override
  Future<void> wear(int id) => _guard(() async {
    final resp = await _dio.post<Map<String, dynamic>>(
      '${AppConfig.apiPrefix}/mall/decorations/$id/wear',
    );
    ApiResponse.fromJson(resp.data!, (_) => null).unwrap();
  });

  @override
  Future<void> takeOff(int id) => _guard(() async {
    final resp = await _dio.post<Map<String, dynamic>>(
      '${AppConfig.apiPrefix}/mall/decorations/$id/take-off',
    );
    ApiResponse.fromJson(resp.data!, (_) => null).unwrap();
  });

  @override
  Future<List<PrettyNo>> fetchPrettyNos({int page = 1, int size = 50}) =>
      _guard(() async {
        final resp = await _dio.get<Map<String, dynamic>>(
          '${AppConfig.apiPrefix}/mall/pretty-no',
          queryParameters: {'page': page, 'size': size},
        );
        return ApiResponse.fromJson(
          resp.data!,
          (data) => (data as List<dynamic>? ?? const [])
              .map((e) => PrettyNo.fromJson(e as Map<String, dynamic>))
              .toList(),
        ).unwrap();
      });

  @override
  Future<String> exchangePrettyNo(int id) => _guard(() async {
    final resp = await _dio.post<Map<String, dynamic>>(
      '${AppConfig.apiPrefix}/mall/pretty-no/$id/exchange',
    );
    return ApiResponse.fromJson(
      resp.data!,
      (data) => (data as Map<String, dynamic>)['no'] as String,
    ).unwrap();
  });

  @override
  Future<LotteryPool> fetchLotteryPool() => _guard(() async {
    final resp = await _dio.get<Map<String, dynamic>>(
      '${AppConfig.apiPrefix}/lottery/pools',
    );
    return ApiResponse.fromJson(
      resp.data!,
      (data) => LotteryPool.fromJson(data as Map<String, dynamic>),
    ).unwrap();
  });

  @override
  Future<DrawResult> draw() => _guard(() async {
    final resp = await _dio.post<Map<String, dynamic>>(
      '${AppConfig.apiPrefix}/lottery/draw',
    );
    return ApiResponse.fromJson(
      resp.data!,
      (data) => DrawResult.fromJson(data as Map<String, dynamic>),
    ).unwrap();
  });

  @override
  Future<List<ExchangeRecord>> fetchExchangeRecords({
    int page = 1,
    int size = 20,
  }) => _guard(() async {
    final resp = await _dio.get<Map<String, dynamic>>(
      '${AppConfig.apiPrefix}/exchange/records',
      queryParameters: {'page': page, 'size': size},
    );
    return ApiResponse.fromJson(
      resp.data!,
      (data) => (data as List<dynamic>? ?? const [])
          .map((e) => ExchangeRecord.fromJson(e as Map<String, dynamic>))
          .toList(),
    ).unwrap();
  });

  Future<T> _guard<T>(Future<T> Function() action) async {
    try {
      return await action();
    } on DioException catch (e) {
      throw ApiException.fromDio(e);
    }
  }
}

/// Mock 实现：拥有/佩戴/售出状态会话内生效，余额走共享钱包。
class MallRepositoryMock implements MallRepository {
  static const _decoSeeds = [
    (11, '星河漫游', 120, 0),
    (12, '樱花之约', 80, 30),
    (13, '暗夜霓虹', 150, 0),
    (14, '碧海晴空', 60, 30),
    (15, '鎏金岁月', 300, 0),
    (16, '像素童话', 90, 30),
  ];

  static final Set<int> _owned = {12};
  static int? _worn;
  static final Set<int> _soldNos = {};
  static int _nextRecordId = 800;
  static final List<ExchangeRecord> _records = [
    ExchangeRecord(
      id: 799,
      kind: 1,
      name: '头像框「樱花之约」',
      cost: 80,
      createdAt: DateTime.now().subtract(const Duration(days: 2)),
    ),
    ExchangeRecord(
      id: 798,
      kind: 3,
      name: '积分抽奖',
      cost: 85,
      createdAt: DateTime.now().subtract(const Duration(days: 3)),
    ),
  ];

  static const _prettyNoSeeds = [
    (21, 'N888888', 3, 999),
    (22, 'N666666', 3, 899),
    (23, 'N520520', 2, 520),
    (24, 'N131420', 2, 480),
    (25, 'N100001', 2, 380),
    (26, 'N123321', 1, 200),
    (27, 'N456654', 1, 200),
    (28, 'N789987', 1, 180),
  ];

  static const _pool = LotteryPool(
    cost: 85,
    prizes: [
      LotteryPrize(id: 1, name: '10 忧珠', kind: 1, amount: 10, weight: 45),
      LotteryPrize(id: 2, name: '30 忧珠', kind: 1, amount: 30, weight: 25),
      LotteryPrize(id: 3, name: '88 忧珠', kind: 1, amount: 88, weight: 15),
      LotteryPrize(id: 4, name: '188 忧珠', kind: 1, amount: 188, weight: 8),
      LotteryPrize(id: 5, name: '头像框体验卡(30天)', kind: 2, amount: 1, weight: 6),
      LotteryPrize(id: 6, name: '888 忧珠', kind: 1, amount: 888, weight: 1),
    ],
  );

  @override
  Future<List<Decoration>> fetchDecorations() async {
    await Future<void>.delayed(const Duration(milliseconds: 450));
    return [
      for (final s in _decoSeeds)
        Decoration(
          id: s.$1,
          name: s.$2,
          preview: 'https://picsum.photos/seed/yiora-deco-${s.$1}/200/200',
          price: s.$3,
          durationDays: s.$4,
          owned: _owned.contains(s.$1),
        ),
    ];
  }

  @override
  Future<void> exchangeDecoration(int id) async {
    await Future<void>.delayed(const Duration(milliseconds: 500));
    final seed = _decoSeeds.firstWhere(
      (s) => s.$1 == id,
      orElse: () => throw const ApiException(code: 40400, message: '装扮不存在或已下架'),
    );
    if (_owned.contains(id)) {
      throw const ApiException(code: 42900, message: '已拥有该装扮，无需重复兑换');
    }
    if (MockYouzhuWallet.balance < seed.$3) {
      throw const ApiException(code: 40300, message: '忧珠余额不足');
    }
    _owned.add(id);
    MockYouzhuWallet.apply(
      bizType: 4,
      amount: -seed.$3,
      remark: '兑换头像框「${seed.$2}」',
    );
    _records.insert(
      0,
      ExchangeRecord(
        id: _nextRecordId++,
        kind: 1,
        name: '头像框「${seed.$2}」',
        cost: seed.$3,
        createdAt: DateTime.now(),
      ),
    );
  }

  @override
  Future<List<MyDecoration>> fetchMyDecorations() async {
    await Future<void>.delayed(const Duration(milliseconds: 400));
    return [
      for (final s in _decoSeeds.where((s) => _owned.contains(s.$1)))
        MyDecoration(
          decorationId: s.$1,
          name: s.$2,
          preview: 'https://picsum.photos/seed/yiora-deco-${s.$1}/200/200',
          worn: _worn == s.$1,
          expireAt: s.$4 > 0
              ? DateTime.now().add(Duration(days: s.$4 - 2))
              : null,
        ),
    ];
  }

  @override
  Future<void> wear(int id) async {
    await Future<void>.delayed(const Duration(milliseconds: 350));
    if (!_owned.contains(id)) {
      throw const ApiException(code: 40400, message: '未拥有该装扮或已过期');
    }
    _worn = id;
  }

  @override
  Future<void> takeOff(int id) async {
    await Future<void>.delayed(const Duration(milliseconds: 350));
    if (_worn == id) _worn = null;
  }

  @override
  Future<List<PrettyNo>> fetchPrettyNos({int page = 1, int size = 50}) async {
    await Future<void>.delayed(const Duration(milliseconds: 450));
    return [
      for (final s in _prettyNoSeeds.where((s) => !_soldNos.contains(s.$1)))
        PrettyNo(id: s.$1, no: s.$2, rarity: s.$3, price: s.$4),
    ];
  }

  @override
  Future<String> exchangePrettyNo(int id) async {
    await Future<void>.delayed(const Duration(milliseconds: 500));
    final seed = _prettyNoSeeds.firstWhere(
      (s) => s.$1 == id,
      orElse: () => throw const ApiException(code: 40400, message: '靓号不存在'),
    );
    if (_soldNos.contains(id)) {
      throw const ApiException(code: 42900, message: '手慢了，该靓号已被兑换');
    }
    if (MockYouzhuWallet.balance < seed.$4) {
      throw const ApiException(code: 40300, message: '忧珠余额不足');
    }
    _soldNos.add(id);
    MockYouzhuWallet.apply(
      bizType: 4,
      amount: -seed.$4,
      remark: '兑换靓号 ${seed.$2}',
    );
    _records.insert(
      0,
      ExchangeRecord(
        id: _nextRecordId++,
        kind: 2,
        name: '靓号 ${seed.$2}',
        cost: seed.$4,
        createdAt: DateTime.now(),
      ),
    );
    return seed.$2;
  }

  @override
  Future<LotteryPool> fetchLotteryPool() async {
    await Future<void>.delayed(const Duration(milliseconds: 400));
    return _pool;
  }

  @override
  Future<DrawResult> draw() async {
    await Future<void>.delayed(const Duration(milliseconds: 700));
    if (MockYouzhuWallet.balance < _pool.cost) {
      throw const ApiException(code: 40300, message: '忧珠余额不足');
    }
    MockYouzhuWallet.apply(bizType: 5, amount: -_pool.cost, remark: '积分抽奖消耗');

    // 按权重抽取
    final total = _pool.prizes.fold<int>(0, (sum, p) => sum + p.weight);
    var roll = Random().nextInt(total);
    var prize = _pool.prizes.first;
    for (final p in _pool.prizes) {
      if (roll < p.weight) {
        prize = p;
        break;
      }
      roll -= p.weight;
    }
    if (prize.kind == 1) {
      MockYouzhuWallet.apply(
        bizType: 5,
        amount: prize.amount,
        remark: '抽奖中奖「${prize.name}」',
      );
    }
    _records.insert(
      0,
      ExchangeRecord(
        id: _nextRecordId++,
        kind: 3,
        name: '积分抽奖 · ${prize.name}',
        cost: _pool.cost,
        createdAt: DateTime.now(),
      ),
    );
    return DrawResult(prize: prize, balance: MockYouzhuWallet.balance);
  }

  @override
  Future<List<ExchangeRecord>> fetchExchangeRecords({
    int page = 1,
    int size = 20,
  }) async {
    await Future<void>.delayed(const Duration(milliseconds: 400));
    final start = ((page - 1) * size).clamp(0, _records.length);
    final end = (start + size).clamp(0, _records.length);
    return _records.sublist(start, end);
  }
}

final mallRepositoryProvider = Provider<MallRepository>((ref) {
  if (AppConfig.useMock) return MallRepositoryMock();
  return MallRepositoryHttp(ref.watch(dioProvider));
});
