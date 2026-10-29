import 'dart:convert';

import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

import 'models.dart';

class CrmDatabase {
  Database? _db;
  Database get connection => _db ?? (throw const UserFacingError('资料库尚未打开'));

  Future<void> open() async {
    if (_db != null) return;
    _db = await openDatabase(p.join(await getDatabasesPath(), 'clcrm.sqlite3'),
      version: 1,
      onConfigure: (db) async {
        await db.execute('PRAGMA foreign_keys = ON');
      },
      onCreate: (db, _) async {
        const common = '''created_at TEXT NOT NULL, updated_at TEXT NOT NULL,
          deleted_at TEXT, record_version INTEGER NOT NULL DEFAULT 1''';
        await db.execute('''CREATE TABLE customers (
          id TEXT PRIMARY KEY, customer_no TEXT NOT NULL UNIQUE,
          name TEXT NOT NULL CHECK(length(trim(name)) > 0), name_key TEXT NOT NULL,
          province TEXT NOT NULL, city TEXT NOT NULL, district TEXT NOT NULL DEFAULT '',
          address TEXT NOT NULL DEFAULT '', short_name TEXT NOT NULL DEFAULT '',
          source TEXT NOT NULL DEFAULT '', note TEXT NOT NULL DEFAULT '', $common)''');
        await db.execute('''CREATE TABLE customer_aliases (
          id TEXT PRIMARY KEY, customer_id TEXT NOT NULL REFERENCES customers(id),
          name TEXT NOT NULL, recorded_at TEXT NOT NULL)''');
        await db.execute('''CREATE TABLE categories (
          id TEXT PRIMARY KEY, name TEXT NOT NULL, kind TEXT NOT NULL DEFAULT 'general',
          enabled INTEGER NOT NULL DEFAULT 1, sort_order INTEGER NOT NULL DEFAULT 0,
          $common)''');
        await db.execute('''CREATE TABLE customer_categories (
          customer_id TEXT NOT NULL REFERENCES customers(id),
          category_id TEXT NOT NULL REFERENCES categories(id),
          PRIMARY KEY(customer_id, category_id))''');
        await db.execute('''CREATE TABLE contacts (
          id TEXT PRIMARY KEY, customer_id TEXT NOT NULL REFERENCES customers(id),
          name TEXT NOT NULL DEFAULT '', phone TEXT NOT NULL DEFAULT '',
          phone_key TEXT NOT NULL DEFAULT '', position TEXT NOT NULL DEFAULT '',
          wechat TEXT NOT NULL DEFAULT '', is_primary INTEGER NOT NULL DEFAULT 0,
          $common, CHECK(length(trim(name)) > 0 OR length(trim(phone)) > 0))''');
        await db.execute('''CREATE UNIQUE INDEX one_primary_contact
          ON contacts(customer_id) WHERE is_primary = 1 AND deleted_at IS NULL''');
        await db.execute('''CREATE TABLE purchases (
          id TEXT PRIMARY KEY, customer_id TEXT NOT NULL REFERENCES customers(id),
          contact_id TEXT REFERENCES contacts(id), category_id TEXT NOT NULL REFERENCES categories(id),
          purchased_on TEXT NOT NULL, item_name TEXT NOT NULL, content TEXT NOT NULL,
          status TEXT NOT NULL CHECK(status IN ('pending','confirmed')),
          specification TEXT NOT NULL DEFAULT '', quantity_text TEXT NOT NULL DEFAULT '',
          unit TEXT NOT NULL DEFAULT '', amount_text TEXT NOT NULL DEFAULT '',
          contract_no TEXT NOT NULL DEFAULT '', delivery_status TEXT NOT NULL DEFAULT '',
          note TEXT NOT NULL DEFAULT '', details_json TEXT NOT NULL DEFAULT '{}', $common)''');
        await db.execute('''CREATE TABLE interactions (
          id TEXT PRIMARY KEY, customer_id TEXT NOT NULL REFERENCES customers(id),
          contact_id TEXT REFERENCES contacts(id), occurred_at TEXT NOT NULL,
          method TEXT NOT NULL, content TEXT NOT NULL,
          source_task_id TEXT UNIQUE, $common)''');
        await db.execute('''CREATE TABLE tasks (
          id TEXT PRIMARY KEY, customer_id TEXT NOT NULL REFERENCES customers(id),
          contact_id TEXT REFERENCES contacts(id), title TEXT NOT NULL, planned_at TEXT NOT NULL,
          status TEXT NOT NULL CHECK(status IN ('pending','completed','canceled')),
          completed_at TEXT, canceled_at TEXT, source_interaction_id TEXT REFERENCES interactions(id),
          result_interaction_id TEXT REFERENCES interactions(id), $common)''');
        await db.execute('''CREATE TABLE task_changes (
          id TEXT PRIMARY KEY, task_id TEXT NOT NULL REFERENCES tasks(id),
          old_planned_at TEXT NOT NULL, new_planned_at TEXT NOT NULL,
          changed_at TEXT NOT NULL, reason TEXT NOT NULL DEFAULT '')''');
        await db.execute('''CREATE TABLE app_settings (key TEXT PRIMARY KEY, value TEXT NOT NULL)''');
        await db.execute('''CREATE TABLE operation_events (
          id TEXT PRIMARY KEY, type TEXT NOT NULL, object_id TEXT,
          occurred_at TEXT NOT NULL, summary TEXT NOT NULL)''');
        await db.execute('CREATE INDEX contacts_customer ON contacts(customer_id)');
        await db.execute('CREATE INDEX contacts_phone ON contacts(phone_key)');
        await db.execute('CREATE INDEX customers_region ON customers(province,city,district)');
        await db.execute('CREATE INDEX aliases_customer ON customer_aliases(customer_id)');
        await db.execute('CREATE INDEX interactions_customer_time ON interactions(customer_id,occurred_at)');
        await db.execute('CREATE INDEX interactions_time ON interactions(occurred_at)');
        await db.execute('CREATE INDEX tasks_due ON tasks(status,planned_at)');
        await db.execute('CREATE INDEX tasks_customer ON tasks(customer_id,status,planned_at)');
        await db.execute('CREATE INDEX purchases_customer ON purchases(customer_id,purchased_on)');
        final now = utcNow();
        for (final entry in [('software', '软件'), ('clothing', '服装'), ('service', '服务')]) {
          await db.insert('categories', {'id': entry.$1, 'name': entry.$2,
            'kind': entry.$1, 'created_at': now, 'updated_at': now});
        }
      },
      onDowngrade: (db, oldVersion, newVersion) async {
        throw const UserFacingError('资料库来自较新版本，请使用对应版本的 ClCrm 打开');
      });
  }

  DataRow _newRow([String? id]) {
    final now = utcNow();
    return {'id': id ?? newId(), 'created_at': now, 'updated_at': now,
      'deleted_at': null, 'record_version': 1};
  }

  Future<void> _event(DatabaseExecutor db, String type, String? id, String summary) =>
    db.insert('operation_events', {'id': newId(), 'type': type,
      'object_id': id, 'occurred_at': utcNow(), 'summary': summary}).then((_) {});

  Future<Map<String, String>> preferences() async => {
    for (final row in await connection.query('app_settings'))
      row['key'] as String: row['value'] as String,
  };
  Future<void> setPreference(String key, String value) async {
    if (!{'theme', 'font_scale', 'font_system', 'reminder_enabled', 'notice_private', 'reminder_advance_day'}.contains(key)) {
      throw const UserFacingError('此项设置的业务规则尚未确定');
    }
    await connection.insert('app_settings', {'key': key, 'value': value},
      conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<List<CrmRecord>> categories() async => (await connection.query('categories',
    orderBy: 'sort_order, created_at, id')).map(CrmRecord.new).toList();

  Future<void> reorderCategories(List<String> ids) async {
    await connection.transaction((tx) async {
      final current = await tx.query('categories', columns: ['id']);
      final expected = current.map((r) => r['id'] as String).toSet();
      if (ids.toSet().length != ids.length || ids.length != expected.length || !ids.toSet().containsAll(expected)) {
        throw const UserFacingError('类别已变化，请刷新后排序');
      }
      for (var i = 0; i < ids.length; i++) {
        await tx.rawUpdate('UPDATE categories SET sort_order=?,updated_at=?,record_version=record_version+1 WHERE id=?',
          [i, utcNow(), ids[i]]);
      }
      await _event(tx, 'category_reorder', null, '调整类别顺序');
    });
  }

  Future<List<CrmRecord>> contactDirectory() async => (await connection.rawQuery('''
    SELECT p.*,c.name customer_name FROM contacts p JOIN customers c ON c.id=p.customer_id
    WHERE p.deleted_at IS NULL AND c.deleted_at IS NULL ORDER BY p.updated_at DESC,p.id LIMIT 200'''))
    .map(CrmRecord.new).toList();

  Future<List<String>> purchaseNames(String? categoryId) async => (await connection.query('purchases',
    columns: ['item_name'], distinct: true, where: 'deleted_at IS NULL${categoryId == null ? '' : ' AND category_id=?'}',
    whereArgs: categoryId == null ? null : [categoryId], orderBy: 'item_name', limit: 100))
    .map((r) => r['item_name'] as String).toList();

  Future<void> importNewCustomers(List<DataRow> rows) async {
    if (rows.isEmpty || rows.length > 1000) throw const UserFacingError('当前单批新增客户需为1–1000行');
    await connection.transaction((tx) async {
      for (final values in rows) {
        for (final key in ['name','province','city']) {
          if ((values[key]?.toString() ?? '').trim().isEmpty) throw const UserFacingError('客户名称、省、市不能为空');
        }
        final name = (values['name'] as String).trim();
        final matches = await tx.query('customers', columns: ['id'],
          where: 'name_key=? AND deleted_at IS NULL', whereArgs: [nameKey(name)], limit: 1);
        if (matches.isNotEmpty && values['allow_duplicate'] != true) {
          throw const UserFacingError('存在未确认的同名客户，整批未写入，请重新预览');
        }
        final id = newId();
        await tx.insert('customers', {..._newRow(id), 'customer_no': id, 'name_key': nameKey(name),
          for (final key in ['name','province','city','district','address','short_name','source','note'])
            key: (values[key]?.toString() ?? '').trim()});
      }
      await _event(tx, 'xlsx_customer_import', null, 'Excel整批新增${rows.length}个客户');
    });
  }

  Future<void> saveCategory(String name, {CrmRecord? existing, bool enabled = true}) async {
    if (name.trim().isEmpty) throw const UserFacingError('请填写类别名称');
    await connection.transaction((tx) async {
      final collision = await tx.query('categories', where: 'name = ? AND id != ?',
        whereArgs: [name.trim(), existing?.id ?? '']);
      if (collision.isNotEmpty) throw const UserFacingError('已存在同名业务类别');
      if (existing == null) {
        final row = {..._newRow(), 'name': name.trim(), 'kind': 'general', 'enabled': 1};
        await tx.insert('categories', row);
        await _event(tx, 'category_create', row['id'] as String, '新增业务类别');
      } else {
        await tx.update('categories', {'name': name.trim(), 'enabled': enabled ? 1 : 0,
          'updated_at': utcNow(), 'record_version': existing.integer('record_version') + 1},
          where: 'id = ?', whereArgs: [existing.id]);
        await _event(tx, 'category_update', existing.id, '修改业务类别');
      }
    });
  }

  Future<List<CrmRecord>> findCustomerDuplicates(String name, {String? excluding}) async =>
    (await connection.query('customers', where: 'deleted_at IS NULL AND name_key = ? AND id != ?',
      whereArgs: [nameKey(name), excluding ?? ''])).map(CrmRecord.new).toList();

  Future<List<CrmRecord>> findPhoneDuplicates(String phone, {String? excluding}) async {
    if (phoneKey(phone).isEmpty) return [];
    return (await connection.rawQuery('''SELECT c.*, a.name customer_name FROM contacts c
      JOIN customers a ON a.id = c.customer_id WHERE c.deleted_at IS NULL
      AND a.deleted_at IS NULL AND c.phone_key = ? AND c.id != ?''',
      [phoneKey(phone), excluding ?? ''])).map(CrmRecord.new).toList();
  }

  Future<String> saveCustomer(DataRow values, Set<String> categoryIds, {CrmRecord? existing}) async {
    for (final key in ['name', 'province', 'city']) {
      if ((values[key]?.toString() ?? '').trim().isEmpty) {
        throw const UserFacingError('客户名称、省及市不能为空');
      }
    }
    return connection.transaction((tx) async {
      final id = existing?.id ?? newId();
      final fields = {for (final key in ['name', 'province', 'city', 'district',
        'address', 'short_name', 'source', 'note']) key: (values[key]?.toString() ?? '').trim()};
      final row = <String, Object?>{...fields, 'name_key': nameKey(fields['name']!)};
      if (existing == null) {
        // The full random identifier is stable; no unconfirmed sequential number policy.
        await tx.insert('customers', {..._newRow(id), ...row, 'customer_no': id});
      } else {
        final current = await tx.query('customers', where: 'id = ? AND deleted_at IS NULL', whereArgs: [id]);
        if (current.isEmpty || current.single['record_version'] != existing.integer('record_version')) {
          throw const UserFacingError('客户资料已变化，请返回后重新编辑');
        }
        if (existing.text('name') != fields['name']) {
          await tx.insert('customer_aliases', {'id': newId(), 'customer_id': id,
            'name': existing.text('name'), 'recorded_at': utcNow()});
        }
        await tx.update('customers', {...row, 'updated_at': utcNow(),
          'record_version': existing.integer('record_version') + 1}, where: 'id = ?', whereArgs: [id]);
      }
      await tx.delete('customer_categories', where: 'customer_id = ?', whereArgs: [id]);
      for (final categoryId in categoryIds) {
        final found = await tx.query('categories', where: 'id = ?', whereArgs: [categoryId]);
        if (found.isEmpty) throw const UserFacingError('所选类别不存在');
        await tx.insert('customer_categories', {'customer_id': id, 'category_id': categoryId});
      }
      await _event(tx, existing == null ? 'customer_create' : 'customer_update', id, '保存客户');
      return id;
    });
  }

  Future<Set<String>> customerCategoryIds(String id) async =>
    (await connection.query('customer_categories', where: 'customer_id = ?', whereArgs: [id]))
      .map((r) => r['category_id'] as String).toSet();

  Future<void> _checkCustomer(DatabaseExecutor tx, String id) async {
    final rows = await tx.query('customers', where: 'id = ? AND deleted_at IS NULL', whereArgs: [id]);
    if (rows.isEmpty) throw const UserFacingError('客户不存在或已删除');
  }

  Future<void> _checkContact(DatabaseExecutor tx, String customerId, String? contactId) async {
    if (contactId == null || contactId.isEmpty) return;
    final rows = await tx.query('contacts', where: 'id = ? AND customer_id = ? AND deleted_at IS NULL',
      whereArgs: [contactId, customerId]);
    if (rows.isEmpty) throw const UserFacingError('联系人不属于此客户或已删除');
  }

  Future<void> saveContact(String customerId, DataRow values, {CrmRecord? existing}) async {
    final name = values['name']?.toString().trim() ?? '';
    final phone = values['phone']?.toString().trim() ?? '';
    if (name.isEmpty && phone.isEmpty) throw const UserFacingError('姓名、电话至少填写一项');
    await connection.transaction((tx) async {
      await _checkCustomer(tx, customerId);
      if (values['is_primary'] == 1) {
        await tx.rawUpdate('''UPDATE contacts SET is_primary = 0, updated_at = ?,
          record_version = record_version + 1 WHERE customer_id = ? AND is_primary = 1
          AND id != ?''', [utcNow(), customerId, existing?.id ?? '']);
      }
      final id = existing?.id ?? newId();
      final row = <String, Object?>{'customer_id': customerId, 'name': name, 'phone': phone,
        'phone_key': phoneKey(phone), 'position': values['position'] ?? '',
        'wechat': values['wechat'] ?? '', 'is_primary': values['is_primary'] == 1 ? 1 : 0};
      if (existing == null) {
        await tx.insert('contacts', {..._newRow(id), ...row});
      } else {
        final changed = await tx.update('contacts', {...row, 'updated_at': utcNow(),
          'record_version': existing.integer('record_version') + 1},
          where: 'id = ? AND customer_id = ? AND record_version = ? AND deleted_at IS NULL',
          whereArgs: [id, customerId, existing.integer('record_version')]);
        if (changed != 1) throw const UserFacingError('联系人已变化，请重新打开后编辑');
      }
      await _event(tx, 'contact_save', id, '保存联系人');
    });
  }

  Future<List<String>> regionOptions(String field, {String province = '', String city = ''}) async {
    if (!{'province','city','district'}.contains(field)) throw const UserFacingError('无效地区层级');
    final where = <String>['deleted_at IS NULL', "$field != ''"];
    final args = <Object?>[];
    if (province.isNotEmpty) { where.add('province=?'); args.add(province); }
    if (city.isNotEmpty) { where.add('city=?'); args.add(city); }
    return (await connection.query('customers', columns: [field], distinct: true,
      where: where.join(' AND '), whereArgs: args, orderBy: field))
      .map((r) => r[field] as String).toList();
  }

  Future<PageResult> customers({String query = '', String? categoryId,
    String province = '', String city = '', String district = '', int offset = 0, int limit = 40}) async {
    final args = <Object?>[];
    final where = <String>['a.deleted_at IS NULL'];
    if (query.trim().isNotEmpty) {
      final q = '%${query.trim().replaceAll('\\', '\\\\').replaceAll('%', '\\%').replaceAll('_', '\\_')}%';
      final phone = '%${phoneKey(query).replaceAll('\\', '\\\\').replaceAll('%', '\\%').replaceAll('_', '\\_')}%';
      where.add('''(a.name LIKE ? ESCAPE '\\' OR a.short_name LIKE ? ESCAPE '\\'
        OR EXISTS(SELECT 1 FROM customer_aliases x WHERE x.customer_id=a.id AND x.name LIKE ? ESCAPE '\\')
        OR EXISTS(SELECT 1 FROM contacts c WHERE c.customer_id=a.id AND c.deleted_at IS NULL
          AND (c.name LIKE ? ESCAPE '\\' OR (? <> '' AND c.phone_key LIKE ? ESCAPE '\\'))))''');
      args.addAll([q, q, q, q, phoneKey(query), phone]);
    }
    if (categoryId != null) {
      where.add('EXISTS(SELECT 1 FROM customer_categories cc WHERE cc.customer_id=a.id AND cc.category_id=?)');
      args.add(categoryId);
    }
    if (province.isNotEmpty) { where.add('a.province = ?'); args.add(province); }
    if (city.isNotEmpty) { where.add('a.city = ?'); args.add(city); }
    if (district.isNotEmpty) { where.add('a.district = ?'); args.add(district); }
    final rows = await connection.rawQuery('''SELECT a.*,
      (SELECT name FROM contacts c WHERE c.customer_id=a.id AND c.is_primary=1 AND c.deleted_at IS NULL LIMIT 1) primary_name,
      (SELECT MAX(occurred_at) FROM interactions i WHERE i.customer_id=a.id AND i.deleted_at IS NULL) last_contact,
      (SELECT MIN(planned_at) FROM tasks t WHERE t.customer_id=a.id AND t.status='pending' AND t.deleted_at IS NULL) next_contact
      FROM customers a WHERE ${where.join(' AND ')} ORDER BY a.updated_at DESC,a.id LIMIT ? OFFSET ?''',
      [...args, limit + 1, offset]);
    return PageResult(rows.take(limit).map(CrmRecord.new).toList(), rows.length > limit);
  }

  Future<CrmRecord?> customer(String id) async {
    final rows = await connection.rawQuery('''SELECT c.*,
      (SELECT MAX(occurred_at) FROM interactions i WHERE i.customer_id=c.id AND i.deleted_at IS NULL) last_contact,
      (SELECT MIN(planned_at) FROM tasks t WHERE t.customer_id=c.id AND t.status='pending' AND t.deleted_at IS NULL) next_contact
      FROM customers c WHERE c.id=? AND c.deleted_at IS NULL''', [id]);
    return rows.isEmpty ? null : CrmRecord(rows.single);
  }

  Future<List<CrmRecord>> related(String table, String customerId) async {
    const ordering = {'contacts': 'is_primary DESC,created_at', 'purchases': 'purchased_on DESC,created_at DESC',
      'interactions': 'occurred_at DESC,created_at DESC', 'tasks': 'planned_at,created_at'};
    if (!ordering.containsKey(table)) throw const UserFacingError('不支持的资料类型');
    return (await connection.query(table, where: 'customer_id = ? AND deleted_at IS NULL',
      whereArgs: [customerId], orderBy: ordering[table], limit: 200)).map(CrmRecord.new).toList();
  }

  Future<void> savePurchase(String customerId, DataRow values, DataRow details) async {
    for (final key in ['purchased_on', 'category_id', 'item_name', 'content']) {
      if ((values[key]?.toString() ?? '').trim().isEmpty) throw const UserFacingError('请补全购买必填资料');
    }
    final status = values['status']?.toString() ?? '';
    if (!purchaseStates.containsKey(status)) throw const UserFacingError('购买状态无效');
    await connection.transaction((tx) async {
      await _checkCustomer(tx, customerId);
      await _checkContact(tx, customerId, values['contact_id'] as String?);
      final category = await tx.query('categories', where: 'id = ? AND enabled=1', whereArgs: [values['category_id']]);
      if (category.isEmpty) throw const UserFacingError('业务类别不存在或已停用');
      final row = {..._newRow(), 'customer_id': customerId,
        for (final key in ['contact_id', 'category_id', 'purchased_on', 'item_name', 'content', 'status',
          'specification', 'quantity_text', 'unit', 'amount_text', 'contract_no', 'delivery_status', 'note'])
          key: values[key] ?? (key == 'contact_id' ? null : ''),
        'details_json': jsonEncode(details)};
      await tx.insert('purchases', row);
      await _event(tx, 'purchase_create', row['id'] as String, '新增购买记录');
    });
  }

  Future<void> createTask(String customerId, String title, DateTime plannedAt, {String? contactId}) async {
    if (title.trim().isEmpty) throw const UserFacingError('请填写跟进事项');
    await connection.transaction((tx) async {
      await _checkCustomer(tx, customerId);
      await _checkContact(tx, customerId, contactId);
      final row = {..._newRow(), 'customer_id': customerId, 'contact_id': contactId,
        'title': title.trim(), 'planned_at': utcText(plannedAt), 'status': 'pending'};
      await tx.insert('tasks', row);
      await _event(tx, 'task_create', row['id'] as String, '新建跟进任务');
    });
  }

  Future<void> recordInteraction(InteractionInput input, {String? completingTaskId}) async {
    if (input.content.trim().isEmpty) throw const UserFacingError('请填写实际联系内容');
    if (!contactMethods.contains(input.method)) throw const UserFacingError('联系方法无效');
    if (input.occurredAt.isAfter(DateTime.now())) throw const UserFacingError('尚未发生的联系请先安排为跟进任务');
    if (input.nextAt != null && input.nextTitle.trim().isEmpty) {
      throw const UserFacingError('安排下次联系时需填写跟进事项');
    }
    await connection.transaction((tx) async {
      await _checkCustomer(tx, input.customerId);
      await _checkContact(tx, input.customerId, input.contactId);
      if (completingTaskId != null) {
        final tasks = await tx.query('tasks', where: 'id=? AND customer_id=? AND status=? AND deleted_at IS NULL',
          whereArgs: [completingTaskId, input.customerId, 'pending']);
        if (tasks.isEmpty) throw const UserFacingError('该任务已处理或不存在，未重复生成联系记录');
      }
      final id = newId();
      await tx.insert('interactions', {..._newRow(id), 'customer_id': input.customerId,
        'contact_id': input.contactId, 'occurred_at': utcText(input.occurredAt),
        'method': input.method, 'content': input.content.trim(), 'source_task_id': completingTaskId});
      if (input.nextAt != null) {
        await tx.insert('tasks', {..._newRow(), 'customer_id': input.customerId,
          'contact_id': input.contactId, 'title': input.nextTitle.trim(),
          'planned_at': utcText(input.nextAt!), 'status': 'pending', 'source_interaction_id': id});
      }
      if (completingTaskId != null) {
        await tx.rawUpdate('''UPDATE tasks SET status='completed', completed_at=?, result_interaction_id=?,
          updated_at=?, record_version=record_version+1 WHERE id=? AND status='pending' ''',
          [utcNow(), id, utcNow(), completingTaskId]);
      }
      await _event(tx, 'interaction_create', id, completingTaskId == null ? '记录实际联系' : '完成任务并记录实际联系');
    });
  }

  Future<List<CrmRecord>> tasks({String state = 'pending', int limit = 200, String? window}) async {
    final now = DateTime.now();
    final args = <Object?>[state];
    String range = '';
    if (window == 'today' || window == 'future') {
      final begin = DateTime(now.year, now.month, now.day + (window == 'future' ? 1 : 0));
      final end = DateTime(now.year, now.month, now.day + (window == 'future' ? 8 : 1));
      range = ' AND t.planned_at>=? AND t.planned_at<?';
      args.addAll([utcText(begin), utcText(end)]);
    } else if (window == 'overdue') {
      range = ' AND t.planned_at<?'; args.add(utcText(now));
    }
    args.add(limit);
    return (await connection.rawQuery('''SELECT t.*,c.name customer_name,
      p.name contact_name FROM tasks t JOIN customers c ON c.id=t.customer_id
      LEFT JOIN contacts p ON p.id=t.contact_id WHERE t.deleted_at IS NULL
      AND c.deleted_at IS NULL AND t.status=?$range ORDER BY t.planned_at,t.id LIMIT ?''', args))
      .map(CrmRecord.new).toList();
  }

  Future<CrmRecord?> task(String id) async {
    final rows = await connection.query('tasks', where: 'id=? AND deleted_at IS NULL', whereArgs: [id]);
    return rows.isEmpty ? null : CrmRecord(rows.single);
  }

  Future<void> rescheduleTask(CrmRecord task, DateTime date, String reason) async {
    await connection.transaction((tx) async {
      final changed = await tx.rawUpdate('''UPDATE tasks SET planned_at=?,updated_at=?,record_version=record_version+1
        WHERE id=? AND status='pending' AND deleted_at IS NULL AND record_version=?''',
        [utcText(date), utcNow(), task.id, task.integer('record_version')]);
      if (changed != 1) throw const UserFacingError('任务已变化，请重新打开');
      await tx.insert('task_changes', {'id': newId(), 'task_id': task.id,
        'old_planned_at': task.text('planned_at'), 'new_planned_at': utcText(date),
        'changed_at': utcNow(), 'reason': reason.trim()});
      await _event(tx, 'task_reschedule', task.id, '调整跟进时间');
    });
  }

  Future<void> cancelTask(CrmRecord task) async {
    await connection.transaction((tx) async {
      final changed = await tx.rawUpdate('''UPDATE tasks SET status='canceled',canceled_at=?,updated_at=?,
        record_version=record_version+1 WHERE id=? AND status='pending' AND deleted_at IS NULL''',
        [utcNow(), utcNow(), task.id]);
      if (changed != 1) throw const UserFacingError('任务已处理');
      await _event(tx, 'task_cancel', task.id, '取消跟进任务');
    });
  }

  Future<DataRow> statistics(DateTime start, DateTime end) async {
    final args = [utcText(start), utcText(end)];
    final total = await connection.rawQuery('''SELECT COUNT(*) interaction_count,
      COUNT(DISTINCT i.customer_id) customer_count FROM interactions i
      JOIN customers c ON c.id=i.customer_id WHERE i.deleted_at IS NULL AND c.deleted_at IS NULL
      AND i.occurred_at>=? AND i.occurred_at<=?''', args);
    final regions = await connection.rawQuery('''SELECT c.province,COUNT(*) interaction_count,
      COUNT(DISTINCT i.customer_id) customer_count FROM interactions i JOIN customers c ON c.id=i.customer_id
      WHERE i.deleted_at IS NULL AND c.deleted_at IS NULL AND i.occurred_at>=? AND i.occurred_at<=?
      GROUP BY c.province ORDER BY customer_count DESC,c.province''', args);
    return {...total.single, 'regions': regions};
  }

  Future<List<CrmRecord>> contactedCustomers(DateTime start, DateTime end, {String? province}) async {
    final extra = province == null ? '' : ' AND c.province=?';
    return (await connection.rawQuery('''SELECT c.*,COUNT(i.id) interaction_count,
      MAX(i.occurred_at) range_last_contact FROM customers c JOIN interactions i ON i.customer_id=c.id
      WHERE c.deleted_at IS NULL AND i.deleted_at IS NULL AND i.occurred_at>=? AND i.occurred_at<=?$extra
      GROUP BY c.id ORDER BY range_last_contact DESC,c.id''',
      [utcText(start), utcText(end), if (province != null) province]))
      .map(CrmRecord.new).toList();
  }

  Future<List<CrmRecord>> events() async => (await connection.query('operation_events',
    orderBy: 'occurred_at DESC,id', limit: 100)).map(CrmRecord.new).toList();

  Future<void> fileEvent(String type, String summary) => _event(connection, type, null, summary);

  Future<Map<String, List<DataRow>>> exportSnapshot() => connection.transaction((tx) async {
    const tables = ['customers', 'contacts', 'categories', 'customer_categories',
      'purchases', 'interactions', 'tasks', 'customer_aliases', 'task_changes'];
    var total = 0;
    for (final table in tables) {
      total += Sqflite.firstIntValue(await tx.rawQuery('SELECT COUNT(*) FROM $table')) ?? 0;
    }
    if (total > 10000) throw const UserFacingError('当前Excel导出总行数上限为10000，批量导出方案待完善');
    return {for (final table in tables) table: await tx.query(table)};
  });
}
