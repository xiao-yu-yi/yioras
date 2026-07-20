/// 信息流相对时间：刚刚 / N分钟前 / N小时前 / 昨天 / MM-dd / yyyy-MM-dd
String formatRelativeTime(DateTime time, {DateTime? now}) {
  final current = now ?? DateTime.now();
  final diff = current.difference(time);

  if (diff.inMinutes < 1) return '刚刚';
  if (diff.inHours < 1) return '${diff.inMinutes}分钟前';
  if (diff.inHours < 24 && current.day == time.day) return '${diff.inHours}小时前';

  final yesterday = current.subtract(const Duration(days: 1));
  if (time.year == yesterday.year &&
      time.month == yesterday.month &&
      time.day == yesterday.day) {
    return '昨天';
  }

  String pad(int n) => n.toString().padLeft(2, '0');
  if (time.year == current.year) return '${pad(time.month)}-${pad(time.day)}';
  return '${time.year}-${pad(time.month)}-${pad(time.day)}';
}

/// 计数缩写：1.2万 / 3456
String formatCount(int count) {
  if (count >= 10000) {
    final w = count / 10000;
    return w >= 100 ? '${w.round()}万' : '${w.toStringAsFixed(1)}万';
  }
  return count.toString();
}
