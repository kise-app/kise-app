/// One plan as a card: its name, its price, and what it includes, with a tick or a cross per
/// feature. Used side by side in the upgrade sheet, so plans can be compared at a glance.
///
/// The colour strip on top says which kind of plan it is: gold for the trial, grey for Basic, the
/// brand green for anything that includes the assistant.
library;

import 'package:flutter/material.dart';

import '../../platform/settings.dart';

/// What a card shows. Built from the server's plan DTOs by the callers.
class PlanSummary {
  const PlanSummary({
    required this.code,
    required this.name,
    required this.price,
    required this.typedRequests,
    required this.receiptsPerMonth,
    required this.voicePerMonth,
    this.current = false,
  });

  final String code;
  final String name;

  /// Free text as the admin wrote it; empty when not set.
  final String price;
  final bool typedRequests;

  /// A month; null is no monthly limit, 0 is none.
  final int? receiptsPerMonth;
  final int? voicePerMonth;

  /// The plan this account is on now.
  final bool current;

  bool get includesAssistant => typedRequests || receiptsPerMonth != 0 || voicePerMonth != 0;
}

class PlanCard extends StatelessWidget {
  const PlanCard({super.key, required this.plan, required this.settings, this.width = 216});

  final PlanSummary plan;
  final AppSettings settings;
  final double width;

  String _allowance(int? value, String amOne, String enOne, String amMany, String enMany) {
    if (value == null) return settings.say('ያልተገደበ $amMany', 'Unlimited $enMany');
    if (value == 0) return settings.say('$amMany የለም', 'No $enMany');
    return settings.say(
      'በወር $value ${value == 1 ? amOne : amMany}',
      '$value ${value == 1 ? enOne : enMany} a month',
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final accent = switch (plan.code) {
      'trial' => const Color(0xFFF2B234),
      'basic' => scheme.outlineVariant,
      _ => plan.includesAssistant ? scheme.primary : scheme.outline,
    };
    final highlighted = plan.current;

    Widget feature(bool included, String text) => Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 20,
            height: 20,
            margin: const EdgeInsets.only(top: 1),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: included ? scheme.primary : scheme.surfaceContainerHighest,
            ),
            child: Icon(
              included ? Icons.check_rounded : Icons.close_rounded,
              size: 14,
              color: included ? scheme.onPrimary : scheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: included ? null : scheme.onSurfaceVariant,
              ),
            ),
          ),
        ],
      ),
    );

    return Container(
      key: Key('plan-card-${plan.code}'),
      width: width,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: highlighted ? scheme.primary : scheme.outlineVariant,
          width: highlighted ? 2 : 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(height: 5, color: accent),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        plan.name,
                        style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
                      ),
                    ),
                    if (plan.current)
                      Container(
                        key: Key('plan-current-${plan.code}'),
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: scheme.primaryContainer,
                          borderRadius: BorderRadius.circular(99),
                        ),
                        child: Text(
                          settings.say('ያለዎት', 'Yours'),
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: scheme.onPrimaryContainer,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  plan.price.isEmpty ? settings.say('ዋጋ አልተገለጸም', 'Price on request') : plan.price,
                  key: Key('plan-price-${plan.code}'),
                  style: plan.price.isEmpty
                      ? theme.textTheme.bodyMedium?.copyWith(color: scheme.onSurfaceVariant)
                      : theme.textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w800,
                          color: plan.includesAssistant ? scheme.primary : null,
                        ),
                ),
                const SizedBox(height: 12),
                Divider(height: 1, color: scheme.outlineVariant),
                const SizedBox(height: 12),
                feature(
                  plan.typedRequests,
                  settings.say('በጽሑፍ መመዝገብ እና መጠየቅ', 'Typed requests and questions'),
                ),
                feature(
                  plan.receiptsPerMonth != 0,
                  _allowance(
                    plan.receiptsPerMonth,
                    'ደረሰኝ',
                    'receipt scan',
                    'ደረሰኞች',
                    'receipt scans',
                  ),
                ),
                feature(
                  plan.voicePerMonth != 0,
                  _allowance(
                    plan.voicePerMonth,
                    'የድምፅ መልዕክት',
                    'voice note',
                    'የድምፅ መልዕክቶች',
                    'voice notes',
                  ),
                ),
                feature(
                  true,
                  settings.say('ወጪ፣ በጀት፣ ቋሚ ወጪ እና ሪፖርት', 'Expenses, budgets and reports'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Plans side by side, scrolling sideways when they do not fit; every card as tall as the tallest.
class PlanCardRow extends StatelessWidget {
  const PlanCardRow({super.key, required this.plans, required this.settings});

  final List<PlanSummary> plans;
  final AppSettings settings;

  @override
  Widget build(BuildContext context) => SingleChildScrollView(
    key: const Key('plan-card-row'),
    scrollDirection: Axis.horizontal,
    clipBehavior: Clip.none,
    child: IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final (index, plan) in plans.indexed) ...[
            if (index > 0) const SizedBox(width: 12),
            PlanCard(plan: plan, settings: settings),
          ],
        ],
      ),
    ),
  );
}
