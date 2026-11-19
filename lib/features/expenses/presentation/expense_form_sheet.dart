/// The expense entry form — for recording a new expense and for editing or deleting one.
///
/// Presented as a modal bottom sheet from the dashboard's "Add expense" button, the expenses tab,
/// and by tapping an expense in the list. It captures what a person actually needs to record a
/// spend:
///
/// * **amount** in major units (birr), converted to minor (santim) on submit;
/// * **category** — a required picker from the owner's categories;
/// * **date** — defaults to today (from `todayProvider`, the app's one source of "now"); the picker
///   returns a Gregorian date, sent tagged `gregorian`, and the backend renders both calendars back;
/// * **payment method** and an optional **note**;
/// * an optional **item line** — toggle it on to also record *what* was bought: an item name, a
///   quantity, and the unit it is counted in. This is what feeds the month-end usage report.
///
/// Editing pre-fills every field and sends the whole form as a PATCH; switching the item line off
/// on an expense that had one clears it. Delete asks for confirmation first.
///
/// On success it refreshes every month view (list, dashboard, item usage) and pops.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../platform/api/api.dart';
import '../../../platform/settings.dart';
import '../../../shared_kernel/money.dart';
import 'expense_providers.dart';

/// The payment methods the backend accepts, in the order the pickers show them.
const paymentMethods = ['cash', 'telebirr', 'bank', 'card', 'other'];

String paymentMethodLabel(String method, AppSettings settings) => switch (method) {
  'cash' => settings.say('ጥሬ ገንዘብ', 'Cash'),
  'telebirr' => 'Telebirr',
  'bank' => settings.say('ባንክ', 'Bank'),
  'card' => settings.say('ካርድ', 'Card'),
  _ => settings.say('ሌላ', 'Other'),
};

/// What the sheet did, so a caller can show a confirmation.
enum ExpenseFormResult { recorded, updated, deleted }

/// Show the form as a modal sheet. Pass [expense] to edit (and offer delete) instead of record.
Future<ExpenseFormResult?> showExpenseForm(BuildContext context, {ExpenseDto? expense}) =>
    showModalBottomSheet<ExpenseFormResult>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (_) => ExpenseFormSheet(expense: expense),
    );

/// Ask before deleting. Returns true when the user confirmed.
Future<bool> confirmDeleteExpense(BuildContext context, AppSettings settings) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(settings.say('ወጪውን ልሰርዝ?', 'Delete this expense?')),
      content: Text(settings.say('ይህ ሊመለስ አይችልም።', 'This cannot be undone.')),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: Text(settings.say('ተመለስ', 'Cancel')),
        ),
        FilledButton(
          key: const Key('confirm-delete'),
          style: FilledButton.styleFrom(
            backgroundColor: Theme.of(context).colorScheme.error,
            foregroundColor: Theme.of(context).colorScheme.onError,
          ),
          onPressed: () => Navigator.of(context).pop(true),
          child: Text(settings.say('ሰርዝ', 'Delete')),
        ),
      ],
    ),
  );
  return confirmed ?? false;
}

class ExpenseFormSheet extends ConsumerStatefulWidget {
  const ExpenseFormSheet({super.key, this.expense});

  /// The expense being edited, or null to record a new one.
  final ExpenseDto? expense;

  @override
  ConsumerState<ExpenseFormSheet> createState() => _ExpenseFormSheetState();
}

class _ExpenseFormSheetState extends ConsumerState<ExpenseFormSheet> {
  final _formKey = GlobalKey<FormState>();
  final _amount = TextEditingController();
  final _note = TextEditingController();
  final _itemName = TextEditingController();
  final _quantity = TextEditingController();

  String? _categoryId;
  String _paymentMethod = 'cash';
  late DateTime _date;
  bool _trackItem = false;
  String? _unitId;
  bool _submitting = false;
  String? _submitError;

  static const _paymentMethods = paymentMethods;

  bool get _editing => widget.expense != null;

  @override
  void initState() {
    super.initState();
    final expense = widget.expense;
    if (expense == null) {
      _date = ref.read(todayProvider);
      return;
    }
    _amount.text = _majorText(expense.amount);
    _categoryId = expense.categoryId;
    _paymentMethod = _paymentMethods.contains(expense.paymentMethod)
        ? expense.paymentMethod
        : 'other';
    _date = DateTime.tryParse(expense.spentOn.gregorian) ?? ref.read(todayProvider);
    _note.text = expense.note ?? '';
    final item = expense.item;
    if (item != null) {
      _trackItem = true;
      _itemName.text = item.itemName ?? '';
      _quantity.text = item.quantity;
      _unitId = item.unitId;
    }
  }

  /// 12500 santim -> "125", 12550 -> "125.5": what a person would have typed.
  static String _majorText(Money amount) {
    final major = amount.majorUnits;
    return major == major.roundToDouble()
        ? major.round().toString()
        : major.toStringAsFixed(2).replaceFirst(RegExp(r'0$'), '');
  }

  @override
  void dispose() {
    _amount.dispose();
    _note.dispose();
    _itemName.dispose();
    _quantity.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    if (_categoryId == null) {
      setState(
        () => _submitError = ref.read(settingsProvider).say('ምድብ ይምረጡ', 'Choose a category'),
      );
      return;
    }
    setState(() {
      _submitting = true;
      _submitError = null;
    });
    final settings = ref.read(settingsProvider);
    final amountMinor = Money.fromMajor(
      num.tryParse(_amount.text.trim()) ?? 0,
      settings.currency,
    ).minorUnits;
    final date =
        '${_date.year.toString().padLeft(4, '0')}-${_date.month.toString().padLeft(2, '0')}-${_date.day.toString().padLeft(2, '0')}';
    final note = _note.text.trim();
    final itemName = _trackItem && _itemName.text.trim().isNotEmpty ? _itemName.text.trim() : null;
    final quantity = _trackItem && _quantity.text.trim().isNotEmpty ? _quantity.text.trim() : null;
    final unitId = _trackItem ? _unitId : null;
    try {
      final api = ref.read(expensesApiProvider);
      final expense = widget.expense;
      if (expense == null) {
        await api.record(
          categoryId: _categoryId!,
          amountMinor: amountMinor,
          date: date,
          // The date picker returns a Gregorian date, so tag it gregorian regardless of the
          // owner's display calendar — the backend renders both calendars back.
          dateCalendar: 'gregorian',
          note: note.isEmpty ? null : note,
          paymentMethod: _paymentMethod,
          itemName: itemName,
          quantity: quantity,
          unitId: unitId,
        );
      } else {
        await api.update(
          expense.id,
          // Only when changed: an expense filed under a since-archived category can still be
          // edited, because re-sending that category would be refused.
          categoryId: _categoryId != expense.categoryId ? _categoryId : null,
          amountMinor: amountMinor,
          date: date,
          dateCalendar: 'gregorian',
          // Always sent, so emptying the field clears the note.
          note: note,
          paymentMethod: _paymentMethod,
          itemName: itemName,
          quantity: quantity,
          unitId: unitId,
          clearItem: !_trackItem && expense.item != null,
        );
      }
      // Refresh every month view and the item suggestions so the change (and any new item) shows.
      invalidateMonthData(ref);
      ref.invalidate(itemsProvider);
      if (mounted) {
        Navigator.of(context)
            .pop(_editing ? ExpenseFormResult.updated : ExpenseFormResult.recorded);
      }
    } on ApiException catch (error) {
      setState(() => _submitError = error.message);
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  Future<void> _delete() async {
    final settings = ref.read(settingsProvider);
    if (!await confirmDeleteExpense(context, settings)) return;
    setState(() {
      _submitting = true;
      _submitError = null;
    });
    try {
      await ref.read(expensesApiProvider).delete(widget.expense!.id);
      invalidateMonthData(ref);
      if (mounted) Navigator.of(context).pop(ExpenseFormResult.deleted);
    } on ApiException catch (error) {
      setState(() => _submitError = error.message);
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(settingsProvider);
    final theme = Theme.of(context);
    final categories = ref.watch(categoriesProvider);
    final viewInsets = MediaQuery.of(context).viewInsets.bottom;

    return Padding(
      padding: EdgeInsets.fromLTRB(20, 8, 20, 20 + viewInsets),
      child: SingleChildScrollView(
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                _editing
                    ? settings.say('ወጪ አስተካክል', 'Edit expense')
                    : settings.say('ወጪ መዝግብ', 'Record an expense'),
                style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 20),
              TextFormField(
                key: const Key('expense-amount'),
                controller: _amount,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: InputDecoration(
                  labelText: settings.say('መጠን', 'Amount'),
                  suffixText: settings.currency,
                  prefixIcon: const Icon(Icons.payments_outlined),
                ),
                validator: (v) {
                  final value = num.tryParse((v ?? '').trim());
                  if (value == null || value <= 0) {
                    return settings.say('ትክክለኛ መጠን ያስገቡ', 'Enter a valid amount');
                  }
                  return null;
                },
              ),
              const SizedBox(height: 14),
              categories.when(
                loading: () => const LinearProgressIndicator(),
                error: (e, _) => Text(
                  settings.say('ምድቦችን መጫን አልተቻለም', 'Could not load categories'),
                  style: TextStyle(color: theme.colorScheme.error),
                ),
                data: (list) => DropdownButtonFormField<String>(
                  key: const Key('expense-category'),
                  // An archived category is not offered, so an old expense filed under one has to
                  // be re-filed rather than crash the picker.
                  initialValue: list.any((c) => c.id == _categoryId) ? _categoryId : null,
                  decoration: InputDecoration(
                    labelText: settings.say('ምድብ', 'Category'),
                    prefixIcon: const Icon(Icons.category_outlined),
                  ),
                  items: [
                    for (final c in list)
                      DropdownMenuItem(
                        value: c.id,
                        child: Text(settings.isAmharic ? (c.nameAm ?? c.name) : c.name),
                      ),
                  ],
                  onChanged: (v) => setState(() => _categoryId = v),
                ),
              ),
              const SizedBox(height: 14),
              _DateField(
                date: _date,
                label: settings.say('ቀን', 'Date'),
                onPick: (picked) => setState(() => _date = picked),
              ),
              const SizedBox(height: 14),
              DropdownButtonFormField<String>(
                key: const Key('expense-payment'),
                initialValue: _paymentMethod,
                decoration: InputDecoration(
                  labelText: settings.say('የክፍያ ዘዴ', 'Payment method'),
                  prefixIcon: const Icon(Icons.account_balance_wallet_outlined),
                ),
                items: [
                  for (final m in _paymentMethods)
                    DropdownMenuItem(value: m, child: Text(paymentMethodLabel(m, settings))),
                ],
                onChanged: (v) => setState(() => _paymentMethod = v ?? 'cash'),
              ),
              const SizedBox(height: 14),
              TextFormField(
                key: const Key('expense-note'),
                controller: _note,
                decoration: InputDecoration(
                  labelText: settings.say('ማስታወሻ (አማራጭ)', 'Note (optional)'),
                  prefixIcon: const Icon(Icons.notes_outlined),
                ),
              ),
              const SizedBox(height: 8),
              SwitchListTile(
                key: const Key('expense-track-item'),
                contentPadding: EdgeInsets.zero,
                title: Text(settings.say('ዕቃ መዝግብ', 'Track an item')),
                subtitle: Text(
                  settings.say(
                    'ምን ያህል ኪሎ/ሊትር እንደገዙ ይመዝግቡ',
                    'Record how much (kg, litre…) you bought',
                  ),
                  style: theme.textTheme.bodySmall,
                ),
                value: _trackItem,
                onChanged: (v) => setState(() => _trackItem = v),
              ),
              if (_trackItem) _buildItemLine(settings, theme),
              if (_submitError != null) ...[
                const SizedBox(height: 12),
                Text(
                  _submitError!,
                  key: const Key('expense-error'),
                  style: TextStyle(color: theme.colorScheme.error),
                ),
              ],
              const SizedBox(height: 20),
              FilledButton(
                key: const Key('expense-submit'),
                onPressed: _submitting ? null : _submit,
                style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 16)),
                child: _submitting
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Text(
                        _editing
                            ? settings.say('ለውጡን አስቀምጥ', 'Save changes')
                            : settings.say('መዝግብ', 'Save expense'),
                      ),
              ),
              if (_editing) ...[
                const SizedBox(height: 8),
                TextButton.icon(
                  key: const Key('expense-delete'),
                  onPressed: _submitting ? null : _delete,
                  icon: Icon(Icons.delete_outline_rounded, color: theme.colorScheme.error),
                  label: Text(
                    settings.say('ሰርዝ', 'Delete expense'),
                    style: TextStyle(color: theme.colorScheme.error),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildItemLine(AppSettings settings, ThemeData theme) {
    final units = ref.watch(unitsProvider);
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextFormField(
            key: const Key('expense-item-name'),
            controller: _itemName,
            decoration: InputDecoration(
              labelText: settings.say('የዕቃ ስም', 'Item name'),
              hintText: settings.say('ለምሳሌ ስኳር', 'e.g. Sugar'),
              prefixIcon: const Icon(Icons.shopping_basket_outlined),
            ),
            validator: (v) {
              if (_trackItem && (v == null || v.trim().isEmpty)) {
                return settings.say('የዕቃ ስም ያስፈልጋል', 'Item name is required');
              }
              return null;
            },
          ),
          const SizedBox(height: 14),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: TextFormField(
                  key: const Key('expense-quantity'),
                  controller: _quantity,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: InputDecoration(labelText: settings.say('ብዛት', 'Quantity')),
                  validator: (v) {
                    if (!_trackItem) return null;
                    final value = num.tryParse((v ?? '').trim());
                    if (value == null || value <= 0) {
                      return settings.say('ብዛት ያስገቡ', 'Enter a quantity');
                    }
                    return null;
                  },
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: units.when(
                  loading: () => const Padding(
                    padding: EdgeInsets.only(top: 8),
                    child: LinearProgressIndicator(),
                  ),
                  error: (e, _) => Text(
                    settings.say('ክፍሎችን መጫን አልተቻለም', 'Could not load units'),
                    style: TextStyle(color: theme.colorScheme.error, fontSize: 12),
                  ),
                  data: (list) => DropdownButtonFormField<String>(
                    key: const Key('expense-unit'),
                    initialValue: list.any((u) => u.id == _unitId) ? _unitId : null,
                    isExpanded: true,
                    decoration: InputDecoration(labelText: settings.say('ክፍል', 'Unit')),
                    items: [
                      for (final u in list)
                        DropdownMenuItem(
                          value: u.id,
                          child: Text(
                            '${u.code} · ${settings.isAmharic ? (u.nameAm ?? u.name) : u.name}',
                          ),
                        ),
                    ],
                    onChanged: (v) => setState(() => _unitId = v),
                    validator: (v) =>
                        (_trackItem && v == null) ? settings.say('ክፍል ይምረጡ', 'Pick a unit') : null,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _DateField extends StatelessWidget {
  const _DateField({required this.date, required this.label, required this.onPick});

  final DateTime date;
  final String label;
  final ValueChanged<DateTime> onPick;

  @override
  Widget build(BuildContext context) {
    final text =
        '${date.year.toString().padLeft(4, '0')}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
    return InkWell(
      key: const Key('expense-date'),
      onTap: () async {
        final picked = await showDatePicker(
          context: context,
          initialDate: date,
          firstDate: DateTime(2000),
          lastDate: DateTime(2100),
        );
        if (picked != null) onPick(picked);
      },
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: label,
          prefixIcon: const Icon(Icons.calendar_today_outlined),
        ),
        child: Text(text),
      ),
    );
  }
}
