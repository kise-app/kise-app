/// Personal settings.
///
/// Ordered by consequence: who you are, then the calendar and language that change every screen,
/// then currency and budget, then the account (categories, password). The two big choices are
/// cards rather than segmented buttons — each one shows *today's date in that calendar*, so the
/// effect of the choice is visible before making it.
///
/// Name, calendar and language are saved to the account (see `ProfileSync`); theme stays on this
/// device; the budget lives on the server.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../platform/api/api.dart';
import '../../../platform/session/session_controller.dart';
import '../../../platform/settings.dart';
import '../../../platform/theme.dart';
import '../../../shared/month_data.dart';
import '../../../shared/widgets/option_card.dart';
import '../../../shared_kernel/ethiopian_date.dart';
import '../../../shared_kernel/money.dart';
import '../../../shared_kernel/period.dart';
import '../../categories/presentation/categories_screen.dart';
import '../../plans/upgrade_sheet.dart';
import 'change_password_dialog.dart';

const budgetShortcutsMajor = [5000, 10000, 15000, 25000];

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsProvider);
    final today = ref.watch(todayProvider);

    return Scaffold(
      body: ListView(
        padding: EdgeInsets.zero,
        children: [
          _Header(settings: settings),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 20, 16, 32),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _ProfileCard(settings: settings),
                const SizedBox(height: 24),
                _CalendarPicker(settings: settings, today: today),
                const SizedBox(height: 24),
                _LanguagePicker(settings: settings),
                const SizedBox(height: 24),
                _ThemePicker(settings: settings),
                const SizedBox(height: 24),
                _CurrencyPicker(settings: settings),
                const SizedBox(height: 24),
                _BudgetPicker(settings: settings),
                const SizedBox(height: 24),
                _PlanCard(settings: settings),
                const SizedBox(height: 24),
                _AccountSection(settings: settings),
                const SizedBox(height: 32),
                _SignOutButton(settings: settings),
                const SizedBox(height: 20),
                Center(
                  child: Text(
                    settings.say('ኪሴ · ስሪት 0.1', 'Kise · version 0.1'),
                    style: Theme.of(context).textTheme.bodySmall
                        ?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.settings});

  final AppSettings settings;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.extension<KiseColors>()!;
    final onHero = colors.heroForeground;
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: colors.heroGradient,
        ),
        // Flat bottom edge: nothing overlaps this header, so it runs straight into the page.
      ),
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 30),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                settings.say('ማስተካከያ', 'Settings'),
                style: theme.textTheme.headlineSmall?.copyWith(
                  color: onHero,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                settings.say('ለውጦች ወዲያውኑ ተቀምጠው ይተገበራሉ።', 'Changes save and apply immediately.'),
                style: theme.textTheme.bodyMedium?.copyWith(color: onHero.withValues(alpha: 0.85)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Sign out, at the very end: the one action here that leaves the app rather than adjusting it.
/// Asks once, because a stray tap would drop the person on the login screen.
class _SignOutButton extends ConsumerWidget {
  const _SignOutButton({required this.settings});

  final AppSettings settings;

  Future<void> _confirm(BuildContext context, WidgetRef ref) async {
    final leave = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(settings.say('ይውጡ?', 'Sign out?')),
        content: Text(
          settings.say(
            'ወጪዎችዎ ተቀምጠዋል። እንደገና ለማየት መልሰው ይግቡ።',
            'Your expenses stay saved. Sign in again to see them.',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(settings.say('ተመለስ', 'Cancel')),
          ),
          FilledButton(
            key: const Key('sign-out-confirm'),
            // The app-wide filled button stretches to full width, which reads oddly in a dialog.
            style: FilledButton.styleFrom(minimumSize: const Size(0, 44)),
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(settings.say('ውጣ', 'Sign out')),
          ),
        ],
      ),
    );
    if (leave == true) await ref.read(sessionProvider.notifier).signOut();
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    return Center(
      child: TextButton.icon(
        key: const Key('sign-out'),
        onPressed: () => _confirm(context, ref),
        style: TextButton.styleFrom(
          foregroundColor: scheme.error,
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        ),
        icon: const Icon(Icons.logout_rounded, size: 20),
        label: Text(settings.say('ውጣ', 'Sign out')),
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle({required this.title, this.hint});

  final String title;
  final String? hint;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
          if (hint != null)
            Text(
              hint!,
              style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
        ],
      ),
    );
  }
}

class _ProfileCard extends ConsumerStatefulWidget {
  const _ProfileCard({required this.settings});

  final AppSettings settings;

  @override
  ConsumerState<_ProfileCard> createState() => _ProfileCardState();
}

class _ProfileCardState extends ConsumerState<_ProfileCard> {
  late final TextEditingController _controller = TextEditingController(
    text: widget.settings.ownerName,
  );

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final name = widget.settings.ownerName;
    final initial = name.isEmpty ? '?' : name.characters.first.toUpperCase();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SectionTitle(title: widget.settings.say('የእርስዎ መረጃ', 'About you')),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Container(
                  width: 52,
                  height: 52,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(color: scheme.primaryContainer, shape: BoxShape.circle),
                  child: Text(
                    initial,
                    key: const Key('profile-initial'),
                    style: theme.textTheme.titleLarge?.copyWith(
                      color: scheme.onPrimaryContainer,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: TextField(
                    key: const Key('owner-name-field'),
                    controller: _controller,
                    textCapitalization: TextCapitalization.words,
                    decoration: InputDecoration(
                      labelText: widget.settings.say('ስም', 'Your name'),
                      hintText: widget.settings.say('ለምሳሌ ሰላም', 'e.g. Selam'),
                      filled: false,
                      border: InputBorder.none,
                      enabledBorder: InputBorder.none,
                      focusedBorder: InputBorder.none,
                      contentPadding: EdgeInsets.zero,
                    ),
                    onChanged: ref.read(settingsProvider.notifier).setOwnerName,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _CalendarPicker extends ConsumerWidget {
  const _CalendarPicker({required this.settings, required this.today});

  final AppSettings settings;
  final DateTime today;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ethiopian = EthiopianDate.fromGregorian(today);
    final gregorianLabel = '${gregorianMonthNamesEn[today.month - 1]} ${today.day}, ${today.year}';

    void choose(CalendarKind next) {
      if (next == settings.calendar) return;
      final period = ref.read(selectedPeriodProvider);
      ref.read(settingsProvider.notifier).setCalendar(next);
      // Keep the viewed month pointing at the same stretch of time.
      ref.read(selectedPeriodProvider.notifier).state = period.asCalendar(next);
    }

    return Column(
      key: const Key('calendar-selector'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SectionTitle(
          title: settings.say('መቁጠሪያ', 'Calendar'),
          hint: settings.say(
            'ሁሉም ቀኖችና ወራት በዚህ መቁጠሪያ ይታያሉ።',
            'Every date and month is shown in this calendar.',
          ),
        ),
        Row(
          children: [
            Expanded(
              child: OptionCard(
                title: settings.say('የኢትዮጵያ', 'Ethiopian'),
                subtitle: ethiopian.format(locale: settings.language.wire),
                icon: Icons.brightness_5_outlined,
                selected: settings.calendar == CalendarKind.ethiopian,
                onTap: () => choose(CalendarKind.ethiopian),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: OptionCard(
                title: settings.say('ግሪጎሪያን', 'Gregorian'),
                subtitle: gregorianLabel,
                icon: Icons.public_outlined,
                selected: settings.calendar == CalendarKind.gregorian,
                onTap: () => choose(CalendarKind.gregorian),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        _PeriodPreview(settings: settings, today: today),
      ],
    );
  }
}

/// Shows how the month will be labelled, in both calendars, before the choice is committed.
class _PeriodPreview extends StatelessWidget {
  const _PeriodPreview({required this.settings, required this.today});

  final AppSettings settings;
  final DateTime today;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final period = Period.fromDate(today, settings.calendar);
    final label = settings.calendar == CalendarKind.ethiopian
        ? EthiopianDate.fromGregorian(today).format(locale: settings.language.wire)
        : '${gregorianMonthNamesEn[today.month - 1]} ${today.day}, ${today.year}';

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Row(
        children: [
          Icon(Icons.visibility_outlined, size: 18, color: scheme.onSurfaceVariant),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  key: const Key('settings-preview-date'),
                  style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600),
                ),
                Text(
                  '${period.label(settings.language)}  ·  '
                  '${period.counterpartLabel(settings.language)}',
                  key: const Key('settings-preview-period'),
                  style: theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _LanguagePicker extends ConsumerWidget {
  const _LanguagePicker({required this.settings});

  final AppSettings settings;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final controller = ref.read(settingsProvider.notifier);
    return Column(
      key: const Key('language-selector'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SectionTitle(title: settings.say('ቋንቋ', 'Language')),
        Row(
          children: [
            Expanded(
              child: OptionCard(
                title: 'አማርኛ',
                subtitle: 'ሐምሌ · ነሐሴ · ጳጉሜን',
                selected: settings.isAmharic,
                onTap: () => controller.setLanguage(Language.amharic),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: OptionCard(
                title: 'English',
                subtitle: 'Hamle · Nehase · Pagumen',
                selected: !settings.isAmharic,
                onTap: () => controller.setLanguage(Language.english),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

/// Four palettes as swatches: each is a small version of its own hero gradient, so the choice is
/// visible before it is made. The whole app fades to the new colours on tap.
class _ThemePicker extends ConsumerWidget {
  const _ThemePicker({required this.settings});

  final AppSettings settings;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final controller = ref.read(settingsProvider.notifier);
    return Column(
      key: const Key('theme-selector'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SectionTitle(
          title: settings.say('ገጽታ', 'Appearance'),
          hint: settings.say('የመተግበሪያው ቀለም።', 'The colour of the app.'),
        ),
        Card(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 16, 12, 14),
            child: Row(
              children: [
                for (final option in AppTheme.values)
                  Expanded(
                    child: _ThemeSwatch(
                      option: option,
                      selected: settings.theme == option,
                      label: option.name(settings.isAmharic),
                      onTap: () => controller.setTheme(option),
                    ),
                  ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        SegmentedButton<AppThemeMode>(
          key: const Key('theme-mode-selector'),
          showSelectedIcon: false,
          segments: [
            for (final mode in AppThemeMode.values)
              ButtonSegment<AppThemeMode>(
                value: mode,
                icon: Icon(switch (mode) {
                  AppThemeMode.system => Icons.brightness_auto_outlined,
                  AppThemeMode.light => Icons.light_mode_outlined,
                  AppThemeMode.dark => Icons.dark_mode_outlined,
                }),
                label: Text(mode.name(settings.isAmharic)),
              ),
          ],
          selected: {settings.themeMode},
          onSelectionChanged: (selection) => controller.setThemeMode(selection.first),
        ),
      ],
    );
  }
}

class _ThemeSwatch extends StatelessWidget {
  const _ThemeSwatch({
    required this.option,
    required this.selected,
    required this.label,
    required this.onTap,
  });

  final AppTheme option;
  final bool selected;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final gradient = option.heroGradient(theme.brightness);

    return InkWell(
      key: Key('theme-option-${option.wire}'),
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Column(
          children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 220),
              curve: Curves.easeOutCubic,
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: gradient,
                ),
                border: Border.all(
                  color: selected ? scheme.onSurface : Colors.transparent,
                  width: 2.5,
                ),
                boxShadow: selected
                    ? [
                        BoxShadow(
                          color: gradient.last.withValues(alpha: 0.4),
                          blurRadius: 14,
                          offset: const Offset(0, 6),
                        ),
                      ]
                    : const [],
              ),
              child: selected
                  ? const Icon(Icons.check_rounded, color: Colors.white, size: 26)
                  : null,
            ),
            const SizedBox(height: 8),
            Text(
              label,
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.labelMedium?.copyWith(
                fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                color: selected ? scheme.onSurface : scheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The account currency, shown rather than chosen: it is fixed when the account is opened, because
/// every amount already recorded is written in it.
class _CurrencyPicker extends StatelessWidget {
  const _CurrencyPicker({required this.settings});

  final AppSettings settings;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      key: const Key('currency-selector'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SectionTitle(title: settings.say('ገንዘብ', 'Currency')),
        Card(
          margin: EdgeInsets.zero,
          child: ListTile(
            leading: const Icon(Icons.payments_outlined),
            title: Text(settings.currency, key: const Key('account-currency')),
            subtitle: Text(
              settings.say(
                'መለያው ሲከፈት የተመረጠ። የተመዘገቡ መጠኖች በዚህ ስለተጻፉ አይቀየርም።',
                'Chosen when the account was opened. It stays fixed because your recorded '
                    'amounts are written in it.',
              ),
              style: theme.textTheme.bodySmall,
            ),
          ),
        ),
      ],
    );
  }
}

class _BudgetPicker extends ConsumerStatefulWidget {
  const _BudgetPicker({required this.settings});

  final AppSettings settings;

  @override
  ConsumerState<_BudgetPicker> createState() => _BudgetPickerState();
}

/// The overall monthly budget, kept on the server so every device shows the same target. A
/// shortcut chip applies at once; a typed amount applies on "done" or the save button.
class _BudgetPickerState extends ConsumerState<_BudgetPicker> {
  final TextEditingController _field = TextEditingController();
  bool _edited = false;
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _field.dispose();
    super.dispose();
  }

  Future<void> _write(Future<void> Function(BudgetsApi api) action) async {
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await action(ref.read(budgetsApiProvider));
      ref.invalidate(budgetsProvider);
      ref.invalidate(monthSummaryProvider);
      _edited = false;
    } on ApiException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _apply(String text, {required bool hasBudget}) async {
    final major = double.tryParse(text.trim());
    if (major == null || major <= 0) {
      if (hasBudget) await _write((api) => api.clearOverall());
      return;
    }
    final minor = Money.fromMajor(major, widget.settings.currency).minorUnits;
    await _write((api) => api.setOverall(minor).then((_) {}));
  }

  @override
  Widget build(BuildContext context) {
    final settings = widget.settings;
    final theme = Theme.of(context);
    final budget = ref.watch(overallBudgetProvider);
    final loading = ref.watch(budgetsProvider).isLoading;
    // Show the server's figure until the person starts typing their own.
    if (!_edited) {
      final text = budget == null ? '' : budget.majorUnits.round().toString();
      if (_field.text != text) _field.text = text;
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SectionTitle(
          title: settings.say('የወሩ ገደብ', 'Monthly budget'),
          hint: settings.say(
            'ካልፈለጉ ባዶ ይተዉት፤ ማጠቃለያው ላይ አይታይም። የምድብ ገደቦች በምድቦች ውስጥ ይዘጋጃሉ።',
            'Leave it empty and the summary will not show a target. Category limits are set '
                'under Categories.',
          ),
        ),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            for (final amount in budgetShortcutsMajor)
              ChoiceChipPill(
                label: Money.fromMajor(
                  amount,
                  settings.currency,
                ).formatRounded(withCurrency: false),
                selected:
                    budget?.minorUnits == Money.fromMajor(amount, settings.currency).minorUnits,
                onTap: () {
                  _edited = false;
                  _write(
                    (api) => api
                        .setOverall(Money.fromMajor(amount, settings.currency).minorUnits)
                        .then((_) {}),
                  );
                },
              ),
            if (budget != null)
              ChoiceChipPill(
                key: const Key('budget-clear'),
                label: settings.say('አጥፋ', 'Clear'),
                selected: false,
                onTap: () {
                  _edited = false;
                  _write((api) => api.clearOverall());
                },
              ),
          ],
        ),
        const SizedBox(height: 12),
        TextField(
          key: const Key('budget-field'),
          controller: _field,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          textInputAction: TextInputAction.done,
          inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))],
          decoration: InputDecoration(
            labelText: settings.say('የራስዎ ገደብ', 'Custom amount'),
            prefixIcon: const Icon(Icons.savings_outlined),
            suffixText: settings.currency,
            errorText: _error,
            suffixIcon: _saving || loading
                ? const Padding(
                    padding: EdgeInsets.all(14),
                    child: SizedBox.square(
                      dimension: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  )
                : IconButton(
                    key: const Key('budget-save'),
                    tooltip: settings.say('አስቀምጥ', 'Save'),
                    icon: const Icon(Icons.check_rounded),
                    onPressed: () => _apply(_field.text, hasBudget: budget != null),
                  ),
          ),
          onChanged: (_) => _edited = true,
          onSubmitted: (text) => _apply(text, hasBudget: budget != null),
        ),
        if (budget != null) ...[
          const SizedBox(height: 8),
          Text(
            settings.say(
              'ገደብ: ${Money(budget.minorUnits, settings.currency).formatRounded()}',
              'Budget: ${Money(budget.minorUnits, settings.currency).formatRounded()}',
            ),
            key: const Key('budget-summary'),
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.primary,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ],
    );
  }
}

/// The account's plan: Trial (with days left), Basic or Pro, and what that means for the
/// assistant. Plans are changed by the Kise team for now, so this only shows.
class _PlanCard extends ConsumerWidget {
  const _PlanCard({required this.settings});

  final AppSettings settings;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(sessionProvider).valueOrNull;
    if (session is! SignedIn) return const SizedBox.shrink();
    final plan = session.profile.plan;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final days = plan.daysLeft;
    // Anyone on a plan with all of the assistant sees no upgrade; everyone else can look.
    final isTop =
        plan.aiEnabled &&
        !plan.isTrial &&
        plan.receiptsPerMonth == null &&
        plan.voicePerMonth == null;
    String name(String am, String en) => plan.name.isNotEmpty ? plan.name : settings.say(am, en);
    final (title, detail) = switch (plan.effective) {
      'trial' => (
        name('የሙከራ ጊዜ', 'Trial'),
        settings.say('ሁሉም አገልግሎቶች፣ ረዳቱን ጨምሮ', 'Everything, including the assistant'),
      ),
      'basic' => (
        name('መሰረታዊ', 'Basic'),
        plan.aiEnabled
            ? settings.say('ከረዳቱ የተወሰነውን ጨምሮ', 'Includes some of the assistant')
            : settings.say(
                'ከረዳቱ (ድምፅ፣ ደረሰኝ፣ ጥያቄ) በስተቀር ሁሉም',
                'Everything except the assistant (voice, receipts, questions)',
              ),
      ),
      _ => (
        name('ፕሮ', 'Pro'),
        plan.aiEnabled
            ? settings.say('ሁሉም አገልግሎቶች፣ ረዳቱን ጨምሮ', 'Everything, including the assistant')
            : settings.say('ከረዳቱ በስተቀር ሁሉም', 'Everything except the assistant'),
      ),
    };
    String allowance(int? value, String am, String en) => value == null
        ? settings.say('ያልተገደበ $am', 'Unlimited $en')
        : value == 0
        ? settings.say('$am የለም', 'No $en')
        : settings.say('በወር $value $am', '$value $en a month');
    final accent = switch (plan.effective) {
      'trial' => const Color(0xFFF2B234),
      'basic' => scheme.outlineVariant,
      _ => plan.aiEnabled ? scheme.primary : scheme.outline,
    };
    Widget chip(IconData icon, String text, {bool on = true}) => Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: on ? scheme.primaryContainer : scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(99),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: on ? scheme.onPrimaryContainer : scheme.onSurfaceVariant),
          const SizedBox(width: 5),
          Text(
            text,
            style: theme.textTheme.labelMedium?.copyWith(
              color: on ? scheme.onPrimaryContainer : scheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SectionTitle(title: settings.say('እቅድ', 'Plan')),
        Material(
          key: const Key('plan-card'),
          color: scheme.surface,
          clipBehavior: Clip.antiAlias,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
            side: BorderSide(color: scheme.outlineVariant),
          ),
          child: InkWell(
            // Anyone without all of the assistant can see the plans, including during a trial.
            onTap: isTop ? null : () => showUpgradeSheet(context, settings),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Container(height: 5, color: accent),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 14, 12, 16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(
                            plan.aiEnabled
                                ? Icons.workspace_premium_rounded
                                : Icons.lock_outline_rounded,
                            color: plan.aiEnabled ? scheme.primary : scheme.onSurfaceVariant,
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              title,
                              key: const Key('plan-name'),
                              style: theme.textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                          if (days != null)
                            Container(
                              key: const Key('plan-days-left'),
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                              decoration: BoxDecoration(
                                color: days <= 3
                                    ? scheme.errorContainer
                                    : scheme.secondaryContainer,
                                borderRadius: BorderRadius.circular(99),
                              ),
                              child: Text(
                                settings.say('$days ቀን ይቀራል', '$days days left'),
                                style: theme.textTheme.labelMedium?.copyWith(
                                  fontWeight: FontWeight.w700,
                                  color: days <= 3
                                      ? scheme.onErrorContainer
                                      : scheme.onSecondaryContainer,
                                ),
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Text(
                        detail,
                        style: theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
                      ),
                      if (plan.aiEnabled) ...[
                        const SizedBox(height: 12),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            chip(
                              Icons.receipt_long_rounded,
                              allowance(plan.receiptsPerMonth, 'ደረሰኝ', 'scans'),
                              on: plan.receiptsPerMonth != 0,
                            ),
                            chip(
                              Icons.mic_rounded,
                              allowance(plan.voicePerMonth, 'ድምፅ', 'voice notes'),
                              on: plan.voicePerMonth != 0,
                            ),
                          ],
                        ),
                      ],
                      if (!isTop) ...[
                        const SizedBox(height: 14),
                        Row(
                          children: [
                            Text(
                              settings.say('እቅዶችን ይመልከቱ', 'See plans'),
                              key: const Key('plan-see-plans'),
                              style: theme.textTheme.labelLarge?.copyWith(
                                color: scheme.primary,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            Icon(Icons.chevron_right_rounded, color: scheme.primary, size: 20),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// Categories, and the password: things about the account rather than the screen.
class _AccountSection extends ConsumerWidget {
  const _AccountSection({required this.settings});

  final AppSettings settings;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SectionTitle(title: settings.say('መለያ', 'Account')),
        Card(
          margin: EdgeInsets.zero,
          child: Column(
            children: [
              ListTile(
                key: const Key('open-categories'),
                leading: const Icon(Icons.category_outlined),
                title: Text(settings.say('ምድቦች', 'Categories')),
                subtitle: Text(
                  settings.say(
                    'ጨምር፣ ስም ቀይር፣ ቀለም እና የወር ገደብ',
                    'Add, rename, colour and monthly limits',
                  ),
                ),
                trailing: const Icon(Icons.chevron_right_rounded),
                onTap: () =>
                    Navigator.of(context)
                        .push(MaterialPageRoute<void>(builder: (_) => const CategoriesScreen())),
              ),
              const Divider(height: 1),
              ListTile(
                key: const Key('change-password'),
                leading: const Icon(Icons.lock_reset_rounded),
                title: Text(settings.say('የይለፍ ቃል ቀይር', 'Change password')),
                trailing: const Icon(Icons.chevron_right_rounded),
                onTap: () => showDialog<void>(
                  context: context,
                  builder: (_) => const ChangePasswordDialog(),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
