import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../app_controller.dart';
import '../core/models.dart';
import '../ui/common.dart';
import '../ui/glass_bottom_navigation.dart';
import 'data_exchange_page.dart';
import 'editors.dart';

class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key, required this.controller});
  final AppController controller;

  void information(BuildContext context, String title, String body, {bool pending = true}) =>
    openPage(context, InfoPage(title: title, body: body, pending: pending));

  Widget entry(BuildContext context, IconData icon, String title, VoidCallback action, {bool pending = false}) =>
    ListTile(leading: Icon(icon), title: Text(title), trailing: Row(mainAxisSize: MainAxisSize.min,
      children: [if (pending) Text('待完善', style: Theme.of(context).textTheme.labelMedium),
        const Icon(Icons.chevron_right)]), onTap: action);

  @override
  Widget build(BuildContext context) => Scaffold(appBar: AppBar(title: const Text('我的')),
    body: ListView(padding: EdgeInsets.fromLTRB(16, 16, 16,
      AppBottomNavigation.contentBottomPadding(context)), children: [
      Padding(padding: const EdgeInsets.only(bottom: 20), child: Row(children: [
        ClipRRect(borderRadius: BorderRadius.circular(18), child: Image.asset('assets/clcrm.png', width: 64, height: 64)),
        const SizedBox(width: 14), Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('ClCrm', style: Theme.of(context).textTheme.headlineSmall), const Text('客户档案与业务跟进'),
        ])),
      ])),
      Section('通用设置', children: [
        ListTile(leading: const Icon(Icons.palette_outlined), title: const Text('主题'),
          trailing: DropdownButton<String>(value: controller.preferences['theme'] ?? 'system', underline: const SizedBox(),
            items: const [DropdownMenuItem(value: 'system', child: Text('跟随系统')),
              DropdownMenuItem(value: 'light', child: Text('浅色')), DropdownMenuItem(value: 'dark', child: Text('深色'))],
            onChanged: (v) { if (v != null) performAction(context, () => controller.setPreference('theme', v)); })),
        entry(context, Icons.language, '语言', () => information(context, '语言',
          '当前提供简体中文界面。繁体中文、英语、日语与韩语的首发范围和翻译内容待补充。'), pending: true),
        entry(context, Icons.format_size, '字体大小', () => openPage(context, FontPage(controller: controller))),
      ]),
      Section('提醒与显示', children: [
        entry(context, Icons.notifications_outlined, '跟进提醒', () => openPage(context, NotificationSettingsPage(controller: controller))),
        entry(context, Icons.today_outlined, '每日汇总', () => information(context, '每日汇总',
          '每日汇总的时刻与通知内容待补充。离线应用长期未启动时，不能保证每天重新计算最新任务数量。当前未启用每日汇总排程。'), pending: true),
        entry(context, Icons.event_available_outlined, '到期提醒', () => information(context, '到期提醒',
          '软件授权、维护与服务到期日可以在购买记录中保存。自动任务的生成、取消和时间规则待补充，当前不会自动生成到期任务。'), pending: true),
        entry(context, Icons.visibility_outlined, '通知内容隐私', () => openPage(context, NotificationSettingsPage(controller: controller))),
      ]),
      Section('业务配置', children: [
        entry(context, Icons.category_outlined, '业务类别', () => openPage(context, CategoriesPage(controller: controller))),
        entry(context, Icons.contacts_outlined, '联系人资料', () => openPage(context, ContactsDirectoryPage(controller: controller))),
        entry(context, Icons.public, '地区资料', () => information(context, '地区资料',
          '客户表单当前手工填写省、市及可选区县。离线地区字典的覆盖范围、来源及版本待补充，当前没有自动匹配或纠正地区。'), pending: true),
        entry(context, Icons.payments_outlined, '金额与数量格式', () => information(context, '金额与数量格式',
          '币种、数量与工时精度待补充。购买记录暂按原文保存，区分空白和0，不参与金额计算或币种转换。'), pending: true),
      ]),
      Section('数据与安全', children: [
        entry(context, Icons.table_chart_outlined, '表格与数据', () => openPage(context, DataExchangePage(controller: controller))),
        entry(context, Icons.cloud_outlined, '完整备份与恢复', () => information(context, '完整备份与恢复',
          '完整备份包含全部业务资料、配置和附件，计划通过系统“文件”手动保存到本机或iCloud Drive，程序自动处理默认密码。\n\n'
          'A用户的备份不能由B用户导入。用户识别、归属校验、换机及重装恢复规则尚未确定，因此当前不生成完整备份、不提供覆盖恢复。\n\n'
          'Excel导出不等于完整备份。不要在缺少可靠副本时卸载应用。'), pending: true),
        entry(context, Icons.delete_outline, '回收站', () => information(context, '回收站',
          '保留期限、关联资料删除与恢复规则待补充。为避免误删，当前没有删除客户、联系人、购买或联系的入口。取消跟进任务不会删除记录。'), pending: true),
        entry(context, Icons.lock_outline, '安全锁', () => information(context, '安全锁',
          '启动验证、导出验证与后台遮罩规则待补充，当前未接入应用锁。程序默认备份密码与设备认证属于不同机制。'), pending: true),
        entry(context, Icons.storage_outlined, '数据存储与删除', () => information(context, '数据存储与删除',
          '客户、联系人、购买、实际联系和任务保存在当前设备的SQLite资料库。应用无需注册账号，不连接开发者业务服务器。\n\n'
          'Excel文件保存到你选择的位置且不设密码；导出的副本不会随应用内修改自动更新或删除。\n\n'
          '删除应用或设备损坏可能丢失本机资料。完整备份当前尚未开放，Excel不包含附件与全部设置。Apple系统设备备份的纳入策略待确认。\n\n'
          '删除与回收站规则尚未定稿，当前不提供一键清空。', pending: false)),
        entry(context, Icons.admin_panel_settings_outlined, '权限说明', () => information(context, '权限说明',
          '通知：只有在跟进提醒页面主动开启时才申请。拒绝权限不影响保存任务和查看待办。\n\n'
          '文件：只读取你通过系统选择器选择的Excel，并将导出文件交给你选择的保存位置；选择云盘时由系统文件服务处理传输。\n\n'
          '电话：拨打前确认并交给系统处理，不读取通话记录，不把拨号当成实际联系。\n\n'
          '当前未读取系统通讯录、定位、麦克风和私人聊天，附件与设备认证尚未接入。', pending: false)),
        entry(context, Icons.history, '操作记录', () => openPage(context, OperationHistoryPage(controller: controller))),
      ]),
      Section('隐私与条款', children: [
        entry(context, Icons.privacy_tip_outlined, '隐私政策', () => information(context, '隐私政策',
          '草案 · 开发者主体、支持邮箱、公开政策网址与正式文案待补充。\n\n'
          '当前业务资料在设备本机处理，用于客户检索、购买记录、实际联系、任务和只读统计。应用未接入开发者服务器、广告或行为分析服务。\n\n'
          'Excel文件只在你主动操作时读取或保存；导出没有密码。系统文件服务和本地通知的实际行为见“权限说明”。\n\n'
          '完整备份归属、安全锁、附件和系统设备备份策略仍待完善，接入后需要同步更新本页。当前页面不是已定稿的正式政策。'), pending: true),
        entry(context, Icons.article_outlined, '使用条款', () => information(context, '使用条款',
          '草案 · 正式内容与发布信息待补充。\n\n'
          'ClCrm用于本机客户管理和业务跟进。通知状态不能证明用户已联系客户，实际联系需保存结果。\n\n'
          '请区分Excel业务交换与完整备份；当前尚未开放的功能会显示待完善。支持作者的真实交易尚未接入。'), pending: true),
      ]),
      Section('支持与关于', children: [
        entry(context, Icons.star_border, '给个好评', () => information(context, '给个好评',
          'ClCrm应用商店标识的归属待确认。当前不打开评价页面，避免跳转其他应用。'), pending: true),
        entry(context, Icons.volunteer_activism_outlined, '支持作者', () => information(context, '支持作者',
          '支持作者页面已预留。商品接入与真实交易待确认，当前不会发起扣款。商品标识保留在项目资料中，不将资料金额冒充商店实时价格。'), pending: true),
        entry(context, Icons.mail_outline, '联系与反馈', () => information(context, '联系与反馈',
          '开发者：待补充\n支持邮箱：待补充\n公开政策网址：待补充\n\n'
          '当前没有在线反馈服务。后续反馈时请遮挡截图中的客户姓名、电话和联系内容，不提供设备口令或完整备份。'), pending: true),
        entry(context, Icons.info_outline, '关于 ClCrm', () => openPage(context, const AboutClCrmPage())),
        entry(context, Icons.description_outlined, '开源许可', () => showLicensePage(context: context, applicationName: 'ClCrm')),
      ]),
    ]));
}

class FontPage extends StatefulWidget {
  const FontPage({super.key, required this.controller});
  final AppController controller;
  @override
  State<FontPage> createState() => _FontPageState();
}
class _FontPageState extends State<FontPage> {
  late bool system = widget.controller.systemFont;
  late double scale = widget.controller.fontScale.clamp(.85, 1.6).toDouble();
  bool saving = false;
  @override
  Widget build(BuildContext context) => Scaffold(appBar: AppBar(title: const Text('字体大小')),
    body: ListView(padding: const EdgeInsets.all(16), children: [
      SwitchListTile.adaptive(title: const Text('跟随系统'), value: system,
        onChanged: saving ? null : (v) => setState(() => system = v)),
      if (!system) ...[Slider(value: scale, min: .85, max: 1.6, divisions: 15,
        label: '${(scale * 100).round()}%', onChanged: saving ? null : (v) => setState(() => scale = v)),
        Text('自定义 ${(scale * 100).round()}%')],
      Padding(padding: const EdgeInsets.symmetric(vertical: 24), child: Text('客户档案与下一次跟进',
        textScaler: system ? MediaQuery.textScalerOf(context) : TextScaler.linear(scale))),
      FilledButton(onPressed: saving ? null : () async {
        setState(() => saving = true);
        final success = await performAction(context, () async {
          await widget.controller.setPreference('font_scale', scale.toString());
          await widget.controller.setPreference('font_system', system.toString());
        });
        if (!mounted) return;
        setState(() => saving = false);
        if (success) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('字号设置已保存')));
      }, child: const Text('应用字号')),
    ]));
}

class NotificationSettingsPage extends StatefulWidget {
  const NotificationSettingsPage({super.key, required this.controller});
  final AppController controller;
  @override
  State<NotificationSettingsPage> createState() => _NotificationSettingsPageState();
}
class _NotificationSettingsPageState extends State<NotificationSettingsPage> {
  bool busy = false;
  Future<void> change(Future<void> Function() action) async {
    if (busy) return;
    setState(() => busy = true);
    await performAction(context, action);
    if (mounted) setState(() => busy = false);
  }
  @override
  Widget build(BuildContext context) => AnimatedBuilder(animation: widget.controller.notifications,
    builder: (context, _) {
      final service = widget.controller.notifications;
      return Scaffold(appBar: AppBar(title: const Text('跟进提醒')), body: ListView(padding: const EdgeInsets.all(16), children: [
        if (busy) const LinearProgressIndicator(),
        SwitchListTile.adaptive(title: const Text('开启跟进提醒'), value: service.enabled,
          onChanged: busy ? null : (v) => change(() => service.configure(active: v))),
        SwitchListTile.adaptive(title: const Text('提前一天提醒'), value: service.advanceDay,
          onChanged: busy ? null : (v) => change(() => service.configure(advance: v))),
        SwitchListTile.adaptive(title: const Text('隐藏客户与事项内容'), value: service.privateContent,
          onChanged: busy ? null : (v) => change(() => service.configure(hideContent: v))),
        const SizedBox(height: 16), Text(service.status),
        Text('系统状态：${service.authorization == 'authorized' ? '已授权' : service.authorization == 'disabled' ? '未授权' : '未确认或不可用'}'),
        const SizedBox(height: 16), OutlinedButton(onPressed: busy ? null : () => change(service.reconcile), child: const Text('重新检查提醒')),
        TextButton(onPressed: busy ? null : () => change(service.openSettings), child: const Text('打开系统设置')),
        const SizedBox(height: 20), const Text('当前仅排程最近的60条未来提醒，超出部分保留在应用内待办，返回应用后重新协调。每日汇总和购买到期自动提醒待完善。'),
      ]));
    });
}

class CategoriesPage extends StatefulWidget {
  const CategoriesPage({super.key, required this.controller});
  final AppController controller;
  @override
  State<CategoriesPage> createState() => _CategoriesPageState();
}
class _CategoriesPageState extends State<CategoriesPage> {
  late Future<List<CrmRecord>> result = widget.controller.db.categories();
  bool busy = false;
  Future<void> edit([CrmRecord? category]) async {
    if (busy) return;
    final text = TextEditingController(text: category?.text('name') ?? '');
    final value = await showDialog<String>(context: context, builder: (ctx) => AlertDialog(
      title: Text(category == null ? '新增业务类别' : '重命名类别'),
      content: TextField(controller: text, autofocus: true, maxLength: 80,
        decoration: const InputDecoration(labelText: '名称')),
      actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
        FilledButton(onPressed: () { if (text.text.trim().isNotEmpty) Navigator.pop(ctx, text.text.trim()); }, child: const Text('保存'))]));
    // Keep the controller alive until the route's reverse transition has completed.
    Future<void>.delayed(const Duration(milliseconds: 400), text.dispose);
    if (value == null || !mounted) return;
    setState(() => busy = true);
    final ok = await performAction(context, () => widget.controller.db.saveCategory(value,
      existing: category, enabled: category?.flag('enabled') ?? true));
    if (!mounted) return;
    setState(() { busy = false; if (ok) result = widget.controller.db.categories(); });
    if (ok) widget.controller.changed();
  }
  @override
  Widget build(BuildContext context) => Scaffold(appBar: AppBar(title: const Text('业务类别'), actions: [
    IconButton(tooltip: '新增类别', onPressed: busy ? null : () => edit(), icon: const Icon(Icons.add)),
  ]), body: FutureBuilder<List<CrmRecord>>(future: result, builder: (context, snapshot) {
    if (snapshot.hasError) return const EmptyState('业务类别读取失败');
    if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
    final categories = snapshot.data!;
    return ReorderableListView.builder(padding: const EdgeInsets.all(16),
      itemCount: categories.length, buildDefaultDragHandles: false,
      onReorder: (oldIndex, newIndex) async {
        if (busy) return;
        if (newIndex > oldIndex) newIndex--;
        final ids = categories.map((c) => c.id).toList();
        ids.insert(newIndex, ids.removeAt(oldIndex));
        setState(() => busy = true);
        final ok = await performAction(context, () => widget.controller.db.reorderCategories(ids));
        if (!mounted) return;
        setState(() { busy = false; result = widget.controller.db.categories(); });
        if (ok) widget.controller.changed();
      }, itemBuilder: (context,index) {
        final c = categories[index];
        return Card(key: ValueKey(c.id), child: ListTile(
        leading: ReorderableDragStartListener(index: index, enabled: !busy, child: const Icon(Icons.drag_handle)),
        title: Text(c.text('name')),
        subtitle: Text(c.flag('enabled') ? '启用' : '已停用，保留历史记录'),
        onTap: busy ? null : () => edit(c), trailing: Switch.adaptive(value: c.flag('enabled'),
          onChanged: busy ? null : (v) async {
            setState(() => busy = true);
            final ok = await performAction(context, () => widget.controller.db.saveCategory(c.text('name'), existing: c, enabled: v));
            if (!mounted) return;
            setState(() { busy = false; if (ok) result = widget.controller.db.categories(); });
            if (ok) widget.controller.changed();
          })));
      });
  }));
}

class ContactsDirectoryPage extends StatefulWidget {
  const ContactsDirectoryPage({super.key, required this.controller});
  final AppController controller;
  @override
  State<ContactsDirectoryPage> createState() => _ContactsDirectoryPageState();
}
class _ContactsDirectoryPageState extends State<ContactsDirectoryPage> {
  late Future<List<CrmRecord>> records = widget.controller.db.contactDirectory();
  @override
  Widget build(BuildContext context) => Scaffold(appBar: AppBar(title: const Text('联系人资料')),
    body: FutureBuilder<List<CrmRecord>>(future: records, builder: (context,snapshot) {
      if (snapshot.hasError) return EmptyState('联系人读取失败', action: TextButton(
        onPressed: () => setState(() => records = widget.controller.db.contactDirectory()), child: const Text('重试')));
      if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
      final list = snapshot.data!;
      return ListView(padding: const EdgeInsets.all(16), children: [
        if (list.isEmpty) const EmptyState('请先在客户档案中添加联系人'),
        for (final person in list) Card(child: ListTile(
          title: Text(person.text('name').isEmpty ? person.text('phone') : person.text('name')),
          subtitle: Text('${person.text('customer_name')}\n${person.text('phone')}'),
          trailing: const Icon(Icons.chevron_right), onTap: () async {
            await openPage(context, ContactEditor(controller: widget.controller,
              customerId: person.text('customer_id'), contact: person));
            if (mounted) setState(() => records = widget.controller.db.contactDirectory());
          })),
        if (list.length >= 200) const Text('当前展示最近修改的200名联系人，更多资料可从客户档案访问。'),
      ]);
    }));
}

class AboutClCrmPage extends StatefulWidget {
  const AboutClCrmPage({super.key});
  @override
  State<AboutClCrmPage> createState() => _AboutClCrmPageState();
}
class _AboutClCrmPageState extends State<AboutClCrmPage> {
  late final Future<Map<String, String>?> information = readInformation();
  Future<Map<String, String>?> readInformation() async {
    try { return await const MethodChannel('vip.ichiki.javalee.clcrm/app_info').invokeMapMethod<String, String>('getAppInfo'); }
    catch (_) { return null; }
  }
  @override
  Widget build(BuildContext context) => Scaffold(appBar: AppBar(title: const Text('关于 ClCrm')),
    body: ListView(padding: const EdgeInsets.all(20), children: [
      Center(child: Image.asset('assets/clcrm.png', width: 112, height: 112)), const SizedBox(height: 16),
      Center(child: Text('ClCrm', style: Theme.of(context).textTheme.headlineMedium)),
      const SizedBox(height: 20), const Text('客户档案、购买记录与业务跟进。无需注册，业务资料保存在当前设备。'),
      const SizedBox(height: 20),
      FutureBuilder<Map<String, String>?>(future: information, builder: (context, snapshot) {
        final version = snapshot.data?['version'] ?? '';
        final build = snapshot.data?['build'] ?? '';
        return ValueLine('版本', version.isEmpty ? '版本信息暂不可用' : '$version${build.isEmpty ? '' : ' ($build)'}');
      }),
      const ValueLine('开发者', '待补充'),
      ListTile(title: const Text('开源许可'), trailing: const Icon(Icons.chevron_right),
        onTap: () => showLicensePage(context: context, applicationName: 'ClCrm')),
    ]));
}

class OperationHistoryPage extends StatelessWidget {
  const OperationHistoryPage({super.key, required this.controller});
  final AppController controller;
  @override
  Widget build(BuildContext context) => Scaffold(appBar: AppBar(title: const Text('操作记录')),
    body: FutureBuilder<List<CrmRecord>>(future: controller.db.events(), builder: (context, snapshot) {
      if (snapshot.hasError) return const EmptyState('操作记录读取失败');
      if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
      final list = snapshot.data!;
      return ListView(padding: const EdgeInsets.all(16), children: [
        if (list.isEmpty) const EmptyState('暂无操作记录'),
        for (final record in list) ListTile(leading: const Icon(Icons.history),
          title: Text(record.text('summary')), subtitle: Text(displayTime(record.values['occurred_at']))),
        if (list.length >= 100) const Text('当前展示最近100条记录。'),
      ]);
    }));
}
