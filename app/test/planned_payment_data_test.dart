import 'dart:convert';

import 'package:cashflow/models/planned_payment_model.dart';
import 'package:cashflow/models/subscription_model.dart';
import 'package:cashflow/providers/data_provider.dart';
import 'package:cashflow/services/business_clock.dart';
import 'package:cashflow/services/reminder_notification_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/fake_reminders.dart';
import 'support/mcc_test_cache.dart';

Map<String, dynamic> _paymentJson({
  int id = 5,
  String kind = 'recurring',
  String nextDue = '2026-11-25',
  bool completed = false,
  Map<String, dynamic>? lastRecord,
  List<Map<String, dynamic>>? records,
}) =>
    {
      'id': id,
      'name': kind == 'recurring' ? 'Детский сад' : 'Страховка',
      'kind': kind,
      'expected_amount': '8500.00',
      'currency': 'RUB',
      'card_id': null,
      'note': null,
      'interval': kind == 'recurring' ? {'count': 1, 'unit': 'month'} : null,
      'anchor_date': nextDue,
      'next_due_date': nextDue,
      'reminder_days': [1],
      'is_completed': completed,
      'completed_at': completed ? '2026-11-11T08:00:00Z' : null,
      'is_archived': false,
      'archived_at': null,
      'created_at': '2026-11-01T08:00:00Z',
      'updated_at': '2026-11-01T08:00:00Z',
      'last_record': lastRecord,
      if (records != null) 'records': records,
    };

Map<String, dynamic> _record({int id = 1, String due = '2026-11-25'}) => {
      'id': id,
      'payment_id': 5,
      'due_date': due,
      'paid_at': '2026-11-11',
      'amount': '8500.00',
      'currency': 'RUB',
      'card_id': null,
      'created_at': '2026-11-11T08:00:00Z',
    };

http.Response _jsonResponse(String body, int status) => http.Response.bytes(
      utf8.encode(body),
      status,
      headers: {'content-type': 'application/json; charset=utf-8'},
    );

DataProvider _provider(
  FakeReminders reminders,
  Future<http.Response> Function(http.Request request) handler,
) =>
    DataProvider(
      mccCacheStore: isolatedMccCache(),
      apiBaseUrl: 'https://cashflow.test',
      reminderNotificationService: reminders,
      businessClock: BusinessClock(now: () => DateTime.utc(2026, 11, 11, 9)),
      httpClient: MockClient(handler),
    )..currentAuthUser = const AuthIdentity(
        id: 7,
        username: 'tester',
        role: 'viewer',
      );

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('fetches payments, caches per account and schedules payment reminders',
      () async {
    final reminders = FakeReminders();
    final provider = _provider(reminders, (request) async {
      expect(request.url.path, '/api/payments');
      expect(request.url.queryParameters['status'], 'all');
      return _jsonResponse(
        json.encode({
          'items': [
            _paymentJson(nextDue: '2026-11-01'),
            _paymentJson(
              id: 6,
              kind: 'one_off',
              nextDue: '2026-11-13',
            ),
            _paymentJson(id: 8, kind: 'one_off', completed: true),
          ],
          'total': 3,
        }),
        200,
      );
    });

    expect(await provider.fetchPlannedPayments(), isTrue);

    final today = provider.businessToday;
    expect(today, DateTime(2026, 11, 11));
    final recurring = provider.openPayments(PlannedPaymentKind.recurring);
    expect(recurring.single.isOverdue(today), isTrue);
    expect(provider.openPayments(PlannedPaymentKind.oneOff).single.id, 6);
    expect(provider.closedPayments(PlannedPaymentKind.oneOff).single.id, 8);
    expect(
      reminders.lastSpecs(ReminderKind.payment).map((spec) => spec.entityId),
      [5, 6],
    );
    expect(
      (await SharedPreferences.getInstance())
          .getString('data:v1:https%3A%2F%2Fcashflow.test:7:plannedPayments'),
      isNotNull,
    );
  });

  test('create, mark paid, undo and delete go through the payments API',
      () async {
    final reminders = FakeReminders();
    final requests = <http.Request>[];
    final provider = _provider(reminders, (request) async {
      requests.add(request);
      final path = request.url.path;
      if (request.method == 'POST' && path == '/api/payments') {
        return _jsonResponse(json.encode(_paymentJson()), 201);
      }
      if (path == '/api/payments/5/records') {
        return _jsonResponse(
          json.encode(_paymentJson(
            nextDue: '2026-12-25',
            lastRecord: _record(),
            records: [_record()],
          )),
          201,
        );
      }
      if (path == '/api/payments/5/records/1') {
        return _jsonResponse(json.encode(_paymentJson(records: const [])), 200);
      }
      if (request.method == 'DELETE' && path == '/api/payments/5') {
        return http.Response('', 204);
      }
      return http.Response('{"error": "unexpected"}', 500);
    });

    final created = await provider.createPlannedPayment(
      PlannedPaymentModel(
        name: 'Детский сад',
        kind: PlannedPaymentKind.recurring,
        expectedAmount: 8500,
        currency: 'RUB',
        interval:
            const BillingInterval(count: 1, unit: BillingIntervalUnit.months),
        nextDueDate: DateTime(2026, 11, 25),
      ),
    );
    expect(created.id, 5);
    final createBody = json.decode(requests.first.body) as Map;
    expect(createBody['kind'], 'recurring');
    expect(createBody['next_due_date'], '2026-11-25');
    expect(createBody['anchor_date'], '2026-11-25');
    expect(createBody['card_id'], isNull);
    expect(createBody['reminder_days'], [1]);

    final paid = await provider.markPlannedPaymentPaid(
      5,
      paidAt: DateTime(2026, 11, 11),
      amount: 8700,
    );
    expect(paid.nextDueDate, DateTime(2026, 12, 25));
    final payBody = json.decode(requests[1].body) as Map;
    expect(payBody, {'paid_at': '2026-11-11', 'amount': '8700.00'});
    expect(
      reminders.lastSpecs(ReminderKind.payment).single.dueDate,
      DateTime(2026, 12, 25),
    );

    final undone = await provider.undoPlannedPaymentRecord(5, 1);
    expect(undone.nextDueDate, DateTime(2026, 11, 25));
    expect(requests[2].method, 'DELETE');

    await provider.deletePlannedPayment(5);
    expect(provider.plannedPayments, isEmpty);
    expect(reminders.lastSpecs(ReminderKind.payment), isEmpty);
  });

  test('API errors surface the server message', () async {
    final provider = _provider(
      FakeReminders(),
      (_) async => http.Response(
        json.encode({'error': 'paid_at cannot be in the future'}),
        400,
      ),
    );

    await expectLater(
      provider.markPlannedPaymentPaid(5, paidAt: DateTime(2026, 11, 12)),
      throwsA(predicate((error) =>
          error.toString().contains('paid_at cannot be in the future'))),
    );
  });

  test('exact reminder permission reschedules every kind', () async {
    final reminders = FakeReminders();
    final provider =
        _provider(reminders, (_) async => http.Response('{}', 500));

    expect(await provider.canScheduleExactReminders(), isFalse);
    expect(await provider.requestExactReminderPermission(), isTrue);
    expect(reminders.exactRequests, 1);
    expect(reminders.synchronized.keys,
        containsAll([ReminderKind.subscription, ReminderKind.payment]));
  });
}
