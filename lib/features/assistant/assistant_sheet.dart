/// The assistant: say, type or photograph what you spent, check it, save it. Or ask a question.
///
/// One sheet, two modes:
///
/// * **Record** — type "bread 40, taxi 100", tap the mic and speak (Amharic, English, or both), or
///   photograph a receipt. The server reads it and returns *drafts*; each shows its category,
///   amount, date in the person's calendar, payment method and anything worth double-checking. The
///   person unticks what is wrong, taps a draft to adjust it in the normal expense form, and saves
///   the rest in one go. Nothing is recorded until they do.
///   Monthly commitments are understood too: "rent 8,000 every month on the 5th" becomes a new
///   fixed monthly expense, and "I paid the rent" marks the existing one paid for this month.
/// * **Ask** — "how much on food this month?", typed or spoken, is answered from the server's own
///   figures.
///
/// The microphone and camera sit behind [VoiceRecorder] and [ReceiptPicker] (see `capture.dart`),
/// so this widget is testable without plugins. A voice note stops on its own at the plan's limit
/// (the server's `max_voice_seconds`) and what was said so far is sent, as if Stop had been tapped.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../platform/api/api.dart';
import '../../platform/settings.dart';
import '../../shared/category_visuals.dart';
import '../../shared/month_data.dart';
import '../../shared_kernel/period.dart';
import '../expenses/presentation/expense_form_sheet.dart';
import '../expenses/presentation/expense_providers.dart' show categoriesProvider;
import '../plans/upgrade_sheet.dart';
import 'capture.dart';

/// Whether this server has the assistant switched on. Any failure reads as "off", so a missing
/// feature hides its button rather than showing an error.
final assistantStatusProvider = FutureProvider<AssistantStatusDto>((ref) async {
  try {
    return await ref.watch(assistantApiProvider).status();
  } on ApiException {
    return const AssistantStatusDto(enabled: false, hourlyLimit: 0);
  }
});

/// Open the sheet. Returns how many expenses were saved.
Future<int?> showAssistantSheet(BuildContext context) => showModalBottomSheet<int>(
  context: context,
  isScrollControlled: true,
  useSafeArea: true,
  showDragHandle: true,
  builder: (_) => const AssistantSheet(),
);

/// The small button that opens the assistant, shown only when the server has it switched on.
/// On a plan without it (Basic, or an ended trial) it carries a lock and explains Pro instead.
class AssistantButton extends ConsumerWidget {
  const AssistantButton({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final status = ref.watch(assistantStatusProvider).valueOrNull;
    if (status == null || !status.enabled) return const SizedBox.shrink();
    final settings = ref.watch(settingsProvider);
    final allowed = status.allowed;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: FloatingActionButton.small(
        key: const Key('assistant-open'),
        heroTag: null,
        tooltip: allowed
            ? settings.say('በድምፅ ወይም በደረሰኝ መዝግብ', 'Record by voice or receipt')
            : settings.say('ረዳቱ የፕሮ አገልግሎት ነው', 'The assistant is part of Pro'),
        onPressed: () async {
          if (!allowed) {
            await showUpgradeSheet(context, settings);
            return;
          }
          final messenger = ScaffoldMessenger.maybeOf(context);
          final saved = await showAssistantSheet(context);
          if (saved != null && saved > 0) {
            messenger?.showSnackBar(
              SnackBar(content: Text(settings.say('$saved ወጪዎች ተመዝግበዋል', 'Saved $saved expenses'))),
            );
          }
        },
        child: Icon(allowed ? Icons.auto_awesome_rounded : Icons.lock_outline_rounded),
      ),
    );
  }
}

enum _Mode { record, ask }

enum _Phase { idle, recording, working, saving }

class AssistantSheet extends ConsumerStatefulWidget {
  const AssistantSheet({super.key});

  @override
  ConsumerState<AssistantSheet> createState() => _AssistantSheetState();
}

class _AssistantSheetState extends ConsumerState<AssistantSheet> {
  final _input = TextEditingController();
  // Made on first use: most visits never touch the microphone, and the plugin should not be woken
  // for them — nor, in dispose, after `ref` is gone.
  VoiceRecorder? _voice;
  VoiceRecorder get _recorder => _voice ??= ref.read(voiceRecorderProvider)();
  _Mode _mode = _Mode.record;
  _Phase _phase = _Phase.idle;
  Timer? _ticker;
  Duration _elapsed = Duration.zero;

  DraftReplyDto? _reply;
  List<DraftExpenseDto> _drafts = [];
  List<bool> _selected = [];
  List<FixedDraftDto> _fixed = [];
  List<bool> _fixedSelected = [];
  List<PaymentDraftDto> _payments = [];
  List<bool> _paymentSelected = [];
  String? _answer;

  /// What was heard when the question was asked out loud.
  String? _heard;
  String? _error;

  AppSettings get _settings => ref.read(settingsProvider);

  String get _today {
    final d = ref.read(todayProvider);
    return '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-'
        '${d.day.toString().padLeft(2, '0')}';
  }

  @override
  void dispose() {
    _ticker?.cancel();
    final voice = _voice;
    if (voice != null) {
      if (_phase == _Phase.recording) voice.cancel();
      voice.dispose();
    }
    _input.dispose();
    super.dispose();
  }

  // -- talking to the server --------------------------------------------

  int get _secondsLeft => (_maxVoiceNote - _elapsed).inSeconds.clamp(0, 1 << 30);

  /// The plan's limit, so the server never refuses a note the app let someone record.
  Duration get _maxVoiceNote =>
      ref.read(assistantStatusProvider).valueOrNull?.maxVoiceNote ?? defaultMaxVoiceNote;

  String _describe(Object error) {
    final settings = _settings;
    if (error is ApiException) {
      return switch (error.code) {
        'assistant_unavailable' => settings.say(
          'ረዳቱ በዚህ አገልጋይ ላይ አልበራም።',
          'The assistant is not switched on here.',
        ),
        'assistant_failed' => settings.say(
          'ማንበብ አልተቻለም። እባክዎ እንደገና ይሞክሩ።',
          'That could not be read. Please try again.',
        ),
        'upgrade_required' => settings.say(
          'ረዳቱ የፕሮ አገልግሎት ነው። የሙከራ ጊዜዎ አብቅቷል።',
          'The assistant is part of Pro, and your trial has ended.',
        ),
        'allowance_used_up' => settings.say(
          'የዚህ ወር ድርሻዎ አልቋል። በሚቀጥለው ወር 1 ቀን እንደገና ይጀምራል።',
          "You have used this month's allowance. It starts again on the 1st.",
        ),
        'voice_note_too_long' => settings.say(
          'የድምፅ መልዕክቱ በጣም ረጅም ነው። አጠር አድርገው ይሞክሩ።',
          'That voice note is too long. Please keep it shorter.',
        ),
        'network_error' => settings.say('ከአገልጋዩ ጋር መገናኘት አልተቻለም።', 'Could not reach the server.'),
        _ => error.message,
      };
    }
    return settings.say('የሆነ ችግር ተፈጥሯል።', 'Something went wrong.');
  }

  Future<void> _run(Future<DraftReplyDto> Function(AssistantApi api) read) async {
    setState(() {
      _phase = _Phase.working;
      _error = null;
      _answer = null;
    });
    try {
      final reply = await read(ref.read(assistantApiProvider));
      if (!mounted) return;
      setState(() {
        _reply = reply;
        _drafts = [...reply.drafts];
        _selected = List<bool>.filled(reply.drafts.length, true, growable: true);
        _fixed = [...reply.fixedDrafts];
        _fixedSelected = List<bool>.filled(reply.fixedDrafts.length, true, growable: true);
        _payments = [...reply.paymentDrafts];
        // A month already marked paid starts unticked: saying it twice should not pay twice.
        _paymentSelected = [
          for (final p in reply.paymentDrafts) !p.warnings.contains('already_paid'),
        ];
      });
    } catch (error) {
      if (mounted) setState(() => _error = _describe(error));
    } finally {
      if (mounted) setState(() => _phase = _Phase.idle);
    }
  }

  Future<void> _send() async {
    final text = _input.text.trim();
    if (text.isEmpty || _phase != _Phase.idle) return;
    FocusScope.of(context).unfocus();
    if (_mode == _Mode.ask) {
      setState(() {
        _phase = _Phase.working;
        _error = null;
        _answer = null;
        _heard = null;
      });
      try {
        final answer = await ref.read(assistantApiProvider).ask(text, today: _today);
        if (mounted) setState(() => _answer = answer);
      } catch (error) {
        if (mounted) setState(() => _error = _describe(error));
      } finally {
        if (mounted) setState(() => _phase = _Phase.idle);
      }
      return;
    }
    await _run((api) => api.readText(text, today: _today));
  }

  Future<void> _toggleRecording() async {
    final settings = _settings;
    if (_phase == _Phase.recording) {
      await _stopRecording();
      return;
    }
    if (_phase != _Phase.idle) return;
    if (!await _recorder.requestPermission()) {
      setState(
        () => _error = settings.say(
          'ማይክሮፎን አልተፈቀደም። በስልኩ ማስተካከያ ይፍቀዱ።',
          'Microphone access is off. Allow it in your phone settings.',
        ),
      );
      return;
    }
    try {
      await _recorder.start();
    } catch (_) {
      setState(() => _error = settings.say('መቅዳት አልተቻለም።', 'Could not start recording.'));
      return;
    }
    setState(() {
      _phase = _Phase.recording;
      _elapsed = Duration.zero;
      _error = null;
      _answer = null;
    });
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(() => _elapsed += const Duration(seconds: 1));
      // Time is up: send what was said, exactly as if Stop had been tapped.
      if (_elapsed >= _maxVoiceNote) _stopRecording();
    });
  }

  Future<void> _stopRecording() async {
    _ticker?.cancel();
    _ticker = null;
    final audio = await _recorder.stop();
    if (!mounted) return;
    setState(() => _phase = _Phase.idle);
    if (audio == null) {
      setState(() => _error = _settings.say('ምንም አልተቀዳም።', 'Nothing was recorded.'));
      return;
    }
    if (_mode == _Mode.ask) {
      await _askOutLoud(audio);
      return;
    }
    await _run(
      (api) => api.readVoice(
        audio.bytes,
        contentType: audio.contentType,
        filename: audio.filename,
        today: _today,
      ),
    );
  }

  Future<void> _askOutLoud(CapturedMedia audio) async {
    setState(() {
      _phase = _Phase.working;
      _error = null;
      _answer = null;
      _heard = null;
    });
    try {
      final reply = await ref
          .read(assistantApiProvider)
          .askVoice(
            audio.bytes,
            contentType: audio.contentType,
            filename: audio.filename,
            today: _today,
          );
      if (mounted) {
        setState(() {
          _answer = reply.answer;
          _heard = reply.transcript;
        });
      }
    } catch (error) {
      if (mounted) setState(() => _error = _describe(error));
    } finally {
      if (mounted) setState(() => _phase = _Phase.idle);
    }
  }

  Future<void> _pickReceipt(ReceiptSource source) async {
    if (_phase != _Phase.idle) return;
    final CapturedMedia? image;
    try {
      image = await ref.read(receiptPickerProvider).pick(source);
    } catch (_) {
      setState(() => _error = _settings.say('ፎቶውን መክፈት አልተቻለም።', 'Could not open the photo.'));
      return;
    }
    if (image == null || !mounted) return;
    await _run(
      (api) => api.readReceipt(
        image!.bytes,
        contentType: image.contentType,
        filename: image.filename,
        today: _today,
      ),
    );
  }

  // -- saving -------------------------------------------------------------

  int get _selectedCount =>
      _selected.where((s) => s).length +
      _fixedSelected.where((s) => s).length +
      _paymentSelected.where((s) => s).length;

  /// Save every ticked draft: record expenses, schedule commitments, mark payments. What fails stays
  /// on screen (and what succeeded leaves it), so a retry can never save anything twice.
  Future<void> _saveSelected() async {
    if (_selectedCount == 0) return;
    setState(() {
      _phase = _Phase.saving;
      _error = null;
    });
    final expenses = ref.read(expensesApiProvider);
    final fixed = ref.read(fixedExpensesApiProvider);
    var saved = 0;
    String? failure;

    Future<bool> attempt(Future<void> Function() save) async {
      try {
        await save();
        saved++;
        return true;
      } on ApiException catch (error) {
        failure ??= error.message;
        return false;
      }
    }

    final keptDrafts = <DraftExpenseDto>[];
    for (var i = 0; i < _drafts.length; i++) {
      final draft = _drafts[i];
      if (!_selected[i]) {
        keptDrafts.add(draft);
        continue;
      }
      final ok = await attempt(
        () => expenses.record(
          categoryId: draft.categoryId,
          amountMinor: draft.amount.minorUnits,
          date: draft.spentOn.gregorian,
          dateCalendar: 'gregorian',
          note: draft.note,
          paymentMethod: draft.paymentMethod,
          itemName: draft.item?.itemName,
          quantity: draft.item?.quantity,
          unitId: draft.item?.unitId,
        ),
      );
      if (!ok) keptDrafts.add(draft);
    }

    final keptFixed = <FixedDraftDto>[];
    for (var i = 0; i < _fixed.length; i++) {
      final draft = _fixed[i];
      if (!_fixedSelected[i]) {
        keptFixed.add(draft);
        continue;
      }
      final ok = await attempt(
        () => fixed.schedule(
          categoryId: draft.categoryId,
          title: draft.title,
          amountMinor: draft.amount.minorUnits,
          startPeriod: draft.startPeriod,
          dueDay: draft.dueDay,
          note: draft.note,
        ),
      );
      if (!ok) keptFixed.add(draft);
    }

    final keptPayments = <PaymentDraftDto>[];
    for (var i = 0; i < _payments.length; i++) {
      final draft = _payments[i];
      if (!_paymentSelected[i]) {
        keptPayments.add(draft);
        continue;
      }
      final ok = await attempt(
        () => fixed.settle(
          draft.fixedExpenseId,
          draft.period,
          amountMinor: draft.amount.minorUnits,
          settledOn: draft.paidOn.gregorian,
        ),
      );
      if (!ok) keptPayments.add(draft);
    }

    if (saved > 0) invalidateMonthData(ref);
    if (!mounted) return;
    if (failure == null) {
      Navigator.of(context).pop(saved);
      return;
    }
    setState(() {
      _drafts = keptDrafts;
      _selected = List<bool>.filled(keptDrafts.length, true, growable: true);
      _fixed = keptFixed;
      _fixedSelected = List<bool>.filled(keptFixed.length, true, growable: true);
      _payments = keptPayments;
      _paymentSelected = List<bool>.filled(keptPayments.length, true, growable: true);
      _phase = _Phase.idle;
      _error = _settings.say(
        '$saved ተቀምጠዋል፤ የቀሩት አልተቀመጡም፦ $failure',
        '$saved saved; the rest were not: $failure',
      );
    });
  }

  Future<void> _editDraft(int index) async {
    final draft = _drafts[index];
    final result = await showExpenseForm(
      context,
      draft: ExpenseDraft(
        categoryId: draft.categoryId,
        amountMinor: draft.amount.minorUnits,
        date: DateTime.parse(draft.spentOn.gregorian),
        paymentMethod: draft.paymentMethod,
        note: draft.note,
        itemName: draft.item?.itemName,
        quantity: draft.item?.quantity,
        unitId: draft.item?.unitId,
      ),
    );
    if (result == ExpenseFormResult.recorded && mounted) {
      // The form recorded it; it is no longer a draft.
      setState(() {
        _drafts.removeAt(index);
        _selected.removeAt(index);
      });
    }
  }

  // -- layout ---------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(settingsProvider);
    // Watched so the plan's voice note limit is loaded before the first recording.
    ref.watch(assistantStatusProvider);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final viewInsets = MediaQuery.of(context).viewInsets.bottom;
    final busy = _phase == _Phase.working || _phase == _Phase.saving;
    final selectedCount = _selectedCount;
    final hasDrafts = _drafts.isNotEmpty || _fixed.isNotEmpty || _payments.isNotEmpty;
    // Category names as the person reads them; the draft carries the server's names as fallback.
    final categories = {
      for (final c in ref.watch(categoriesProvider).valueOrNull ?? const <CategoryDto>[]) c.id: c,
    };

    return Padding(
      padding: EdgeInsets.fromLTRB(20, 0, 20, 16 + viewInsets),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(Icons.auto_awesome_rounded, color: scheme.primary),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    settings.say('ረዳት', 'Assistant'),
                    style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            SegmentedButton<_Mode>(
              key: const Key('assistant-mode'),
              showSelectedIcon: false,
              segments: [
                ButtonSegment(
                  value: _Mode.record,
                  icon: const Icon(Icons.receipt_long_outlined),
                  label: Text(settings.say('መዝግብ', 'Record')),
                ),
                ButtonSegment(
                  value: _Mode.ask,
                  icon: const Icon(Icons.question_answer_outlined),
                  label: Text(settings.say('ጠይቅ', 'Ask')),
                ),
              ],
              selected: {_mode},
              onSelectionChanged: busy || _phase == _Phase.recording
                  ? null
                  : (selection) => setState(() {
                      _mode = selection.first;
                      _error = null;
                      _answer = null;
                    }),
            ),
            const SizedBox(height: 14),
            TextField(
              key: const Key('assistant-input'),
              controller: _input,
              enabled: !busy && _phase != _Phase.recording,
              minLines: 1,
              maxLines: 3,
              maxLength: _mode == _Mode.ask ? 500 : 1000,
              textInputAction: TextInputAction.send,
              decoration: InputDecoration(
                hintText: _mode == _Mode.ask
                    ? settings.say(
                        'ለምሳሌ፦ በዚህ ወር ለምግብ ምን ያህል አወጣሁ?',
                        'e.g. How much did I spend on food this month?',
                      )
                    : settings.say(
                        'ለምሳሌ፦ ዳቦ 40፣ ታክሲ 100 በቴሌብር',
                        'e.g. bread 40, taxi 100 with telebirr',
                      ),
                counterText: '',
                suffixIcon: IconButton(
                  key: const Key('assistant-send'),
                  tooltip: settings.say('ላክ', 'Send'),
                  icon: const Icon(Icons.send_rounded),
                  onPressed: busy ? null : _send,
                ),
              ),
              onSubmitted: (_) => _send(),
            ),
            ...[
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: FilledButton.tonalIcon(
                      key: const Key('assistant-mic'),
                      onPressed: busy ? null : _toggleRecording,
                      style: FilledButton.styleFrom(
                        backgroundColor: _phase == _Phase.recording ? scheme.errorContainer : null,
                        foregroundColor: _phase == _Phase.recording
                            ? scheme.onErrorContainer
                            : null,
                      ),
                      icon: Icon(
                        _phase == _Phase.recording ? Icons.stop_rounded : Icons.mic_rounded,
                      ),
                      label: Text(
                        _phase == _Phase.recording
                            ? settings.say(
                                'አቁም · ${_secondsLeft}s ቀርቷል',
                                'Stop · ${_secondsLeft}s left',
                              )
                            : settings.say('ተናገር', 'Speak'),
                      ),
                    ),
                  ),
                  if (_mode == _Mode.record) ...[
                    const SizedBox(width: 8),
                    IconButton.filledTonal(
                      key: const Key('assistant-camera'),
                      tooltip: settings.say('ደረሰኝ ፎቶ አንሳ', 'Photograph a receipt'),
                      onPressed: busy || _phase == _Phase.recording
                          ? null
                          : () => _pickReceipt(ReceiptSource.camera),
                      icon: const Icon(Icons.photo_camera_outlined),
                    ),
                    IconButton.filledTonal(
                      key: const Key('assistant-gallery'),
                      tooltip: settings.say('የደረሰኝ ፎቶ ምረጥ', 'Choose a receipt photo'),
                      onPressed: busy || _phase == _Phase.recording
                          ? null
                          : () => _pickReceipt(ReceiptSource.gallery),
                      icon: const Icon(Icons.photo_library_outlined),
                    ),
                  ],
                ],
              ),
              const SizedBox(height: 6),
              Text(
                _mode == _Mode.ask
                    ? settings.say(
                        'ድምፅዎ ጥያቄውን ለመረዳት ብቻ ይላካል፤ አይቀመጥም።',
                        'Your voice is sent only to understand the question, and is not kept.',
                      )
                    : settings.say(
                        'ድምፅና ፎቶዎች ለማንበብ ብቻ ይላካሉ፤ አይቀመጡም።',
                        'Voice notes and photos are sent only to be read, and are not kept.',
                      ),
                style: theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
              ),
            ],
            if (_phase == _Phase.working) ...[
              const SizedBox(height: 16),
              Row(
                key: const Key('assistant-working'),
                children: [
                  const SizedBox.square(
                    dimension: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                  const SizedBox(width: 10),
                  Text(settings.say('እያነበብኩ ነው…', 'Reading…')),
                ],
              ),
            ],
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(
                _error!,
                key: const Key('assistant-error'),
                style: TextStyle(color: scheme.error),
              ),
            ],
            if (_answer != null) ...[
              const SizedBox(height: 16),
              if (_heard != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Text(
                    '“${_heard!}”',
                    key: const Key('assistant-heard'),
                    style: theme.textTheme.bodyMedium?.copyWith(fontStyle: FontStyle.italic),
                  ),
                ),
              Card(
                margin: EdgeInsets.zero,
                color: scheme.secondaryContainer,
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text(
                    _answer!,
                    key: const Key('assistant-answer'),
                    style: TextStyle(color: scheme.onSecondaryContainer),
                  ),
                ),
              ),
            ],
            if (_reply != null && _mode == _Mode.record) ...[
              const SizedBox(height: 16),
              if (_reply!.transcript != null)
                Text(
                  '“${_reply!.transcript!}”',
                  key: const Key('assistant-transcript'),
                  style: theme.textTheme.bodyMedium?.copyWith(fontStyle: FontStyle.italic),
                ),
              if (_reply!.message.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    _reply!.message,
                    key: const Key('assistant-message'),
                    style: theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
                  ),
                ),
              const SizedBox(height: 8),
              for (var i = 0; i < _drafts.length; i++)
                _DraftCard(
                  key: Key('draft-$i'),
                  draft: _drafts[i],
                  category: categories[_drafts[i].categoryId],
                  settings: settings,
                  selected: _selected[i],
                  onSelected: busy ? null : (v) => setState(() => _selected[i] = v),
                  onTap: busy ? null : () => _editDraft(i),
                ),
              for (var i = 0; i < _fixed.length; i++)
                _FixedDraftCard(
                  key: Key('fixed-draft-$i'),
                  draft: _fixed[i],
                  category: categories[_fixed[i].categoryId],
                  settings: settings,
                  selected: _fixedSelected[i],
                  onSelected: busy ? null : (v) => setState(() => _fixedSelected[i] = v),
                ),
              for (var i = 0; i < _payments.length; i++)
                _PaymentDraftCard(
                  key: Key('payment-draft-$i'),
                  draft: _payments[i],
                  settings: settings,
                  selected: _paymentSelected[i],
                  onSelected: busy ? null : (v) => setState(() => _paymentSelected[i] = v),
                ),
              if (hasDrafts) ...[
                const SizedBox(height: 12),
                FilledButton(
                  key: const Key('assistant-save'),
                  onPressed: busy || selectedCount == 0 ? null : _saveSelected,
                  style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 16)),
                  child: _phase == _Phase.saving
                      ? const SizedBox.square(
                          dimension: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : Text(settings.say('$selectedCount አስቀምጥ', 'Save $selectedCount')),
                ),
              ],
            ],
          ],
        ),
      ),
    );
  }
}

class _DraftCard extends StatelessWidget {
  const _DraftCard({
    super.key,
    required this.draft,
    required this.category,
    required this.settings,
    required this.selected,
    required this.onSelected,
    required this.onTap,
  });

  final DraftExpenseDto draft;
  final CategoryDto? category;
  final AppSettings settings;
  final bool selected;
  final ValueChanged<bool>? onSelected;
  final VoidCallback? onTap;

  String _date() {
    final d = draft.spentOn;
    if (settings.calendar == CalendarKind.ethiopian) {
      final day = int.tryParse(d.ethiopian.split('-').last) ?? 1;
      return '${settings.isAmharic ? d.ethiopianMonthNameAm : d.ethiopianMonthNameEn} $day';
    }
    return d.gregorian;
  }

  String _warning(String code) => switch (code) {
    'date_unclear' => settings.say('ቀኑን ያረጋግጡ', 'Check the date'),
    'date_in_future' => settings.say('ቀኑ ወደ ዛሬ ተቀይሯል', 'Date moved to today'),
    'date_long_ago' => settings.say('ቀኑ የቆየ ነው', 'Date is long ago'),
    'category_guessed' => settings.say('ምድቡን ያረጋግጡ', 'Check the category'),
    _ => code,
  };

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final name = settings.isAmharic
        ? (category?.nameAm ?? draft.categoryNameAm ?? draft.categoryName)
        : (category?.name ?? draft.categoryName);
    final color = categoryColor(category?.color);
    final details = [
      _date(),
      paymentMethodLabel(draft.paymentMethod, settings),
      if (draft.item != null)
        '${draft.item!.quantity} ${draft.item!.unitCode} ${draft.item!.itemName}',
      if (draft.note != null) draft.note!,
    ].join(' · ');

    return Card(
      margin: const EdgeInsets.only(top: 6),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(4, 8, 12, 8),
          child: Row(
            children: [
              Checkbox(
                value: selected,
                onChanged: onSelected == null ? null : (v) => onSelected!(v ?? false),
              ),
              Icon(categoryIcon(category?.icon), color: color, size: 20),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(name, style: const TextStyle(fontWeight: FontWeight.w600)),
                    Text(details, style: theme.textTheme.bodySmall),
                    if (draft.warnings.isNotEmpty)
                      Wrap(
                        spacing: 6,
                        children: [
                          for (final w in draft.warnings)
                            Text(
                              '⚠ ${_warning(w)}',
                              style: theme.textTheme.labelSmall?.copyWith(color: scheme.tertiary),
                            ),
                        ],
                      ),
                  ],
                ),
              ),
              Text(
                draft.amount.format(),
                style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A shared row: tick box, leading icon, two lines of text, trailing amount.
class _ChoiceCard extends StatelessWidget {
  const _ChoiceCard({
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.details,
    required this.amount,
    required this.selected,
    required this.onSelected,
    this.warnings = const [],
  });

  final IconData icon;
  final Color iconColor;
  final String title;
  final String details;
  final String amount;
  final bool selected;
  final ValueChanged<bool>? onSelected;
  final List<String> warnings;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      margin: const EdgeInsets.only(top: 6),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onSelected == null ? null : () => onSelected!(!selected),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(4, 8, 12, 8),
          child: Row(
            children: [
              Checkbox(
                value: selected,
                onChanged: onSelected == null ? null : (v) => onSelected!(v ?? false),
              ),
              Icon(icon, color: iconColor, size: 20),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
                    Text(details, style: theme.textTheme.bodySmall),
                    for (final w in warnings)
                      Text(
                        '⚠ $w',
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: theme.colorScheme.tertiary,
                        ),
                      ),
                  ],
                ),
              ),
              Text(
                amount,
                style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// "Every month from ጳጉሜን 2018 · due day 5" — a new fixed monthly expense.
class _FixedDraftCard extends StatelessWidget {
  const _FixedDraftCard({
    super.key,
    required this.draft,
    required this.category,
    required this.settings,
    required this.selected,
    required this.onSelected,
  });

  final FixedDraftDto draft;
  final CategoryDto? category;
  final AppSettings settings;
  final bool selected;
  final ValueChanged<bool>? onSelected;

  @override
  Widget build(BuildContext context) {
    final start = draft.startPeriod.label(settings.language);
    return _ChoiceCard(
      icon: Icons.event_repeat_rounded,
      iconColor: categoryColor(category?.color),
      title: settings.say('በየወሩ · ${draft.title}', 'Every month · ${draft.title}'),
      details: settings.say(
        'ከ$start ጀምሮ · ቀን ${draft.dueDay}',
        'From $start · due day ${draft.dueDay}',
      ),
      amount: draft.amount.format(),
      selected: selected,
      onSelected: onSelected,
      warnings: [
        for (final w in draft.warnings)
          switch (w) {
            'due_day_unclear' => settings.say('ቀኑን ያረጋግጡ', 'Check the due day'),
            'category_guessed' => settings.say('ምድቡን ያረጋግጡ', 'Check the category'),
            _ => w,
          },
      ],
    );
  }
}

/// "Mark Rent paid · ነሐሴ 2018" — a payment on an existing fixed monthly expense.
class _PaymentDraftCard extends StatelessWidget {
  const _PaymentDraftCard({
    super.key,
    required this.draft,
    required this.settings,
    required this.selected,
    required this.onSelected,
  });

  final PaymentDraftDto draft;
  final AppSettings settings;
  final bool selected;
  final ValueChanged<bool>? onSelected;

  @override
  Widget build(BuildContext context) {
    return _ChoiceCard(
      icon: Icons.check_circle_outline_rounded,
      iconColor: Theme.of(context).colorScheme.primary,
      title: settings.say('${draft.title} ተከፍሏል', 'Mark ${draft.title} paid'),
      details: draft.period.label(settings.language),
      amount: draft.amount.format(),
      selected: selected,
      onSelected: onSelected,
      warnings: [
        for (final w in draft.warnings)
          switch (w) {
            'already_paid' => settings.say('ይህ ወር ቀድሞ ተከፍሏል', 'This month is already paid'),
            'date_unclear' => settings.say('ቀኑን ያረጋግጡ', 'Check the date'),
            _ => w,
          },
      ],
    );
  }
}
