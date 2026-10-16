import 'package:cashflow/models/partner_offer_model.dart';
import 'package:cashflow/services/partner_offer_catalog.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  // 12:00 in Moscow on 16 October 2026.
  final now = DateTime.utc(2026, 10, 16, 9);

  PartnerOffer offer(
    int id, {
    String name = 'Магазин',
    List<String> groups = const [],
    double? rate,
    String? rateLabel,
    DateTime? endsAt,
    DateTime? startsAt,
    String preference = 'undecided',
  }) =>
      PartnerOffer(
        id: id,
        bankId: 1,
        cardUserId: 1,
        bankName: 'Банк',
        name: name,
        description: '',
        preference: preference,
        isAvailable: true,
        collectedAt: now,
        lastSeenAt: now,
        rateValue: rate,
        rateLabel: rateLabel,
        startsAt: startsAt,
        endsAt: endsAt,
        groups: groups,
      );

  // Exclusive end at Moscow midnight after the last valid day.
  DateTime endAfter(int lastDayOffset) =>
      DateTime.utc(2026, 10, 16 + lastDayOffset, 21);

  test('percent falls back to the rate label', () {
    expect(offer(1, rateLabel: 'Кэшбэк до 7,5 %').percent, 7.5);
    expect(offer(1, rate: 4, rateLabel: 'до 10%').percent, 4);
    expect(offer(1, rateLabel: '500 бонусов').percent, isNull);
  });

  test('filters by category, percent, text and category names', () {
    final offers = [
      offer(1, name: 'Пицца', groups: ['Еда'], rate: 10),
      offer(2, name: 'Кроссовки', groups: ['Одежда', 'Спорт'], rate: 5),
      offer(3, name: 'Кино', rateLabel: '300 бонусов'),
    ];
    List<int> ids(PartnerOfferQuery query) =>
        filterPartnerOffers(offers, query, now).map((o) => o.id).toList();

    expect(ids(const PartnerOfferQuery(groups: {'Спорт'})), [2]);
    expect(ids(const PartnerOfferQuery(groups: {partnerOfferNoGroup})), [3]);
    expect(ids(const PartnerOfferQuery(minPercent: 6)), [1]);
    expect(ids(const PartnerOfferQuery(text: 'одеж')), [2]);
  });

  test('deadline windows use the last valid Moscow day', () {
    final offers = [
      offer(1, endsAt: endAfter(0)),
      offer(2, endsAt: endAfter(5)),
      offer(3, endsAt: endAfter(20)),
      offer(4),
      offer(5, startsAt: now.add(const Duration(days: 2))),
    ];
    List<int> ids(PartnerOfferDeadline deadline, [DateTime? endsBy]) =>
        filterPartnerOffers(
          offers,
          PartnerOfferQuery(
            deadline: deadline,
            endsBy: endsBy,
            sort: PartnerOfferSort.deadline,
          ),
          now,
        ).map((o) => o.id).toList();

    expect(ids(PartnerOfferDeadline.any), [1, 2, 3, 4]);
    expect(ids(PartnerOfferDeadline.endingToday), [1]);
    expect(ids(PartnerOfferDeadline.endingWeek), [1, 2]);
    expect(ids(PartnerOfferDeadline.endingMonth), [1, 2, 3]);
    expect(ids(PartnerOfferDeadline.endsBy, DateTime(2026, 10, 21)), [1, 2]);
    expect(ids(PartnerOfferDeadline.endsBy, DateTime(2026, 10, 20)), [1]);
    expect(ids(PartnerOfferDeadline.upcoming), [5]);
  });

  test('sorts by rate, name and interest', () {
    final offers = [
      offer(1, name: 'Б', rate: 5),
      offer(2, name: 'а', rateLabel: 'бонусы', preference: 'interesting'),
      offer(3, name: 'В', rate: 15),
    ];
    List<int> ids(PartnerOfferSort sort) => filterPartnerOffers(
          offers,
          PartnerOfferQuery(sort: sort),
          now,
        ).map((o) => o.id).toList();

    expect(ids(PartnerOfferSort.rate), [3, 1, 2]);
    expect(ids(PartnerOfferSort.name), [2, 1, 3]);
    expect(ids(PartnerOfferSort.smart).first, 2);
  });

  test('breakdown counts every category and keeps uncategorised last', () {
    final offers = [
      offer(1, groups: ['Еда'], rate: 10),
      offer(2, groups: ['Еда', 'Онлайн'], rate: 15),
      offer(3),
      offer(4, groups: ['Онлайн']),
      offer(5, groups: ['Аптеки']),
      offer(6, groups: ['Аптеки']),
      offer(7, groups: ['Аптеки']),
    ];
    final counts = countPartnerOfferGroups(offers);
    expect(
      counts.map((item) => '${item.name}:${item.count}'),
      ['Аптеки:3', 'Еда:2', 'Онлайн:2', '$partnerOfferNoGroup:1'],
    );
    expect(counts[1].bestPercent, 15);

    final sections = sectionPartnerOffers(offers, only: {'Еда', 'Онлайн'});
    expect(sections.map((section) => section.name), ['Еда', 'Онлайн']);
    expect(sections.last.offers.map((o) => o.id), [2, 4]);
  });
}
