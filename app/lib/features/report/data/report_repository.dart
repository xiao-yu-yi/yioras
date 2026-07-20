import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/config/app_config.dart';
import '../../../core/network/api_client.dart';
import '../../../core/network/api_exception.dart';
import '../../../core/network/api_response.dart';

/// 举报对象类型（对齐 server CreateReportReq targetType 1|2|3|4）
enum ReportTargetType {
  post(1, '帖子'),
  comment(2, '评论'),
  user(3, '用户'),
  message(4, '私信');

  const ReportTargetType(this.value, this.label);

  final int value;
  final String label;
}

/// 举报分类（对齐 server category 1|2|3|4|5）
enum ReportCategory {
  illegal(1, '违法违规'),
  porn(2, '色情低俗'),
  fraud(3, '诈骗骗钱'),
  infringement(4, '侵权盗用'),
  other(5, '其他问题');

  const ReportCategory(this.value, this.label);

  final int value;
  final String label;
}

/// 举报仓库：POST /reports 落举报单，后台工作台处置。
abstract interface class ReportRepository {
  /// 提交举报；同对象待处理期内重复提交会被服务端驳回（提示已举报过）
  Future<void> submit({
    required ReportTargetType targetType,
    required int targetId,
    required ReportCategory category,
    String reason,
  });
}

class ReportRepositoryHttp implements ReportRepository {
  ReportRepositoryHttp(this._dio);

  final Dio _dio;

  @override
  Future<void> submit({
    required ReportTargetType targetType,
    required int targetId,
    required ReportCategory category,
    String reason = '',
  }) async {
    try {
      final resp = await _dio.post<Map<String, dynamic>>(
        '${AppConfig.apiPrefix}/reports',
        data: {
          'targetType': targetType.value,
          'targetId': targetId,
          'category': category.value,
          if (reason.trim().isNotEmpty) 'reason': reason.trim(),
        },
      );
      ApiResponse.fromJson(resp.data!, (_) => null).unwrap();
    } on DioException catch (e) {
      throw ApiException.fromDio(e);
    }
  }
}

/// Mock 实现：记录同对象重复举报，模拟服务端防刷提示。
class ReportRepositoryMock implements ReportRepository {
  static final Set<String> _pending = {};

  @override
  Future<void> submit({
    required ReportTargetType targetType,
    required int targetId,
    required ReportCategory category,
    String reason = '',
  }) async {
    await Future<void>.delayed(const Duration(milliseconds: 600));
    final key = '${targetType.value}-$targetId';
    if (!_pending.add(key)) {
      throw const ApiException(code: 42900, message: '你已举报过，平台正在处理');
    }
  }
}

final reportRepositoryProvider = Provider<ReportRepository>((ref) {
  if (AppConfig.useMock) return ReportRepositoryMock();
  return ReportRepositoryHttp(ref.watch(dioProvider));
});
