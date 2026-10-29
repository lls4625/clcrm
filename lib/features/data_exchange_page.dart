import 'package:flutter/material.dart';

import '../app_controller.dart';
import '../services/xlsx_service.dart';
import '../ui/common.dart';

class DataExchangePage extends StatefulWidget {
  const DataExchangePage({super.key, required this.controller});
  final AppController controller;
  @override
  State<DataExchangePage> createState() => _DataExchangePageState();
}

class _DataExchangePageState extends State<DataExchangePage> {
  late final XlsxService service = XlsxService(widget.controller.db);
  bool busy = false;
  String? message;
  WorkbookPreview? preview;
  Future<void> execute(Future<void> Function() action) async {
    if (busy) return;
    setState(() { busy = true; message = null; });
    await performAction(context, action);
    if (mounted) setState(() { busy = false;
      if (service.auditIssue != null) message = '${message ?? ''}\n${service.auditIssue}';
    });
  }
  @override
  Widget build(BuildContext context) => PopScope(canPop: !busy, child: Scaffold(
    appBar: AppBar(title: const Text('表格与数据')), body: ListView(padding: const EdgeInsets.all(16), children: [
      if (busy) const LinearProgressIndicator(),
      Section('Excel 数据交换', children: [
        ListTile(leading: const Icon(Icons.file_open_outlined), title: const Text('选择 Excel 并预览'),
          subtitle: const Text('当前只读预览，不写入资料库'), onTap: busy ? null : () => execute(() async {
            final file = await service.pickPreview();
            if (mounted) setState(() { preview = file; message = file == null ? '已取消文件选择' : '文件已读取，尚未导入'; });
          })),
        ListTile(leading: const Icon(Icons.ios_share), title: const Text('导出全部业务资料'),
          subtitle: const Text('不含附件和全部设置，Excel 无密码'), onTap: busy ? null : () => execute(() async {
            if (!await confirmAction(context, '导出业务资料', '导出文件包含客户与联系内容，且未设置密码。继续选择保存位置？', confirm: '继续')) return;
            final saved = await service.export();
            if (mounted) setState(() => message = saved ? '系统文件保存已完成；iCloud上传状态请在“文件”中查看' : '已取消保存');
          })),
        ListTile(leading: const Icon(Icons.table_chart_outlined), title: const Text('导出空白模板'),
          onTap: busy ? null : () => execute(() async {
            final saved = await service.export(template: true);
            if (mounted) setState(() => message = saved ? '模板已交由系统保存' : '已取消保存');
          })),
      ]),
      if (message != null) Padding(padding: const EdgeInsets.only(bottom: 16), child: Text(message!)),
      if (preview != null) ...[
        Text(preview!.fileName, style: Theme.of(context).textTheme.titleMedium), const SizedBox(height: 12),
        for (final sheet in preview!.sheets) Card(child: ExpansionTile(
          title: Text(sheet.name), subtitle: Text('${sheet.rowCount} 行数据 · 预览最多10行'),
          children: [SingleChildScrollView(scrollDirection: Axis.horizontal, child: DataTable(
            columns: [const DataColumn(label: Text('行')), ...sheet.headers.asMap().entries.map((e) =>
              DataColumn(label: Text(e.value.isEmpty ? '列${e.key + 1}' : e.value)))],
            rows: sheet.samples.asMap().entries.map((entry) => DataRow(cells: [
              DataCell(Text('${entry.key + 2}')),
              ...List.generate(sheet.headers.length, (i) => DataCell(SizedBox(width: 150,
                child: Text(i < entry.value.length ? entry.value[i] : '', maxLines: 4, overflow: TextOverflow.ellipsis)))),
            ])).toList(),
          ))],
        )),
        const SizedBox(height: 12),
        Section('客户新增导入', children: [
          if (preview!.importIssues.isNotEmpty) Padding(padding: const EdgeInsets.all(16),
            child: Text(preview!.importIssues.join('\n'), style: TextStyle(color: Theme.of(context).colorScheme.error))),
          for (final row in preview!.newCustomers) ListTile(
            title: Text('第${row.line}行 · ${row.fields['name']}'),
            subtitle: Text('${row.fields['province']} ${row.fields['city']}${row.duplicates.isEmpty ? '' : '\n同名候选：${row.duplicates.join('；')}'}'),
            trailing: row.duplicates.isEmpty ? const Icon(Icons.add_circle_outline) : Checkbox(value: row.allowDuplicate,
              onChanged: busy ? null : (v) => setState(() => row.allowDuplicate = v ?? false))),
          if (preview!.newCustomers.any((r) => r.duplicates.isNotEmpty)) const Padding(padding: EdgeInsets.all(16),
            child: Text('勾选同名行表示仍作为独立客户新增，不会覆盖或合并。')),
          Padding(padding: const EdgeInsets.all(16), child: FilledButton(onPressed:
            busy || preview!.importIssues.isNotEmpty || preview!.newCustomers.any((r) => r.duplicates.isNotEmpty && !r.allowDuplicate)
              ? null : () => execute(() async {
                final batch = preview!;
                if (!await confirmAction(context, '新增客户', '本批将新增${batch.newCustomers.length}个客户，不覆盖已有资料。', confirm: '确认新增')) return;
                await widget.controller.db.importNewCustomers(batch.newCustomers.map((r) => {
                  ...r.fields, 'allow_duplicate': r.allowDuplicate,
                }).toList());
                widget.controller.changed();
                if (mounted) setState(() { message = '已整批新增${batch.newCustomers.length}个客户'; preview = null; });
              }), child: const Text('确认新增客户'))),
        ]),
        const Text('现有客户更新、联系人及其他关联资料导入待完善。空白模板可用于首次新增客户。'),
      ],
    ])));
}
