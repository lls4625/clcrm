import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../core/database.dart';
import '../core/models.dart';

/// Native requests are projections of tasks, never evidence of actual contact.
class LocalNotifications extends ChangeNotifier {
  LocalNotifications(this.db);
  final CrmDatabase db;
  static const channel = MethodChannel('vip.ichiki.javalee.clcrm/notifications');
  String authorization = 'unknown';
  String status = '尚未启用';
  int scheduled = 0;
  int waiting = 0;
  int failed = 0;
  bool enabled = false;
  bool privateContent = true;
  bool advanceDay = true;
  String? pendingTaskId;
  Future<void> _queue = Future.value();

  Future<void> initialize() async {
    final prefs = await db.preferences();
    enabled = prefs['reminder_enabled'] == 'true';
    privateContent = prefs['notice_private'] != 'false';
    advanceDay = prefs['reminder_advance_day'] != 'false';
    channel.setMethodCallHandler((call) async {
      if (call.method == 'openTask' && call.arguments is String) {
        pendingTaskId = call.arguments as String;
        notifyListeners();
      }
    });
    try { pendingTaskId = await channel.invokeMethod<String>('takePendingTask'); }
    catch (_) { /* Platform support is reported by reconcile. */ }
    await reconcile();
  }

  Future<void> configure({bool? active, bool? hideContent, bool? advance}) async {
    if (active != null) {
      if (active) {
        try {
          final granted = await channel.invokeMethod<bool>('requestPermission') ?? false;
          if (!granted) throw const UserFacingError('系统尚未允许通知，请在系统设置中检查 ClCrm 通知权限');
        } on MissingPluginException { throw const UserFacingError('当前平台未接入系统通知'); }
      }
      await db.setPreference('reminder_enabled', active.toString()); enabled = active;
    }
    if (hideContent != null) {
      await db.setPreference('notice_private', hideContent.toString()); privateContent = hideContent;
    }
    if (advance != null) {
      await db.setPreference('reminder_advance_day', advance.toString()); advanceDay = advance;
    }
    await reconcile();
  }

  Future<void> reconcile() {
    _queue = _queue.then((_) => _reconcile()).catchError((Object _) {
      status = '提醒协调失败，任务资料仍然保留'; failed = 1; notifyListeners();
    });
    return _queue;
  }

  Future<void> _reconcile() async {
    if (!Platform.isIOS) {
      authorization = 'unsupported'; status = '当前平台未接入通知'; notifyListeners(); return;
    }
    try {
      authorization = await channel.invokeMethod<String>('permissionState') ?? 'unknown';
      final tasks = await db.tasks(limit: 10000);
      final candidates = <Map<String, Object?>>[];
      final now = DateTime.now();
      if (enabled) {
        for (final task in tasks) {
          final due = DateTime.parse(task.text('planned_at'));
          for (final days in [0, if (advanceDay) 1]) {
            final local = due.toLocal();
            final fire = days == 0 ? due : DateTime(local.year, local.month, local.day - 1,
              local.hour, local.minute, local.second, local.millisecond, local.microsecond);
            if (!fire.isAfter(now)) continue;
            candidates.add({'id': 'clcrm.task.${task.id}.$days', 'taskId': task.id,
              'title': privateContent ? 'ClCrm 跟进提醒' : task.text('customer_name'),
              'body': privateContent ? '打开 ClCrm 查看跟进事项' : '${task.text('title')}\n${displayTime(task.values['planned_at'])}',
              'timestamp': fire.millisecondsSinceEpoch / 1000});
          }
        }
      }
      candidates.sort((a,b) => (a['timestamp'] as double).compareTo(b['timestamp'] as double));
      final selected = candidates.take(60).toList();
      final result = await channel.invokeMapMethod<String, dynamic>('replaceRequests', selected);
      scheduled = (result?['scheduled'] as num?)?.toInt() ?? 0;
      failed = (result?['failed'] as num?)?.toInt() ?? 0;
      waiting = candidates.length - scheduled - failed;
      if (waiting < 0) waiting = 0;
      status = !enabled ? '应用提醒未开启' : authorization != 'authorized' ? '系统未授权，任务仍在待办中'
        : '已排程 $scheduled 条 · 待排程 $waiting 条${failed == 0 ? '' : ' · 失败 $failed 条'}';
    } on MissingPluginException {
      authorization = 'unsupported'; status = '系统通知桥接尚不可用'; scheduled = 0;
    } catch (_) {
      status = '提醒协调失败，任务资料仍然保留'; failed = 1;
    }
    notifyListeners();
  }

  String? takeTask() {
    final id = pendingTaskId; pendingTaskId = null;
    if (id != null) channel.invokeMethod<void>('clearPendingTask').catchError((Object _) {});
    return id;
  }
  Future<void> openSettings() async {
    if (await channel.invokeMethod<bool>('openSettings') != true) {
      throw const UserFacingError('暂时无法打开系统设置');
    }
  }
}
