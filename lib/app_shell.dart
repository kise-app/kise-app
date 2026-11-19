/// The shell that holds the app's tabs.
///
/// `IndexedStack` rather than swapping widgets, so the dashboard keeps its scroll position and the
/// selected month when the person visits Settings and comes back.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'features/dashboard/presentation/dashboard_screen.dart';
import 'features/expenses/presentation/expenses_screen.dart';
import 'features/fixed_expenses/presentation/fixed_expenses_screen.dart';
import 'features/settings/presentation/settings_screen.dart';
import 'platform/settings.dart';

class AppShell extends ConsumerStatefulWidget {
  const AppShell({super.key});

  @override
  ConsumerState<AppShell> createState() => _AppShellState();
}

class _AppShellState extends ConsumerState<AppShell> {
  int _index = 0;

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(settingsProvider);
    final theme = Theme.of(context);

    return Scaffold(
      body: IndexedStack(
        index: _index,
        children: const [
          DashboardScreen(),
          ExpensesScreen(),
          FixedExpensesScreen(),
          SettingsScreen(),
        ],
      ),
      // Flat, with a hairline above it: the headers carry the curves, the bar stays out of the way.
      bottomNavigationBar: DecoratedBox(
        decoration: BoxDecoration(
          color: theme.cardTheme.color,
          border: Border(
            top: BorderSide(
              color: theme.colorScheme.outlineVariant.withValues(alpha: 0.5),
            ),
          ),
        ),
        child: NavigationBar(
          selectedIndex: _index,
          onDestinationSelected: (index) => setState(() => _index = index),
          destinations: [
            NavigationDestination(
              icon: const Icon(Icons.dashboard_outlined),
              selectedIcon: const Icon(Icons.dashboard),
              label: settings.say('ማጠቃለያ', 'Summary'),
            ),
            NavigationDestination(
              icon: const Icon(Icons.receipt_long_outlined),
              selectedIcon: const Icon(Icons.receipt_long),
              label: settings.say('ወጪዎች', 'Expenses'),
            ),
            NavigationDestination(
              icon: const Icon(Icons.event_repeat_outlined),
              selectedIcon: const Icon(Icons.event_repeat),
              label: settings.say('ቋሚ ወጪ', 'Fixed'),
            ),
            NavigationDestination(
              key: const Key('settings-tab'),
              icon: const Icon(Icons.settings_outlined),
              selectedIcon: const Icon(Icons.settings),
              label: settings.say('ማስተካከያ', 'Settings'),
            ),
          ],
        ),
      ),
    );
  }
}
