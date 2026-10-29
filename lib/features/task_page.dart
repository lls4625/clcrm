import 'package:flutter/material.dart';

import '../app_controller.dart';
import '../core/models.dart';
import '../ui/common.dart';
import '../ui/glass_bottom_navigation.dart';
import 'customer_pages.dart';
import 'editors.dart';

class TasksPage extends StatefulWidget {
  const TasksPage({super.key, required this.controller});
  final AppController controller;
  @override
  State<TasksPage> createState() => _TasksPageState();
}

class _TasksPageState extends State<TasksPage> {
  String filter = 'today';
  List<CrmRecord> records = [];
  bool loading = true;
  String? error;
  int request = 0;
  @override
  void initState() { super.initState(); widget.controller.addListener(load); load(); }
  @override
  void dispose() { request++; widget.controller.removeListener(load); super.dispose(); }
  Future<void> load() async {
    final current = ++request;
    if (mounted) setState(() { loading = true; error = null; });
    try {
      final list = await widget.controller.db.tasks(state: filter == 'completed' ? 'completed' : filter == 'canceled' ? 'canceled' : 'pending', window: filter);
      if (mounted && current == request) setState(() { records = list; loading = false; });
    } catch (_) { if (mounted && current == request) setState(() { loading = false; error = '待办读取失败'; }); }
  }
  List<CrmRecord> visible() {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final tomorrow = DateTime(now.year, now.month, now.day + 1);
    final weekEnd = DateTime(now.year, now.month, now.day + 8);
    return records.where((record) {
      final due = DateTime.parse(record.text('planned_at')).toLocal();
      return switch (filter) {
        'today' => !due.isBefore(today) && due.isBefore(tomorrow),
        'overdue' => due.isBefore(now),
        'future' => !due.isBefore(tomorrow) && due.isBefore(weekEnd),
        _ => true,
      };
    }).toList();
  }
  @override
  Widget build(BuildContext context) {
    final list = visible();
    return Scaffold(appBar: AppBar(title: const Text('待办'), actions: [
      IconButton(tooltip: '刷新待办', onPressed: load, icon: const Icon(Icons.refresh)),
    ]), body: Column(children: [
      SingleChildScrollView(scrollDirection: Axis.horizontal, padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Row(children: [for (final entry in {'today':'今日','overdue':'逾期','future':'未来7天',
          'all':'全部待办','completed':'已完成','canceled':'已取消'}.entries)
          Padding(padding: const EdgeInsets.only(right: 8), child: ChoiceChip(label: Text(entry.value),
            selected: filter == entry.key, onSelected: (_) { setState(() => filter = entry.key); load(); }))])),
      if (loading) const LinearProgressIndicator(),
      Expanded(child: error != null ? EmptyState(error!, action: TextButton(onPressed: load, child: const Text('重试')))
        : RefreshIndicator(onRefresh: load, child: ListView(
          padding: EdgeInsets.fromLTRB(16, 16, 16, AppBottomNavigation.contentBottomPadding(context)),
          physics: const AlwaysScrollableScrollPhysics(), children: [
            if (list.isEmpty) EmptyState(loading ? '正在读取' : '暂无对应跟进任务',
              icon: Icons.event_available_outlined),
            for (final task in list) Card(child: ListTile(contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              leading: Icon(task.text('status') == 'completed' ? Icons.check_circle_outline : Icons.event_note_outlined),
              title: Text(task.text('title')), subtitle: Text('${task.text('customer_name')}\n${displayTime(task.values['planned_at'])}'),
              onTap: () => openPage(context, CustomerDetailPage(controller: widget.controller, customerId: task.text('customer_id'))),
              trailing: task.text('status') == 'pending' ? PopupMenuButton<String>(tooltip: '任务操作',
                onSelected: (action) => taskAction(task, action), itemBuilder: (_) => const [
                  PopupMenuItem(value: 'complete', child: Text('记录结果并完成')),
                  PopupMenuItem(value: 'reschedule', child: Text('调整时间')),
                  PopupMenuItem(value: 'cancel', child: Text('取消任务')),
                ]) : Text(taskStates[task.text('status')] ?? ''))),
            if (records.length >= 200) const Padding(padding: EdgeInsets.all(12),
              child: Text('当前显示最早的 200 条任务。更多任务请在客户档案查看或导出 Excel。')),
          ]))),
    ]));
  }
  Future<void> taskAction(CrmRecord task, String action) async {
    if (action == 'complete') {
      await openPage(context, InteractionEditor(controller: widget.controller,
        customerId: task.text('customer_id'), task: task));
    } else if (action == 'reschedule') {
      final date = await selectDateTime(context, initial: DateTime.parse(task.text('planned_at')).toLocal());
      if (date == null || !mounted) return;
      if (await performAction(context, () => widget.controller.db.rescheduleTask(task, date, '')) && mounted) widget.controller.changed();
    } else if (action == 'cancel') {
      if (!await confirmAction(context, '取消跟进？', '任务将保留为已取消，不会生成实际联系记录。', confirm: '取消任务') || !mounted) return;
      if (await performAction(context, () => widget.controller.db.cancelTask(task)) && mounted) widget.controller.changed();
    }
  }
}
