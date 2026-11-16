import 'dart:convert';

import 'package:cashflow/models/card_model.dart';
import 'package:cashflow/models/mcc_lookup_model.dart';
import 'package:cashflow/models/planned_payment_model.dart';
import 'package:cashflow/models/subscription_model.dart';
import 'package:cashflow/providers/data_provider.dart';
import 'package:cashflow/screens/home_screen.dart';
import 'package:cashflow/screens/planned_payments_screen.dart';
import 'package:cashflow/screens/widgets/payment_card_suggestion_view.dart';
import 'package:cashflow/services/business_clock.dart';
import 'package:cashflow/services/reminder_notification_service.dart';
import 'package:cashflow/theme/cashflow_theme.dart';
import 'package:cashflow/utils/mcc_search.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/fake_reminders.dart';
import 'support/mcc_test_cache.dart';

Map<String, dynamic> _option({
  int offerId = 31,
  int cardId = 3,
  double percent = 5,
  String category = 'Кафе и рестораны',
  String type = 'standard',
}) =>
    {
      'offer_id': offerId,
      'card_id': cardId,
      'bank_id': 1,
      'bank_name': 'ВТБ',
      'last_four_digits': '1234',
      'category_name': category,
      'category_type': type,
      'cashback_percent': percent,
    };

Map<String, dynamic> _suggestion({
  String status = 'best',
  Map<String, dynamic>? best,
  List<Map<String, dynamic>> alternatives = const [],
}) =>
    {
      'mcc_code': '5814',
      'as_of': '2026-11-25',
      'status': status,
      'best': best,
      'alternatives': alternatives,
    };

Map<String, dynamic> _paymentJson({
  int id = 5,
  String? mcc = '5814',
  Map<String, dynamic>? suggestion,
  String nextDue = '2026-11-25',
  int? cardId,
  bool completed = false,
  Map<String, dynamic>? lastRecord,
}) =>
    {
      'id': id,
      'name': 'Кофе по подписке',
      'kind': 'recurring',
      'expected_amount': '1200.00',
      'currency': 'RUB',
      'card_id': cardId,
      'note': null,
      'mcc_code': mcc,
      'card_suggestion': suggestion,
      'interval': {'count': 1, 'unit': 'month'},
      'anchor_date': nextDue,
      'next_due_date': nextDue,
      'reminder_days': [1],
      'is_completed': completed,
      'completed_at': null,
      'is_archived': false,
      'archived_at': null,
      'created_at': '2026-11-01T08:00:00Z',
      'updated_at': '2026-11-01T08:00:00Z',
      'last_record': lastRecord,
    };

http.Response _json(Object body, int status) => http.Response.bytes(
      utf8.encode(json.encode(body)),
      status,
      headers: {'content-type': 'application/json; charset=utf-8'},
    );

DataProvider _provider(
  Future<http.Response> Function(http.Request request) handler,
) =>
    DataProvider(
      mccCacheStore: isolatedMccCache(),
      apiBaseUrl: 'https://cashflow.test',
      reminderNotificationService: FakeReminders(),
      businessClock: BusinessClock(now: () => DateTime.utc(2026, 11, 24, 9)),
      httpClient: MockClient(handler),
    )..currentAuthUser = const AuthIdentity(
        id: 7,
        username: 'tester',
        role: 'viewer',
      );

PlannedPaymentModel _model(Map<String, dynamic> json) =>
    PlannedPaymentModel.fromJson(json);

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('model', () {
    test('MCC and suggestion round-trip through the cache JSON', () {
      final payment = _model(_paymentJson(
        suggestion: _suggestion(
          best: _option(),
          alternatives: [_option(offerId: 32, cardId: 4, percent: 1.5)],
        ),
      ));

      expect(payment.mccCode, '5814');
      final suggestion = payment.cardSuggestion!;
      expect(suggestion.status, PaymentCardSuggestionStatus.best);
      expect(suggestion.asOf, DateTime(2026, 11, 25));
      expect(suggestion.best!.cardId, 3);
      expect(suggestion.best!.cashbackPercent, 5);
      expect(suggestion.alternatives.single.cardId, 4);

      final restored = _model(
          json.decode(json.encode(payment.toJson())) as Map<String, dynamic>);
      expect(restored.mccCode, '5814');
      expect(restored.cardSuggestion!.best!.offerId, 31);
      expect(restored.cardSuggestion!.alternatives.single.cashbackPercent, 1.5);
      expect(payment.toMutationJson()['mcc_code'], '5814');
      expect(payment.toMutationJson().containsKey('card_suggestion'), isFalse);
    });

    test('older answers and unknown statuses degrade to no hint', () {
      final old = _paymentJson()
        ..remove('mcc_code')
        ..remove('card_suggestion');
      final payment = _model(old);
      expect(payment.mccCode, isNull);
      expect(payment.cardSuggestion, isNull);
      expect(payment.toMutationJson()['mcc_code'], isNull);

      final odd =
          _model(_paymentJson(suggestion: _suggestion(status: 'something_new')))
              .cardSuggestion!;
      expect(odd.status, PaymentCardSuggestionStatus.noRules);
      final empty =
          _model(_paymentJson(suggestion: _suggestion())).cardSuggestion!;
      expect(empty.status, PaymentCardSuggestionStatus.noBonus);
      expect(empty.best, isNull);
    });

    test('copyWith changes the card and keeps the code', () {
      final payment = _model(_paymentJson(suggestion: _suggestion()));
      final moved = payment.copyWith(cardId: 9);
      expect(moved.cardId, 9);
      expect(moved.mccCode, '5814');
      expect(moved.cardSuggestion, isNotNull);
    });
  });

  group('MCC input', () {
    test('validation accepts empty or exactly four digits', () {
      expect(validatePaymentMcc(null), isNull);
      expect(validatePaymentMcc(''), isNull);
      expect(validatePaymentMcc(' 4900 '), isNull);
      expect(validatePaymentMcc('490'), isNotNull);
      expect(validatePaymentMcc('49000'), isNotNull);
      expect(validatePaymentMcc('кафе'), isNotNull);
    });

    test('catalogue search matches code prefixes and titles like Benefit', () {
      const catalogue = [
        MccCodeModel(code: '4900', title: 'Коммунальные услуги'),
        MccCodeModel(code: '4814', title: 'Телекоммуникационные услуги'),
        MccCodeModel(code: '5814', title: 'Фастфуд'),
      ];
      List<String> codes(String query) => searchMccCodes(catalogue, query,
          code: (item) => item.code,
          title: (item) => item.title ?? '').map((item) => item.code).toList();

      expect(codes('48'), ['4814']);
      expect(codes('коммунал'), ['4900']);
      expect(codes('ус'), isEmpty);
      expect(codes('услуги'), ['4900', '4814']);
      expect(codes(''), isEmpty);
    });
  });

  group('suggestion view', () {
    Widget host(PaymentCardSuggestion suggestion) => MaterialApp(
          theme: CashFlowTheme.light(),
          home: Scaffold(
            body: PaymentCardSuggestionView(
              suggestion: suggestion,
              cardLabel: (option) => 'Карта •${option.lastFourDigits}',
            ),
          ),
        );

    testWidgets('names the best card, percent, category and date',
        (tester) async {
      final suggestion = PaymentCardSuggestion.fromJson(_suggestion(
        best: _option(percent: 5.5),
        alternatives: [_option(offerId: 40, cardId: 4, percent: 1)],
      ));

      await tester.pumpWidget(host(suggestion));

      expect(find.byKey(const ValueKey('payment-card-suggestion')),
          findsOneWidget);
      expect(find.text('Карта •1234'), findsOneWidget);
      expect(find.text('5,5%'), findsOneWidget);
      expect(
          find.textContaining('«Кафе и рестораны» · MCC 5814'), findsOneWidget);
      expect(find.textContaining('25.11.2026'), findsOneWidget);
      expect(find.textContaining('Ещё: Карта •1234 1%'), findsOneWidget);
    });

    testWidgets('says when nothing earns more than the base rate',
        (tester) async {
      await tester.pumpWidget(host(
          PaymentCardSuggestion.fromJson(_suggestion(status: 'no_bonus'))));
      expect(find.textContaining('Нет повышенного кешбэка по MCC 5814'),
          findsOneWidget);

      await tester.pumpWidget(host(
          PaymentCardSuggestion.fromJson(_suggestion(status: 'no_rules'))));
      expect(find.textContaining('не загружены'), findsOneWidget);
    });

    test('stackable bonus percent carries a plus', () {
      final option =
          PaymentCardOption.fromJson(_option(type: 'stackable_bonus'));
      expect(paymentCardPercentLabel(option), '+5%');
    });
  });

  group('editor', () {
    testWidgets('saves the MCC and right away offers the best card',
        (tester) async {
      await tester.binding.setSurfaceSize(const Size(420, 1800));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final requests = <(String, Map<String, dynamic>)>[];
      final provider = _provider((request) async {
        final body = json.decode(request.body) as Map<String, dynamic>;
        requests.add((request.method, body));
        final cardId = body['card_id'] as int?;
        return _json(
          _paymentJson(
            mcc: body['mcc_code'] as String?,
            cardId: cardId,
            suggestion: _suggestion(best: _option()),
          ),
          request.method == 'POST' ? 201 : 200,
        );
      });
      provider.cards = [CardModel(id: 3, lastFourDigits: '1234')];
      provider.mccCatalog = const [
        MccCodeModel(code: '5814', title: 'Фастфуд'),
      ];

      await tester.pumpWidget(ChangeNotifierProvider<DataProvider>.value(
        value: provider,
        child: MaterialApp(
          theme: CashFlowTheme.light(),
          home: Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: TextButton(
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => const PlannedPaymentEditScreen(
                        kind: PlannedPaymentKind.recurring,
                      ),
                    ),
                  ),
                  child: const Text('open'),
                ),
              ),
            ),
          ),
        ),
      ));
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      await tester.enterText(
          find.byKey(const ValueKey('payment-name')), 'Кофе');
      await tester.enterText(
          find.byKey(const ValueKey('payment-amount')), '1200');
      await tester.enterText(find.byKey(const ValueKey('payment-mcc')), '581');
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('payment-mcc-option-5814')));
      await tester.pumpAndSettle();
      expect(find.text('Фастфуд'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('payment-save')));
      await tester.pumpAndSettle();

      expect(requests.first.$1, 'POST');
      expect(requests.first.$2['mcc_code'], '5814');
      expect(find.text('Чем оплатить'), findsOneWidget);
      expect(find.byKey(const ValueKey('payment-card-suggestion')),
          findsOneWidget);

      await tester
          .tap(find.byKey(const ValueKey('payment-card-suggestion-assign')));
      await tester.pumpAndSettle();

      expect(requests.last.$1, 'PUT');
      expect(requests.last.$2['card_id'], 3);
      expect(provider.plannedPayments.single.cardId, 3);
      expect(find.text('open'), findsOneWidget);
    });

    testWidgets('rejects a code that is not four digits', (tester) async {
      await tester.binding.setSurfaceSize(const Size(420, 1800));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      var calls = 0;
      final provider = _provider((request) async {
        calls++;
        return _json({}, 500);
      });

      await tester.pumpWidget(ChangeNotifierProvider<DataProvider>.value(
        value: provider,
        child: MaterialApp(
          theme: CashFlowTheme.light(),
          home: const PlannedPaymentEditScreen(
            kind: PlannedPaymentKind.oneOff,
          ),
        ),
      ));
      await tester.enterText(
          find.byKey(const ValueKey('payment-name')), 'Страховка');
      await tester.enterText(
          find.byKey(const ValueKey('payment-amount')), '100');
      await tester.enterText(find.byKey(const ValueKey('payment-mcc')), '49');
      await tester.tap(find.byKey(const ValueKey('payment-save')));
      await tester.pumpAndSettle();

      expect(find.text('MCC — это 4 цифры, например 4900'), findsOneWidget);
      expect(calls, 0);
    });
  });

  group('reminder «Сделано»', () {
    Map<String, dynamic> paid() => _paymentJson(
          nextDue: '2026-12-25',
          lastRecord: {
            'id': 77,
            'payment_id': 5,
            'due_date': '2026-11-25',
            'paid_at': '2026-11-24',
            'amount': '1200.00',
            'currency': 'RUB',
            'card_id': null,
            'created_at': '2026-11-24T09:00:00Z',
          },
        );

    test('marks the reminded occurrence paid today with the expected amount',
        () async {
      final bodies = <Map<String, dynamic>>[];
      final provider = _provider((request) async {
        expect(request.method, 'POST');
        expect(request.url.path, '/api/payments/5/records');
        bodies.add(json.decode(request.body) as Map<String, dynamic>);
        return _json(paid(), 201);
      });
      provider.plannedPayments = [_model(_paymentJson())];

      final result = await provider.completePaymentFromReminder(
        ReminderTarget(ReminderKind.payment, 5,
            dueDate: DateTime(2026, 11, 25), action: ReminderAction.done),
      );

      expect(result.outcome, PaymentReminderOutcome.marked);
      expect(result.recordId, 77);
      expect(bodies.single['paid_at'], '2026-11-24');
      expect(double.parse(bodies.single['amount'].toString()), 1200);
      expect(
          provider.plannedPayments.single.nextDueDate, DateTime(2026, 12, 25));
    });

    test('a stale notification changes nothing', () async {
      var calls = 0;
      final provider = _provider((request) async {
        calls++;
        return _json(paid(), 201);
      });
      provider.plannedPayments = [_model(_paymentJson(nextDue: '2026-12-25'))];

      final result = await provider.completePaymentFromReminder(
        ReminderTarget(ReminderKind.payment, 5,
            dueDate: DateTime(2026, 11, 25), action: ReminderAction.done),
      );

      expect(result.outcome, PaymentReminderOutcome.alreadyHandled);
      expect(calls, 0);
    });

    testWidgets('the shell marks it paid and offers undo', (tester) async {
      await tester.binding.setSurfaceSize(const Size(400, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final calls = <String>[];
      final provider = _provider((request) async {
        calls.add('${request.method} ${request.url.path}');
        if (request.url.path == '/api/payments/5/records') {
          return _json(paid(), 201);
        }
        if (request.url.path == '/api/payments/5/records/77') {
          return _json(_paymentJson(), 200);
        }
        if (request.url.path == '/api/payments/5') {
          return _json(paid(), 200);
        }
        return _json({}, 404);
      });
      provider.plannedPayments = [_model(_paymentJson())];

      await tester.pumpWidget(ChangeNotifierProvider<DataProvider>.value(
        value: provider,
        child:
            MaterialApp(theme: CashFlowTheme.light(), home: const HomeScreen()),
      ));
      provider.pendingReminderTarget = ReminderTarget(ReminderKind.payment, 5,
          dueDate: DateTime(2026, 11, 25), action: ReminderAction.done);
      provider.notifyListeners();
      await tester.pumpAndSettle();

      expect(calls, contains('POST /api/payments/5/records'));
      expect(find.text('Платёж «Кофе по подписке» отмечен оплаченным'),
          findsOneWidget);

      await tester.tap(find.text('Отменить'));
      await tester.pumpAndSettle();
      expect(calls, contains('DELETE /api/payments/5/records/77'));
    });

    test('a deleted payment is reported, not created', () async {
      final provider = _provider((request) async => _json({}, 404));
      final result = await provider.completePaymentFromReminder(
        const ReminderTarget(ReminderKind.payment, 99),
      );
      expect(result.outcome, PaymentReminderOutcome.notFound);
    });
  });

  group('reminder actions', () {
    PlannedPaymentModel payment({DateTime? due}) => PlannedPaymentModel(
          id: 7,
          name: 'Детский сад',
          kind: PlannedPaymentKind.recurring,
          expectedAmount: 8500,
          currency: 'RUB',
          interval:
              const BillingInterval(count: 1, unit: BillingIntervalUnit.months),
          nextDueDate: due ?? DateTime(2026, 11, 25),
        );

    test('payment reminders carry both buttons and the due date', () {
      expect(ReminderKind.payment.actions,
          [ReminderAction.snooze, ReminderAction.done]);
      expect(ReminderKind.subscription.hasActions, isFalse);
      expect(ReminderAction.byId('reminder_snooze'), ReminderAction.snooze);
      expect(ReminderAction.byId('reminder_done'), ReminderAction.done);
      expect(ReminderAction.byId(null), isNull);
      expect(ReminderAction.snooze.showsUserInterface, isFalse);
      expect(ReminderAction.done.showsUserInterface, isTrue);

      final target = ReminderTarget.parse('payment:7@2026-11-25');
      expect(
          target,
          ReminderTarget(ReminderKind.payment, 7,
              dueDate: DateTime(2026, 11, 25)));
      expect(target!.payload, 'payment:7@2026-11-25');
      expect(
          target.withAction(ReminderAction.done).action, ReminderAction.done);
      expect(ReminderTarget.parse('payment:7@25.11.2026'), isNull);
      expect(ReminderTarget.parse('payment:7'),
          const ReminderTarget(ReminderKind.payment, 7));
    });

    test('regular reminders never use the snooze slot', () {
      final planned = const ReminderPlanner().plan(
        ReminderKind.payment,
        [
          ReminderSpec(
            entityId: 7,
            dueDate: DateTime(2027, 6, 1),
            reminderDays: List.generate(40, (index) => index),
            title: (_) => 't',
            body: (_) => 'b',
          ),
        ],
        DateTime(2026, 11, 11),
      );
      expect(planned, hasLength(ReminderKind.snoozeSlot));
      expect(
        planned.map((item) => item.id),
        isNot(contains(
            ReminderKind.payment.notificationId(7, ReminderKind.snoozeSlot))),
      );
    });

    test('snooze re-posts the same text an hour later in the snooze slot', () {
      final now = DateTime.utc(2026, 11, 24, 7);
      final snooze = planSnooze(
        payload: 'payment:7@2026-11-25',
        now: now,
        title: 'Пора оплатить: Детский сад',
        body: '8500 RUB — оплатить до 25.11.2026 (завтра)',
      )!;

      expect(reminderSnoozeDelay, const Duration(hours: 1));
      expect(snooze.fireAt, DateTime.utc(2026, 11, 24, 8));
      expect(snooze.id,
          ReminderKind.payment.notificationId(7, ReminderKind.snoozeSlot));
      expect(snooze.target.payload, 'payment:7@2026-11-25');
      expect(snooze.title, 'Пора оплатить: Детский сад');
      expect(snooze.body, contains('25.11.2026'));

      final unknownText = planSnooze(payload: 'payment:7', now: now)!;
      expect(unknownText.title, 'Напоминание о платеже');
      expect(planSnooze(payload: 'subscription:7', now: now), isNull);
      expect(planSnooze(payload: null, now: now), isNull);
    });

    test('synchronization keeps a snooze only for the same open due date', () {
      List<ReminderSpec> specsFor(List<PlannedPaymentModel> payments) => [
            for (final item in payments)
              ReminderSpec(
                entityId: item.id!,
                dueDate: item.nextDueDate,
                reminderDays: item.reminderDays,
                title: (_) => '',
                body: (_) => '',
              ),
          ];
      final snoozeId =
          ReminderKind.payment.notificationId(7, ReminderKind.snoozeSlot);
      final pending = [
        (id: snoozeId, payload: 'payment:7@2026-11-25'),
        (id: ReminderKind.payment.notificationId(7, 0), payload: 'payment:7'),
      ];

      expect(
        snoozedRemindersToKeep(
            ReminderKind.payment, specsFor([payment()]), pending),
        {snoozeId},
      );
      // Paid: the payment moved to the next month.
      expect(
        snoozedRemindersToKeep(ReminderKind.payment,
            specsFor([payment(due: DateTime(2026, 12, 25))]), pending),
        isEmpty,
      );
      // Archived or completed: no spec at all.
      expect(snoozedRemindersToKeep(ReminderKind.payment, const [], pending),
          isEmpty);
      expect(
        snoozedRemindersToKeep(
            ReminderKind.subscription, specsFor([payment()]), pending),
        isEmpty,
      );
    });
  });
}
