import 'dart:async';

import 'package:flutter/material.dart';

import 'core/database.dart';
import 'services/notifications.dart';

class AppController extends ChangeNotifier {
  AppController(this.db) : notifications = LocalNotifications(db);
  final CrmDatabase db;
  final LocalNotifications notifications;
  Map<String, String> preferences = {};
  String? startupError;
  bool ready = false;
  int revision = 0;

  Future<void> initialize() async {
    try {
      await db.open();
      preferences = await db.preferences();
      try { await notifications.initialize(); } catch (_) { /* Core data remains available. */ }
      ready = true;
      startupError = null;
    } catch (_) {
      startupError = '本地资料库无法打开。原数据不会被清空，请保留现有数据并检查设备可用空间。';
    }
    notifyListeners();
  }

  ThemeMode get themeMode => switch (preferences['theme']) {
    'light' => ThemeMode.light, 'dark' => ThemeMode.dark, _ => ThemeMode.system,
  };
  bool get systemFont => preferences['font_system'] != 'false';
  double get fontScale => double.tryParse(preferences['font_scale'] ?? '') ?? 1;
  Future<void> setPreference(String key, String value) async {
    await db.setPreference(key, value);
    preferences = {...preferences, key: value};
    notifyListeners();
  }
  void changed() { revision++; notifyListeners(); unawaited(notifications.reconcile()); }
}
