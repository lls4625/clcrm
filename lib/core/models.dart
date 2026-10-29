import 'dart:math';

typedef DataRow = Map<String, Object?>;

String newId() {
  final random = Random.secure();
  final bytes = List<int>.generate(16, (_) => random.nextInt(256));
  bytes[6] = (bytes[6] & 15) | 64;
  bytes[8] = (bytes[8] & 63) | 128;
  final hex = bytes.map((v) => v.toRadixString(16).padLeft(2, '0')).join();
  return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-'
      '${hex.substring(12, 16)}-${hex.substring(16, 20)}-${hex.substring(20)}';
}

String utcText(DateTime value) {
  final d = value.toUtc();
  String two(int n) => n.toString().padLeft(2, '0');
  final fraction = (d.millisecond * 1000 + d.microsecond).toString().padLeft(6, '0');
  return '${d.year.toString().padLeft(4, '0')}-${two(d.month)}-${two(d.day)}'
    'T${two(d.hour)}:${two(d.minute)}:${two(d.second)}.${fraction}Z';
}
String utcNow() => utcText(DateTime.now());
String phoneKey(String value) => value.replaceAll(RegExp(r'[\s()（）\-]'), '');
String nameKey(String value) => value.trim().toLowerCase();
String dateLabel(DateTime date) => '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
String timeLabel(DateTime date) => '${dateLabel(date)} ${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
String displayTime(Object? value, {String empty = '未安排'}) {
  final date = DateTime.tryParse(value?.toString() ?? '');
  return date == null ? empty : timeLabel(date.toLocal());
}

class CrmRecord {
  CrmRecord(DataRow row) : values = Map.unmodifiable(row);
  final DataRow values;
  String get id => text('id');
  String text(String field, [String fallback = '']) => values[field]?.toString() ?? fallback;
  bool flag(String field) => values[field] == 1;
  int integer(String field) => (values[field] as num?)?.toInt() ?? 0;
  bool get deleted => values['deleted_at'] != null;
}

class PageResult {
  const PageResult(this.records, this.hasMore);
  final List<CrmRecord> records;
  final bool hasMore;
}

class UserFacingError implements Exception {
  const UserFacingError(this.message);
  final String message;
  @override
  String toString() => message;
}

class InteractionInput {
  const InteractionInput({required this.customerId, required this.occurredAt,
    required this.content, required this.method, this.contactId,
    this.nextAt, this.nextTitle = ''});
  final String customerId;
  final String? contactId;
  final DateTime occurredAt;
  final String content;
  final String method;
  final DateTime? nextAt;
  final String nextTitle;
}

const contactMethods = ['电话', '微信', '上门', '视频', '邮件', '其他'];
const purchaseStates = {'pending': '待确认', 'confirmed': '已成交'};
const taskStates = {'pending': '待处理', 'completed': '已完成', 'canceled': '已取消'};

/// No implicit midnight or next-action time is selected by these helpers.
DateTime monthStartBoundary(DateTime now, int months) {
  final target = DateTime(now.year, now.month - months, 1);
  final lastDay = DateTime(target.year, target.month + 1, 0).day;
  return DateTime(target.year, target.month, min(now.day, lastDay));
}
