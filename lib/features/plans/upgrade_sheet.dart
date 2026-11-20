/// How to get Kise Pro: what it adds, and how to pay for it.
///
/// Payment is manual for now. The sheet shows the accounts an admin entered in the portal (each
/// number with a copy button), then how to send the payment screenshot: Telegram, a phone call or
/// an email, each opening the right app. The person quotes their account email so the admin can
/// find them and switch them to Pro. Until an admin has entered the details, the sheet only says
/// to contact the Kise team.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../platform/api/api.dart';
import '../../platform/links.dart';
import '../../platform/settings.dart';
import 'plan_card.dart';

/// Fetched each time the sheet opens, so a change in the portal shows without a restart. Any
/// failure reads as "not set up yet" rather than an error.
final paymentInfoProvider = FutureProvider.autoDispose<PaymentInfoDto>((ref) async {
  try {
    return await ref.watch(plansApiProvider).payment();
  } on ApiException {
    return PaymentInfoDto.notReady;
  }
});

Future<void> showUpgradeSheet(BuildContext context, AppSettings settings) =>
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (_) => const UpgradeSheet(),
    );

class UpgradeSheet extends ConsumerWidget {
  const UpgradeSheet({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsProvider);
    final theme = Theme.of(context);
    final info = ref.watch(paymentInfoProvider);

    return SingleChildScrollView(
      key: const Key('upgrade-sheet'),
      padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            settings.say('እቅድ ይምረጡ', 'Choose a plan'),
            style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 4),
          Text(
            settings.say(
              'ረዳቱ (ድምፅ፣ ደረሰኝ፣ ጥያቄ) በእቅዱ ይወሰናል። ሌሎች ሁሉም አገልግሎቶች በሁሉም እቅድ ይሰራሉ።',
              'The assistant (voice, receipts, questions) depends on the plan. '
                  'Everything else works on every plan.',
            ),
            style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
          ),
          const SizedBox(height: 16),
          info.when(
            loading: () => const Padding(
              padding: EdgeInsets.symmetric(vertical: 24),
              child: Center(child: CircularProgressIndicator()),
            ),
            error: (_, _) => _NotReady(settings: settings),
            data: (payment) => payment.ready
                ? _HowToPay(settings: settings, payment: payment)
                : _NotReady(settings: settings),
          ),
        ],
      ),
    );
  }
}

class _NotReady extends StatelessWidget {
  const _NotReady({required this.settings});

  final AppSettings settings;

  @override
  Widget build(BuildContext context) => Text(
    settings.say('ወደ ፕሮ ለማሳደግ የኪሴ ቡድንን ያነጋግሩ።', 'To upgrade, contact the Kise team.'),
    key: const Key('upgrade-contact-us'),
    style: Theme.of(context).textTheme.bodyMedium,
  );
}

class _HowToPay extends ConsumerWidget {
  const _HowToPay({required this.settings, required this.payment});

  final AppSettings settings;
  final PaymentInfoDto payment;

  Future<void> _copy(BuildContext context, String text) async {
    await Clipboard.setData(ClipboardData(text: text));
    if (!context.mounted) return;
    ScaffoldMessenger.maybeOf(context)
        ?.showSnackBar(SnackBar(content: Text(settings.say('ተቀድቷል', 'Copied'))));
  }

  Future<void> _open(BuildContext context, WidgetRef ref, Uri uri) async {
    final opened = await ref.read(linkOpenerProvider)(uri);
    if (opened || !context.mounted) return;
    ScaffoldMessenger.maybeOf(context)
        ?.showSnackBar(SnackBar(content: Text(settings.say('መክፈት አልተቻለም', 'Could not open that'))));
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final muted = theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant);
    final step = theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700);
    final reference = payment.reference;
    final subject = Uri.encodeComponent('Kise Pro');
    final body = Uri.encodeComponent('Kise account: $reference');

    return Column(
      key: const Key('upgrade-how-to-pay'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (payment.plans.isNotEmpty) ...[
          PlanCardRow(
            settings: settings,
            plans: [
              for (final plan in payment.plans)
                PlanSummary(
                  code: plan.plan,
                  name: _planName(plan, settings),
                  price: plan.price,
                  typedRequests: plan.typedRequests,
                  receiptsPerMonth: plan.receiptsPerMonth,
                  voicePerMonth: plan.voicePerMonth,
                  current: plan.current,
                ),
            ],
          ),
          const SizedBox(height: 20),
        ],
        Text(settings.say('1. ከእነዚህ ወደ አንዱ ይክፈሉ', '1. Pay into one of these'), style: step),
        const SizedBox(height: 8),
        for (final (index, account) in payment.accounts.indexed)
          Card(
            key: Key('upgrade-account-$index'),
            margin: const EdgeInsets.only(bottom: 8),
            child: ListTile(
              title: Text(account.bank),
              subtitle: Text('${account.holder}\n${account.number}'),
              isThreeLine: true,
              trailing: IconButton(
                key: Key('upgrade-copy-$index'),
                tooltip: settings.say('ቁጥሩን ቅዳ', 'Copy the number'),
                icon: const Icon(Icons.copy_rounded),
                onPressed: () => _copy(context, account.number),
              ),
            ),
          ),
        const SizedBox(height: 12),
        Text(
          settings.say('2. የክፍያውን ፎቶ (screenshot) ይላኩልን', '2. Send us the payment screenshot'),
          style: step,
        ),
        const SizedBox(height: 4),
        Text.rich(
          TextSpan(
            children: [
              TextSpan(text: settings.say('ከኢሜይልዎ ጋር ይላኩ፦ ', 'Include your account email: ')),
              TextSpan(
                text: reference,
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
            ],
          ),
          key: const Key('upgrade-reference'),
          style: muted,
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            if (payment.telegramUrl != null)
              FilledButton.icon(
                key: const Key('upgrade-telegram'),
                onPressed: () => _open(context, ref, Uri.parse(payment.telegramUrl!)),
                icon: const Icon(Icons.send_rounded),
                label: Text('Telegram @${payment.telegram}'),
              ),
            if (payment.phone.isNotEmpty)
              OutlinedButton.icon(
                key: const Key('upgrade-phone'),
                onPressed: () => _open(
                  context,
                  ref,
                  Uri(scheme: 'tel', path: payment.phone.replaceAll(' ', '')),
                ),
                icon: const Icon(Icons.call_rounded),
                label: Text(payment.phone),
              ),
            if (payment.email.isNotEmpty)
              OutlinedButton.icon(
                key: const Key('upgrade-email'),
                onPressed: () => _open(
                  context,
                  ref,
                  Uri.parse('mailto:${payment.email}?subject=$subject&body=$body'),
                ),
                icon: const Icon(Icons.mail_outline_rounded),
                label: Text(payment.email),
              ),
          ],
        ),
        const SizedBox(height: 16),
        Text(
          payment.note.isNotEmpty
              ? payment.note
              : settings.say(
                  'ክፍያውን ካረጋገጥን በኋላ ወደ ፕሮ እናሳድግዎታለን።',
                  'Once we have checked the payment, we switch you to Pro.',
                ),
          key: const Key('upgrade-note'),
          style: muted,
        ),
      ],
    );
  }
}

/// A plan's name: the admin's, or for an older server that sends none, the built-in one.
String _planName(PlanPriceDto plan, AppSettings settings) {
  if (plan.name.isNotEmpty) return plan.name;
  return switch (plan.plan) {
    'pro' => settings.say('ፕሮ', 'Pro'),
    'basic' => settings.say('መሰረታዊ', 'Basic'),
    _ => plan.plan,
  };
}
