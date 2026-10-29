import 'package:flutter/material.dart';

import 'app_controller.dart';
import 'features/customer_pages.dart';
import 'features/settings_page.dart';
import 'features/task_page.dart';
import 'ui/common.dart';
import 'ui/glass_bottom_navigation.dart';

class HomeShell extends StatefulWidget {
  const HomeShell({super.key, required this.controller});
  final AppController controller;
  @override
  State<HomeShell> createState() => _HomeShellState();
}
class _HomeShellState extends State<HomeShell> with WidgetsBindingObserver {
  int tab = 0;
  bool opening = false;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    widget.controller.notifications.addListener(onNotification);
    WidgetsBinding.instance.addPostFrameCallback((_) => onNotification());
  }
  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    widget.controller.notifications.removeListener(onNotification);
    super.dispose();
  }
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      widget.controller.changed();
    }
  }
  void onNotification() {
    if (!mounted || opening) return;
    final id = widget.controller.notifications.takeTask();
    if (id == null) return;
    opening = true;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      await performAction(context, () async {
        final task = await widget.controller.db.task(id);
        if (!mounted) return;
        if (task == null) {
          await openPage(context, const InfoPage(title: '跟进提醒', body: '原任务不存在或已删除。'));
        } else {
          await openPage(context, CustomerDetailPage(controller: widget.controller, customerId: task.text('customer_id')));
        }
      });
      opening = false;
      if (mounted) onNotification();
    });
  }
  @override
  Widget build(BuildContext context) => Scaffold(extendBody: true, body: IndexedStack(index: tab, children: [
    TasksPage(controller: widget.controller), CustomersPage(controller: widget.controller),
    SettingsPage(controller: widget.controller),
  ]), bottomNavigationBar: MediaQuery.viewInsetsOf(context).bottom > 0 ? null : AppBottomNavigation(
    selectedIndex: tab,
    onSelected: (i) { if (i != tab) setState(() => tab = i); },
  ));
}
