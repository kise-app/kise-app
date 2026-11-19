/// The assistant: say, type or photograph what you spent, check it, save it. Or ask a question.
///
/// One sheet, two modes:
///
/// * **Record** — type "bread 40, taxi 100", tap the mic and speak (Amharic, English, or both), or
///   photograph a receipt. The server reads it and returns *drafts*; each shows its category,
///   amount, date in the person's calendar, payment method and anything worth double-checking. The
///   person unticks what is wrong, taps a draft to adjust it in the normal expense form, and saves
///   the rest in one go. Nothing is recorded until they do.
/// * **Ask** — "how much on food this month?" is answered from the server's own figures.
///
/// The microphone and camera sit behind [VoiceRecorder] and [ReceiptPicker] (see `capture.dart`),
/// so this widget is testable without plugins. Voice notes stop on their own after a minute.
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
class AssistantButton extends ConsumerWidget {
  const AssistantButton({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final enabled = ref.watch(assistantStatusProvider).valueOrNull?.enabled ?? false;
    if (!enabled) return const SizedBox.shrink();
    final settings = ref.watch(settingsProvider);
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: FloatingActionButton.small(
        key: const Key('assistant-open'),
        heroTag: null,
        tooltip: settings.say('በድምፅ ወይም በደረሰኝ መዝግብ', 'Record by voice or receipt'),
        onPressed: () async {
          final messenger = ScaffoldMessenger.maybeOf(context);
          final saved = await showAssistantSheet(context);
          if (saved != null && saved > 0) {
            messenger?.showSnackBar(
              SnackBar(content: Text(settings.say('$saved ወጪዎች ተመዝግበዋል', 'Saved $saved expenses'))),
            );
          }
        },
        child: const Icon(Icons.auto_awesome_rounded),
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
  String? _answer;
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
      if (_elapsed >= maxVoiceNote) _stopRecording();
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
    await _run(
      (api) => api.readVoice(
        audio.bytes,
        contentType: audio.contentType,
        filename: audio.filename,
        today: _today,
      ),
    );
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

  Future<void> _saveSelected() async {
    final chosen = [
      for (var i = 0; i < _drafts.length; i++)
        if (_selected[i]) i,
    ];
    if (chosen.isEmpty) return;
    setState(() {
      _phase = _Phase.saving;
      _error = null;
    });
    final api = ref.read(expensesApiProvider);
    final saved = <int>{};
    String? failure;
    for (final i in chosen) {
      final draft = _drafts[i];
      try {
        await api.record(
          categoryId: draft.categoryId,
          amountMinor: draft.amount.minorUnits,
          date: draft.spentOn.gregorian,
          dateCalendar: 'gregorian',
          note: draft.note,
          paymentMethod: draft.paymentMethod,
          itemName: draft.item?.itemName,
          quantity: draft.item?.quantity,
          unitId: draft.item?.unitId,
        );
        saved.add(i);
      } on ApiException catch (error) {
        failure ??= error.message;
      }
    }
    if (saved.isNotEmpty) invalidateMonthData(ref);
    if (!mounted) return;
    if (failure == null) {
      Navigator.of(context).pop(saved.length);
      return;
    }
    // Keep only what did not save, so retrying cannot record anything twice.
    setState(() {
      _drafts = [
        for (var i = 0; i < _drafts.length; i++)
          if (!saved.contains(i)) _drafts[i],
      ];
      _selected = List<bool>.filled(_drafts.length, true, growable: true);
      _phase = _Phase.idle;
      _error = _settings.say(
        '${saved.length} ተመዝግበዋል፤ የቀሩት አልተመዘገቡም፦ $failure',
        '${saved.length} saved; the rest were not: $failure',
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
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final viewInsets = MediaQuery.of(context).viewInsets.bottom;
    final busy = _phase == _Phase.working || _phase == _Phase.saving;
    final selectedCount = _selected.where((s) => s).length;
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
            if (_mode == _Mode.record) ...[
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
                                'አቁም · ${_elapsed.inSeconds}s',
                                'Stop · ${_elapsed.inSeconds}s',
                              )
                            : settings.say('ተናገር', 'Speak'),
                      ),
                    ),
                  ),
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
              ),
              const SizedBox(height: 6),
              Text(
                settings.say(
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
              if (_drafts.isNotEmpty) ...[
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
                      : Text(
                          settings.say('$selectedCount ወጪዎችን መዝግብ', 'Save $selectedCount expenses'),
                        ),
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
