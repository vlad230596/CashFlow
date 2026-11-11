import 'dart:convert';

import 'package:cashflow/models/promo_model.dart';
import 'package:cashflow/providers/data_provider.dart';
import 'package:cashflow/services/business_clock.dart';
import 'package:cashflow/services/reminder_notification_service.dart';
import 'package:cashflow/services/reminder_sources.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/fake_reminders.dart';
import 'support/mcc_test_cache.dart';

const _cacheKey = 'data:v1:https%3A%2F%2Fcashflow.test:7:promos';

Map<String, dynamic> _promoJson({
  int id = 5,
  String kind = 'promo',
  String title = 'Ozon: скидка 500 ₽',
  String? expires = '2026-11-30',
  String? clientId,
  bool used = false,
  bool archived = false,
  String? code = 'OZON500',
}) =>
    {
      'id': id,
      'client_id': clientId,
      'kind': kind,
      'title': title,
      'merchant': 'Ozon',
      'promo_code': code,
      'discount': 'скидка 500 ₽',
      'points_amount': kind == 'points' ? '300.00' : null,
      'points_unit': kind == 'points' ? 'баллов' : null,
      'description': null,
      'source_text': 'OZON: промокод OZON500 до 30 ноября',
      'starts_at': null,
      'expires_at': expires,
      'reminder_days': [3, 1],
      'status': 'active',
      'days_left': 19,
      'is_used': used,
      'used_at': used ? '2026-11-10T08:00:00Z' : null,
      'is_archived': archived,
      'archived_at': archived ? '2026-11-09T08:00:00Z' : null,
      'created_at': '2026-11-01T08:00:00Z',
      'updated_at': '2026-11-01T08:00:00Z',
    };

http.Response _json(Object body, int status) => http.Response.bytes(
      utf8.encode(json.encode(body)),
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

PromoModel _local({
  int? id,
  String title = 'Промокод',
  DateTime? expires,
  bool used = false,
  bool archived = false,
  DateTime? usedAt,
}) =>
    PromoModel(
      id: id,
      kind: PromoKind.promo,
      title: title,
      expiresAt: expires,
      isUsed: used,
      usedAt: usedAt,
      isArchived: archived,
    );

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  final today = DateTime(2026, 11, 11);

  test('status is derived from the Moscow day and lists sort by expiry', () {
    final items = [
      _local(id: 1, title: 'Позже', expires: DateTime(2026, 12, 31)),
      _local(id: 2, title: 'Без срока'),
      _local(id: 3, title: 'Сегодня', expires: today),
      _local(id: 4, title: 'Вчера', expires: DateTime(2026, 11, 10)),
      _local(id: 5, title: 'Давно', expires: DateTime(2026, 10, 1)),
      _local(
        id: 6,
        title: 'Использован',
        expires: DateTime(2026, 11, 20),
        used: true,
        usedAt: DateTime.utc(2026, 11, 5),
      ),
      _local(id: 7, title: 'Архив', archived: true),
      _local(id: 8, title: 'Завтра', expires: DateTime(2026, 11, 12)),
    ];

    List<String> titles(PromoStatus status) =>
        promosWithStatus(items, status, today).map((e) => e.title).toList();

    expect(titles(PromoStatus.active), ['Сегодня', 'Завтра', 'Позже', 'Без срока']);
    expect(titles(PromoStatus.expired), ['Вчера', 'Давно']);
    expect(titles(PromoStatus.used), ['Использован']);
    expect(titles(PromoStatus.archived), ['Архив']);
    expect(items[2].daysLeft(today), 0);
    expect(items[2].isUrgent(today), isTrue);
    expect(items[0].isUrgent(today), isFalse);
    expect(items[1].isUrgent(today), isFalse);
    expect(items[5].isUrgent(today), isFalse);
  });

  test('reminders only for synced active items with an expiry date', () {
    final specs = promoReminderSpecs([
      _local(id: 1, title: 'Активный', expires: DateTime(2026, 11, 30)),
      _local(id: 2, title: 'Без срока'),
      _local(id: 3, title: 'Истёк', expires: DateTime(2026, 11, 1)),
      _local(id: 4, title: 'Использован', expires: DateTime(2026, 11, 30), used: true),
      _local(title: 'Не отправлен', expires: DateTime(2026, 11, 30)),
      PromoModel(
        id: 6,
        kind: PromoKind.points,
        title: 'Баллы',
        pointsAmount: 300,
        expiresAt: DateTime(2026, 12, 15),
        promoCode: null,
      ),
    ], today);

    expect(specs.map((spec) => spec.entityId), [1, 6]);
    expect(specs.first.reminderDays, defaultPromoReminderDays);
    expect(specs.first.dueDate, DateTime(2026, 11, 30));
    expect(specs.first.title(0), 'Последний день: Активный');
    expect(specs.first.title(3), 'Скоро истекает: Активный');
    expect(specs.first.body(3), 'Действует до 30.11.2026');
    expect(specs.last.title(1), 'Скоро сгорят баллы: Баллы');
    expect(specs.last.body(0), 'Сгорят завтра · последний день 15.12.2026');

    final planned = const ReminderPlanner().plan(
      ReminderKind.promo,
      specs,
      DateTime(2026, 11, 11, 12),
    );
    expect(planned.first.id, ReminderKind.promo.notificationId(1, 0));
    expect(planned.first.payload, 'promo:1');
    expect(planned.first.fireAt, DateTime(2026, 11, 27, 10));
    expect(ReminderTarget.parse('promo:12'),
        const ReminderTarget(ReminderKind.promo, 12));
    expect(ReminderKind.promo.block, 3);
  });

  test('fetches promos, caches per account and schedules reminders', () async {
    final reminders = FakeReminders();
    final provider = _provider(reminders, (request) async {
      expect(request.url.path, '/api/promos');
      expect(request.url.queryParameters['status'], 'all');
      return _json({
        'items': [
          _promoJson(),
          _promoJson(id: 6, kind: 'points', title: 'Баллы', code: null),
          _promoJson(id: 7, title: 'Использован', used: true),
        ],
        'total': 3,
      }, 200);
    });

    expect(await provider.fetchPromos(), isTrue);

    expect(provider.promosWithStatusToday(PromoStatus.active).length, 2);
    expect(provider.promosWithStatusToday(PromoStatus.used).single.id, 7);
    expect(provider.promos.first.sourceText,
        'OZON: промокод OZON500 до 30 ноября');
    expect(
      reminders.lastSpecs(ReminderKind.promo).map((spec) => spec.entityId),
      [5, 6],
    );
    final cached =
        (await SharedPreferences.getInstance()).getString(_cacheKey);
    expect(cached, isNotNull);
    expect((json.decode(cached!) as List).length, 3);
  });

  test('create offline keeps a pending item and uploads it idempotently',
      () async {
    final reminders = FakeReminders();
    var online = false;
    final requests = <http.Request>[];
    final provider = _provider(reminders, (request) async {
      requests.add(request);
      if (!online) throw http.ClientException('no network');
      final path = request.url.path;
      if (request.method == 'POST' && path == '/api/promos') {
        final body = json.decode(request.body) as Map<String, dynamic>;
        return _json(
          _promoJson(id: 42, clientId: body['client_id'] as String),
          201,
        );
      }
      if (request.method == 'GET' && path == '/api/promos') {
        final clientId = json.decode(requests
            .firstWhere((r) => r.method == 'POST' && r.url.path == path)
            .body)['client_id'] as String;
        return _json({
          'items': [_promoJson(id: 42, clientId: clientId)],
        }, 200);
      }
      return http.Response('{"error": "unexpected"}', 500);
    });

    final saved = await provider.createPromo(PromoModel(
      kind: PromoKind.promo,
      title: 'Ozon: скидка 500 ₽',
      promoCode: 'OZON500',
      sourceText: 'OZON: промокод OZON500 до 30 ноября\n',
      expiresAt: DateTime(2026, 11, 30),
    ));
    expect(saved.isPending, isTrue);
    expect(saved.id, isNull);
    expect(saved.clientId, matches(RegExp(r'^[A-Za-z0-9_-]{8,64}$')));
    expect(provider.promos.single.isPending, isTrue);
    // No reminders until the server assigns an id.
    expect(reminders.lastSpecs(ReminderKind.promo), isEmpty);
    final cached = json.decode((await SharedPreferences.getInstance())
        .getString(_cacheKey)!) as List;
    expect((cached.single as Map)['pending'], isTrue);

    // A failed refresh keeps the pending item.
    expect(await provider.fetchPromos(), isFalse);
    expect(provider.promos.single.isPending, isTrue);

    online = true;
    expect(await provider.fetchPromos(), isTrue);
    final post = requests.lastWhere(
        (r) => r.method == 'POST' && r.url.path == '/api/promos');
    final body = json.decode(post.body) as Map<String, dynamic>;
    expect(body['client_id'], saved.clientId);
    expect(body['source_text'], 'OZON: промокод OZON500 до 30 ноября\n');
    expect(body['expires_at'], '2026-11-30');
    expect(body['reminder_days'], [3, 1]);
    expect(provider.promos, hasLength(1));
    expect(provider.promos.single.id, 42);
    expect(provider.promos.single.isPending, isFalse);
    expect(
      reminders.lastSpecs(ReminderKind.promo).map((spec) => spec.entityId),
      [42],
    );
  });

  test('validation errors are not saved offline', () async {
    final provider = _provider(
      FakeReminders(),
      (_) async => _json({'error': 'title must contain 1 to 200 characters'}, 400),
    );
    await expectLater(
      provider.createPromo(const PromoModel(kind: PromoKind.promo, title: ' ')),
      throwsA(predicate((error) => error.toString().contains('title must'))),
    );
    expect(provider.promos, isEmpty);
  });

  test('use, archive and delete go through the promos API', () async {
    final reminders = FakeReminders();
    final requests = <String>[];
    final provider = _provider(reminders, (request) async {
      requests.add('${request.method} ${request.url.path}');
      return switch (request.url.path) {
        '/api/promos/5/use' => _json(_promoJson(used: true), 200),
        '/api/promos/5/unuse' => _json(_promoJson(), 200),
        '/api/promos/5/archive' => _json(_promoJson(archived: true), 200),
        '/api/promos/5' => http.Response('', 204),
        _ => http.Response('{"error": "unexpected"}', 500),
      };
    });
    provider.promos = [PromoModel.fromJson(_promoJson())];

    final used = await provider.setPromoUsed(5, true);
    expect(used.status(today), PromoStatus.used);
    expect(reminders.lastSpecs(ReminderKind.promo), isEmpty);
    await provider.setPromoUsed(5, false);
    expect(reminders.lastSpecs(ReminderKind.promo).single.entityId, 5);
    final archived = await provider.setPromoArchived(5, true);
    expect(archived.status(today), PromoStatus.archived);
    await provider.deletePromo(archived);
    expect(provider.promos, isEmpty);
    expect(requests, [
      'POST /api/promos/5/use',
      'POST /api/promos/5/unuse',
      'POST /api/promos/5/archive',
      'DELETE /api/promos/5',
    ]);
  });

  test('parsing uses the server and falls back on the device offline',
      () async {
    var online = true;
    final provider = _provider(FakeReminders(), (request) async {
      if (!online) throw http.ClientException('no network');
      expect(request.url.path, '/api/promos/parse');
      return _json({
        'kind': 'points',
        'title': 'Пятёрочка: 300 баллов',
        'merchant': 'Пятёрочка',
        'promo_code': null,
        'discount': null,
        'points_amount': '300.00',
        'points_unit': 'баллов',
        'description': null,
        'starts_at': null,
        'expires_at': '2026-12-15',
        'expiry_phrase': 'сгорят 15 декабря',
        'expires_at_confidence': 'explicit',
      }, 200);
    });

    final remote = await provider.parsePromoText('Пятёрочка: 300 баллов…');
    expect(remote.kind, PromoKind.points);
    expect(remote.pointsAmount, 300);
    expect(remote.expiresAt, DateTime(2026, 12, 15));
    expect(remote.offline, isFalse);

    online = false;
    final local = await provider
        .parsePromoText('Промокод SALE10 действует до 10 ноября');
    expect(local.offline, isTrue);
    expect(local.promoCode, 'SALE10');
    // 10 November has passed on 11 November 2026: next year.
    expect(local.expiresAt, DateTime(2027, 11, 10));
  });

  test('logout keeps the cache only while offline items exist', () async {
    TestWidgetsFlutterBinding.ensureInitialized();
    FlutterSecureStorage.setMockInitialValues({});
    final provider = _provider(
      FakeReminders(),
      (_) async => throw http.ClientException('no network'),
    );
    await provider.createPromo(const PromoModel(
      kind: PromoKind.promo,
      title: 'Офлайн',
    ));
    await provider.logout();
    expect(provider.promos, isEmpty);
    expect(
      (await SharedPreferences.getInstance()).getString(_cacheKey),
      isNotNull,
    );
  });
}
