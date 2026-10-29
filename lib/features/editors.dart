import 'package:flutter/material.dart';

import '../app_controller.dart';
import '../core/models.dart';
import '../ui/common.dart';

class CustomerEditor extends StatefulWidget {
  const CustomerEditor({super.key, required this.controller, this.customer});
  final AppController controller;
  final CrmRecord? customer;
  @override
  State<CustomerEditor> createState() => _CustomerEditorState();
}

class _CustomerEditorState extends State<CustomerEditor> {
  final form = GlobalKey<FormState>();
  late final Map<String, TextEditingController> fields;
  List<CrmRecord> categories = [];
  Set<String> selected = {};
  bool loaded = false;
  String? loadError;
  @override
  void initState() {
    super.initState();
    fields = {for (final key in ['name','province','city','district','address','short_name','source','note'])
      key: TextEditingController(text: widget.customer?.text(key) ?? '')};
    load();
  }
  Future<void> load() async {
    try {
      final list = await widget.controller.db.categories();
      final ids = widget.customer == null ? <String>{} : await widget.controller.db.customerCategoryIds(widget.customer!.id);
      if (mounted) setState(() { categories = list; selected = ids; loaded = true; });
    } catch (_) { if (mounted) setState(() => loadError = '业务类别读取失败，请返回后重试'); }
  }
  @override
  void dispose() { for (final field in fields.values) { field.dispose(); } super.dispose(); }
  Future<void> save() async {
    if (!loaded) throw const UserFacingError('资料尚未读取完成');
    final duplicates = await widget.controller.db.findCustomerDuplicates(fields['name']!.text,
      excluding: widget.customer?.id);
    if (duplicates.isNotEmpty) {
      if (!mounted) return;
      final proceed = await confirmAction(context, '发现同名客户',
        '${duplicates.map((c) => '${c.text('name')} · ${c.text('province')}${c.text('city')}').join('\n')}\n\n仍然保存为独立客户？', confirm: '仍然保存');
      if (!proceed) throw const UserFacingError('已取消保存，编辑内容已保留');
    }
    await widget.controller.db.saveCustomer({for (final entry in fields.entries) entry.key: entry.value.text},
      selected, existing: widget.customer);
    widget.controller.changed();
  }
  @override
  Widget build(BuildContext context) => EditorScaffold(title: widget.customer == null ? '新建客户' : '编辑客户',
    formKey: form, onSave: save, children: [
      textField(fields['name']!, '客户名称', isRequired: true),
      Row(children: [Expanded(child: textField(fields['province']!, '省 / 直辖市', isRequired: true)),
        const SizedBox(width: 12), Expanded(child: textField(fields['city']!, '市', isRequired: true))]),
      if (loadError != null) Text(loadError!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
      if (!loaded && loadError == null) const LinearProgressIndicator(),
      const Text('业务类别'), const SizedBox(height: 8),
      Wrap(spacing: 8, children: categories.where((c) => c.flag('enabled') || selected.contains(c.id))
        .map((c) => FilterChip(label: Text('${c.text('name')}${c.flag('enabled') ? '' : ' · 已停用'}'),
          selected: selected.contains(c.id), onSelected: (value) {
            if (value && !c.flag('enabled')) return;
            setState(() { if (value) { selected.add(c.id); } else { selected.remove(c.id); } });
          })).toList()),
      const SizedBox(height: 16),
      ExpansionTile(title: const Text('更多资料'), children: [
        textField(fields['district']!, '区县'), textField(fields['address']!, '详细地址'),
        textField(fields['short_name']!, '简称'), textField(fields['source']!, '客户来源'),
        textField(fields['note']!, '备注', lines: 3),
      ]),
    ]);
}

class ContactEditor extends StatefulWidget {
  const ContactEditor({super.key, required this.controller, required this.customerId, this.contact});
  final AppController controller;
  final String customerId;
  final CrmRecord? contact;
  @override
  State<ContactEditor> createState() => _ContactEditorState();
}

class _ContactEditorState extends State<ContactEditor> {
  late final Map<String, TextEditingController> fields;
  late bool primary;
  @override
  void initState() {
    super.initState();
    fields = {for (final key in ['name','phone','position','wechat'])
      key: TextEditingController(text: widget.contact?.text(key) ?? '')};
    primary = widget.contact?.flag('is_primary') ?? false;
  }
  @override
  void dispose() { for (final c in fields.values) { c.dispose(); } super.dispose(); }
  Future<void> save() async {
    if (fields['name']!.text.trim().isEmpty && fields['phone']!.text.trim().isEmpty) {
      throw const UserFacingError('姓名、电话至少填写一项');
    }
    final duplicates = await widget.controller.db.findPhoneDuplicates(fields['phone']!.text,
      excluding: widget.contact?.id);
    if (duplicates.isNotEmpty) {
      if (!mounted) return;
      if (!await confirmAction(context, '发现相同电话',
        '${duplicates.map((r) => '${r.text('customer_name')} · ${r.text('name')}').join('\n')}\n仍然保存？', confirm: '仍然保存')) {
        throw const UserFacingError('已取消保存，编辑内容已保留');
      }
    }
    await widget.controller.db.saveContact(widget.customerId,
      {for (final e in fields.entries) e.key: e.value.text.trim(), 'is_primary': primary ? 1 : 0}, existing: widget.contact);
    widget.controller.changed();
  }
  @override
  Widget build(BuildContext context) => EditorScaffold(title: widget.contact == null ? '添加联系人' : '编辑联系人',
    onSave: save, children: [textField(fields['name']!, '姓名'),
      textField(fields['phone']!, '电话', keyboard: TextInputType.phone),
      textField(fields['position']!, '职务'), textField(fields['wechat']!, '微信'),
      SwitchListTile.adaptive(contentPadding: EdgeInsets.zero, title: const Text('主要联系人'),
        value: primary, onChanged: (value) => setState(() => primary = value)),
    ]);
}

class InteractionEditor extends StatefulWidget {
  const InteractionEditor({super.key, required this.controller, required this.customerId, this.task});
  final AppController controller;
  final String customerId;
  final CrmRecord? task;
  @override
  State<InteractionEditor> createState() => _InteractionEditorState();
}

class _InteractionEditorState extends State<InteractionEditor> {
  final form = GlobalKey<FormState>();
  final content = TextEditingController();
  final nextTitle = TextEditingController();
  DateTime occurredAt = DateTime.now();
  DateTime? nextAt;
  String method = '电话';
  String? contactId;
  List<CrmRecord> contacts = [];
  bool loaded = false;
  @override
  void initState() {
    super.initState();
    contactId = widget.task?.text('contact_id');
    if (contactId == '') contactId = null;
    load();
  }
  Future<void> load() async {
    final ok = await performAction(context, () async {
      final list = await widget.controller.db.related('contacts', widget.customerId);
      if (mounted) setState(() { contacts = list; loaded = true;
        if (!contacts.any((c) => c.id == contactId)) contactId = null;
      });
    });
    if (!ok && mounted) setState(() => loaded = false);
  }
  @override
  void dispose() { content.dispose(); nextTitle.dispose(); super.dispose(); }
  Future<void> save() async {
    if (!loaded) throw const UserFacingError('联系人资料尚未加载，请返回重试');
    if (occurredAt.isAfter(DateTime.now())) {
      throw const UserFacingError('尚未发生的联系请先安排为跟进任务');
    }
    await widget.controller.db.recordInteraction(InteractionInput(customerId: widget.customerId,
      occurredAt: occurredAt, content: content.text, method: method, contactId: contactId,
      nextAt: nextAt, nextTitle: nextTitle.text), completingTaskId: widget.task?.id);
    widget.controller.changed();
  }
  @override
  Widget build(BuildContext context) => EditorScaffold(
    title: widget.task == null ? '记录联系' : '完成跟进', formKey: form, onSave: save, children: [
      if (widget.task != null) ...[Text(widget.task!.text('title'), style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 18)],
      DateField(label: '实际联系时间', value: occurredAt, onChanged: (value) => setState(() => occurredAt = value!)),
      contactDropdown(contacts, contactId, (id) => setState(() => contactId = id)),
      DropdownButtonFormField<String>(initialValue: method, decoration: const InputDecoration(labelText: '联系方式'),
        items: contactMethods.map((s) => DropdownMenuItem(value: s, child: Text(s))).toList(),
        onChanged: (value) => setState(() => method = value!)),
      const SizedBox(height: 14), textField(content, '联系内容', isRequired: true, lines: 4),
      const Divider(height: 32), Text('下一次跟进', style: Theme.of(context).textTheme.titleMedium),
      const SizedBox(height: 14),
      Wrap(spacing: 8, children: [for (final days in [1,3,7,30]) ActionChip(
        label: Text(days == 1 ? '明天' : '$days天后'), onPressed: () async {
          final now = DateTime.now();
          final date = DateTime(now.year, now.month, now.day + days);
          final time = await showTimePicker(context: context, initialTime: TimeOfDay.fromDateTime(nextAt ?? now));
          if (time != null && mounted) setState(() => nextAt = DateTime(date.year,date.month,date.day,time.hour,time.minute));
        })]),
      const SizedBox(height: 14),
      DateField(label: '下次联系时间（选填）', value: nextAt, clearable: true,
        onChanged: (value) => setState(() => nextAt = value)),
      if (nextAt != null) textField(nextTitle, '下次跟进事项', isRequired: true, lines: 2),
      ListTile(contentPadding: EdgeInsets.zero, leading: const Icon(Icons.attach_file),
        title: const Text('附件'), trailing: const Text('待完善'),
        onTap: () => openPage(context, const InfoPage(title: '联系附件', pending: true,
          body: '附件类型、容量和安全落盘协议待补充，当前不接收附件文件。'))),
    ]);
}

Widget contactDropdown(List<CrmRecord> contacts, String? selected, ValueChanged<String?> onChanged) =>
  Padding(padding: const EdgeInsets.only(bottom: 14), child: DropdownButtonFormField<String>(
    key: ValueKey('contact-$selected-${contacts.length}'), initialValue: selected ?? '',
    isExpanded: true, decoration: const InputDecoration(labelText: '联系人（选填）'),
    items: [const DropdownMenuItem(value: '', child: Text('不指定联系人')),
      ...contacts.map((c) => DropdownMenuItem(value: c.id,
        child: Text(c.text('name').isEmpty ? c.text('phone') : c.text('name'))))],
    onChanged: (value) => onChanged(value == '' ? null : value)));

class TaskEditor extends StatefulWidget {
  const TaskEditor({super.key, required this.controller, required this.customerId});
  final AppController controller;
  final String customerId;
  @override
  State<TaskEditor> createState() => _TaskEditorState();
}

class _TaskEditorState extends State<TaskEditor> {
  final form = GlobalKey<FormState>();
  final title = TextEditingController();
  DateTime? due;
  String? contactId;
  List<CrmRecord> contacts = [];
  bool loaded = false;
  @override
  void initState() { super.initState(); load(); }
  Future<void> load() async {
    await performAction(context, () async {
      final list = await widget.controller.db.related('contacts', widget.customerId);
      if (mounted) setState(() { contacts = list; loaded = true; });
    });
  }
  @override
  void dispose() { title.dispose(); super.dispose(); }
  @override
  Widget build(BuildContext context) => EditorScaffold(title: '安排跟进', formKey: form,
    onSave: () async {
      if (!loaded) throw const UserFacingError('资料未加载完成，请返回重试');
      if (due == null) throw const UserFacingError('请选择完整的跟进日期与时间');
      await widget.controller.db.createTask(widget.customerId, title.text, due!, contactId: contactId);
      widget.controller.changed();
    }, children: [textField(title, '跟进事项', isRequired: true, lines: 2),
      contactDropdown(contacts, contactId, (id) => setState(() => contactId = id)),
      DateField(label: '计划联系时间', value: due, onChanged: (v) => setState(() => due = v)),
      ListTile(contentPadding: EdgeInsets.zero, leading: const Icon(Icons.notifications_none),
        title: const Text('系统本地提醒'), subtitle: Text(widget.controller.notifications.status)),
    ]);
}

class PurchaseEditor extends StatefulWidget {
  const PurchaseEditor({super.key, required this.controller, required this.customerId});
  final AppController controller;
  final String customerId;
  @override
  State<PurchaseEditor> createState() => _PurchaseEditorState();
}

class _PurchaseEditorState extends State<PurchaseEditor> {
  final form = GlobalKey<FormState>();
  final fields = {for (final key in ['item_name','content','specification','quantity_text','unit',
    'amount_text','contract_no','delivery_status','note','software_version','modules','license_quantity',
    'style_no','color','size','service_scope','agreed_times','agreed_hours']) key: TextEditingController()};
  final dates = <String, DateTime?>{};
  DateTime purchasedOn = DateTime.now();
  String? categoryId;
  String? contactId;
  String status = 'pending';
  String licenseKind = '';
  List<CrmRecord> categories = [];
  List<CrmRecord> contacts = [];
  bool loaded = false;
  @override
  void initState() { super.initState(); load(); }
  Future<void> load() async {
    await performAction(context, () async {
      final cats = await widget.controller.db.categories();
      final people = await widget.controller.db.related('contacts', widget.customerId);
      if (mounted) setState(() { categories = cats.where((c) => c.flag('enabled')).toList();
        contacts = people; loaded = true; });
    });
  }
  @override
  void dispose() { for (final c in fields.values) { c.dispose(); } super.dispose(); }
  String get kind {
    for (final c in categories) { if (c.id == categoryId) return c.text('kind'); }
    return 'general';
  }
  Widget detailDate(String key, String label) => DateField(label: label, value: dates[key],
    dateOnly: true, clearable: true, onChanged: (v) => setState(() => dates[key] = v));
  Future<void> save() async {
    if (!loaded || categoryId == null) throw const UserFacingError('请选择业务类别');
    final data = <String, Object?>{for (final e in fields.entries) e.key: e.value.text.trim(),
      'category_id': categoryId, 'contact_id': contactId, 'status': status, 'purchased_on': dateLabel(purchasedOn)};
    final detailKeys = switch (kind) {
      'software' => ['software_version','modules','license_quantity'],
      'clothing' => ['style_no','color','size'],
      'service' => ['service_scope','agreed_times','agreed_hours'],
      _ => <String>[],
    };
    final dateKeys = switch (kind) {
      'software' => ['license_expires_on','maintenance_expires_on'],
      'clothing' => ['delivery_on'],
      'service' => ['service_start_on','service_end_on'],
      _ => <String>[],
    };
    final details = <String, Object?>{for (final key in detailKeys) key: fields[key]!.text.trim(),
      for (final key in dateKeys) if (dates[key] != null && !(key == 'license_expires_on' && licenseKind == 'permanent'))
        key: dateLabel(dates[key]!),
      if (kind == 'software') 'license_kind': licenseKind};
    await widget.controller.db.savePurchase(widget.customerId, data, details);
    widget.controller.changed();
  }
  @override
  Widget build(BuildContext context) => EditorScaffold(title: '添加购买记录', formKey: form, onSave: save, children: [
    DateField(label: '购买日期', value: purchasedOn, dateOnly: true,
      onChanged: (v) => setState(() => purchasedOn = v!)),
    DropdownButtonFormField<String>(initialValue: categoryId, isExpanded: true,
      decoration: const InputDecoration(labelText: '业务类别'),
      items: categories.map((c) => DropdownMenuItem(value: c.id, child: Text(c.text('name')))).toList(),
      onChanged: (id) => setState(() => categoryId = id), validator: (v) => v == null ? '请选择业务类别' : null),
    const SizedBox(height: 14), textField(fields['item_name']!, '商品或服务名称', isRequired: true),
    Align(alignment: Alignment.centerLeft, child: TextButton.icon(icon: const Icon(Icons.history),
      label: const Text('选择已录入名称'), onPressed: () async {
        await performAction(context, () async {
          final names = await widget.controller.db.purchaseNames(categoryId);
          if (!mounted) return;
          if (names.isEmpty) {
            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('暂无历史名称，可直接填写'))); return;
          }
          final selected = await showModalBottomSheet<String>(context: context, showDragHandle: true,
            builder: (ctx) => SafeArea(child: ListView(children: names.map((name) => ListTile(
              title: Text(name), onTap: () => Navigator.pop(ctx, name))).toList())));
          if (selected != null && mounted) setState(() => fields['item_name']!.text = selected);
        });
      })),
    textField(fields['content']!, '购买内容', isRequired: true, lines: 3),
    DropdownButtonFormField<String>(initialValue: status, decoration: const InputDecoration(labelText: '购买状态'),
      items: purchaseStates.entries.map((e) => DropdownMenuItem(value: e.key, child: Text(e.value))).toList(),
      onChanged: (v) => setState(() => status = v!)),
    const SizedBox(height: 14), contactDropdown(contacts, contactId, (v) => setState(() => contactId = v)),
    ExpansionTile(title: const Text('通用选填资料'), children: [
      textField(fields['specification']!, '规格型号'), textField(fields['quantity_text']!, '数量（原文）'),
      textField(fields['unit']!, '单位'), textField(fields['amount_text']!, '金额（原文，暂不汇总）'),
      textField(fields['contract_no']!, '订单或合同编号'), textField(fields['delivery_status']!, '交付情况'),
      textField(fields['note']!, '备注', lines: 2),
    ]),
    if (kind == 'software') ExpansionTile(title: const Text('软件资料'), children: [
      textField(fields['software_version']!, '软件版本'), textField(fields['modules']!, '模块'),
      textField(fields['license_quantity']!, '授权数量（原文）'),
      DropdownButtonFormField<String>(initialValue: licenseKind, decoration: const InputDecoration(labelText: '授权方式'),
        items: const [DropdownMenuItem(value: '', child: Text('未填写')),
          DropdownMenuItem(value: 'permanent', child: Text('永久授权')),
          DropdownMenuItem(value: 'term', child: Text('限期授权'))],
        onChanged: (v) => setState(() => licenseKind = v!)),
      const SizedBox(height: 14),
      if (licenseKind != 'permanent') detailDate('license_expires_on', '授权到期日'),
      detailDate('maintenance_expires_on', '维护到期日'),
    ]),
    if (kind == 'clothing') ExpansionTile(title: const Text('服装资料'), children: [
      textField(fields['style_no']!, '款号'), textField(fields['color']!, '颜色'),
      textField(fields['size']!, '尺码'), detailDate('delivery_on', '约定交货日'),
    ]),
    if (kind == 'service') ExpansionTile(title: const Text('服务资料'), children: [
      textField(fields['service_scope']!, '服务范围', lines: 2), detailDate('service_start_on', '服务开始日'),
      detailDate('service_end_on', '服务到期日'), textField(fields['agreed_times']!, '约定次数（原文）'),
      textField(fields['agreed_hours']!, '约定工时（原文）'),
    ]),
    ListTile(contentPadding: EdgeInsets.zero, leading: const Icon(Icons.attach_file), title: const Text('附件'),
      trailing: const Text('待完善'), onTap: () => openPage(context, const InfoPage(
        title: '购买附件', pending: true, body: '附件容量、类型与安全落盘协议待补充。当前仅保存文字资料。'))),
    const Padding(padding: EdgeInsets.only(top: 12), child: Text('到期自动提醒待完善，录入到期日不会自动排程。')),
  ]);
}
