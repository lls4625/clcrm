import 'package:flutter/material.dart';

import '../core/models.dart';

Future<void> openPage(BuildContext context, Widget page) => Navigator.of(context)
  .push<void>(MaterialPageRoute(builder: (_) => page));

Future<bool> confirmAction(BuildContext context, String title, String body,
    {String confirm = '确认'}) async => await showDialog<bool>(context: context,
  builder: (ctx) => AlertDialog(title: Text(title), content: Text(body), actions: [
    TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
    FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(confirm)),
  ])) ?? false;

Future<bool> performAction(BuildContext context, Future<void> Function() action) async {
  try { await action(); return true; }
  catch (error) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(
        error is UserFacingError ? error.message : '操作未完成，原资料已保留。请稍后重试。')));
    }
    return false;
  }
}

class InfoPage extends StatelessWidget {
  const InfoPage({super.key, required this.title, required this.body, this.pending = false});
  final String title;
  final String body;
  final bool pending;
  @override
  Widget build(BuildContext context) => Scaffold(appBar: AppBar(title: Text(title)),
    body: ListView(padding: const EdgeInsets.all(20), children: [
      if (pending) ...[const Align(alignment: Alignment.centerLeft,
        child: Chip(avatar: Icon(Icons.schedule, size: 18), label: Text('待完善'))),
        const SizedBox(height: 16)],
      SelectableText(body, style: Theme.of(context).textTheme.bodyLarge),
    ]));
}

class EmptyState extends StatelessWidget {
  const EmptyState(this.text, {super.key, this.icon = Icons.inbox_outlined, this.action});
  final String text;
  final IconData icon;
  final Widget? action;
  @override
  Widget build(BuildContext context) => Padding(padding: const EdgeInsets.all(32),
    child: Column(mainAxisSize: MainAxisSize.min, children: [
      Icon(icon, size: 44, color: Theme.of(context).colorScheme.outline),
      const SizedBox(height: 12), Text(text, textAlign: TextAlign.center),
      if (action != null) ...[const SizedBox(height: 16), action!],
    ]));
}

class Section extends StatelessWidget {
  const Section(this.title, {super.key, required this.children, this.action});
  final String title;
  final List<Widget> children;
  final Widget? action;
  @override
  Widget build(BuildContext context) => Padding(padding: const EdgeInsets.only(bottom: 20),
    child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Padding(padding: const EdgeInsets.fromLTRB(4, 8, 4, 10), child: Row(children: [
        Expanded(child: Text(title, style: Theme.of(context).textTheme.titleMedium)),
        if (action != null) action!,
      ])),
      Card(margin: EdgeInsets.zero, clipBehavior: Clip.antiAlias,
        child: Column(children: children)),
    ]));
}

class ValueLine extends StatelessWidget {
  const ValueLine(this.label, this.value, {super.key});
  final String label;
  final String value;
  @override
  Widget build(BuildContext context) => Padding(padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
    child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      SizedBox(width: 96, child: Text(label, style: TextStyle(color: Theme.of(context).colorScheme.outline))),
      Expanded(child: SelectableText(value.isEmpty ? '未填写' : value)),
    ]));
}

Future<DateTime?> selectDateTime(BuildContext context, {DateTime? initial, bool dateOnly = false}) async {
  final now = DateTime.now();
  final date = await showDatePicker(context: context, initialDate: initial ?? now,
    firstDate: DateTime(1900), lastDate: DateTime(2200));
  if (date == null || !context.mounted) return null;
  if (dateOnly) return date;
  final time = await showTimePicker(context: context,
    initialTime: TimeOfDay.fromDateTime(initial ?? now));
  return time == null ? null : DateTime(date.year, date.month, date.day, time.hour, time.minute);
}

class DateField extends StatelessWidget {
  const DateField({super.key, required this.label, required this.value,
    required this.onChanged, this.dateOnly = false, this.clearable = false});
  final String label;
  final DateTime? value;
  final ValueChanged<DateTime?> onChanged;
  final bool dateOnly;
  final bool clearable;
  @override
  Widget build(BuildContext context) => Padding(padding: const EdgeInsets.only(bottom: 14),
    child: InputDecorator(decoration: InputDecoration(labelText: label,
      suffixIcon: clearable && value != null ? IconButton(tooltip: '清除日期',
        onPressed: () => onChanged(null), icon: const Icon(Icons.close)) : const Icon(Icons.calendar_today_outlined)),
      child: InkWell(onTap: () async {
        final date = await selectDateTime(context, initial: value, dateOnly: dateOnly);
        if (date != null) onChanged(date);
      }, child: Padding(padding: const EdgeInsets.symmetric(vertical: 10),
        child: Text(value == null ? '请选择' : dateOnly ? dateLabel(value!) : timeLabel(value!))))));
}

class EditorScaffold extends StatefulWidget {
  const EditorScaffold({super.key, required this.title, required this.children,
    required this.onSave, this.formKey});
  final String title;
  final List<Widget> children;
  final Future<void> Function() onSave;
  final GlobalKey<FormState>? formKey;
  @override
  State<EditorScaffold> createState() => _EditorScaffoldState();
}

class _EditorScaffoldState extends State<EditorScaffold> {
  bool saving = false;
  bool dirty = false;
  bool mayLeave = false;
  Future<void> save() async {
    if (saving || (widget.formKey?.currentState?.validate() == false)) return;
    setState(() => saving = true);
    final success = await performAction(context, widget.onSave);
    if (!mounted) return;
    if (success) {
      setState(() { saving = false; dirty = false; mayLeave = true; });
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) Navigator.pop(context);
      });
    } else { setState(() => saving = false); }
  }
  @override
  Widget build(BuildContext context) {
    final body = Form(key: widget.formKey,
      onChanged: () { if (!dirty) setState(() => dirty = true); },
      child: Listener(onPointerDown: (_) { if (!dirty) setState(() => dirty = true); },
        child: ListView(padding: const EdgeInsets.all(20),
          children: [...widget.children, const SizedBox(height: 40)])));
    return PopScope(canPop: !saving && (!dirty || mayLeave),
    onPopInvokedWithResult: (didPop, result) async {
      if (didPop || saving) return;
      if (await confirmAction(context, '放弃编辑？', '未保存的修改将丢失。', confirm: '放弃') && mounted) {
        setState(() => mayLeave = true);
        WidgetsBinding.instance.addPostFrameCallback((_) { if (mounted) Navigator.pop(context); });
      }
    }, child: Scaffold(appBar: AppBar(title: Text(widget.title), actions: [
      Padding(padding: const EdgeInsets.only(right: 12), child: FilledButton(
        onPressed: saving ? null : save,
        child: saving ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)) : const Text('保存'))),
    ]), body: AbsorbPointer(absorbing: saving, child: body)));
  }
}

Widget textField(TextEditingController controller, String label, {bool isRequired = false,
    int lines = 1, TextInputType? keyboard}) => Padding(padding: const EdgeInsets.only(bottom: 14),
  child: TextFormField(controller: controller, decoration: InputDecoration(labelText: label),
    minLines: lines, maxLines: lines == 1 ? 1 : lines + 3,
    keyboardType: keyboard ?? (lines == 1 ? TextInputType.text : TextInputType.multiline),
    validator: isRequired ? (value) => value == null || value.trim().isEmpty ? '请填写$label' : null : null));
