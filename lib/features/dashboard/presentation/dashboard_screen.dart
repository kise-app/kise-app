/// The dashboard.
///
/// Top to bottom: a gradient hero carrying the greeting, today in both calendars and the month
/// navigator; the summary card, overlapping the hero's lower edge; the day-by-day chart; the
/// category breakdown; and, when the month has any, the item-usage chart. Each section is its own
/// widget, so this file is only the arrangement.
///
/// The figures come from `GET /api/reports/summary` for the month being viewed. While a month is
/// loading the previous month's figures stay on screen (with a thin progress bar) so paging does not
/// flash empty cards; a failed load keeps the layout and offers a retry.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../platform/api/api.dart';
import '../../../platform/settings.dart';
import '../../../shared/month_data.dart';
import '../../../shared/widgets/gradient_action_button.dart';
import '../../../shared/widgets/reveal.dart';
import '../../expenses/presentation/expense_form_sheet.dart';
import '../../item_usage/presentation/item_usage_chart.dart';
import '../month_summary.dart';
import 'widgets/category_card.dart';
import 'widgets/daily_chart_card.dart';
import 'widgets/hero_header.dart';
import 'widgets/spend_summary_card.dart';

class DashboardScreen extends ConsumerWidget {
  const DashboardScreen({super.key});

  /// How far the summary card hangs below the gradient. The gradient stops this many pixels above
  /// the bottom of the hero stack, so roughly half the card sits on it and half on the page.
  static const double _heroOverlap = 118;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsProvider);
    final period = ref.watch(selectedPeriodProvider);
    final today = ref.watch(todayProvider);
    final summary = ref.watch(monthSummaryProvider);
    final itemUsage = ref.watch(itemUsageProvider).valueOrNull;
    final todayDay = period.dayOf(today);

    final dto = summary.valueOrNull;
    final month = dto == null
        ? MonthSummary.empty(period.lengthInDays, settings.currency)
        : MonthSummary(dto, settings.currency);

    return Scaffold(
      body: RefreshIndicator(
        onRefresh: () async {
          invalidateMonthData(ref);
          await ref.read(monthSummaryProvider.future).catchError((_) => month.dto);
        },
        child: ListView(
          padding: EdgeInsets.zero,
          children: [
            Stack(
              children: [
                const Positioned.fill(bottom: _heroOverlap, child: HeroBackdrop()),
                Column(
                  children: [
                    HeroHeader(today: today, settings: settings),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Reveal(
                        order: 0,
                        child: SpendSummaryCard(month: month, settings: settings),
                      ),
                    ),
                  ],
                ),
              ],
            ),
            if (summary.isLoading)
              const Padding(
                padding: EdgeInsets.fromLTRB(32, 10, 32, 0),
                child: LinearProgressIndicator(key: Key('summary-loading'), minHeight: 2),
              ),
            if (summary.hasError && !summary.isLoading)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                child: _LoadError(
                  message: summary.error is ApiException
                      ? (summary.error! as ApiException).message
                      : settings.say('ማጠቃለያውን መጫን አልተቻለም', 'Could not load the summary'),
                  retryLabel: settings.say('እንደገና ሞክር', 'Retry'),
                  onRetry: () => ref.invalidate(monthSummaryProvider),
                ),
              ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 112),
              child: Column(
                children: [
                  Reveal(
                    order: 1,
                    child: DailyChartCard(
                      month: month,
                      settings: settings,
                      period: period,
                      todayIndex: todayDay == null ? null : todayDay - 1,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Reveal(
                    order: 2,
                    child: CategoryCard(month: month, settings: settings),
                  ),
                  if (itemUsage != null && !itemUsage.isEmpty) ...[
                    const SizedBox(height: 16),
                    Reveal(
                      order: 3,
                      child: ItemUsageChart(
                        report: itemUsage,
                        amharic: settings.isAmharic,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
      floatingActionButton: GradientActionButton(
        key: const Key('add-expense'),
        icon: Icons.add_rounded,
        label: settings.say('ወጪ መዝግብ', 'Add expense'),
        onPressed: () => showExpenseForm(context),
      ),
    );
  }
}

class _LoadError extends StatelessWidget {
  const _LoadError({required this.message, required this.retryLabel, required this.onRetry});

  final String message;
  final String retryLabel;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      key: const Key('summary-error'),
      margin: EdgeInsets.zero,
      color: scheme.errorContainer,
      child: ListTile(
        leading: Icon(Icons.cloud_off_outlined, color: scheme.onErrorContainer),
        title: Text(message, style: TextStyle(color: scheme.onErrorContainer)),
        trailing: TextButton(onPressed: onRetry, child: Text(retryLabel)),
      ),
    );
  }
}
