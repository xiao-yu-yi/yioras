import 'package:flutter_test/flutter_test.dart';
import 'package:yiora/core/utils/time_format.dart';

void main() {
  group('formatRelativeTime', () {
    final now = DateTime(2026, 7, 20, 12, 0, 0);

    test('1 分钟内显示刚刚', () {
      expect(
        formatRelativeTime(now.subtract(const Duration(seconds: 30)), now: now),
        '刚刚',
      );
    });

    test('1 小时内显示分钟', () {
      expect(
        formatRelativeTime(now.subtract(const Duration(minutes: 5)), now: now),
        '5分钟前',
      );
    });

    test('当天显示小时', () {
      expect(
        formatRelativeTime(now.subtract(const Duration(hours: 3)), now: now),
        '3小时前',
      );
    });

    test('前一天显示昨天', () {
      expect(formatRelativeTime(DateTime(2026, 7, 19, 23, 0), now: now), '昨天');
    });

    test('同年显示月-日', () {
      expect(formatRelativeTime(DateTime(2026, 3, 5, 8, 0), now: now), '03-05');
    });

    test('跨年显示完整日期', () {
      expect(
        formatRelativeTime(DateTime(2025, 12, 31, 8, 0), now: now),
        '2025-12-31',
      );
    });
  });

  group('formatCount', () {
    test('万以下原样输出', () => expect(formatCount(3456), '3456'));
    test('万以上保留一位小数', () => expect(formatCount(12345), '1.2万'));
    test('百万级取整', () => expect(formatCount(1234567), '123万'));
  });
}
