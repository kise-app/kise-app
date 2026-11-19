/// The form for scheduling or editing a Fixed Monthly Expense — rent, internet, school fees.
///
/// Captures a title, the monthly amount, a category and the day of the month it falls due (1–30:
/// Ethiopian months have 30 days, and a due day past the end of a short month such as ጳጉሜን or
/// February is pulled back to its last day by the server). A new commitment starts in the month
/// being viewed, in the calendar the user is viewing it in — which becomes its anchor calendar.
///
/// An optional **last month** ends a commitment that does not run forever (a 12-month lease, a
/// school year). It is stepped month by month in the anchor calendar and can never precede the
/// start; the server additionally refuses to end before a month that is already paid.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../platform/api/api.dart';
import '../../../platform/settings.dart';
import '../../../shared/month_data.dart';
import '../../../shared_kernel/money.dart';
import '../../../shared_kernel/period.dart';
import '../../expenses/presentation/expense_providers.dart' show categoriesProvider;

/// Show the form. Pass [commitment] to edit instead of schedule. Returns true on save.
Future<bool?> showFixedExpenseForm(BuildContext context, {FixedExpenseDto? commitment}) =>
    showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (_) => FixedExpenseFormSheet(commitment: commitment),
    );

class FixedExpenseFormSheet extends ConsumerStatefulWidget {
  const FixedExpenseFormSheet({super.key, this.commitment});

  final FixedExpenseDto? commitment;

  @override
  ConsumerState<FixedExpenseFormSheet> createState() => _FixedExpenseFormSheetState();
}

class _FixedExpenseFormSheetState extends ConsumerState<FixedExpenseFormSheet> {
  final _formKey = GlobalKey<FormState>();
  final _title = TextEditingController();
  final _amount = TextEditingController();
  final _note = TextEditingController();
  String? _categoryId;
  int _dueDay = 1;
  bool _hasEnd = false;
  late Period _start;
  late Period _end;
  bool _submitting = false;
  String? _error;

  bool get _editing => widget.commitment != null;

  @override
  void initState() {
    super.initState();
    final commitment = widget.commitment;
    _start = commitment?.startPeriod ?? ref.read(selectedPeriodProvider);
    _hasEnd = commitment?.endPeriod != null;
    // A year is the common case for a commitment with an end: offer it as the starting point.
    _end = commitment?.endPeriod ?? _start.shift(_start.calendar.monthsPerYear - 1);
    if (commitment != null) {
      _title.text = commitment.title;
      final major = commitment.amount.majorUnits;
      _amount.text = major == major.roundToDouble()
          ? major.round().toString()
          : major.toStringAsFixed(2);
      _note.text = commitment.note ?? '';
      _categoryId = commitment.categoryId;
      _dueDay = commitment.dueDay;
    }
  }

  @override
  void dispose() {
    _title.dispose();
    _amount.dispose();
    _note.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final settings = ref.read(settingsProvider);
    if (!_formKey.currentState!.validate()) return;
    if (_categoryId == null) {
      setState(() => _error = settings.say('ምድብ ይምረጡ', 'Choose a category'));
      return;
    }
    setState(() {
      _submitting = true;
      _error = null;
    });
    final amountMinor = Money.fromMajor(num.parse(_amount.text.trim())).minorUnits;
    final note = _note.text.trim();
    final api = ref.read(fixedExpensesApiProvider);
    try {
      final commitment = widget.commitment;
      if (commitment == null) {
        await api.schedule(
          categoryId: _categoryId!,
          title: _title.text.trim(),
          amountMinor: amountMinor,
          startPeriod: _start,
          endPeriod: _hasEnd ? _end : null,
          dueDay: _dueDay,
          note: note.isEmpty ? null : note,
        );
      } else {
        await api.update(
          commitment.id,
          title: _title.text.trim(),
          amountMinor: amountMinor,
          categoryId: _categoryId != commitment.categoryId ? _categoryId : null,
          dueDay: _dueDay,
          note: note,
          endPeriod: _hasEnd && _end != commitment.endPeriod ? _end : null,
          clearEndPeriod: !_hasEnd && commitment.endPeriod != null,
        );
      }
      invalidateMonthData(ref);
      if (mounted) Navigator.of(context).pop(true);
    } on ApiException catch (error) {
      setState(() => _error = error.message);
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(settingsProvider);
    final categories = ref.watch(categoriesProvider);
    final theme = Theme.of(context);
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
                    ? settings.say('ቋሚ ወጪ አስተካክል', 'Edit fixed expense')
                    : settings.say('ቋሚ ወርሃዊ ወጪ ጨምር', 'Add a fixed monthly expense'),
                style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
              ),
              if (!_editing) ...[
                const SizedBox(height: 4),
                Text(
                  settings.say(
                    'ከ${_start.label(settings.language)} ጀምሮ በየወሩ',
                    'Every month from ${_start.label(settings.language)}',
                  ),
                  key: const Key('fixed-start-label'),
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
              const SizedBox(height: 20),
              TextFormField(
                key: const Key('fixed-title'),
                controller: _title,
                textCapitalization: TextCapitalization.sentences,
                decoration: InputDecoration(
                  labelText: settings.say('ርዕስ', 'Title'),
                  hintText: settings.say('ለምሳሌ ቤት ኪራይ', 'e.g. Rent'),
                  prefixIcon: const Icon(Icons.label_outline_rounded),
                ),
                validator: (v) => (v == null || v.trim().isEmpty)
                    ? settings.say('ርዕስ ያስፈልጋል', 'A title is required')
                    : null,
              ),
              const SizedBox(height: 14),
              TextFormField(
                key: const Key('fixed-amount'),
                controller: _amount,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: InputDecoration(
                  labelText: settings.say('ወርሃዊ መጠን', 'Monthly amount'),
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
                  key: const Key('fixed-category'),
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
              DropdownButtonFormField<int>(
                key: const Key('fixed-due-day'),
                initialValue: _dueDay,
                decoration: InputDecoration(
                  labelText: settings.say('የሚከፈልበት ቀን', 'Due day of the month'),
                  helperText: settings.say(
                    'ከወሩ ርዝመት በላይ ከሆነ በወሩ መጨረሻ ቀን ይሆናል',
                    'Falls on the last day in shorter months',
                  ),
                  prefixIcon: const Icon(Icons.event_outlined),
                ),
                items: [
                  for (var day = 1; day <= 30; day++)
                    DropdownMenuItem(value: day, child: Text('$day')),
                ],
                onChanged: (v) => setState(() => _dueDay = v ?? 1),
              ),
              const SizedBox(height: 8),
              SwitchListTile(
                key: const Key('fixed-has-end'),
                contentPadding: EdgeInsets.zero,
                title: Text(settings.say('የሚያበቃበት ወር አለው', 'Ends after a set month')),
                subtitle: Text(
                  settings.say('ለምሳሌ የአንድ ዓመት ውል', 'e.g. a one-year lease'),
                  style: theme.textTheme.bodySmall,
                ),
                value: _hasEnd,
                onChanged: (v) => setState(() => _hasEnd = v),
              ),
              if (_hasEnd)
                InputDecorator(
                  decoration: InputDecoration(
                    labelText: settings.say('የመጨረሻው ወር', 'Last month'),
                    prefixIcon: const Icon(Icons.event_busy_outlined),
                  ),
                  child: Row(
                    children: [
                      IconButton(
                        key: const Key('fixed-end-previous'),
                        tooltip: settings.say('ያለፈው ወር', 'Previous month'),
                        visualDensity: VisualDensity.compact,
                        icon: const Icon(Icons.chevron_left_rounded),
                        onPressed: _end > _start
                            ? () => setState(() => _end = _end.previous)
                            : null,
                      ),
                      Expanded(
                        child: Text(
                          _end.label(settings.language),
                          key: const Key('fixed-end-label'),
                          textAlign: TextAlign.center,
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                      ),
                      IconButton(
                        key: const Key('fixed-end-next'),
                        tooltip: settings.say('የሚቀጥለው ወር', 'Next month'),
                        visualDensity: VisualDensity.compact,
                        icon: const Icon(Icons.chevron_right_rounded),
                        onPressed: () => setState(() => _end = _end.next),
                      ),
                    ],
                  ),
                ),
              const SizedBox(height: 14),
              TextFormField(
                key: const Key('fixed-note'),
                controller: _note,
                decoration: InputDecoration(
                  labelText: settings.say('ማስታወሻ (አማራጭ)', 'Note (optional)'),
                  prefixIcon: const Icon(Icons.notes_outlined),
                ),
              ),
              if (_error != null) ...[
                const SizedBox(height: 12),
                Text(
                  _error!,
                  key: const Key('fixed-error'),
                  style: TextStyle(color: theme.colorScheme.error),
                ),
              ],
              const SizedBox(height: 20),
              FilledButton(
                key: const Key('fixed-submit'),
                onPressed: _submitting ? null : _submit,
                style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 16)),
                child: _submitting
                    ? const SizedBox(
                        height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2))
                    : Text(_editing
                        ? settings.say('ለውጡን አስቀምጥ', 'Save changes')
                        : settings.say('ጨምር', 'Add')),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
