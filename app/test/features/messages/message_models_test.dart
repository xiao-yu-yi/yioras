import 'package:flutter_test/flutter_test.dart';
import 'package:yiora/features/messages/model/message_models.dart';

void main() {
  group('MessagesOverview', () {
    test('会话未读数汇总', () {
      final overview = MessagesOverview(
        unreadByType: const {},
        conversations: [
          ConversationSummary(id: 1, peerName: 'A', unread: 2),
          ConversationSummary(id: 2, peerName: 'B'),
          ConversationSummary(id: 3, peerName: 'C', unread: 5),
        ],
      );
      expect(overview.conversationUnread, 7);
    });
  });

  group('NotificationType', () {
    test('按值解析类型', () {
      expect(NotificationType.fromValue(1), NotificationType.likeFav);
      expect(NotificationType.fromValue(2), NotificationType.commentAt);
      expect(NotificationType.fromValue(3), NotificationType.system);
    });

    test('未知值回落系统通知', () {
      expect(NotificationType.fromValue(99), NotificationType.system);
    });
  });
}
