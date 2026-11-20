/// The month navigator: the control that makes the dual calendar visible.
///
/// It shows the Period in the active calendar (`ሐምሌ 2018`) with the same stretch of time named in
/// the other one beneath (`July - August 2026`), because an Ethiopian month straddles two Gregorian
/// ones and hiding that would confuse rather than simplify.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../platform/settings.dart';
import '../../platform/theme.dart';
import '../../shared_kernel/period.dart';

class PeriodNavigator extends ConsumerWidget {
  const PeriodNavigator({super.key, this.onGradient = false, this.keyPrefix = ''});

  /// Frosted-glass styling for use over the dashboard's hero gradient, where a solid surface pill
  /// would punch a hole in the picture.
  final bool onGradient;

  /// Prefixed to the test keys (`period-label`, `jump-to-today`), so a navigator on another tab of
  /// the same IndexedStack does not collide with the dashboard's.
  final String keyPrefix;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final period = ref.watch(selectedPeriodProvider);
    final settings = ref.watch(settingsProvider);
    final today = ref.watch(todayProvider);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final currentPeriod = Period.fromDate(today, settings.calendar);
    final isCurrent = period == currentPeriod;
    // Only this month and the ones before it: there is nothing to show in a month not yet lived.
    final canGoForward = period < currentPeriod;

    final onHero = theme.extension<KiseColors>()!.heroForeground;
    final foreground = onGradient ? onHero : scheme.onSurface;
    final secondary = onGradient ? onHero.withValues(alpha: 0.78) : scheme.onSurfaceVariant;
    final background = onGradient ? onHero.withValues(alpha: 0.16) : scheme.surfaceContainerHighest;
    final buttonBackground = onGradient ? onHero.withValues(alpha: 0.14) : theme.cardTheme.color;

    return Container(
      padding: const EdgeInsets.all(6),
      decoration: BoxDecoration(color: background, borderRadius: BorderRadius.circular(999)),
      child: Row(
        children: [
          _StepButton(
            icon: Icons.chevron_left_rounded,
            tooltip: settings.say('ያለፈው ወር', 'Previous month'),
            color: foreground,
            background: buttonBackground,
            onPressed: () => ref.read(selectedPeriodProvider.notifier).state = period.previous,
          ),
          Expanded(
            child: Column(
              children: [
                Text(
                  period.label(settings.language),
                  key: Key('${keyPrefix}period-label'),
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: foreground,
                  ),
                  textAlign: TextAlign.center,
                ),
                Text(
                  period.counterpartLabel(settings.language),
                  key: Key('${keyPrefix}period-counterpart-label'),
                  style: theme.textTheme.bodySmall?.copyWith(color: secondary),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
          if (!isCurrent)
            _StepButton(
              icon: Icons.today_rounded,
              tooltip: settings.say('ወደ አሁኑ ወር', 'Back to this month'),
              color: foreground,
              background: buttonBackground,
              onPressed: () => ref.read(selectedPeriodProvider.notifier).state = currentPeriod,
              buttonKey: Key('${keyPrefix}jump-to-today'),
            ),
          _StepButton(
            icon: Icons.chevron_right_rounded,
            tooltip: settings.say('የሚቀጥለው ወር', 'Next month'),
            color: foreground,
            background: buttonBackground,
            buttonKey: Key('${keyPrefix}next-month'),
            onPressed: canGoForward
                ? () => ref.read(selectedPeriodProvider.notifier).state = period.next
                : null,
          ),
        ],
      ),
    );
  }
}

class _StepButton extends StatelessWidget {
  const _StepButton({
    required this.icon,
    required this.tooltip,
    required this.color,
    required this.background,
    required this.onPressed,
    this.buttonKey,
  });

  final IconData icon;
  final String tooltip;
  final Color color;
  final Color? background;

  /// Null greys the button out (the next month, from the current one).
  final VoidCallback? onPressed;
  final Key? buttonKey;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      key: buttonKey,
      onPressed: onPressed,
      tooltip: tooltip,
      icon: Icon(icon, color: onPressed == null ? color.withValues(alpha: 0.3) : color),
      style: IconButton.styleFrom(
        backgroundColor: background,
        disabledBackgroundColor: background?.withValues(alpha: (background!.a * 0.5)),
      ),
    );
  }
}
