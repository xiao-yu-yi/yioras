import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/config/app_config.dart';
import '../../../core/network/api_client.dart';
import '../../../core/network/api_response.dart';
import '../model/software.dart';

/// 软件库域 API（文档 3.6 / server routes：GET /software 列表、/software/:id 详情、
/// POST /software/:id/download 下载解析）。列表为页码分页，data 直接是数组。
class SoftwareApi {
  SoftwareApi(this._dio);

  final Dio _dio;

  /// GET /software?type=&categoryId=&sort=&page=&size=
  Future<List<SoftwareItem>> fetchList({
    int type = 0,
    int categoryId = 0,
    SoftwareSort sort = SoftwareSort.newest,
    int page = 1,
    int size = 20,
  }) async {
    final resp = await _dio.get<Map<String, dynamic>>(
      '${AppConfig.apiPrefix}/software',
      queryParameters: {
        if (type > 0) 'type': type,
        if (categoryId > 0) 'categoryId': categoryId,
        'sort': sort.value,
        'page': page,
        'size': size,
      },
    );
    return ApiResponse.fromJson(
      resp.data!,
      (data) => (data as List<dynamic>? ?? const [])
          .map((e) => SoftwareItem.fromJson(e as Map<String, dynamic>))
          .toList(),
    ).unwrap();
  }

  /// GET /software/:id 详情（介绍图/发布者/版本列表）
  Future<SoftwareDetail> fetchDetail(int id) async {
    final resp = await _dio.get<Map<String, dynamic>>(
      '${AppConfig.apiPrefix}/software/$id',
    );
    return ApiResponse.fromJson(
      resp.data!,
      (data) => SoftwareDetail.fromJson(data as Map<String, dynamic>),
    ).unwrap();
  }

  /// POST /software/:id/download 记下载数并返回链接（versionId=0 取最新已发布版）
  Future<SoftwareDownload> resolveDownload(int id, {int versionId = 0}) async {
    final resp = await _dio.post<Map<String, dynamic>>(
      '${AppConfig.apiPrefix}/software/$id/download',
      data: {'versionId': versionId},
    );
    return ApiResponse.fromJson(
      resp.data!,
      (data) => SoftwareDownload.fromJson(data as Map<String, dynamic>),
    ).unwrap();
  }

  /// GET /software/mine 我的发布（含审核状态，登录态）
  Future<List<SoftwareItem>> fetchMine({int page = 1, int size = 20}) async {
    final resp = await _dio.get<Map<String, dynamic>>(
      '${AppConfig.apiPrefix}/software/mine',
      queryParameters: {'page': page, 'size': size},
    );
    return ApiResponse.fromJson(
      resp.data!,
      (data) => (data as List<dynamic>? ?? const [])
          .map((e) => SoftwareItem.fromJson(e as Map<String, dynamic>))
          .toList(),
    ).unwrap();
  }

  /// GET /software/categories?type= 分类（data 为 CategoryItem 数组）
  Future<List<SoftwareCategory>> fetchCategories(int type) async {
    final resp = await _dio.get<Map<String, dynamic>>(
      '${AppConfig.apiPrefix}/software/categories',
      queryParameters: {if (type > 0) 'type': type},
    );
    return ApiResponse.fromJson(
      resp.data!,
      (data) => (data as List<dynamic>? ?? const [])
          .map((e) => SoftwareCategory.fromJson(e as Map<String, dynamic>))
          .toList(),
    ).unwrap();
  }
}

final softwareApiProvider = Provider<SoftwareApi>((ref) {
  return SoftwareApi(ref.watch(dioProvider));
});
