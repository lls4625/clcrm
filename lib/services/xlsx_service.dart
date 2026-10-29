import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:excel/excel.dart';
import 'package:file_picker/file_picker.dart';

import '../core/database.dart';
import '../core/models.dart';

const sheetNames = {'customers':'客户', 'contacts':'联系人', 'categories':'业务类别',
  'customer_categories':'客户类别关联', 'purchases':'购买记录', 'interactions':'联系记录',
  'tasks':'跟进任务', 'customer_aliases':'客户曾用名', 'task_changes':'任务改期历史'};

const exchangeColumns = <String, Map<String, String>>{
  'customers': {'id':'内部ID','customer_no':'客户编号','name':'客户名称','province':'省','city':'市',
    'district':'区县','address':'详细地址','short_name':'简称','source':'来源','note':'备注',
    'created_at':'创建时间UTC','updated_at':'修改时间UTC','record_version':'记录版本','deleted_at':'删除时间UTC'},
  'contacts': {'id':'内部ID','customer_id':'所属客户ID','name':'姓名','phone':'电话','position':'职务',
    'wechat':'微信','is_primary':'主要联系人标记','created_at':'创建时间UTC','updated_at':'修改时间UTC',
    'record_version':'记录版本','deleted_at':'删除时间UTC'},
  'categories': {'id':'内部ID','name':'类别名称','kind':'固定类型','enabled':'启用标记','sort_order':'排序',
    'created_at':'创建时间UTC','updated_at':'修改时间UTC','record_version':'记录版本','deleted_at':'删除时间UTC'},
  'customer_categories': {'customer_id':'客户ID','category_id':'类别ID'},
  'purchases': {'id':'内部ID','customer_id':'客户ID','contact_id':'联系人ID','category_id':'类别ID',
    'purchased_on':'购买日期','item_name':'商品或服务名称','content':'购买内容','status':'购买状态代码',
    'specification':'规格型号','quantity_text':'数量原文','unit':'单位','amount_text':'金额原文',
    'contract_no':'合同编号','delivery_status':'交付情况','note':'备注','details_json':'分类补充字段JSON',
    'created_at':'创建时间UTC','updated_at':'修改时间UTC','record_version':'记录版本','deleted_at':'删除时间UTC'},
  'interactions': {'id':'内部ID','customer_id':'客户ID','contact_id':'联系人ID','occurred_at':'实际联系时间UTC',
    'method':'联系方法','content':'联系内容','source_task_id':'完成来源任务ID',
    'created_at':'创建时间UTC','updated_at':'修改时间UTC','record_version':'记录版本','deleted_at':'删除时间UTC'},
  'tasks': {'id':'内部ID','customer_id':'客户ID','contact_id':'联系人ID','title':'跟进事项','planned_at':'计划时间UTC',
    'status':'任务状态代码','completed_at':'完成时间UTC','canceled_at':'取消时间UTC',
    'source_interaction_id':'来源联系ID','result_interaction_id':'完成结果联系ID',
    'created_at':'创建时间UTC','updated_at':'修改时间UTC','record_version':'记录版本','deleted_at':'删除时间UTC'},
  'customer_aliases': {'id':'内部ID','customer_id':'客户ID','name':'曾用名','recorded_at':'记录时间UTC'},
  'task_changes': {'id':'内部ID','task_id':'任务ID','old_planned_at':'原计划时间UTC',
    'new_planned_at':'新计划时间UTC','changed_at':'改期时间UTC','reason':'改期原因'},
};

class SheetPreview {
  const SheetPreview(this.name, this.headers, this.samples, this.rowCount);
  final String name;
  final List<String> headers;
  final List<List<String>> samples;
  final int rowCount;
}

class WorkbookPreview {
  const WorkbookPreview(this.fileName, this.sheets, this.newCustomers, this.importIssues);
  final String fileName;
  final List<SheetPreview> sheets;
  final List<NewCustomerRow> newCustomers;
  final List<String> importIssues;
}

class NewCustomerRow {
  NewCustomerRow(this.line, this.fields, this.duplicates);
  final int line;
  final DataRow fields;
  final List<String> duplicates;
  bool allowDuplicate = false;
}

class XlsxService {
  XlsxService(this.db);
  final CrmDatabase db;
  bool _active = false;
  String? auditIssue;
  // Defensive parser ceilings for this initial implementation, not promised capacity.
  static const maxFileBytes = 10 * 1024 * 1024;
  static const maxExpandedBytes = 60 * 1024 * 1024;

  Future<T> _exclusive<T>(Future<T> Function() operation) async {
    if (_active) throw const UserFacingError('已有文件操作正在进行');
    _active = true;
    auditIssue = null;
    try { return await operation(); } finally { _active = false; }
  }

  Future<bool> export({bool template = false}) => _exclusive(() async {
    final data = template ? <String, List<DataRow>>{} : await db.exportSnapshot();
    final book = Excel.createExcel();
    final guide = book['说明'];
    guide.appendRow([TextCellValue('ClCrm 业务资料 ${template ? '模板' : '导出'}')]);
    for (final line in ['无密码Excel文件；不是完整应用备份，不包含附件或全部设置。',
      'ID、手机号与编号按文本保存；时间字段标明UTC；日期字段使用YYYY-MM-DD。',
      '购买状态：pending=待确认，confirmed=已成交。任务状态：pending/completed/canceled。',
      '当前仅支持客户表的新增导入：客户名称、省、市必填，内部ID与客户编号留空，其他业务表保持空白。',
      '更新、清空和跨库合并规则未定；含已有ID的文件只预览，不覆盖本机资料。',
      '完整备份及所属用户校验待完善，不能以此工作簿替代完整备份。']) {
      guide.appendRow([TextCellValue(line)]);
    }
    final meta = book['_ClCrmSchema'];
    meta.appendRow([TextCellValue('ClCrmExchange'), TextCellValue('1')]);
    for (final entry in exchangeColumns.entries) {
      final sheet = book[sheetNames[entry.key]!];
      sheet.appendRow(entry.value.values.map(TextCellValue.new).toList());
      meta.appendRow([TextCellValue(sheetNames[entry.key]!), ...entry.value.keys.map(TextCellValue.new)]);
      for (final row in data[entry.key] ?? <DataRow>[]) {
        sheet.appendRow(entry.value.keys.map((key) => TextCellValue(row[key]?.toString() ?? '')).toList());
      }
    }
    if (book.tables.containsKey('Sheet1')) book.delete('Sheet1');
    book.setDefaultSheet('说明');
    final bytes = book.encode();
    if (bytes == null) throw const UserFacingError('Excel文件未能生成');
    final stamp = DateTime.now().toIso8601String().replaceAll(':', '-').split('.').first;
    final location = await FilePicker.saveFile(fileName: 'ClCrm_${template ? '模板' : '资料'}_$stamp.xlsx',
      bytes: Uint8List.fromList(bytes), mimeType: 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet');
    if (location != null) await _audit(template ? 'xlsx_template_export' : 'xlsx_export',
      template ? '导出Excel空白模板' : '导出Excel业务资料');
    return location != null;
  });

  Future<void> _audit(String type, String summary) async {
    try { await db.fileEvent(type, summary); }
    catch (_) { auditIssue = '文件操作已完成，但操作记录未能保存'; }
  }

  Future<WorkbookPreview?> pickPreview() => _exclusive(() async {
    final selected = await FilePicker.pickFiles(type: FileType.custom, allowedExtensions: ['xlsx']);
    if (selected.isEmpty) return null;
    final file = selected.first;
    if (!file.name.toLowerCase().endsWith('.xlsx')) {
      throw const UserFacingError('当前仅预览不超过10MB的xlsx文件');
    }
    final path = file.path;
    if (path == null) throw const UserFacingError('系统未提供可读取文件，请先将文件下载到本机');
    final source = File(path);
    if (await source.length() > maxFileBytes) throw const UserFacingError('文件超出当前预览大小限制');
    final bytes = await source.readAsBytes();
    try {
      _preflight(bytes);
      final book = Excel.decodeBytes(bytes);
      if (book.tables.length > 20) throw const UserFacingError('当前最多预览20张工作表');
      final sheets = <SheetPreview>[];
      var rows = 0;
      for (final entry in book.tables.entries) {
        final sheet = entry.value;
        rows += sheet.maxRows;
        if (rows > 10000 || sheet.maxColumns > 100) {
          throw const UserFacingError('当前预览上限为总计10000行、每表100列');
        }
        for (final row in sheet.rows) {
          for (final cell in row) {
            if (cell?.value is FormulaCellValue) throw const UserFacingError('请先将公式转换为静态值再导入');
            if ((cell?.value?.toString().length ?? 0) > 20000) throw const UserFacingError('单元格文字过长，请拆分内容');
          }
        }
        final values = sheet.rows;
        sheets.add(SheetPreview(entry.key,
          values.isEmpty ? [] : values.first.map((c) => c?.value?.toString() ?? '').toList(),
          values.skip(1).take(10).map((row) => row.map((c) => c?.value?.toString() ?? '').toList()).toList(),
          sheet.maxRows > 0 ? sheet.maxRows - 1 : 0));
      }
      final issues = <String>[];
      final imported = <NewCustomerRow>[];
      for (final entry in book.tables.entries) {
        if (entry.key == '客户' || entry.key == '说明' || entry.key == '_ClCrmSchema') continue;
        if (entry.value.rows.skip(1).any((r) => r.any((c) => (c?.value?.toString() ?? '').trim().isNotEmpty))) {
          issues.add('“${entry.key}”含业务资料：当前只支持客户新增，该文件不允许写入');
        }
      }
      final customerSheet = book.tables['客户'];
      if (customerSheet == null || customerSheet.rows.isEmpty) {
        issues.add('缺少“客户”工作表及表头');
      } else {
        final headers = customerSheet.rows.first.map((c) => c?.value?.toString().trim() ?? '').toList();
        final columns = exchangeColumns['customers']!;
        for (final header in headers.where((h) => h.isNotEmpty)) {
          if (!columns.values.contains(header)) issues.add('客户表包含未知列“$header”，请使用固定模板');
        }
        for (final requiredHeader in ['客户名称','省','市']) {
          if (!headers.contains(requiredHeader)) issues.add('客户表缺少“$requiredHeader”列');
        }
        if (headers.where((h) => h.isNotEmpty).toSet().length != headers.where((h) => h.isNotEmpty).length) {
          issues.add('客户表包含重复列名');
        }
        final seen = <String>{};
        for (var i = 1; i < customerSheet.rows.length; i++) {
          final cells = customerSheet.rows[i];
          if (cells.every((c) => (c?.value?.toString() ?? '').trim().isEmpty)) continue;
          String value(String field) {
            final index = headers.indexOf(columns[field]!);
            return index < 0 || index >= cells.length ? '' : cells[index]?.value?.toString().trim() ?? '';
          }
          if (value('id').isNotEmpty || value('customer_no').isNotEmpty) {
            issues.add('客户表第${i+1}行包含已有标识：暂不支持更新或跨库写入'); continue;
          }
          final fields = <String, Object?>{for (final key in ['name','province','city','district','address','short_name','source','note']) key: value(key)};
          if (['name','province','city'].any((key) => (fields[key] as String).isEmpty)) {
            issues.add('客户表第${i+1}行缺少客户名称、省或市'); continue;
          }
          final matches = await db.findCustomerDuplicates(fields['name'] as String);
          final duplicates = matches.map((c) => '${c.text('name')} · ${c.text('province')}${c.text('city')}').toList();
          if (!seen.add(nameKey(fields['name'] as String))) duplicates.add('同一文件前面已有同名客户');
          imported.add(NewCustomerRow(i+1, fields, duplicates));
        }
      }
      if (imported.isEmpty) issues.add('没有可新增的客户行');
      if (imported.length > 1000) issues.add('当前单批最多新增1000个客户');
      await _audit('xlsx_preview', '读取Excel预览，尚未写入业务资料');
      return WorkbookPreview(file.name, sheets, imported, issues);
    } on UserFacingError { rethrow; }
    catch (_) { throw const UserFacingError('文件损坏、格式不受支持或使用了密码保护，未修改任何业务资料'); }
  });

  void _preflight(Uint8List bytes) {
    // Check the declared central-directory entry count before constructing ZIP entries.
    final view = ByteData.sublistView(bytes);
    int end = -1;
    for (var i = bytes.length - 22; i >= 0 && i >= bytes.length - 65557; i--) {
      if (view.getUint32(i, Endian.little) == 0x06054b50 &&
          i + 22 + view.getUint16(i + 20, Endian.little) == bytes.length) { end = i; break; }
    }
    if (end < 0) throw const UserFacingError('不是有效的xlsx归档');
    final count = view.getUint16(end + 10, Endian.little);
    if (count > 512 || view.getUint16(end + 4, Endian.little) != 0 ||
        view.getUint16(end + 6, Endian.little) != 0) {
      throw const UserFacingError('不支持分卷、ZIP64或包含过多对象的工作簿');
    }
    final directory = ZipDirectory.read(InputStream(bytes));
    var expanded = 0;
    for (final entry in directory.fileHeaders) {
      final path = entry.filename.replaceAll('\\', '/');
      if (path.startsWith('/') || path.split('/').contains('..') || path.contains(':') || path.endsWith('vbaProject.bin')) {
        throw const UserFacingError('工作簿包含不受支持的对象或路径');
      }
      expanded += entry.uncompressedSize ?? maxExpandedBytes;
      if (expanded > maxExpandedBytes) throw const UserFacingError('解压内容超出当前预览资源限制');
    }
  }
}
