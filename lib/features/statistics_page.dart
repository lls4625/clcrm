import 'package:flutter/material.dart' hide DataRow;

import '../app_controller.dart';
import '../core/models.dart';
import '../ui/common.dart';
import 'customer_pages.dart';

class StatisticsPage extends StatefulWidget {
  const StatisticsPage({super.key, required this.controller});
  final AppController controller;
  @override
  State<StatisticsPage> createState() => _StatisticsPageState();
}

class _StatisticsPageState extends State<StatisticsPage> {
  int months = 1;
  late DateTime end;
  late DateTime start;
  late Future<DataRow> result;
  @override
  void initState() { super.initState(); refresh(); }
  void refresh() {
    end = DateTime.now(); start = monthStartBoundary(end, months);
    result = widget.controller.db.statistics(start, end);
  }
  Future<void> drill(String? province) async {
    final rangeStart = start;
    final rangeEnd = end;
    final list = await widget.controller.db.contactedCustomers(rangeStart, rangeEnd, province: province);
    if (!mounted) return;
    await openPage(context, Scaffold(appBar: AppBar(title: Text(province == null ? '联系客户' : '$province · 联系客户')),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        Text('${timeLabel(rangeStart)} 至 ${timeLabel(rangeEnd)}'), const SizedBox(height: 12),
        if (list.isEmpty) const EmptyState('该范围没有联系客户'),
        for (final c in list) Card(child: ListTile(title: Text(c.text('name')),
          subtitle: Text('${c.text('province')} ${c.text('city')} · ${c.integer('interaction_count')} 次联系'),
          trailing: const Icon(Icons.chevron_right), onTap: () => openPage(context,
            CustomerDetailPage(controller: widget.controller, customerId: c.id)))),
      ])));
  }
  @override
  Widget build(BuildContext context) => Scaffold(appBar: AppBar(title: const Text('联系统计'), actions: [
    IconButton(tooltip: '刷新统计', onPressed: () => setState(refresh), icon: const Icon(Icons.refresh)),
  ]), body: ListView(padding: const EdgeInsets.all(16), children: [
    const Align(alignment: Alignment.centerLeft, child: Chip(label: Text('设备本地日历 · 统计预览'))),
    Wrap(spacing: 8, children: [for (final n in [1,2,3]) ChoiceChip(label: Text('近$n个月'),
      selected: months == n, onSelected: (_) => setState(() { months = n; refresh(); }))]),
    const SizedBox(height: 12), Text('${timeLabel(start)} 至 ${timeLabel(end)}'),
    const SizedBox(height: 20), FutureBuilder<DataRow>(future: result, builder: (context, snapshot) {
      if (snapshot.hasError) return EmptyState('统计读取失败', action: TextButton(
        onPressed: () => setState(refresh), child: const Text('重试')));
      if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
      final data = snapshot.data!;
      final regions = data['regions'] as List<DataRow>;
      return Column(children: [
        Section('本期实际联系', children: [
          ListTile(title: const Text('联系客户数'), trailing: Text('${data['customer_count']}'), onTap: () => performAction(context, () => drill(null))),
          ListTile(title: const Text('联系次数'), trailing: Text('${data['interaction_count']}')),
        ]),
        Section('按省 / 直辖市', children: regions.isEmpty ? [const EmptyState('暂无实际联系')]
          : regions.map((row) => ListTile(title: Text(row['province']?.toString() ?? '地区未完善'),
            subtitle: Text('${row['customer_count']} 个客户 · ${row['interaction_count']} 次联系'),
            trailing: const Icon(Icons.chevron_right), onTap: () => performAction(context, () => drill(row['province'] as String?)))).toList()),
      ]);
    }),
    ListTile(title: const Text('更多统计条件'), trailing: const Text('待完善'),
      onTap: () => openPage(context, const InfoPage(title: '更多统计条件', pending: true,
        body: '近7天、自定义区间、业务时区、联系人组合筛选、长期未联系及市区县下钻，待口径补充后接入。当前仅提供设备本地日历的近1/2/3个月只读预览，不用于尚未确认的组合统计验收。'))),
  ]));
}
