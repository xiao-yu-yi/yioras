import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/config/app_config.dart';
import '../../../core/network/api_client.dart';
import '../../../core/network/api_exception.dart';
import '../../../core/network/api_response.dart';
import '../model/message_models.dart';

/// 消息域仓库接口；统一抛 [ApiException]。
/// 实时增量（WS 长连接）接入后，本仓库仅承担首屏快照与补拉。
abstract interface class MessagesRepository {
  Future<MessagesOverview> fetchOverview();

  Future<List<NotificationItem>> fetchNotifications(NotificationType type);
}

class MessagesRepositoryHttp implements MessagesRepository {
  MessagesRepositoryHttp(this._dio);

  final Dio _dio;

  @override
  Future<MessagesOverview> fetchOverview() => _guard(() async {
    final resp = await _dio.get<Map<String, dynamic>>(
      '${AppConfig.apiPrefix}/im/conversations',
    );
    return ApiResponse.fromJson(resp.data!, (data) {
      final map = data as Map<String, dynamic>;
      final unread = map['unreadByType'] as Map<String, dynamic>? ?? const {};
      return MessagesOverview(
        unreadByType: {
          for (final type in NotificationType.values)
            type: (unread['${type.value}'] as num?)?.toInt() ?? 0,
        },
        conversations: (map['list'] as List<dynamic>? ?? const [])
            .map((e) => ConversationSummary.fromJson(e as Map<String, dynamic>))
            .toList(),
      );
    }).unwrap();
  });

  @override
  Future<List<NotificationItem>> fetchNotifications(NotificationType type) =>
      _guard(() async {
        final resp = await _dio.get<Map<String, dynamic>>(
          '${AppConfig.apiPrefix}/notifications',
          queryParameters: {'type': type.value},
        );
        return ApiResponse.fromJson(
          resp.data!,
          (data) => ((data as Map<String, dynamic>)['list'] as List<dynamic>)
              .map((e) => NotificationItem.fromJson(e as Map<String, dynamic>))
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

/// Mock 实现：AI 管家置顶会话 + 私信样例 + 各类通知样例。
class MessagesRepositoryMock implements MessagesRepository {
  @override
  Future<MessagesOverview> fetchOverview() async {
    await Future<void>.delayed(const Duration(milliseconds: 500));
    final now = DateTime.now();
    return MessagesOverview(
      unreadByType: const {
        NotificationType.likeFav: 3,
        NotificationType.commentAt: 1,
        NotificationType.system: 2,
      },
      conversations: [
        ConversationSummary(
          id: 1,
          peerName: 'Yo酱',
          lastPreview: '你好呀，我是 Yo酱～有问题都可以问我哦',
          lastMsgAt: now.subtract(const Duration(minutes: 5)),
          unread: 1,
          isBot: true,
        ),
        ConversationSummary(
          id: 2,
          peerName: '小鱼干',
          peerAvatar: 'https://picsum.photos/seed/yiora-avatar-0/100/100',
          lastPreview: '那个脚本我发你邮箱了，记得查收',
          lastMsgAt: now.subtract(const Duration(hours: 2)),
          unread: 2,
        ),
        ConversationSummary(
          id: 3,
          peerName: '拾光者',
          peerAvatar: 'https://picsum.photos/seed/yiora-avatar-3/100/100',
          lastPreview: '[图片]',
          lastMsgAt: now.subtract(const Duration(days: 1)),
        ),
        ConversationSummary(
          id: 4,
          peerName: '绿萝',
          peerAvatar: 'https://picsum.photos/seed/yiora-avatar-5/100/100',
          lastPreview: '好的，明天见！',
          lastMsgAt: now.subtract(const Duration(days: 3)),
        ),
      ],
    );
  }

  @override
  Future<List<NotificationItem>> fetchNotifications(
    NotificationType type,
  ) async {
    await Future<void>.delayed(const Duration(milliseconds: 450));
    final now = DateTime.now();
    return switch (type) {
      NotificationType.likeFav => [
        NotificationItem(
          id: 11,
          type: type,
          actorName: '夜风',
          actorAvatar: 'https://picsum.photos/seed/yiora-avatar-2/100/100',
          content: '赞了你的帖子《安卓端夜间模式适配进度》',
          createdAt: now.subtract(const Duration(minutes: 30)),
        ),
        NotificationItem(
          id: 12,
          type: type,
          actorName: '喵呜',
          content: '收藏了你的帖子《本周影视安利》',
          createdAt: now.subtract(const Duration(hours: 5)),
        ),
        NotificationItem(
          id: 13,
          type: type,
          actorName: '深夜码农',
          content: '赞了你的评论「这个思路不错，学习了」',
          createdAt: now.subtract(const Duration(days: 1)),
          isRead: true,
        ),
      ],
      NotificationType.commentAt => [
        NotificationItem(
          id: 21,
          type: type,
          actorName: '柚子茶',
          content: '评论了你的帖子：期待夜间模式，眼睛有救了',
          createdAt: now.subtract(const Duration(hours: 1)),
        ),
        NotificationItem(
          id: 22,
          type: type,
          actorName: '小鱼干',
          content: '在帖子《Steam 夏促蹲点攻略》中 @ 了你',
          createdAt: now.subtract(const Duration(days: 2)),
          isRead: true,
        ),
      ],
      NotificationType.system => [
        NotificationItem(
          id: 31,
          type: type,
          content: '你的帖子《第一次用 Flutter 写长列表》已通过审核并发布',
          createdAt: now.subtract(const Duration(hours: 3)),
        ),
        NotificationItem(
          id: 32,
          type: type,
          content: '欢迎加入 Yiora！完成新手任务可领取忧珠奖励',
          createdAt: now.subtract(const Duration(days: 6)),
          isRead: true,
        ),
      ],
    };
  }
}

final messagesRepositoryProvider = Provider<MessagesRepository>((ref) {
  if (AppConfig.useMock) return MessagesRepositoryMock();
  return MessagesRepositoryHttp(ref.watch(dioProvider));
});

/// 消息主页快照
final messagesOverviewProvider = FutureProvider.autoDispose<MessagesOverview>((
  ref,
) {
  return ref.watch(messagesRepositoryProvider).fetchOverview();
});

/// 某一类通知列表（聚合页数据源）
final notificationsProvider = FutureProvider.autoDispose
    .family<List<NotificationItem>, NotificationType>((ref, type) {
      return ref.watch(messagesRepositoryProvider).fetchNotifications(type);
    });
