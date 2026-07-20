import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/config/app_config.dart';
import '../../../core/network/api_client.dart';
import '../../../core/network/api_exception.dart';
import '../../../core/network/api_response.dart';
import '../../feed/data/feed_repository.dart';
import '../model/user_profile.dart';

/// 用户域仓库：他人主页 / 关注关系 / 发起私信会话。
abstract interface class UserRepository {
  Future<UserProfile> fetchUserProfile(int uid);

  Future<void> follow(int uid);

  Future<void> unfollow(int uid);

  /// 发起（或复用）与 [peerId] 的单聊会话，返回会话 ID
  Future<int> openConversation(int peerId);
}

class UserRepositoryHttp implements UserRepository {
  UserRepositoryHttp(this._dio);

  final Dio _dio;

  @override
  Future<UserProfile> fetchUserProfile(int uid) => _guard(() async {
    final resp = await _dio.get<Map<String, dynamic>>(
      '${AppConfig.apiPrefix}/users/$uid',
    );
    return ApiResponse.fromJson(
      resp.data!,
      (data) => UserProfile.fromJson(data as Map<String, dynamic>),
    ).unwrap();
  });

  @override
  Future<void> follow(int uid) => _guard(() async {
    final resp = await _dio.post<Map<String, dynamic>>(
      '${AppConfig.apiPrefix}/users/$uid/follow',
    );
    ApiResponse.fromJson(resp.data!, (_) => null).unwrap();
  });

  @override
  Future<void> unfollow(int uid) => _guard(() async {
    final resp = await _dio.post<Map<String, dynamic>>(
      '${AppConfig.apiPrefix}/users/$uid/unfollow',
    );
    ApiResponse.fromJson(resp.data!, (_) => null).unwrap();
  });

  @override
  Future<int> openConversation(int peerId) => _guard(() async {
    final resp = await _dio.post<Map<String, dynamic>>(
      '${AppConfig.apiPrefix}/im/conversations',
      data: {'peerId': peerId},
    );
    return ApiResponse.fromJson(
      resp.data!,
      (data) =>
          ((data as Map<String, dynamic>)['conversationId'] as num).toInt(),
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

/// Mock 实现：资料与帖子从推荐流作者聚合生成；关注状态存内存。
class UserRepositoryMock implements UserRepository {
  UserRepositoryMock({required this._feedRepository});

  final FeedRepository _feedRepository;

  /// 会话内的关注集合
  static final Set<int> _followed = {};

  @override
  Future<UserProfile> fetchUserProfile(int uid) async {
    await Future<void>.delayed(const Duration(milliseconds: 450));
    final page = await _feedRepository.fetchRecommend(size: 100);
    final posts = page.list.where((p) => p.author.id == uid).toList();
    if (posts.isEmpty) {
      throw const ApiException(code: 40400, message: '用户不存在或已注销');
    }
    final author = posts.first.author;
    return UserProfile(
      id: author.id,
      displayNo: 'N${100000 + author.id}',
      nickname: author.nickname,
      avatar: author.avatar,
      cover: 'https://picsum.photos/seed/yiora-user-cover-$uid/800/360',
      signature: '热爱分享的 Yiora 用户',
      level: author.level,
      badge: author.badge,
      followCount: 80 + uid * 3,
      fansCount: 1200 + uid * 41,
      likeCount: 5600 + uid * 87,
      postCount: posts.length,
      following: _followed.contains(uid),
      posts: posts,
    );
  }

  @override
  Future<void> follow(int uid) async {
    await Future<void>.delayed(const Duration(milliseconds: 350));
    _followed.add(uid);
  }

  @override
  Future<void> unfollow(int uid) async {
    await Future<void>.delayed(const Duration(milliseconds: 350));
    _followed.remove(uid);
  }

  @override
  Future<int> openConversation(int peerId) async {
    await Future<void>.delayed(const Duration(milliseconds: 350));
    // Mock 会话数据固定，复用会话 2（小鱼干）演示聊天链路
    return 2;
  }
}

final userRepositoryProvider = Provider<UserRepository>((ref) {
  if (AppConfig.useMock) {
    return UserRepositoryMock(
      feedRepository: ref.watch(feedRepositoryProvider),
    );
  }
  return UserRepositoryHttp(ref.watch(dioProvider));
});

/// 他人主页资料（autoDispose family）
final userProfileProvider = FutureProvider.autoDispose.family<UserProfile, int>(
  (ref, uid) {
    return ref.watch(userRepositoryProvider).fetchUserProfile(uid);
  },
);
