import '../models/cashback_category_model.dart';
import '../utils/cashback_needs.dart';

class MonthlyPlanGroup {
  const MonthlyPlanGroup(
      {required this.key, required this.title, required this.offers});

  final String key;

  final String title;
  final List<CashbackCategoryModel> offers;

  bool get isCovered => offers.any((offer) => offer.isSelected);
  int get selectedCount => offers.where((offer) => offer.isSelected).length;
  double get bestPercent => offers.fold<double>(
        0,
        (best, offer) =>
            offer.cashbackPercent > best ? offer.cashbackPercent : best,
      );
}

enum MonthlyPlanFilter { all, uncovered, duplicates }

/// Pure monthly projection: no provider, widgets or mutation of source offers.
class MonthlyPlanProjection {
  MonthlyPlanProjection({required this.categories, required this.catalog});
  final List<CashbackCategoryModel> categories;
  final CashbackNeedCatalog catalog;

  Set<String> get needKeys => {
        for (final category in categories) ...catalog.keysFor(category),
      };
  Set<String> get coveredNeedKeys => {
        for (final category in categories)
          if (category.isSelected) ...catalog.keysFor(category),
      };
  int get duplicateCount {
    final counts = <String, int>{};
    for (final category in categories.where((offer) => offer.isSelected)) {
      for (final key in catalog.keysFor(category)) {
        counts[key] = (counts[key] ?? 0) + 1;
      }
    }
    return counts.values.where((count) => count > 1).length;
  }

  List<MonthlyPlanGroup> groups(
      {MonthlyPlanFilter filter = MonthlyPlanFilter.all,
      String query = '',
      Set<int> rejectedCategoryIds = const {}}) {
    final grouped = <String, List<CashbackCategoryModel>>{};
    final titles = <String, String>{};
    for (final category in categories) {
      for (final need in catalog.resolve(category).needs) {
        titles[need.key] = need.title;
        grouped.putIfAbsent(need.key, () => []).add(category);
      }
    }

    final groups = grouped.entries.map((entry) {
      entry.value.sort((a, b) {
        if (a.isSelected != b.isSelected) return a.isSelected ? -1 : 1;
        final aRejected = rejectedCategoryIds.contains(a.id);
        final bRejected = rejectedCategoryIds.contains(b.id);
        if (aRejected != bRejected) return aRejected ? 1 : -1;
        return b.cashbackPercent.compareTo(a.cashbackPercent);
      });
      return MonthlyPlanGroup(
          key: entry.key, title: titles[entry.key]!, offers: entry.value);
    }).where((group) {
      if (filter == MonthlyPlanFilter.uncovered && group.isCovered) {
        return false;
      }
      if (filter == MonthlyPlanFilter.duplicates && group.selectedCount < 2) {
        return false;
      }
      if (query.isEmpty) return true;
      final normalizedQuery = query.toLowerCase();
      return group.title.toLowerCase().contains(normalizedQuery) ||
          catalog
              .aliases(group.title)
              .any((alias) => alias.toLowerCase().contains(normalizedQuery)) ||
          group.offers.any(
              (offer) => offer.name.toLowerCase().contains(normalizedQuery));
    }).toList();

    groups.sort((a, b) {
      final priorityComparison =
          catalog.priority(a.title).compareTo(catalog.priority(b.title));
      if (priorityComparison != 0) return priorityComparison;
      return a.title.compareTo(b.title);
    });
    return groups;
  }
}

int selectedStandardCount(
        Iterable<CashbackCategoryModel> categories, int cardId) =>
    categories
        .where((category) =>
            category.cardId == cardId &&
            category.isSelected &&
            category.isSelectable)
        .length;
