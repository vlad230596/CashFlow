import 'dart:convert';

import 'package:cashflow/models/subscription_model.dart';
import 'package:cashflow/providers/data_provider.dart';
import 'package:cashflow/services/subscription_notification_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _FakeNotifications implements SubscriptionNotificationService {
  final synchronized = <List<SubscriptionModel>>[];
  final canceled = <int>[];
  var permissionRequests = 0;

  @override
  Stream<int> get notificationTaps => const Stream.empty();

  @override
  Future<void> initialize() async {}

  @override
  Future<bool> requestPermission() async {
    permissionRequests++;
    return true;
  }

  @override
  Future<void> synchronize(Iterable<SubscriptionModel> subscriptions) async {
    synchronized.add(subscriptions.toList());
  }

  @override
  Future<void> cancelSubscription(int subscriptionId) async {
    canceled.add(subscriptionId);
  }

  @override
  int? consumePendingSubscriptionId() => null;
}

Map<String, dynamic> _subscriptionJson({
  int id = 12,
  bool archived = false,
  String unit = 'year',
  List<int>? reminderDays,
}) {
  return {
    'id': id,
    'name': 'Cloud storage',
    'kind': 'subscription',
    'expected_amount': '3590.00',
    'currency': 'RUB',
    'card_id': 4,
    'billing_interval': {'count': 1, 'unit': unit},
    'next_payment_date': '2027-03-12',
    'reminder_days': reminderDays ?? [30, 7, 1],
    'is_archived': archived,
    'archived_at': archived ? '2026-09-25T10:00:00Z' : null,
    'created_at': '2026-09-25T08:00:00Z',
    'updated_at': '2026-09-25T08:00:00Z',
    'last_payment': {
      'id': 20,
      'amount': '3590.00',
      'currency': 'RUB',
      'card_id': 4,
      'paid_at': '2026-03-12',
      'created_at': '2026-09-25T08:00:00Z',
    },
    'payments': const [],
    'active_periods': [
      {
        'id': 3,
        'started_at': '2026-09-25T08:00:00Z',
        'ended_at': archived ? '2026-09-25T10:00:00Z' : null,
      },
    ],
  };
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('subscription model parses decimal strings and singular API units', () {
    final subscription = SubscriptionModel.fromJson(_subscriptionJson());

    expect(subscription.expectedAmount, 3590);
    expect(subscription.billingInterval.unit, BillingIntervalUnit.years);
    expect(subscription.lastPayment?.paidAt, DateTime(2026, 3, 12));
    expect(subscription.monthlyEquivalent, closeTo(3590 / 12, 0.001));
    expect(subscription.yearlyEquivalent, 3590);
    expect(subscription.activePeriods, hasLength(1));
    expect(
      subscription.toMutationJson()['billing_interval'],
      {'count': 1, 'unit': 'year'},
    );
  });

  test('uses notification defaults when server did not provide reminders', () {
    final annual = SubscriptionModel.fromJson(
      _subscriptionJson(reminderDays: const []),
    );
    final monthly = SubscriptionModel.fromJson(
      _subscriptionJson(unit: 'month', reminderDays: const []),
    );
    final trial = SubscriptionModel.fromJson({
      ..._subscriptionJson(reminderDays: const []),
      'kind': 'trial',
    });

    expect(annual.effectiveReminderDays, [30, 7, 1]);
    expect(monthly.effectiveReminderDays, [7, 1]);
    expect(trial.effectiveReminderDays, [3, 1]);
  });

  test('fetches wrapped subscription list and caches it', () async {
    final notifications = _FakeNotifications();
    final provider = DataProvider(
      apiBaseUrl: 'https://cashflow.test',
      subscriptionNotificationService: notifications,
      httpClient: MockClient((request) async {
        expect(request.url.path, '/api/subscriptions');
        expect(request.url.queryParameters['status'], 'all');
        return http.Response(
          json.encode({
            'items': [_subscriptionJson()],
            'total': 1
          }),
          200,
        );
      }),
    )..currentAuthUser = const AuthIdentity(
        id: 7,
        username: 'tester',
        role: 'editor',
      );

    expect(await provider.fetchSubscriptions(), isTrue);
    expect(provider.activeSubscriptions.single.name, 'Cloud storage');
    expect(notifications.synchronized.last, hasLength(1));
    expect(
      (await SharedPreferences.getInstance()).getString('subscriptions:7'),
      isNotNull,
    );
  });

  test('creates and archives a subscription and updates notifications',
      () async {
    final notifications = _FakeNotifications();
    final requests = <http.Request>[];
    final provider = DataProvider(
      apiBaseUrl: 'https://cashflow.test',
      subscriptionNotificationService: notifications,
      httpClient: MockClient((request) async {
        requests.add(request);
        if (request.url.path.endsWith('/archive')) {
          return http.Response(
            json.encode(_subscriptionJson(archived: true)),
            200,
          );
        }
        return http.Response(json.encode(_subscriptionJson()), 201);
      }),
    );
    final draft = SubscriptionModel(
      name: 'Cloud storage',
      kind: SubscriptionKind.subscription,
      expectedAmount: 3590,
      currency: 'RUB',
      cardId: 4,
      billingInterval: const BillingInterval(
        count: 1,
        unit: BillingIntervalUnit.years,
      ),
      nextPaymentDate: DateTime(2027, 3, 12),
      lastPayment: SubscriptionPayment(
        paidAt: DateTime(2026, 3, 12),
        amount: 3590,
        currency: 'RUB',
        cardId: 4,
      ),
    );

    final created = await provider.createSubscription(draft);
    expect(created.id, 12);
    final createPayload = json.decode(requests.first.body);
    expect(createPayload['expected_amount'], '3590.00');
    expect(createPayload['billing_interval']['unit'], 'year');
    expect(createPayload['last_payment']['paid_at'], '2026-03-12');

    await provider.archiveSubscription(12);
    expect(provider.archivedSubscriptions.single.id, 12);
    expect(notifications.canceled, [12]);
  });

  test('notification permission is only requested after first save', () async {
    final notifications = _FakeNotifications();
    final provider = DataProvider(
      apiBaseUrl: 'https://cashflow.test',
      subscriptionNotificationService: notifications,
      httpClient: MockClient((_) async => http.Response('{}', 500)),
    );

    expect(await provider.requestSubscriptionNotificationPermission(), false);
    expect(notifications.permissionRequests, 0);
    provider.subscriptions = [
      SubscriptionModel.fromJson(_subscriptionJson()),
    ];
    expect(await provider.requestSubscriptionNotificationPermission(), true);
    expect(notifications.permissionRequests, 1);
  });
}
