import '../models/partner_offer_model.dart';

/// Section of offers the bank did not place in any catalogue category.
const partnerOfferNoGroup = 'Без категории';

enum PartnerOfferDeadline {
  any,
  endingToday,
  endingWeek,
  endingMonth,
  endsBy,
  upcoming,
}

enum PartnerOfferSort { smart, deadline, rate, name, updated }

/// Everything the «Акции» screen narrows the catalogue by. Filters combine
/// with a logical AND; an empty [groups] set means every category.
class PartnerOfferQuery {
  const PartnerOfferQuery({
    this.text = '',
    this.preference,
    this.bankId,
    this.ownerId,
    this.groups = const {},
    this.minPercent,
    this.deadline = PartnerOfferDeadline.any,
    this.endsBy,
    this.sort = PartnerOfferSort.smart,
  });

  final String text;

  /// Only offers with this personal rating; null keeps every rating.
  final String? preference;
  final int? bankId;
  final int? ownerId;
  final Set<String> groups;
  final double? minPercent;
  final PartnerOfferDeadline deadline;

  /// Last allowed final day (calendar date) for [PartnerOfferDeadline.endsBy].
  final DateTime? endsBy;
  final PartnerOfferSort sort;

  PartnerOfferQuery withoutGroups() => PartnerOfferQuery(
        text: text,
        preference: preference,
        bankId: bankId,
        ownerId: ownerId,
        minPercent: minPercent,
        deadline: deadline,
        endsBy: endsBy,
        sort: sort,
      );
}

/// Categories of an offer, with [partnerOfferNoGroup] for an uncategorised one.
List<String> partnerOfferGroups(PartnerOffer offer) =>
    offer.groups.isEmpty ? const [partnerOfferNoGroup] : offer.groups;

/// Active offers matching [query], sorted as it asks.
List<PartnerOffer> filterPartnerOffers(
  Iterable<PartnerOffer> offers,
  PartnerOfferQuery query,
  DateTime now,
) {
  final text = query.text.trim().toLowerCase();
  final result = offers.where((offer) {
    if (!offer.isAvailable ||
        (offer.endsAt != null && !offer.endsAt!.isAfter(now))) {
      return false;
    }
    if (query.preference != null && offer.preference != query.preference) {
      return false;
    }
    if (text.isNotEmpty && !_matchesText(offer, text)) return false;
    if (query.bankId != null && offer.bankId != query.bankId) return false;
    if (query.ownerId != null && offer.cardUserId != query.ownerId) {
      return false;
    }
    if (query.groups.isNotEmpty &&
        !partnerOfferGroups(offer).any(query.groups.contains)) {
      return false;
    }
    if (query.minPercent != null &&
        (offer.percent == null || offer.percent! < query.minPercent!)) {
      return false;
    }
    return _matchesDeadline(offer, query, now);
  }).toList();
  result.sort((a, b) => comparePartnerOffers(a, b, query.sort));
  return result;
}

bool _matchesText(PartnerOffer offer, String text) =>
    offer.name.toLowerCase().contains(text) ||
    offer.description.toLowerCase().contains(text) ||
    offer.bankName.toLowerCase().contains(text) ||
    (offer.rateLabel?.toLowerCase().contains(text) ?? false) ||
    offer.groups.any((group) => group.toLowerCase().contains(text));

bool _matchesDeadline(
  PartnerOffer offer,
  PartnerOfferQuery query,
  DateTime now,
) {
  final upcoming = offer.startsAt?.isAfter(now) ?? false;
  if (query.deadline == PartnerOfferDeadline.upcoming) return upcoming;
  if (upcoming) return false;
  final lastDay = partnerOfferLastDay(offer, now);
  return switch (query.deadline) {
    PartnerOfferDeadline.any => true,
    PartnerOfferDeadline.endingToday => lastDay == 0,
    PartnerOfferDeadline.endingWeek =>
      lastDay != null && lastDay >= 0 && lastDay <= 7,
    PartnerOfferDeadline.endingMonth =>
      lastDay != null && lastDay >= 0 && lastDay <= 30,
    PartnerOfferDeadline.endsBy => query.endsBy == null ||
        (lastDay != null &&
            lastDay >= 0 &&
            lastDay <= _calendarDaysUntil(query.endsBy!, now)),
    PartnerOfferDeadline.upcoming => upcoming,
  };
}

int comparePartnerOffers(
  PartnerOffer a,
  PartnerOffer b,
  PartnerOfferSort sort,
) {
  switch (sort) {
    case PartnerOfferSort.smart:
      final preference = _preferenceRank(a.preference)
          .compareTo(_preferenceRank(b.preference));
      return preference == 0 ? comparePartnerDeadline(a, b) : preference;
    case PartnerOfferSort.deadline:
      return comparePartnerDeadline(a, b);
    case PartnerOfferSort.rate:
      final aRate = a.percent;
      final bRate = b.percent;
      if (aRate != bRate) {
        if (aRate == null) return 1;
        if (bRate == null) return -1;
        return bRate.compareTo(aRate);
      }
      return comparePartnerDeadline(a, b);
    case PartnerOfferSort.name:
      final name = a.name.toLowerCase().compareTo(b.name.toLowerCase());
      return name == 0 ? comparePartnerDeadline(a, b) : name;
    case PartnerOfferSort.updated:
      return b.collectedAt.compareTo(a.collectedAt);
  }
}

int _preferenceRank(String preference) => preference == 'interesting' ? 0 : 1;

int comparePartnerDeadline(PartnerOffer a, PartnerOffer b) {
  // DateTime's maximum epoch value stays representable by Dart's web runtime.
  const noDeadline = 8640000000000000;
  final aEnd = a.endsAt?.millisecondsSinceEpoch ?? noDeadline;
  final bEnd = b.endsAt?.millisecondsSinceEpoch ?? noDeadline;
  return aEnd.compareTo(bEnd);
}

/// Calendar days in Moscow from today to [value]'s day.
int? partnerOfferDaysUntil(DateTime? value, DateTime now) {
  if (value == null) return null;
  final local = value.toUtc().add(const Duration(hours: 3));
  final moscowNow = now.toUtc().add(const Duration(hours: 3));
  return DateTime.utc(local.year, local.month, local.day)
      .difference(DateTime.utc(moscowNow.year, moscowNow.month, moscowNow.day))
      .inDays;
}

/// Days from today to the offer's last valid day; the end itself is exclusive.
int? partnerOfferLastDay(PartnerOffer offer, DateTime now) =>
    offer.endsAt == null
        ? null
        : partnerOfferDaysUntil(
            offer.endsAt!.subtract(const Duration(microseconds: 1)), now);

/// Days from today (Moscow) to a picked calendar date.
int _calendarDaysUntil(DateTime date, DateTime now) {
  final moscowNow = now.toUtc().add(const Duration(hours: 3));
  return DateTime.utc(date.year, date.month, date.day)
      .difference(DateTime.utc(moscowNow.year, moscowNow.month, moscowNow.day))
      .inDays;
}

class PartnerOfferGroupCount {
  const PartnerOfferGroupCount(this.name, this.count, this.bestPercent);

  final String name;
  final int count;

  /// Highest comparable percent in the category, if any offer has one.
  final double? bestPercent;
}

/// Category breakdown: biggest categories first, uncategorised last.
List<PartnerOfferGroupCount> countPartnerOfferGroups(
  Iterable<PartnerOffer> offers,
) {
  final counts = <String, int>{};
  final best = <String, double>{};
  for (final offer in offers) {
    for (final group in partnerOfferGroups(offer)) {
      counts[group] = (counts[group] ?? 0) + 1;
      final percent = offer.percent;
      if (percent != null &&
          percent > (best[group] ?? double.negativeInfinity)) {
        best[group] = percent;
      }
    }
  }
  final result = [
    for (final entry in counts.entries)
      PartnerOfferGroupCount(entry.key, entry.value, best[entry.key]),
  ];
  result.sort((a, b) {
    if ((a.name == partnerOfferNoGroup) != (b.name == partnerOfferNoGroup)) {
      return a.name == partnerOfferNoGroup ? 1 : -1;
    }
    final count = b.count.compareTo(a.count);
    return count == 0 ? a.name.compareTo(b.name) : count;
  });
  return result;
}

class PartnerOfferSection {
  const PartnerOfferSection(this.name, this.offers);

  final String name;
  final List<PartnerOffer> offers;
}

/// Already sorted offers split by category. An offer in several categories
/// appears in each; with [only] set, other categories are left out.
List<PartnerOfferSection> sectionPartnerOffers(
  List<PartnerOffer> offers, {
  Set<String> only = const {},
}) {
  final byGroup = <String, List<PartnerOffer>>{};
  for (final offer in offers) {
    for (final group in partnerOfferGroups(offer)) {
      if (only.isNotEmpty && !only.contains(group)) continue;
      byGroup.putIfAbsent(group, () => []).add(offer);
    }
  }
  return [
    for (final group in countPartnerOfferGroups(offers))
      if (byGroup.containsKey(group.name))
        PartnerOfferSection(group.name, byGroup[group.name]!),
  ];
}
