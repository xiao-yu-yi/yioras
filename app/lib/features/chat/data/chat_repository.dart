import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/config/app_config.dart';
import '../../../core/network/api_client.dart';
import '../../../core/network/api_exception.dart';
import '../../../core/network/api_response.dart';
import '../../messages/data/messages_repository.dart';
import '../../messages/model/message_models.dart';
import '../model/chat_message.dart';

/// 聊天仓库：会话信息 + 历史消息（实时收发走 WS 客户端）。
abstract interface class ChatRepository {
  Future<ConversationSummary> fetchConversation(int conversationId);

  /// 历史消息（时间升序返回；游标分页随消息量增长再加）
  Future<List<ChatMessage>> fetchHistory(int conversationId);
}

class ChatRepositoryHttp implements ChatRepository {
  ChatRepositoryHttp(this._dio);

  final Dio _dio;

  @override
  Future<ConversationSummary> fetchConversation(int conversationId) =>
      _guard(() async {
        final resp = await _dio.get<Map<String, dynamic>>(
          '${AppConfig.apiPrefix}/im/conversations/$conversationId',
        );
        return ApiResponse.fromJson(
          resp.data!,
          (data) => ConversationSummary.fromJson(data as Map<String, dynamic>),
        ).unwrap();
      });

  @override
  Future<List<ChatMessage>> fetchHistory(int conversationId) =>
      _guard(() async {
        final resp = await _dio.get<Map<String, dynamic>>(
          '${AppConfig.apiPrefix}/im/conversations/$conversationId/messages',
        );
        return ApiResponse.fromJson(resp.data!, (data) {
          final list =
              (data as Map<String, dynamic>)['list'] as List<dynamic>? ??
              const [];
          return list.map((e) {
            final json = e as Map<String, dynamic>;
            return ChatMessage(
              localId: 'srv-${json['msgId']}',
              msgId: (json['msgId'] as num).toInt(),
              conversationId: conversationId,
              text: json['text'] as String? ?? '',
              mine: json['mine'] as bool? ?? false,
              createdAt:
                  DateTime.tryParse(json['createdAt'] as String? ?? '') ??
                  DateTime.now(),
              seq: (json['seq'] as num?)?.toInt() ?? 0,
            );
          }).toList();
        }).unwrap();
      });

  Future<T> _guard<T>(Future<T> Function() action) async {
    try {
      return await action();
    } on DioException catch (e) {
      throw ApiException.fromDio(e);
    }
  }
}

/// Mock 实现：会话信息复用消息主页 Mock 数据，历史消息按会话生成。
class ChatRepositoryMock implements ChatRepository {
  ChatRepositoryMock({required this._messagesRepository});

  final MessagesRepository _messagesRepository;

  @override
  Future<ConversationSummary> fetchConversation(int conversationId) async {
    final overview = await _messagesRepository.fetchOverview();
    final conversation = overview.conversations
        .where((c) => c.id == conversationId)
        .firstOrNull;
    if (conversation == null) {
      throw const ApiException(code: 40400, message: '会话不存在');
    }
    return conversation;
  }

  @override
  Future<List<ChatMessage>> fetchHistory(int conversationId) async {
    await Future<void>.delayed(const Duration(milliseconds: 400));
    final now = DateTime.now();
    if (conversationId == 1) {
      // AI 管家开场白
      return [
        ChatMessage(
          localId: 'srv-1',
          msgId: 1,
          conversationId: conversationId,
          text: '你好呀，我是 Yo酱～有问题都可以问我哦',
          mine: false,
          createdAt: now.subtract(const Duration(minutes: 5)),
          seq: 1,
        ),
      ];
    }
    return [
      ChatMessage(
        localId: 'srv-1',
        msgId: 1,
        conversationId: conversationId,
        text: '在吗？',
        mine: false,
        createdAt: now.subtract(const Duration(hours: 3)),
        seq: 1,
      ),
      ChatMessage(
        localId: 'srv-2',
        msgId: 2,
        conversationId: conversationId,
        text: '在的，什么事～',
        mine: true,
        createdAt: now.subtract(const Duration(hours: 2, minutes: 50)),
        seq: 2,
      ),
      ChatMessage(
        localId: 'srv-3',
        msgId: 3,
        conversationId: conversationId,
        text: '那个脚本我发你邮箱了，记得查收',
        mine: false,
        createdAt: now.subtract(const Duration(hours: 2)),
        seq: 3,
      ),
    ];
  }
}

final chatRepositoryProvider = Provider<ChatRepository>((ref) {
  if (AppConfig.useMock) {
    return ChatRepositoryMock(
      messagesRepository: ref.watch(messagesRepositoryProvider),
    );
  }
  return ChatRepositoryHttp(ref.watch(dioProvider));
});
