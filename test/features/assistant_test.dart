/// Widget tests for the assistant sheet: typed text, voice notes and receipt photos become drafts
/// the person reviews before anything is recorded; questions get an answer. The API, microphone
/// and camera are all fakes.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kise/features/assistant/assistant_sheet.dart';
import 'package:kise/features/assistant/capture.dart';
import 'package:kise/features/expenses/presentation/expenses_screen.dart';
import 'package:kise/platform/api/api.dart';
import 'package:kise/platform/settings.dart';
import 'package:kise/platform/theme.dart';
import 'package:kise/shared_kernel/period.dart';

import '../support/fake_api.dart';

final _today = DateTime.utc(2026, 9, 4);

class FakeRecorder implements VoiceRecorder {
  FakeRecorder({this.allowed = true, this.audio});

  final bool allowed;
  final CapturedMedia? audio;
  final List<String> calls = [];

  @override
  Future<bool> requestPermission() async {
    calls.add('permission');
    return allowed;
  }

  @override
  Future<void> start() async => calls.add('start');

  @override
  Future<CapturedMedia?> stop() async {
    calls.add('stop');
    return audio;
  }

  @override
  Future<void> cancel() async => calls.add('cancel');

  @override
  Future<void> dispose() async => calls.add('dispose');
}

class FakePicker implements ReceiptPicker {
  FakePicker(this.image);

  final CapturedMedia? image;
  final List<ReceiptSource> sources = [];

  @override
  Future<CapturedMedia?> pick(ReceiptSource source) async {
    sources.add(source);
    return image;
  }
}

Widget _host({
  required FakeAssistantApi assistant,
  FakeExpensesApi? expenses,
  FakeRecorder? recorder,
  FakePicker? picker,
  FakeFixedExpensesApi? fixedExpenses,
}) => ProviderScope(
  overrides: [
    todayProvider.overrideWithValue(_today),
    settingsStoreProvider.overrideWithValue(
      InMemorySettingsStore(const AppSettings(language: Language.english)),
    ),
    voiceRecorderProvider.overrideWithValue(() => recorder ?? FakeRecorder()),
    receiptPickerProvider.overrideWithValue(picker ?? FakePicker(null)),
    ...fakeApiOverrides(
      assistant: assistant,
      expenses: expenses,
      fixedExpenses: fixedExpenses,
      categories: FakeCategoriesApi([category('c1', 'Taxi'), category('c2', 'Food')]),
    ),
  ],
  child: MaterialApp(
    theme: buildTheme(),
    home: const Scaffold(body: AssistantSheet()),
  ),
);

void main() {
  setUp(() {
    final view = TestWidgetsFlutterBinding.ensureInitialized().platformDispatcher.views.first;
    view.physicalSize = const Size(1200, 2600);
    view.devicePixelRatio = 1.0;
  });
  tearDown(() {
    final view = TestWidgetsFlutterBinding.ensureInitialized().platformDispatcher.views.first;
    view.resetPhysicalSize();
    view.resetDevicePixelRatio();
  });

  testWidgets('typed text becomes drafts; saving records the ticked ones', (tester) async {
    final assistant = FakeAssistantApi(
      reply: replyOf([
        draftOf(categoryId: 'c1', amountMinor: 15000, paymentMethod: 'telebirr', note: 'Bole'),
        draftOf(categoryId: 'c2', categoryName: 'Food', amountMinor: 4000),
      ], message: 'Found two expenses'),
    );
    final recorded = <Map<String, Object?>>[];
    final expenses = FakeExpensesApi(
      onRecord: (body) async {
        recorded.add(body);
        return expenseRow(id: 'x', amountMinor: body['amount_minor'] as int);
      },
    );
    await tester.pumpWidget(_host(assistant: assistant, expenses: expenses));
    await tester.pumpAndSettle();

    await tester.enterText(find.byKey(const Key('assistant-input')), 'taxi 150 telebirr, bread 40');
    await tester.tap(find.byKey(const Key('assistant-send')));
    await tester.pumpAndSettle();

    expect(assistant.calls.single, {
      'kind': 'text',
      'text': 'taxi 150 telebirr, bread 40',
      'today': '2026-09-04',
    });
    expect(find.text('Found two expenses'), findsOneWidget);
    expect(find.byKey(const Key('draft-0')), findsOneWidget);
    expect(find.text('150.00 ETB'), findsOneWidget);
    expect(find.textContaining('Nehase 29 · Telebirr · Bole'), findsOneWidget);
    expect(recorded, isEmpty, reason: 'nothing is recorded before the person confirms');

    // Untick the second, save the first.
    await tester.tap(
      find.descendant(of: find.byKey(const Key('draft-1')), matching: find.byType(Checkbox)),
    );
    await tester.pumpAndSettle();
    expect(find.text('Save 1'), findsOneWidget);
    await tester.tap(find.byKey(const Key('assistant-save')));
    await tester.pumpAndSettle();

    expect(recorded, hasLength(1));
    expect(recorded.single['category_id'], 'c1');
    expect(recorded.single['amount_minor'], 15000);
    expect(recorded.single['date'], '2026-09-04');
    expect(recorded.single['payment_method'], 'telebirr');
    expect(recorded.single['note'], 'Bole');
  });

  testWidgets('a voice note is recorded, sent, and its transcript shown', (tester) async {
    final recorder = FakeRecorder(
      audio: const CapturedMedia(bytes: [1, 2, 3], contentType: 'audio/mp4', filename: 'v.m4a'),
    );
    final assistant = FakeAssistantApi(
      reply: replyOf([draftOf(amountMinor: 3000)], transcript: 'ቡና 30 ብር'),
    );
    await tester.pumpWidget(_host(assistant: assistant, recorder: recorder));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('assistant-mic')));
    await tester.pump();
    expect(find.textContaining('Stop'), findsOneWidget);
    await tester.pump(const Duration(seconds: 2));
    expect(find.textContaining('Stop · 2s'), findsOneWidget);

    await tester.tap(find.byKey(const Key('assistant-mic')));
    await tester.pumpAndSettle();

    expect(recorder.calls, ['permission', 'start', 'stop']);
    expect(assistant.calls.single['kind'], 'voice');
    expect(assistant.calls.single['bytes'], [1, 2, 3]);
    expect(assistant.calls.single['type'], 'audio/mp4');
    expect(find.text('“ቡና 30 ብር”'), findsOneWidget);
    expect(find.byKey(const Key('draft-0')), findsOneWidget);
  });

  testWidgets('without microphone permission it says how to fix it', (tester) async {
    final recorder = FakeRecorder(allowed: false);
    final assistant = FakeAssistantApi();
    await tester.pumpWidget(_host(assistant: assistant, recorder: recorder));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('assistant-mic')));
    await tester.pumpAndSettle();
    expect(find.textContaining('Microphone access is off'), findsOneWidget);
    expect(recorder.calls, ['permission']);
    expect(assistant.calls, isEmpty);
  });

  testWidgets('a receipt photo is read into drafts', (tester) async {
    final picker = FakePicker(
      const CapturedMedia(bytes: [9, 9], contentType: 'image/jpeg', filename: 'r.jpg'),
    );
    final assistant = FakeAssistantApi(
      reply: replyOf([
        draftOf(categoryId: 'c2', amountMinor: 123450, warnings: ['date_unclear']),
      ]),
    );
    await tester.pumpWidget(_host(assistant: assistant, picker: picker));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('assistant-camera')));
    await tester.pumpAndSettle();

    expect(picker.sources, [ReceiptSource.camera]);
    expect(assistant.calls.single['kind'], 'receipt');
    expect(find.text('1,234.50 ETB'), findsOneWidget);
    expect(find.textContaining('Check the date'), findsOneWidget);
  });

  testWidgets('backing out of the camera sends nothing', (tester) async {
    final assistant = FakeAssistantApi();
    await tester.pumpWidget(_host(assistant: assistant, picker: FakePicker(null)));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('assistant-gallery')));
    await tester.pumpAndSettle();
    expect(assistant.calls, isEmpty);
  });

  testWidgets('tapping a draft opens the expense form pre-filled', (tester) async {
    final assistant = FakeAssistantApi(reply: replyOf([draftOf(amountMinor: 15000, note: 'Bole')]));
    final expenses = FakeExpensesApi();
    await tester.pumpWidget(_host(assistant: assistant, expenses: expenses));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('assistant-input')), 'taxi 150');
    await tester.tap(find.byKey(const Key('assistant-send')));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('draft-0')));
    await tester.pumpAndSettle();
    expect(find.text('Record an expense'), findsOneWidget);
    await tester.enterText(find.byKey(const Key('expense-amount')), '160');
    await tester.tap(find.byKey(const Key('expense-submit')));
    await tester.pumpAndSettle();

    expect(expenses.lastRecord!['amount_minor'], 16000);
    expect(expenses.lastRecord!['category_id'], 'c1');
    expect(expenses.lastRecord!['note'], 'Bole');
    // Recorded from the form, so it is no longer a draft.
    expect(find.byKey(const Key('draft-0')), findsNothing);
  });

  testWidgets('questions get an answer', (tester) async {
    final assistant = FakeAssistantApi(answer: 'You spent 1,250 ETB on food this month.');
    await tester.pumpWidget(_host(assistant: assistant));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Ask'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('assistant-mic')), findsOneWidget, reason: 'Ask takes voice too');
    await tester.enterText(find.byKey(const Key('assistant-input')), 'How much on food?');
    await tester.tap(find.byKey(const Key('assistant-send')));
    await tester.pumpAndSettle();

    expect(assistant.calls.single, {
      'kind': 'ask',
      'question': 'How much on food?',
      'today': '2026-09-04',
    });
    expect(find.text('You spent 1,250 ETB on food this month.'), findsOneWidget);
  });

  testWidgets('server errors are explained in plain words', (tester) async {
    final assistant = FakeAssistantApi(
      error: const ApiException(
        message: 'That is 30 assistant requests this hour; please wait a little',
        code: 'assistant_rate_limited',
        statusCode: 429,
      ),
    );
    await tester.pumpWidget(_host(assistant: assistant));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('assistant-input')), 'taxi 100');
    await tester.tap(find.byKey(const Key('assistant-send')));
    await tester.pumpAndSettle();
    expect(find.textContaining('30 assistant requests this hour'), findsOneWidget);
  });

  testWidgets('"rent every month" schedules a fixed monthly expense', (tester) async {
    final fixed = FakeFixedExpensesApi();
    final assistant = FakeAssistantApi(
      reply: replyOf(const [], fixed: [fixedDraftOf(title: 'Rent', amountMinor: 800000)]),
    );
    await tester.pumpWidget(_host(assistant: assistant, fixedExpenses: fixed));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('assistant-input')), 'rent 8000 every month on 5');
    await tester.tap(find.byKey(const Key('assistant-send')));
    await tester.pumpAndSettle();

    expect(find.text('Every month · Rent'), findsOneWidget);
    expect(find.text('From Pagumen 2018 · due day 5'), findsOneWidget);
    expect(fixed.lastSchedule, isNull, reason: 'nothing is scheduled before confirming');

    await tester.tap(find.byKey(const Key('assistant-save')));
    await tester.pumpAndSettle();
    expect(fixed.lastSchedule!['title'], 'Rent');
    expect(fixed.lastSchedule!['amount_minor'], 800000);
    expect(fixed.lastSchedule!['due_day'], 5);
    expect(fixed.lastSchedule!['start_period'], Period(CalendarKind.ethiopian, 2018, 13));
  });

  testWidgets('"I paid the rent" marks the existing commitment paid', (tester) async {
    final fixed = FakeFixedExpensesApi([fixedExpense('fx-1', 'Rent', 800000)]);
    final assistant = FakeAssistantApi(reply: replyOf(const [], payments: [paymentDraftOf()]));
    await tester.pumpWidget(_host(assistant: assistant, fixedExpenses: fixed));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('assistant-input')), 'I paid the rent');
    await tester.tap(find.byKey(const Key('assistant-send')));
    await tester.pumpAndSettle();

    expect(find.text('Mark Rent paid'), findsOneWidget);
    await tester.tap(find.byKey(const Key('assistant-save')));
    await tester.pumpAndSettle();
    expect(fixed.calls, ['settle:fx-1:800000']);
    expect(fixed.lastSettledOn, '2026-09-04');
  });

  testWidgets('a month already paid starts unticked', (tester) async {
    final assistant = FakeAssistantApi(
      reply: replyOf(
        const [],
        payments: [
          paymentDraftOf(warnings: ['already_paid']),
        ],
      ),
    );
    await tester.pumpWidget(_host(assistant: assistant));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('assistant-input')), 'paid rent');
    await tester.tap(find.byKey(const Key('assistant-send')));
    await tester.pumpAndSettle();

    expect(find.textContaining('This month is already paid'), findsOneWidget);
    expect(find.text('Save 0'), findsOneWidget);
  });

  testWidgets('a question can be asked out loud', (tester) async {
    final recorder = FakeRecorder(
      audio: const CapturedMedia(bytes: [7], contentType: 'audio/mp4', filename: 'q.m4a'),
    );
    final assistant = FakeAssistantApi(answer: 'You spent 600 ETB on food.')
      ..heard = 'How much on food?';
    await tester.pumpWidget(_host(assistant: assistant, recorder: recorder));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Ask'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('assistant-camera')), findsNothing, reason: 'no receipts in Ask');
    await tester.tap(find.byKey(const Key('assistant-mic')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('assistant-mic')));
    await tester.pumpAndSettle();

    expect(assistant.calls.single['kind'], 'ask-voice');
    expect(assistant.calls.single['bytes'], [7]);
    expect(find.text('“How much on food?”'), findsOneWidget);
    expect(find.text('You spent 600 ETB on food.'), findsOneWidget);
  });

  group('the open button', () {
    Widget screen(FakeAssistantApi assistant) => ProviderScope(
      overrides: [
        todayProvider.overrideWithValue(_today),
        settingsStoreProvider.overrideWithValue(
          InMemorySettingsStore(const AppSettings(language: Language.english)),
        ),
        ...fakeApiOverrides(assistant: assistant),
      ],
      child: MaterialApp(theme: buildTheme(), home: const ExpensesScreen()),
    );

    testWidgets('is hidden when the server has the assistant off', (tester) async {
      await tester.pumpWidget(screen(FakeAssistantApi(enabled: false)));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('assistant-open')), findsNothing);
    });

    testWidgets('opens the sheet when on', (tester) async {
      await tester.pumpWidget(screen(FakeAssistantApi()));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('assistant-open')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('assistant-input')), findsOneWidget);
    });

    testWidgets('on Basic it shows a lock and explains Pro instead', (tester) async {
      await tester.pumpWidget(screen(FakeAssistantApi(allowed: false)));
      await tester.pumpAndSettle();
      expect(find.byIcon(Icons.lock_outline_rounded), findsOneWidget);
      await tester.tap(find.byKey(const Key('assistant-open')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('upgrade-sheet')), findsOneWidget);
      expect(find.byKey(const Key('assistant-input')), findsNothing);
    });
  });
}
