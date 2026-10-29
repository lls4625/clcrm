import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../app_controller.dart';
import '../core/models.dart';
import '../ui/common.dart';
import '../ui/glass_bottom_navigation.dart';
import 'editors.dart';
import 'statistics_page.dart';

class CustomersPage extends StatefulWidget {
  const CustomersPage({super.key, required this.controller});
  final AppController controller;
  @override
  State<CustomersPage> createState() => _CustomersPageState();
}

class _CustomersPageState extends State<CustomersPage> {
  final search = TextEditingController();
  Timer? debounce;
  List<CrmRecord> records = [];
  List<CrmRecord> categories = [];
  String? category;
  String province = '', city = '', district = '';
  List<String> provinces = [], cities = [], districts = [];
  bool loading = true;
  bool more = false;
  String? error;
  int request = 0;
  @override
  void initState() { super.initState(); widget.controller.addListener(onChange); load(); }
  void onChange() { load(); }
  @override
  void dispose() { request++; debounce?.cancel(); widget.controller.removeListener(onChange); search.dispose(); super.dispose(); }
  Future<void> load({bool append = false}) async {
    final current = ++request;
    if (mounted) setState(() { loading = true; error = null; });
    try {
      final cats = await widget.controller.db.categories();
      final result = await widget.controller.db.customers(query: search.text,
        categoryId: category, province: province, city: city, district: district,
        offset: append ? records.length : 0);
      final provinceList = await widget.controller.db.regionOptions('province');
      final cityList = await widget.controller.db.regionOptions('city', province: province);
      final districtList = await widget.controller.db.regionOptions('district', province: province, city: city);
      if (!mounted || current != request) return;
      setState(() { categories = cats; records = append ? [...records, ...result.records] : result.records;
        provinces = provinceList; cities = cityList; districts = districtList;
        more = result.hasMore; loading = false; });
    } catch (_) {
      if (mounted && current == request) setState(() { loading = false; error = '客户资料加载失败，请重试'; });
    }
  }
  @override
  Widget build(BuildContext context) => Scaffold(appBar: AppBar(title: const Text('客户'), actions: [
    IconButton(tooltip: '联系统计', onPressed: () => openPage(context,
      StatisticsPage(controller: widget.controller)), icon: const Icon(Icons.bar_chart)),
    IconButton(tooltip: '新建客户', onPressed: () => openPage(context,
      CustomerEditor(controller: widget.controller)), icon: const Icon(Icons.add)),
  ]), body: Column(children: [
    Padding(padding: const EdgeInsets.fromLTRB(16, 8, 16, 8), child: TextField(controller: search,
      decoration: InputDecoration(hintText: '客户、曾用名、联系人或电话', prefixIcon: const Icon(Icons.search),
        suffixIcon: IconButton(tooltip: '清除搜索', onPressed: () { search.clear(); debounce?.cancel(); load(); }, icon: const Icon(Icons.close))),
      onChanged: (_) { debounce?.cancel(); debounce = Timer(const Duration(milliseconds: 250), () { load(); }); })),
    SingleChildScrollView(scrollDirection: Axis.horizontal, padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(children: [ChoiceChip(label: const Text('全部'), selected: category == null,
        onSelected: (_) { setState(() => category = null); load(); }),
        ...categories.map((c) => Padding(padding: const EdgeInsets.only(left: 8),
          child: ChoiceChip(label: Text(c.text('name')), selected: category == c.id,
            onSelected: (_) { setState(() => category = c.id); load(); }))),
      ])),
    SingleChildScrollView(scrollDirection: Axis.horizontal, padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(children: [
        regionMenu('全部省份', province, provinces, (v) { province = v; city = ''; district = ''; load(); }),
        const SizedBox(width: 12),
        regionMenu('全部城市', city, cities, province.isEmpty ? null : (v) { city = v; district = ''; load(); }),
        const SizedBox(width: 12),
        regionMenu('全部区县', district, districts, city.isEmpty ? null : (v) { district = v; load(); }),
      ])),
    if (loading) const Padding(padding: EdgeInsets.only(top: 8), child: LinearProgressIndicator()),
    Expanded(child: error != null ? EmptyState(error!, action: TextButton(onPressed: load, child: const Text('重试')))
      : RefreshIndicator(onRefresh: load, child: ListView.builder(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: EdgeInsets.fromLTRB(12, 12, 12, AppBottomNavigation.contentBottomPadding(context)),
        itemCount: records.isEmpty ? 1 : records.length + (more ? 1 : 0),
        itemBuilder: (context, index) {
          if (records.isEmpty) return EmptyState(loading ? '正在读取' : '暂无匹配客户',
            action: TextButton.icon(onPressed: () => openPage(context,
              CustomerEditor(controller: widget.controller)), icon: const Icon(Icons.add), label: const Text('新建客户')));
          if (index == records.length) return TextButton(onPressed: loading ? null : () => load(append: true), child: const Text('加载更多'));
          final c = records[index];
          return Card(child: ListTile(contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            leading: CircleAvatar(child: const Icon(Icons.business_outlined)),
            title: Text(c.text('name')), subtitle: Padding(padding: const EdgeInsets.only(top: 6), child: Text(
              '${c.text('province')} ${c.text('city')} ${c.text('district')}\n'
              '${c.text('primary_name').isEmpty ? '未指定主要联系人' : c.text('primary_name')}\n'
              '最近：${displayTime(c.values['last_contact'], empty: '尚未联系')}\n'
              '下次：${displayTime(c.values['next_contact'])}')),
            trailing: const Icon(Icons.chevron_right), onTap: () => openPage(context,
              CustomerDetailPage(controller: widget.controller, customerId: c.id))));
        }))),
  ]));

  Widget regionMenu(String label, String value, List<String> options, ValueChanged<String>? changed) =>
    DropdownButton<String>(value: value, underline: const SizedBox(),
      items: [DropdownMenuItem(value: '', child: Text(label)),
        ...{...options, if (value.isNotEmpty) value}.map((s) => DropdownMenuItem(value: s, child: Text(s)))],
      onChanged: changed == null ? null : (v) { if (v != null) changed(v); });
}

class CustomerDetailPage extends StatefulWidget {
  const CustomerDetailPage({super.key, required this.controller, required this.customerId});
  final AppController controller;
  final String customerId;
  @override
  State<CustomerDetailPage> createState() => _CustomerDetailPageState();
}

class _CustomerDetailPageState extends State<CustomerDetailPage> {
  CrmRecord? customer;
  List<CrmRecord> contacts = [], purchases = [], interactions = [], tasks = [];
  List<CrmRecord> categories = [];
  bool loading = true;
  String? error;
  int request = 0;
  @override
  void initState() { super.initState(); widget.controller.addListener(load); load(); }
  @override
  void dispose() { request++; widget.controller.removeListener(load); super.dispose(); }
  Future<void> load() async {
    final current = ++request;
    try {
      final c = await widget.controller.db.customer(widget.customerId);
      final people = await widget.controller.db.related('contacts', widget.customerId);
      final bought = await widget.controller.db.related('purchases', widget.customerId);
      final logs = await widget.controller.db.related('interactions', widget.customerId);
      final plans = await widget.controller.db.related('tasks', widget.customerId);
      final cats = await widget.controller.db.categories();
      if (!mounted || current != request) return;
      setState(() { customer = c; contacts = people; purchases = bought; interactions = logs;
        tasks = plans; categories = cats; loading = false; error = null; });
    } catch (_) { if (mounted && current == request) setState(() { loading = false; error = '客户档案读取失败'; }); }
  }
  String contactName(String id) {
    for (final c in contacts) { if (c.id == id) return c.text('name').isEmpty ? c.text('phone') : c.text('name'); }
    return id.isEmpty ? '未指定联系人' : '历史联系人';
  }
  @override
  Widget build(BuildContext context) {
    final c = customer;
    return Scaffold(appBar: AppBar(title: Text(c?.text('name') ?? '客户档案'), actions: [
      if (c != null) IconButton(tooltip: '编辑客户', onPressed: () => openPage(context,
        CustomerEditor(controller: widget.controller, customer: c)), icon: const Icon(Icons.edit_outlined)),
    ]), body: loading ? const Center(child: CircularProgressIndicator())
      : error != null ? EmptyState(error!, action: TextButton(onPressed: load, child: const Text('重试')))
      : c == null ? const EmptyState('客户不存在或已删除')
      : RefreshIndicator(onRefresh: load, child: ListView(padding: const EdgeInsets.all(16), children: [
        Text(c.text('name'), style: Theme.of(context).textTheme.headlineSmall), const SizedBox(height: 8),
        Text('${c.text('province')} ${c.text('city')} ${c.text('district')}'),
        const SizedBox(height: 16),
        Wrap(spacing: 8, runSpacing: 8, children: [
          FilledButton.icon(onPressed: () => openPage(context, InteractionEditor(controller: widget.controller,
            customerId: c.id)), icon: const Icon(Icons.note_add_outlined), label: const Text('记录联系')),
          OutlinedButton.icon(onPressed: () => openPage(context, TaskEditor(controller: widget.controller,
            customerId: c.id)), icon: const Icon(Icons.event_outlined), label: const Text('安排跟进')),
          OutlinedButton.icon(onPressed: () => openPage(context, ContactEditor(controller: widget.controller,
            customerId: c.id)), icon: const Icon(Icons.person_add_alt), label: const Text('添加联系人')),
        ]), const SizedBox(height: 16),
        Section('联系概览', children: [
          ValueLine('最近联系', displayTime(c.values['last_contact'], empty: '尚未联系')),
          ValueLine('下次联系', displayTime(c.values['next_contact'])),
        ]),
        Section('联系人', children: contacts.isEmpty ? [const EmptyState('暂无联系人')]
          : contacts.map((person) => ListTile(leading: Icon(person.flag('is_primary') ? Icons.star : Icons.person_outline),
            title: Text(person.text('name').isEmpty ? person.text('phone') : person.text('name')),
            subtitle: Text([person.text('phone'), person.text('position'), person.text('wechat')].where((s) => s.isNotEmpty).join(' · ')),
            trailing: Row(mainAxisSize: MainAxisSize.min, children: [
              IconButton(tooltip: '拨打电话', icon: const Icon(Icons.phone_outlined),
                onPressed: person.text('phone').isEmpty ? null : () async {
                  if (!await confirmAction(context, '拨打电话', person.text('phone'), confirm: '拨打') || !context.mounted) return;
                  await performAction(context, () async {
                    final opened = await const MethodChannel('vip.ichiki.javalee.clcrm/app_info')
                      .invokeMethod<bool>('dial', person.text('phone')) ?? false;
                    if (!opened) throw const UserFacingError('当前设备无法打开拨号功能');
                  });
                }),
              IconButton(tooltip: '复制电话号码', icon: const Icon(Icons.copy),
              onPressed: person.text('phone').isEmpty ? null : () async {
                await Clipboard.setData(ClipboardData(text: person.text('phone')));
                if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('电话号码已复制')));
              }),
            ]),
            onTap: () => openPage(context, ContactEditor(controller: widget.controller, customerId: c.id, contact: person)))).toList()),
        Section('购买记录', action: TextButton(onPressed: () => openPage(context,
          PurchaseEditor(controller: widget.controller, customerId: c.id)), child: const Text('添加')),
          children: purchases.isEmpty ? [const EmptyState('暂无购买记录')]
            : purchases.map((purchase) => ListTile(leading: const Icon(Icons.shopping_bag_outlined),
              title: Text(purchase.text('item_name')), subtitle: Text('${purchase.text('purchased_on')} · ${purchaseStates[purchase.text('status')] ?? ''}'),
              trailing: const Icon(Icons.chevron_right), onTap: () => openPurchase(purchase))).toList()),
        Section('联系历史', children: interactions.isEmpty ? [const EmptyState('尚未联系')]
          : interactions.map((record) => ListTile(isThreeLine: true, leading: const Icon(Icons.chat_bubble_outline),
            title: Text('${record.text('method')} · ${displayTime(record.values['occurred_at'])}'),
            subtitle: Text('${contactName(record.text('contact_id'))}\n${record.text('content')}', maxLines: 4, overflow: TextOverflow.ellipsis),
            onTap: () => openPage(context, InfoPage(title: '联系详情', body:
              '实际时间：${displayTime(record.values['occurred_at'])}\n'
              '录入时间：${displayTime(record.values['created_at'])}\n'
              '方式：${record.text('method')}\n联系人：${contactName(record.text('contact_id'))}\n\n${record.text('content')}')))).toList()),
        Section('跟进任务', children: tasks.isEmpty ? [const EmptyState('未安排跟进')]
          : tasks.map((task) => ListTile(title: Text(task.text('title')),
            subtitle: Text('${displayTime(task.values['planned_at'])} · ${taskStates[task.text('status')] ?? ''}'),
            trailing: task.text('status') == 'pending' ? const Icon(Icons.chevron_right) : null,
            onTap: task.text('status') != 'pending' ? null : () => openPage(context,
              InteractionEditor(controller: widget.controller, customerId: c.id, task: task)))).toList()),
        Section('基础资料', children: [ValueLine('客户编号', c.text('customer_no')),
          ValueLine('简称', c.text('short_name')), ValueLine('来源', c.text('source')),
          ValueLine('详细地址', c.text('address')), ValueLine('备注', c.text('note'))]),
        if ([contacts.length, purchases.length, interactions.length, tasks.length].any((n) => n >= 200))
          const Padding(padding: EdgeInsets.all(12), child: Text('详情分区当前最多展示 200 条，完整数据可通过 Excel 导出。')),
      ])));
  }
  Future<void> openPurchase(CrmRecord purchase) async {
    String category = '历史类别';
    for (final item in categories) { if (item.id == purchase.text('category_id')) category = item.text('name'); }
    final details = jsonDecode(purchase.text('details_json', '{}')) as Map<String, dynamic>;
    const labels = {'software_version':'软件版本', 'modules':'模块', 'license_quantity':'授权数量',
      'license_kind':'授权方式', 'license_expires_on':'授权到期日', 'maintenance_expires_on':'维护到期日',
      'style_no':'款号', 'color':'颜色', 'size':'尺码', 'delivery_on':'约定交货日',
      'service_scope':'服务范围', 'service_start_on':'服务开始日','service_end_on':'服务到期日',
      'agreed_times':'约定次数','agreed_hours':'约定工时'};
    await openPage(context, Scaffold(appBar: AppBar(title: Text(purchase.text('item_name'))),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        Section('购买资料', children: [ValueLine('日期', purchase.text('purchased_on')),
          ValueLine('类别', category), ValueLine('状态', purchaseStates[purchase.text('status')] ?? ''),
          ValueLine('内容', purchase.text('content')), ValueLine('经办联系人', contactName(purchase.text('contact_id'))),
          for (final entry in {'specification':'规格型号','quantity_text':'数量','unit':'单位','amount_text':'金额原文',
            'contract_no':'合同编号','delivery_status':'交付情况','note':'备注'}.entries)
            if (purchase.text(entry.key).isNotEmpty) ValueLine(entry.value, purchase.text(entry.key)),
        ]),
        if (details.isNotEmpty) Section('补充资料', children: [for (final entry in details.entries)
          if (entry.value.toString().isNotEmpty) ValueLine(labels[entry.key] ?? entry.key,
            entry.key == 'license_kind' ? (entry.value == 'permanent' ? '永久授权' : entry.value == 'term' ? '限期授权' : '') : entry.value.toString())]),
      ])));
  }
}
