/// Compact relative timestamp for feed cards: "now", "5m", "3h", "2d",
/// then a date ("12 Mar", or "12 Mar 2025" for a different year).
String formatRelativeTime(DateTime time, {DateTime? now}) {
  final current = now ?? DateTime.now();
  final diff = current.difference(time);
  if (diff.isNegative || diff.inSeconds < 60) return 'now';
  if (diff.inMinutes < 60) return '${diff.inMinutes}m';
  if (diff.inHours < 24) return '${diff.inHours}h';
  if (diff.inDays < 7) return '${diff.inDays}d';
  const months = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];
  final date = '${time.day} ${months[time.month - 1]}';
  return time.year == current.year ? date : '$date ${time.year}';
}
