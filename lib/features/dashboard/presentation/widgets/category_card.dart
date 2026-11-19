/// Where the month went: one bar for the part-to-whole picture, then a row per category with its
/// icon, name, share and amount. Identity is carried by the icon and name beside each colour, never
/// by the colour alone.
library;

import 'package:flutter/material.dart';

import '../../../../platform/api/api.dart';
import '../../../../platform/settings.dart';
import '../../../../shared/category_visuals.dart';
import '../../../../shared/month_data.dart';
import '../../../../shared/widgets/section_card.dart';
import '../../../../shared_kernel/money.dart';
import '../../month_summary.dart';

class CategoryCard extends StatelessWidget {
  const CategoryCard({super.key, required this.month, required this.settings});

  final MonthSummary month;
  final AppSettings settings;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final total = month.grandTotal;
    final sorted = month.categoriesBySize;

    return SectionCard(
      title: settings.say('በምድብ', 'By category'),
      subtitle: settings.say('የወሩ ወጪ ክፍፍል', 'Where the month went'),
      child: sorted.isEmpty
          ? Padding(
              key: const Key('categories-empty'),
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Text(
                settings.say('በዚህ ወር ገና ወጪ የለም።', 'Nothing spent this month yet.'),
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            )
          : Column(
              children: [
                _ShareBar(categories: sorted, total: total),
                const SizedBox(height: 8),
                for (final category in sorted)
                  _CategoryRow(category: category, total: total, settings: settings),
              ],
            ),
    );
  }
}

class _ShareBar extends StatelessWidget {
  const _ShareBar({required this.categories, required this.total});

  final List<CategorySpendDto> categories;
  final Money total;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(999),
      child: Row(
        children: [
          for (var index = 0; index < categories.length; index++) ...[
            if (index > 0) const SizedBox(width: 3),
            Expanded(
              flex: (Money(categories[index].totalMinor, total.currency).shareOf(total) * 1000)
                  .round()
                  .clamp(6, 1000),
              child: Container(height: 10, color: categoryColor(categories[index].color)),
            ),
          ],
        ],
      ),
    );
  }
}

class _CategoryRow extends StatelessWidget {
  const _CategoryRow({required this.category, required this.total, required this.settings});

  final CategorySpendDto category;
  final Money total;
  final AppSettings settings;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final amount = Money(category.totalMinor, total.currency);
    final percent = (amount.shareOf(total) * 100).round();
    final color = categoryColor(category.color);

    return Padding(
      padding: const EdgeInsets.only(top: 14),
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(categoryIcon(category.icon), size: 20, color: color),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  category.label(settings.isAmharic),
                  style: theme.textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.w600),
                ),
                if (category.committedMinor > 0)
                  Text(
                    settings.say('ቋሚ ወጪን ያካትታል', 'includes fixed'),
                    style: theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
                  ),
                if (category.budgetMinor != null) _LimitBar(category: category, total: total),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                amount.formatRounded(withCurrency: false),
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
              Text(
                '$percent%',
                style: theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// "4,500 of 5,000" with a thin bar that turns amber at 80% and red past the limit.
class _LimitBar extends StatelessWidget {
  const _LimitBar({required this.category, required this.total});

  final CategorySpendDto category;
  final Money total;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final limit = category.budgetMinor!;
    final level = BudgetLevel.of(category.totalMinor, limit);
    final color = switch (level) {
      BudgetLevel.over => scheme.error,
      BudgetLevel.near => scheme.tertiary,
      BudgetLevel.fine => scheme.primary,
    };
    final spent = Money(category.totalMinor, total.currency).formatRounded(withCurrency: false);
    final cap = Money(limit, total.currency).formatRounded(withCurrency: false);
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(99),
            child: LinearProgressIndicator(
              key: Key('limit-${category.categoryId}'),
              value: (category.totalMinor / limit).clamp(0.0, 1.0),
              minHeight: 5,
              color: color,
              backgroundColor: color.withValues(alpha: 0.15),
            ),
          ),
          const SizedBox(height: 2),
          Text(
            '$spent / $cap',
            style: theme.textTheme.labelSmall?.copyWith(
              color: level == BudgetLevel.fine ? scheme.onSurfaceVariant : color,
            ),
          ),
        ],
      ),
    );
  }
}
