/// The Fixed tab: monthly commitments (rent, internet, school fees) and whether this month is paid.
///
/// For the month in the navigator it shows the totals — committed, paid, still to pay — then one
/// row per commitment owed that month, soonest due first. The circle on a row marks it paid (asking
/// for the amount, since the electricity bill is rarely what was budgeted) or undoes the payment.
/// Tapping a row opens its actions: edit, pause or resume, delete.
///
/// Commitments not owed this month — paused, or outside their start/end — are listed underneath so
/// they can still be found and resumed. Occurrences are computed by the server for whatever calendar
/// is being viewed, so ሐምሌ and July find the same rent.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../platform/api/api.dart';
import '../../../platform/settings.dart';
import '../../../shared/month_data.dart';
import '../../../shared/widgets/gradient_action_button.dart';
import '../../../shared/widgets/period_navigator.dart';
import '../../../shared/widgets/section_card.dart';
import '../../../shared_kernel/ethiopian_date.dart';
import '../../../shared_kernel/money.dart';
import '../../../shared_kernel/period.dart';
import '../../assistant/assistant_sheet.dart';
import 'fixed_expense_form_sheet.dart';

class FixedExpensesScreen extends ConsumerWidget {
  const FixedExpensesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsProvider);
    final month = ref.watch(occurrencesProvider);
    final commitments = ref.watch(fixedExpensesProvider);

    return Scaffold(
      appBar: AppBar(
        title: Text(settings.say('ቋሚ ወርሃዊ ወጪ', 'Fixed monthly expenses')),
        bottom: const PreferredSize(
          preferredSize: Size.fromHeight(76),
          child: Padding(
            padding: EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: PeriodNavigator(keyPrefix: 'fixed-'),
          ),
        ),
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(occurrencesProvider);
          ref.invalidate(fixedExpensesProvider);
          await ref.read(occurrencesProvider.future).then((_) {}, onError: (_) {});
        },
        child: switch ((month, commitments)) {
          (AsyncValue(hasError: true, :final error), _) ||
          (_, AsyncValue(hasError: true, :final error)) =>
            _Message(
              icon: Icons.cloud_off_outlined,
              text: error is ApiException
                  ? error.message
                  : settings.say('መጫን አልተቻለም', 'Could not load fixed expenses'),
              action: TextButton(
                onPressed: () {
                  ref.invalidate(occurrencesProvider);
                  ref.invalidate(fixedExpensesProvider);
                },
                child: Text(settings.say('እንደገና ሞክር', 'Retry')),
              ),
            ),
          (AsyncValue(:final valueOrNull?), AsyncValue(valueOrNull: final all?)) =>
            all.isEmpty
                ? _Message(
                    key: const Key('fixed-empty'),
                    icon: Icons.event_repeat_outlined,
                    text: settings.say(
                      'ቤት ኪራይ፣ ኢንተርኔት እና ሌሎች ወርሃዊ ክፍያዎችን እዚህ ይመዝግቡ።',
                      'Add rent, internet and other monthly commitments here.',
                    ),
                  )
                : _FixedList(month: valueOrNull, all: all, settings: settings),
          _ => const Center(child: CircularProgressIndicator()),
        },
      ),
      floatingActionButton: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          // "Rent 8,000 every month on the 5th" or "I paid the rent", by voice.
          const AssistantButton(),
          GradientActionButton(
            key: const Key('fixed-add'),
            icon: Icons.add_rounded,
            label: settings.say('ቋሚ ወጪ ጨምር', 'Add fixed'),
            onPressed: () => showFixedExpenseForm(context),
          ),
        ],
      ),
    );
  }
}

class _FixedList extends ConsumerWidget {
  const _FixedList({required this.month, required this.all, required this.settings});

  final OccurrenceMonthDto month;
  final List<FixedExpenseDto> all;
  final AppSettings settings;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final owedIds = {for (final o in month.occurrences) o.fixedExpenseId};
    final notOwed = all.where((c) => !owedIds.contains(c.id)).toList();
    final byId = {for (final c in all) c.id: c};

    return ListView(
      key: const Key('fixed-list'),
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 120),
      children: [
        _Totals(month: month, settings: settings),
        const SizedBox(height: 16),
        SectionCard(
          title: settings.say('በዚህ ወር', 'This month'),
          subtitle: month.occurrences.isEmpty
              ? null
              : settings.say('ክበቡን በመንካት እንደተከፈለ ምልክት ያድርጉ', 'Tap the circle to mark it paid'),
          child: month.occurrences.isEmpty
              ? Padding(
                  key: const Key('fixed-none-this-month'),
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Text(settings.say('በዚህ ወር የሚከፈል የለም።', 'Nothing due this month.')),
                )
              : Column(
                  children: [
                    for (final occurrence in month.occurrences)
                      _OccurrenceRow(
                        occurrence: occurrence,
                        commitment: byId[occurrence.fixedExpenseId],
                        settings: settings,
                      ),
                  ],
                ),
        ),
        if (notOwed.isNotEmpty) ...[
          const SizedBox(height: 16),
          SectionCard(
            title: settings.say('በዚህ ወር የማይከፈሉ', 'Not due this month'),
            subtitle: settings.say('የቆሙ ወይም ገና ያልጀመሩ', 'Paused, not started yet, or ended'),
            child: Column(
              children: [
                for (final commitment in notOwed)
                  _CommitmentRow(commitment: commitment, settings: settings),
              ],
            ),
          ),
        ],
      ],
    );
  }
}

class _Totals extends StatelessWidget {
  const _Totals({required this.month, required this.settings});

  final OccurrenceMonthDto month;
  final AppSettings settings;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    Widget cell(String label, Money amount, Key key, {Color? color}) => Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 2),
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text(
                  amount.formatRounded(),
                  key: key,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                    color: color,
                  ),
                ),
              ),
            ],
          ),
        );
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Row(
          children: [
            cell(settings.say('ጠቅላላ', 'Committed'), month.committed,
                const Key('fixed-total-committed')),
            cell(settings.say('ተከፍሏል', 'Paid'), month.settled, const Key('fixed-total-settled'),
                color: theme.colorScheme.primary),
            cell(
              settings.say('ይቀራል', 'Still to pay'),
              month.outstanding,
              const Key('fixed-total-outstanding'),
              color: month.outstanding.isZero ? null : theme.colorScheme.error,
            ),
          ],
        ),
      ),
    );
  }
}

/// "ሐምሌ 5" or "July 12", in the calendar the owner reads.
String _dateLabel(SpendDateDto date, AppSettings settings) {
  if (settings.calendar == CalendarKind.ethiopian) {
    final day = int.tryParse(date.ethiopian.split('-').last) ?? 1;
    final name = settings.isAmharic ? date.ethiopianMonthNameAm : date.ethiopianMonthNameEn;
    return '$name $day';
  }
  final value = DateTime.parse(date.gregorian);
  final names = settings.isAmharic ? gregorianMonthNamesAm : gregorianMonthNamesEn;
  return '${names[value.month - 1]} ${value.day}';
}

class _OccurrenceRow extends ConsumerWidget {
  const _OccurrenceRow({
    required this.occurrence,
    required this.commitment,
    required this.settings,
  });

  final OccurrenceDto occurrence;
  final FixedExpenseDto? commitment;
  final AppSettings settings;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final settled = occurrence.isSettled;
    final category = settings.isAmharic
        ? (occurrence.categoryNameAm ?? occurrence.categoryName)
        : occurrence.categoryName;
    final status = settled && occurrence.settledOn != null
        ? settings.say(
            '${_dateLabel(occurrence.settledOn!, settings)} ተከፍሏል',
            'Paid ${_dateLabel(occurrence.settledOn!, settings)}',
          )
        : settings.say(
            '${_dateLabel(occurrence.dueDate, settings)} ይከፈላል',
            'Due ${_dateLabel(occurrence.dueDate, settings)}',
          );

    return ListTile(
      key: Key('occurrence-${occurrence.fixedExpenseId}'),
      contentPadding: EdgeInsets.zero,
      onTap: commitment == null
          ? null
          : () => _showActions(context, ref, commitment!, settings, occurrence: occurrence),
      leading: IconButton(
        key: Key('settle-${occurrence.fixedExpenseId}'),
        tooltip: settled
            ? settings.say('ክፍያውን መልስ', 'Undo payment')
            : settings.say('እንደተከፈለ ምልክት አድርግ', 'Mark as paid'),
        icon: Icon(
          settled ? Icons.check_circle_rounded : Icons.radio_button_unchecked_rounded,
          color: settled ? theme.colorScheme.primary : theme.colorScheme.onSurfaceVariant,
        ),
        onPressed: () => settled
            ? _unsettle(context, ref, occurrence, settings)
            : _settle(context, ref, occurrence, settings),
      ),
      title: Text(
        occurrence.title,
        style: TextStyle(
          fontWeight: FontWeight.w600,
          decoration: settled ? TextDecoration.lineThrough : null,
        ),
      ),
      subtitle: Text([status, if (category != null) category].join(' · ')),
      trailing: Text(
        occurrence.amount.formatRounded(),
        style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
      ),
    );
  }
}

class _CommitmentRow extends ConsumerWidget {
  const _CommitmentRow({required this.commitment, required this.settings});

  final FixedExpenseDto commitment;
  final AppSettings settings;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final status = commitment.isPaused
        ? settings.say('ቆሟል', 'Paused')
        : settings.say(
            'ከ${commitment.startPeriod.label(settings.language)}',
            'From ${commitment.startPeriod.label(settings.language)}',
          );
    return ListTile(
      key: Key('commitment-${commitment.id}'),
      contentPadding: EdgeInsets.zero,
      onTap: () => _showActions(context, ref, commitment, settings),
      leading: Icon(
        commitment.isPaused ? Icons.pause_circle_outline_rounded : Icons.schedule_rounded,
        color: theme.colorScheme.onSurfaceVariant,
      ),
      title: Text(commitment.title, style: const TextStyle(fontWeight: FontWeight.w600)),
      subtitle: Text(status),
      trailing: Text(commitment.amount.formatRounded()),
    );
  }
}

// -- actions -------------------------------------------------------------

/// Run [action]; refresh every month view on success, show the server's message on failure.
Future<void> _run(
  BuildContext context,
  WidgetRef ref,
  Future<void> Function() action, {
  String? done,
}) async {
  final messenger = ScaffoldMessenger.maybeOf(context);
  try {
    await action();
    invalidateMonthData(ref);
    if (done != null) messenger?.showSnackBar(SnackBar(content: Text(done)));
  } on ApiException catch (error) {
    messenger?.showSnackBar(SnackBar(content: Text(error.message)));
  }
}

Future<void> _settle(
  BuildContext context,
  WidgetRef ref,
  OccurrenceDto occurrence,
  AppSettings settings,
) async {
  final paid = await showDialog<({int amountMinor, DateTime paidOn})>(
    context: context,
    builder: (_) => _SettleDialog(
      occurrence: occurrence,
      settings: settings,
      today: ref.read(todayProvider),
    ),
  );
  if (paid == null || !context.mounted) return;
  final amountMinor = paid.amountMinor;
  await _run(
    context,
    ref,
    () => ref.read(fixedExpensesApiProvider).settle(
          occurrence.fixedExpenseId,
          occurrence.period,
          amountMinor: amountMinor == occurrence.amount.minorUnits ? null : amountMinor,
          settledOn: _isoDate(paid.paidOn),
        ),
    done: settings.say('${occurrence.title} ተከፍሏል', '${occurrence.title} marked as paid'),
  );
}

Future<void> _unsettle(
  BuildContext context,
  WidgetRef ref,
  OccurrenceDto occurrence,
  AppSettings settings,
) =>
    _run(
      context,
      ref,
      () => ref
          .read(fixedExpensesApiProvider)
          .unsettle(occurrence.fixedExpenseId, occurrence.period),
      done: settings.say('ክፍያው ተመልሷል', 'Payment undone'),
    );

Future<void> _showActions(
  BuildContext context,
  WidgetRef ref,
  FixedExpenseDto commitment,
  AppSettings settings, {
  OccurrenceDto? occurrence,
}) async {
  final choice = await showModalBottomSheet<String>(
    context: context,
    showDragHandle: true,
    builder: (sheetContext) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            title: Text(
              commitment.title,
              style: Theme.of(sheetContext).textTheme.titleMedium,
            ),
            subtitle: Text(
              settings.say(
                'በየወሩ ${commitment.amount.formatRounded()} · ቀን ${commitment.dueDay}',
                '${commitment.amount.formatRounded()} a month · due day ${commitment.dueDay}',
              ),
            ),
          ),
          const Divider(height: 1),
          if (occurrence != null)
            ListTile(
              key: const Key('fixed-action-settle'),
              leading: Icon(occurrence.isSettled ? Icons.undo_rounded : Icons.check_rounded),
              title: Text(occurrence.isSettled
                  ? settings.say('ክፍያውን መልስ', 'Undo payment')
                  : settings.say('እንደተከፈለ ምልክት አድርግ', 'Mark as paid')),
              onTap: () => Navigator.of(sheetContext).pop('settle'),
            ),
          ListTile(
            key: const Key('fixed-action-edit'),
            leading: const Icon(Icons.edit_outlined),
            title: Text(settings.say('አስተካክል', 'Edit')),
            onTap: () => Navigator.of(sheetContext).pop('edit'),
          ),
          ListTile(
            key: Key(commitment.isPaused ? 'fixed-action-resume' : 'fixed-action-pause'),
            leading: Icon(
              commitment.isPaused ? Icons.play_arrow_rounded : Icons.pause_rounded,
            ),
            title: Text(commitment.isPaused
                ? settings.say('ቀጥል', 'Resume')
                : settings.say('ለጊዜው አቁም', 'Pause')),
            onTap: () => Navigator.of(sheetContext).pop(commitment.isPaused ? 'resume' : 'pause'),
          ),
          ListTile(
            key: const Key('fixed-action-delete'),
            leading: Icon(Icons.delete_outline_rounded,
                color: Theme.of(sheetContext).colorScheme.error),
            title: Text(
              settings.say('ሰርዝ', 'Delete'),
              style: TextStyle(color: Theme.of(sheetContext).colorScheme.error),
            ),
            onTap: () => Navigator.of(sheetContext).pop('delete'),
          ),
        ],
      ),
    ),
  );
  if (choice == null || !context.mounted) return;
  final api = ref.read(fixedExpensesApiProvider);
  switch (choice) {
    case 'settle':
      if (occurrence == null) return;
      await (occurrence.isSettled
          ? _unsettle(context, ref, occurrence, settings)
          : _settle(context, ref, occurrence, settings));
    case 'edit':
      await showFixedExpenseForm(context, commitment: commitment);
    case 'pause':
      await _run(context, ref, () => api.pause(commitment.id),
          done: settings.say('ለጊዜው ቆሟል', 'Paused'));
    case 'resume':
      await _run(context, ref, () => api.resume(commitment.id),
          done: settings.say('ቀጥሏል', 'Resumed'));
    case 'delete':
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: Text(settings.say('${commitment.title} ልሰርዝ?', 'Delete ${commitment.title}?')),
          content: Text(settings.say(
            'የተመዘገቡ ክፍያዎችም አብረው ይሰረዛሉ። ለጊዜው ማቆም ታሪኩን ይጠብቃል።',
            'Its recorded payments are deleted too. Pausing keeps the history.',
          )),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: Text(settings.say('ተመለስ', 'Cancel')),
            ),
            FilledButton(
              key: const Key('confirm-delete'),
              style: FilledButton.styleFrom(
                backgroundColor: Theme.of(dialogContext).colorScheme.error,
                foregroundColor: Theme.of(dialogContext).colorScheme.onError,
              ),
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: Text(settings.say('ሰርዝ', 'Delete')),
            ),
          ],
        ),
      );
      if (confirmed != true || !context.mounted) return;
      await _run(context, ref, () => api.delete(commitment.id),
          done: settings.say('ተሰርዟል', 'Deleted'));
  }
}

String _isoDate(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-'
    '${d.day.toString().padLeft(2, '0')}';

/// "ነሐሴ 29, 2018" or "September 4, 2026", in the calendar the owner reads.
String _fullDate(DateTime d, AppSettings settings) {
  if (settings.calendar == CalendarKind.ethiopian) {
    return EthiopianDate.fromGregorian(d).format(locale: settings.language.wire);
  }
  final names = settings.isAmharic ? gregorianMonthNamesAm : gregorianMonthNamesEn;
  return '${names[d.month - 1]} ${d.day}, ${d.year}';
}

/// Ask what was actually paid and when: prefilled with the committed amount and today.
class _SettleDialog extends StatefulWidget {
  const _SettleDialog({required this.occurrence, required this.settings, required this.today});

  final OccurrenceDto occurrence;
  final AppSettings settings;
  final DateTime today;

  @override
  State<_SettleDialog> createState() => _SettleDialogState();
}

class _SettleDialogState extends State<_SettleDialog> {
  late final TextEditingController _amount;
  late DateTime _paidOn = widget.today;
  String? _error;

  @override
  void initState() {
    super.initState();
    final major = widget.occurrence.amount.majorUnits;
    _amount = TextEditingController(
      text: major == major.roundToDouble() ? major.round().toString() : major.toStringAsFixed(2),
    );
  }

  @override
  void dispose() {
    _amount.dispose();
    super.dispose();
  }

  void _confirm() {
    final value = num.tryParse(_amount.text.trim());
    if (value == null || value <= 0) {
      setState(() => _error = widget.settings.say('ትክክለኛ መጠን ያስገቡ', 'Enter a valid amount'));
      return;
    }
    Navigator.of(context).pop((amountMinor: Money.fromMajor(value).minorUnits, paidOn: _paidOn));
  }

  @override
  Widget build(BuildContext context) {
    final settings = widget.settings;
    return AlertDialog(
      title: Text(settings.say('${widget.occurrence.title} ተከፍሏል', 'Mark ${widget.occurrence.title} paid')),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            key: const Key('settle-amount'),
            controller: _amount,
            autofocus: true,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: InputDecoration(
              labelText: settings.say('የተከፈለው መጠን', 'Amount paid'),
              suffixText: widget.occurrence.amount.currency,
              errorText: _error,
            ),
            onSubmitted: (_) => _confirm(),
          ),
          const SizedBox(height: 12),
          InkWell(
            key: const Key('settle-date'),
            onTap: () async {
              final picked = await showDatePicker(
                context: context,
                initialDate: _paidOn,
                firstDate: DateTime(2000),
                // A payment cannot be recorded in the future.
                lastDate: widget.today,
              );
              if (picked != null) {
                setState(() => _paidOn = DateTime.utc(picked.year, picked.month, picked.day));
              }
            },
            child: InputDecorator(
              decoration: InputDecoration(
                labelText: settings.say('የተከፈለበት ቀን', 'Paid on'),
                prefixIcon: const Icon(Icons.event_available_outlined),
              ),
              child: Text(_fullDate(_paidOn, settings), key: const Key('settle-date-label')),
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(settings.say('ተመለስ', 'Cancel')),
        ),
        FilledButton(
          key: const Key('settle-confirm'),
          onPressed: _confirm,
          child: Text(settings.say('ተከፍሏል', 'Paid')),
        ),
      ],
    );
  }
}

class _Message extends StatelessWidget {
  const _Message({super.key, required this.icon, required this.text, this.action});

  final IconData icon;
  final String text;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // A ListView so pull-to-refresh still works.
    return ListView(
      padding: const EdgeInsets.all(32),
      children: [
        const SizedBox(height: 80),
        Icon(icon, size: 48, color: theme.colorScheme.onSurfaceVariant),
        const SizedBox(height: 12),
        Text(
          text,
          textAlign: TextAlign.center,
          style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
        ),
        if (action != null) ...[const SizedBox(height: 8), Center(child: action)],
      ],
    );
  }
}
