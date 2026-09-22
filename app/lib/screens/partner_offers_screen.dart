import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/partner_offer_model.dart';
import '../providers/data_provider.dart';

enum _OfferSegment { all, interesting, postponed }

enum _OfferDeadline { any, endingSoon, available, upcoming }

enum _OfferSort { smart, deadline, updated }

class PartnerOffersScreen extends StatefulWidget {
  const PartnerOffersScreen({super.key});

  @override
  State<PartnerOffersScreen> createState() => _PartnerOffersScreenState();
}

class _PartnerOffersScreenState extends State<PartnerOffersScreen> {
  final _searchController = TextEditingController();
  final _listController = ScrollController();
  final Map<int, Future<PartnerOffer>> _details = {};
  _OfferSegment _segment = _OfferSegment.all;
  _OfferDeadline _deadline = _OfferDeadline.any;
  _OfferSort _sort = _OfferSort.smart;
  int? _bankId;
  int? _ownerId;
  int? _selectedOfferId;
  bool _showHidden = false;

  @override
  void dispose() {
    _searchController.dispose();
    _listController.dispose();
    super.dispose();
  }

  Future<void> _changeHiddenMode(DataProvider provider, bool hidden) async {
    setState(() {
      _showHidden = hidden;
      _bankId = null;
      _ownerId = null;
      _selectedOfferId = null;
      _deadline = _OfferDeadline.any;
      _segment = _OfferSegment.all;
    });
    await provider.fetchPartnerOffers(rating: hidden ? 'hidden' : null);
  }

  @override
  Widget build(BuildContext context) => Consumer<DataProvider>(
        builder: (context, provider, _) {
          final source = provider.partnerOffers
              .where((offer) => _showHidden
                  ? offer.preference == 'hidden'
                  : offer.preference != 'hidden')
              .toList();
          final banks = {
            for (final offer in source) offer.bankId: offer.bankName,
          };
          final ownerIds = source.map((offer) => offer.cardUserId).toSet();
          final visible = _filteredOffers(source);

          return LayoutBuilder(
            builder: (context, constraints) {
              final expanded = constraints.maxWidth >= 840;
              final selected = _selectedOffer(visible, expanded);
              final gutter = constraints.maxWidth >= 1200
                  ? 32.0
                  : constraints.maxWidth >= 600
                      ? 24.0
                      : 12.0;
              return Column(
                children: [
                  _Header(
                    searchController: _searchController,
                    showHidden: _showHidden,
                    updatedAt: _latestUpdate(source),
                    loading: provider.partnerOffersLoading,
                    gutter: gutter,
                    onSearchChanged: (_) => setState(() {}),
                    onClearSearch: () {
                      _searchController.clear();
                      setState(() {});
                    },
                    onRefresh: () => provider.fetchPartnerOffers(
                      rating: _showHidden ? 'hidden' : null,
                    ),
                    onShowHidden: () =>
                        _changeHiddenMode(provider, !_showHidden),
                  ),
                  if (!_showHidden)
                    _SegmentBar(
                      selected: _segment,
                      allCount: source.length,
                      interestingCount: source
                          .where((offer) => offer.preference == 'interesting')
                          .length,
                      postponedCount: source
                          .where((offer) => offer.preference == 'undecided')
                          .length,
                      gutter: gutter,
                      onSelected: (value) => setState(() => _segment = value),
                    ),
                  _FilterBar(
                    banks: banks,
                    allCount: source.length,
                    ownerIds: ownerIds,
                    users: provider.users
                        .map((user) => MapEntry(user.id, user.name))
                        .toList(),
                    selectedBankId: _bankId,
                    selectedOwnerId: _ownerId,
                    deadline: _deadline,
                    sort: _sort,
                    resultCount: visible.length,
                    gutter: gutter,
                    onBankChanged: (value) => setState(() => _bankId = value),
                    onOwnerChanged: (value) => setState(() => _ownerId = value),
                    onDeadlineChanged: (value) =>
                        setState(() => _deadline = value),
                    onSortChanged: (value) => setState(() => _sort = value),
                    onReset: _hasFilters
                        ? () => setState(() {
                              _bankId = null;
                              _ownerId = null;
                              _deadline = _OfferDeadline.any;
                            })
                        : null,
                  ),
                  if (provider.partnerOffersError != null)
                    _ErrorBanner(
                      message:
                          '${provider.partnerOffersError}. Показан сохранённый список.',
                      gutter: gutter,
                      onRetry: () => provider.fetchPartnerOffers(
                        rating: _showHidden ? 'hidden' : null,
                      ),
                    ),
                  if (provider.partnerOffersLoading)
                    const LinearProgressIndicator(minHeight: 2),
                  Expanded(
                    child: expanded
                        ? _ExpandedContent(
                            offers: visible,
                            selected: selected,
                            ownerName: (offer) => _ownerName(provider, offer),
                            listController: _listController,
                            onRefresh: () => provider.fetchPartnerOffers(
                              rating: _showHidden ? 'hidden' : null,
                            ),
                            onPreference: (offer, rating) =>
                                _setPreference(provider, offer, rating),
                            onSelected: (offer) => setState(
                              () => _selectedOfferId = offer.id,
                            ),
                            details: selected == null
                                ? null
                                : _detailsFor(provider, selected),
                            onRetryDetails: selected == null
                                ? null
                                : () => setState(() {
                                      _details[selected.id] =
                                          provider.fetchPartnerOfferDetails(
                                              selected.id);
                                    }),
                          )
                        : _CompactContent(
                            offers: visible,
                            emptyLabel: _emptyLabel,
                            ownerName: (offer) => _ownerName(provider, offer),
                            listController: _listController,
                            onRefresh: () => provider.fetchPartnerOffers(
                              rating: _showHidden ? 'hidden' : null,
                            ),
                            onPreference: (offer, rating) =>
                                _setPreference(provider, offer, rating),
                            onDetails: (offer) => _showDetails(provider, offer),
                            gutter: gutter,
                          ),
                  ),
                ],
              );
            },
          );
        },
      );

  bool get _hasFilters =>
      _bankId != null || _ownerId != null || _deadline != _OfferDeadline.any;

  String get _emptyLabel {
    if (_showHidden) return 'Чёрный список пуст.';
    if (_searchController.text.trim().isNotEmpty || _hasFilters) {
      return 'По вашему запросу ничего не найдено.';
    }
    return 'Нет доступных предложений.';
  }

  List<PartnerOffer> _filteredOffers(List<PartnerOffer> offers) {
    final query = _searchController.text.trim().toLowerCase();
    final now = DateTime.now();
    final result = offers.where((offer) {
      if (!_showHidden &&
          ((_segment == _OfferSegment.interesting &&
                  offer.preference != 'interesting') ||
              (_segment == _OfferSegment.postponed &&
                  offer.preference != 'undecided'))) {
        return false;
      }
      if (query.isNotEmpty &&
          !offer.name.toLowerCase().contains(query) &&
          !offer.description.toLowerCase().contains(query) &&
          !offer.bankName.toLowerCase().contains(query)) {
        return false;
      }
      if (_bankId != null && offer.bankId != _bankId) return false;
      if (_ownerId != null && offer.cardUserId != _ownerId) return false;
      switch (_deadline) {
        case _OfferDeadline.any:
          return true;
        case _OfferDeadline.endingSoon:
          final days = _daysUntil(offer.endsAt, now);
          return days != null && days >= 0 && days <= 7;
        case _OfferDeadline.available:
          return offer.isAvailable &&
              (offer.startsAt == null || !offer.startsAt!.isAfter(now)) &&
              (offer.endsAt == null || !offer.endsAt!.isBefore(now));
        case _OfferDeadline.upcoming:
          return offer.startsAt?.isAfter(now) ?? false;
      }
    }).toList();
    result.sort((a, b) {
      switch (_sort) {
        case _OfferSort.smart:
          final preference = _preferenceRank(a.preference)
              .compareTo(_preferenceRank(b.preference));
          return preference == 0 ? _compareDeadline(a, b) : preference;
        case _OfferSort.deadline:
          return _compareDeadline(a, b);
        case _OfferSort.updated:
          return b.collectedAt.compareTo(a.collectedAt);
      }
    });
    return result;
  }

  PartnerOffer? _selectedOffer(List<PartnerOffer> offers, bool expanded) {
    if (!expanded || offers.isEmpty) return null;
    for (final offer in offers) {
      if (offer.id == _selectedOfferId) return offer;
    }
    return offers.first;
  }

  Future<PartnerOffer> _detailsFor(DataProvider provider, PartnerOffer offer) =>
      _details.putIfAbsent(
        offer.id,
        () => provider.fetchPartnerOfferDetails(offer.id),
      );

  Future<void> _setPreference(
    DataProvider provider,
    PartnerOffer offer,
    String rating,
  ) async {
    final previous = offer.preference;
    try {
      await provider.updatePartnerOfferPreference(offer.id, rating);
      if (!mounted || rating != 'hidden') return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Предложение добавлено в чёрный список.'),
          action: SnackBarAction(
            label: 'Отменить',
            onPressed: () =>
                provider.updatePartnerOfferPreference(offer.id, previous),
          ),
        ),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Не удалось сохранить оценку: $error')),
      );
    }
  }

  void _showDetails(DataProvider provider, PartnerOffer offer) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: FractionallySizedBox(
          heightFactor: 0.92,
          child: FutureBuilder<PartnerOffer>(
            future: _detailsFor(provider, offer),
            builder: (context, snapshot) {
              if (snapshot.hasError) {
                return _DetailsError(
                  onRetry: () {
                    _details.remove(offer.id);
                    Navigator.pop(sheetContext);
                    _showDetails(provider, offer);
                  },
                );
              }
              if (!snapshot.hasData) {
                return const Center(child: CircularProgressIndicator());
              }
              return _OfferDetails(
                offer: snapshot.data!,
                ownerName: _ownerName(provider, snapshot.data!),
                onPreference: (rating) {
                  _setPreference(provider, snapshot.data!, rating);
                  Navigator.pop(sheetContext);
                },
              );
            },
          ),
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({
    required this.searchController,
    required this.showHidden,
    required this.updatedAt,
    required this.loading,
    required this.gutter,
    required this.onSearchChanged,
    required this.onClearSearch,
    required this.onRefresh,
    required this.onShowHidden,
  });

  final TextEditingController searchController;
  final bool showHidden;
  final DateTime? updatedAt;
  final bool loading;
  final double gutter;
  final ValueChanged<String> onSearchChanged;
  final VoidCallback onClearSearch;
  final Future<void> Function() onRefresh;
  final VoidCallback onShowHidden;

  @override
  Widget build(BuildContext context) => Padding(
        padding: EdgeInsets.fromLTRB(gutter, 16, gutter, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        showHidden ? 'Чёрный список' : 'Акции',
                        style: Theme.of(context)
                            .textTheme
                            .headlineMedium
                            ?.copyWith(fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        updatedAt == null
                            ? 'Персональные предложения банков'
                            : 'Обновлено ${_relativeUpdate(updatedAt!, DateTime.now())}',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
                IconButton.outlined(
                  tooltip: 'Обновить предложения',
                  onPressed: loading ? null : onRefresh,
                  icon: const Icon(Icons.refresh_outlined),
                ),
                const SizedBox(width: 8),
                PopupMenuButton<String>(
                  tooltip: 'Дополнительные действия',
                  onSelected: (_) => onShowHidden(),
                  itemBuilder: (context) => [
                    PopupMenuItem(
                      value: 'hidden',
                      child: Row(
                        children: [
                          Icon(showHidden
                              ? Icons.arrow_back_outlined
                              : Icons.block_outlined),
                          const SizedBox(width: 12),
                          Text(showHidden
                              ? 'Вернуться к акциям'
                              : 'Открыть чёрный список'),
                        ],
                      ),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 12),
            TextField(
              controller: searchController,
              onChanged: onSearchChanged,
              textInputAction: TextInputAction.search,
              decoration: InputDecoration(
                labelText: 'Поиск акций',
                hintText: 'Магазин или название акции',
                prefixIcon: const Icon(Icons.search_outlined),
                suffixIcon: searchController.text.isEmpty
                    ? null
                    : IconButton(
                        tooltip: 'Очистить поиск',
                        onPressed: onClearSearch,
                        icon: const Icon(Icons.close_outlined),
                      ),
                border: const OutlineInputBorder(),
              ),
            ),
          ],
        ),
      );
}

class _SegmentBar extends StatelessWidget {
  const _SegmentBar({
    required this.selected,
    required this.allCount,
    required this.interestingCount,
    required this.postponedCount,
    required this.gutter,
    required this.onSelected,
  });

  final _OfferSegment selected;
  final int allCount;
  final int interestingCount;
  final int postponedCount;
  final double gutter;
  final ValueChanged<_OfferSegment> onSelected;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
        builder: (context, constraints) {
          final compact = constraints.maxWidth < 500;
          return Padding(
            padding: EdgeInsets.fromLTRB(gutter, 0, gutter, 8),
            child: SizedBox(
              width: double.infinity,
              child: SegmentedButton<_OfferSegment>(
                segments: [
                  ButtonSegment(
                    value: _OfferSegment.all,
                    label:
                        Text(compact ? 'Все · $allCount' : 'Все · $allCount'),
                  ),
                  ButtonSegment(
                    value: _OfferSegment.interesting,
                    label: Text(compact
                        ? 'Интересные'
                        : 'Интересные · $interestingCount'),
                  ),
                  ButtonSegment(
                    value: _OfferSegment.postponed,
                    label: Text(compact
                        ? 'Отложенные'
                        : 'Отложенные · $postponedCount'),
                  ),
                ],
                selected: {selected},
                showSelectedIcon: false,
                onSelectionChanged: (value) => onSelected(value.first),
              ),
            ),
          );
        },
      );
}

class _FilterBar extends StatelessWidget {
  const _FilterBar({
    required this.banks,
    required this.allCount,
    required this.ownerIds,
    required this.users,
    required this.selectedBankId,
    required this.selectedOwnerId,
    required this.deadline,
    required this.sort,
    required this.resultCount,
    required this.gutter,
    required this.onBankChanged,
    required this.onOwnerChanged,
    required this.onDeadlineChanged,
    required this.onSortChanged,
    required this.onReset,
  });

  final Map<int, String> banks;
  final int allCount;
  final Set<int> ownerIds;
  final List<MapEntry<int, String>> users;
  final int? selectedBankId;
  final int? selectedOwnerId;
  final _OfferDeadline deadline;
  final _OfferSort sort;
  final int resultCount;
  final double gutter;
  final ValueChanged<int?> onBankChanged;
  final ValueChanged<int?> onOwnerChanged;
  final ValueChanged<_OfferDeadline> onDeadlineChanged;
  final ValueChanged<_OfferSort> onSortChanged;
  final VoidCallback? onReset;

  @override
  Widget build(BuildContext context) {
    final owners = users.where((user) => ownerIds.contains(user.key)).toList();
    var ownerName = 'Все владельцы';
    for (final owner in owners) {
      if (owner.key == selectedOwnerId) ownerName = owner.value;
    }
    return Container(
      width: double.infinity,
      color: Theme.of(context).colorScheme.surfaceContainerLowest,
      padding: EdgeInsets.fromLTRB(gutter, 8, gutter, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                ChoiceChip(
                  avatar: selectedBankId == null
                      ? const Icon(Icons.filter_list_outlined, size: 18)
                      : null,
                  label: Text('Все ($allCount)'),
                  selected: selectedBankId == null,
                  onSelected: (_) => onBankChanged(null),
                ),
                for (final bank in banks.entries) ...[
                  const SizedBox(width: 8),
                  ChoiceChip(
                    label: Text(bank.value),
                    selected: selectedBankId == bank.key,
                    onSelected: (selected) =>
                        onBankChanged(selected ? bank.key : null),
                  ),
                ],
                if (owners.length > 1) ...[
                  const SizedBox(width: 8),
                  _PopupFilter<int>(
                    tooltip: 'Фильтр по владельцу',
                    label: ownerName,
                    active: selectedOwnerId != null,
                    items: [
                      const PopupMenuItem<int>(
                        value: -1,
                        child: Text('Все владельцы'),
                      ),
                      for (final owner in owners)
                        PopupMenuItem<int>(
                          value: owner.key,
                          child: Text(owner.value),
                        ),
                    ],
                    onSelected: (value) =>
                        onOwnerChanged(value == -1 ? null : value),
                  ),
                ],
                const SizedBox(width: 8),
                _PopupFilter<_OfferDeadline>(
                  tooltip: 'Фильтр по сроку',
                  label: _deadlineFilterLabel(deadline),
                  active: deadline != _OfferDeadline.any,
                  items: const [
                    PopupMenuItem(
                      value: _OfferDeadline.any,
                      child: Text('Любой срок'),
                    ),
                    PopupMenuItem(
                      value: _OfferDeadline.endingSoon,
                      child: Text('Скоро завершатся'),
                    ),
                    PopupMenuItem(
                      value: _OfferDeadline.available,
                      child: Text('Доступны сейчас'),
                    ),
                    PopupMenuItem(
                      value: _OfferDeadline.upcoming,
                      child: Text('Скоро начнутся'),
                    ),
                  ],
                  onSelected: onDeadlineChanged,
                ),
                const SizedBox(width: 8),
                _PopupFilter<_OfferSort>(
                  tooltip: 'Сортировка предложений',
                  label: _sortLabel(sort),
                  active: sort != _OfferSort.smart,
                  icon: Icons.swap_vert_outlined,
                  items: const [
                    PopupMenuItem(
                      value: _OfferSort.smart,
                      child: Text('Сначала интересные'),
                    ),
                    PopupMenuItem(
                      value: _OfferSort.deadline,
                      child: Text('Сначала срочные'),
                    ),
                    PopupMenuItem(
                      value: _OfferSort.updated,
                      child: Text('Сначала обновлённые'),
                    ),
                  ],
                  onSelected: onSortChanged,
                ),
                if (onReset != null) ...[
                  const SizedBox(width: 8),
                  TextButton.icon(
                    onPressed: onReset,
                    icon: const Icon(Icons.close_outlined),
                    label: const Text('Сбросить'),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: Text(
                  '$resultCount ${_offerCountLabel(resultCount)}',
                  style: Theme.of(context).textTheme.labelLarge,
                ),
              ),
              const SizedBox(width: 12),
              Flexible(
                child: Text(
                  _sortLabel(sort),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.end,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _PopupFilter<T> extends StatelessWidget {
  const _PopupFilter({
    required this.tooltip,
    required this.label,
    required this.active,
    required this.items,
    required this.onSelected,
    this.icon = Icons.tune_outlined,
  });

  final String tooltip;
  final String label;
  final bool active;
  final List<PopupMenuEntry<T>> items;
  final ValueChanged<T> onSelected;
  final IconData icon;

  @override
  Widget build(BuildContext context) => PopupMenuButton<T>(
        tooltip: tooltip,
        onSelected: onSelected,
        itemBuilder: (_) => items,
        child: Chip(
          avatar: Icon(icon, size: 18),
          label: Text(label),
          backgroundColor:
              active ? Theme.of(context).colorScheme.secondaryContainer : null,
        ),
      );
}

class _ErrorBanner extends StatelessWidget {
  const _ErrorBanner({
    required this.message,
    required this.gutter,
    required this.onRetry,
  });

  final String message;
  final double gutter;
  final Future<void> Function() onRetry;

  @override
  Widget build(BuildContext context) => Padding(
        padding: EdgeInsets.fromLTRB(gutter, 4, gutter, 8),
        child: Material(
          color: Theme.of(context).colorScheme.errorContainer,
          borderRadius: BorderRadius.circular(12),
          child: ListTile(
            leading: const Icon(Icons.cloud_off_outlined),
            title: Text(message),
            trailing: TextButton(
              onPressed: onRetry,
              child: const Text('Повторить'),
            ),
          ),
        ),
      );
}

class _CompactContent extends StatelessWidget {
  const _CompactContent({
    required this.offers,
    required this.emptyLabel,
    required this.ownerName,
    required this.listController,
    required this.onRefresh,
    required this.onPreference,
    required this.onDetails,
    required this.gutter,
  });

  final List<PartnerOffer> offers;
  final String emptyLabel;
  final String Function(PartnerOffer) ownerName;
  final ScrollController listController;
  final Future<void> Function() onRefresh;
  final void Function(PartnerOffer, String) onPreference;
  final ValueChanged<PartnerOffer> onDetails;
  final double gutter;

  @override
  Widget build(BuildContext context) => RefreshIndicator(
        onRefresh: onRefresh,
        child: offers.isEmpty
            ? ListView(
                controller: listController,
                children: [
                  SizedBox(
                    height: MediaQuery.sizeOf(context).height / 3,
                    child: Center(
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Text(emptyLabel, textAlign: TextAlign.center),
                      ),
                    ),
                  ),
                ],
              )
            : ListView.builder(
                key: const PageStorageKey('partner-offers-list'),
                controller: listController,
                padding: EdgeInsets.fromLTRB(gutter, 4, gutter, 24),
                itemCount: offers.length,
                itemBuilder: (context, index) => _OfferCard(
                  offer: offers[index],
                  ownerName: ownerName(offers[index]),
                  selected: false,
                  onPreference: (rating) => onPreference(offers[index], rating),
                  onDetails: () => onDetails(offers[index]),
                ),
              ),
      );
}

class _ExpandedContent extends StatelessWidget {
  const _ExpandedContent({
    required this.offers,
    required this.selected,
    required this.ownerName,
    required this.listController,
    required this.onRefresh,
    required this.onPreference,
    required this.onSelected,
    required this.details,
    required this.onRetryDetails,
  });

  final List<PartnerOffer> offers;
  final PartnerOffer? selected;
  final String Function(PartnerOffer) ownerName;
  final ScrollController listController;
  final Future<void> Function() onRefresh;
  final void Function(PartnerOffer, String) onPreference;
  final ValueChanged<PartnerOffer> onSelected;
  final Future<PartnerOffer>? details;
  final VoidCallback? onRetryDetails;

  @override
  Widget build(BuildContext context) => Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1400),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Flexible(
                flex: 9,
                child: RefreshIndicator(
                  onRefresh: onRefresh,
                  child: offers.isEmpty
                      ? ListView(
                          children: const [
                            SizedBox(
                              height: 240,
                              child: Center(
                                child: Text('Нет подходящих предложений.'),
                              ),
                            ),
                          ],
                        )
                      : ListView.builder(
                          key: const PageStorageKey(
                              'partner-offers-expanded-list'),
                          controller: listController,
                          padding: const EdgeInsets.fromLTRB(24, 8, 12, 24),
                          itemCount: offers.length,
                          itemBuilder: (context, index) => _OfferCard(
                            offer: offers[index],
                            ownerName: ownerName(offers[index]),
                            selected: offers[index].id == selected?.id,
                            onPreference: (rating) =>
                                onPreference(offers[index], rating),
                            onDetails: () => onSelected(offers[index]),
                          ),
                        ),
                ),
              ),
              Flexible(
                flex: 11,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(12, 8, 24, 24),
                  child: Material(
                    clipBehavior: Clip.antiAlias,
                    color: Theme.of(context).colorScheme.surface,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                      side: BorderSide(
                        color: Theme.of(context).colorScheme.outlineVariant,
                      ),
                    ),
                    child: selected == null || details == null
                        ? const Center(
                            child: Text('Выберите предложение слева.'))
                        : FutureBuilder<PartnerOffer>(
                            key: ValueKey(selected!.id),
                            future: details,
                            builder: (context, snapshot) {
                              if (snapshot.hasError) {
                                return _DetailsError(onRetry: onRetryDetails!);
                              }
                              if (!snapshot.hasData) {
                                return const Center(
                                    child: CircularProgressIndicator());
                              }
                              return _OfferDetails(
                                offer: snapshot.data!,
                                ownerName: ownerName(snapshot.data!),
                                onPreference: (rating) => onPreference(
                                  snapshot.data!,
                                  rating,
                                ),
                              );
                            },
                          ),
                  ),
                ),
              ),
            ],
          ),
        ),
      );
}

class _OfferCard extends StatelessWidget {
  const _OfferCard({
    required this.offer,
    required this.ownerName,
    required this.selected,
    required this.onPreference,
    required this.onDetails,
  });

  final PartnerOffer offer;
  final String ownerName;
  final bool selected;
  final ValueChanged<String> onPreference;
  final VoidCallback onDetails;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Semantics(
      selected: selected,
      button: true,
      label: '${offer.name}, ${offer.bankName}, '
          '${offer.rateLabel ?? 'ставка не указана'}',
      child: Card(
        clipBehavior: Clip.antiAlias,
        margin: const EdgeInsets.only(bottom: 10),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(
            color: selected ? colors.primary : colors.outlineVariant,
            width: selected ? 2 : 1,
          ),
        ),
        child: InkWell(
          onTap: onDetails,
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _OfferLogo(url: offer.iconUrl),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(
                                child: Text(
                                  offer.name,
                                  style: Theme.of(context)
                                      .textTheme
                                      .titleMedium
                                      ?.copyWith(fontWeight: FontWeight.w700),
                                ),
                              ),
                              if (selected)
                                Padding(
                                  padding: const EdgeInsets.only(left: 8),
                                  child: Text(
                                    'Открыто',
                                    style: Theme.of(context)
                                        .textTheme
                                        .labelMedium
                                        ?.copyWith(color: colors.primary),
                                  ),
                                ),
                            ],
                          ),
                          const SizedBox(height: 2),
                          Text(
                            '${offer.bankName} · $ownerName',
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ],
                      ),
                    ),
                    _OfferMenu(
                      preference: offer.preference,
                      onSelected: onPreference,
                      onDetails: onDetails,
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    _InfoBadge(
                      icon: Icons.percent_outlined,
                      text: offer.rateLabel ?? 'Ставка не указана',
                      color: colors.primaryContainer,
                    ),
                    for (final limit in offer.limits.take(2))
                      _InfoBadge(
                        icon: Icons.account_balance_wallet_outlined,
                        text: limit.originalText,
                        color: colors.secondaryContainer,
                      ),
                  ],
                ),
                const SizedBox(height: 10),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      Icons.schedule_outlined,
                      size: 18,
                      color: _isEndingSoon(offer, DateTime.now())
                          ? colors.error
                          : colors.onSurfaceVariant,
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        _deadlineText(offer, DateTime.now()),
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                          color: _isEndingSoon(offer, DateTime.now())
                              ? colors.error
                              : colors.onSurface,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    _PreferenceLabel(preference: offer.preference),
                  ],
                ),
                if (offer.description.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Text(
                    offer.description,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _PreferenceLabel extends StatelessWidget {
  const _PreferenceLabel({required this.preference});
  final String preference;

  @override
  Widget build(BuildContext context) {
    final interesting = preference == 'interesting';
    final hidden = preference == 'hidden';
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          hidden
              ? Icons.block_outlined
              : interesting
                  ? Icons.favorite_border_outlined
                  : Icons.bookmark_border_outlined,
          size: 18,
        ),
        const SizedBox(width: 4),
        Text(
          hidden
              ? 'Скрыто'
              : interesting
                  ? 'Интересно'
                  : 'Отложено',
          style: Theme.of(context).textTheme.labelMedium,
        ),
      ],
    );
  }
}

class _OfferMenu extends StatelessWidget {
  const _OfferMenu({
    required this.preference,
    required this.onSelected,
    required this.onDetails,
  });
  final String preference;
  final ValueChanged<String> onSelected;
  final VoidCallback onDetails;

  @override
  Widget build(BuildContext context) => PopupMenuButton<String>(
        tooltip: 'Действия с предложением',
        onSelected: (value) =>
            value == 'details' ? onDetails() : onSelected(value),
        itemBuilder: (context) => [
          const PopupMenuItem(value: 'interesting', child: Text('Интересно')),
          const PopupMenuItem(value: 'undecided', child: Text('Отложить')),
          PopupMenuItem(
            value: preference == 'hidden' ? 'undecided' : 'hidden',
            child: Text(
                preference == 'hidden' ? 'Восстановить' : 'В чёрный список'),
          ),
          const PopupMenuDivider(),
          const PopupMenuItem(value: 'details', child: Text('Подробнее')),
        ],
      );
}

class _OfferLogo extends StatelessWidget {
  const _OfferLogo({this.url});
  final String? url;

  @override
  Widget build(BuildContext context) {
    final fallback = ColoredBox(
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      child: const Center(child: Icon(Icons.storefront_outlined)),
    );
    return ExcludeSemantics(
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: SizedBox(
          width: 48,
          height: 48,
          child: url == null
              ? fallback
              : Image.network(
                  url!,
                  fit: BoxFit.contain,
                  errorBuilder: (_, __, ___) => fallback,
                ),
        ),
      ),
    );
  }
}

class _InfoBadge extends StatelessWidget {
  const _InfoBadge({
    required this.icon,
    required this.text,
    required this.color,
  });
  final IconData icon;
  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            ExcludeSemantics(child: Icon(icon, size: 16)),
            const SizedBox(width: 4),
            Flexible(child: Text(text)),
          ],
        ),
      );
}

class _OfferDetails extends StatelessWidget {
  const _OfferDetails({
    required this.offer,
    required this.ownerName,
    required this.onPreference,
  });
  final PartnerOffer offer;
  final String ownerName;
  final ValueChanged<String> onPreference;

  @override
  Widget build(BuildContext context) => SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 28),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _OfferLogo(url: offer.iconUrl),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(offer.name,
                          style: Theme.of(context).textTheme.headlineSmall),
                      const SizedBox(height: 2),
                      Text('${offer.bankName} · $ownerName'),
                    ],
                  ),
                ),
                if (offer.rateLabel != null)
                  Text(
                    offer.rateLabel!,
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          color: Theme.of(context).colorScheme.primary,
                          fontWeight: FontWeight.w700,
                        ),
                  ),
              ],
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                FilledButton.tonalIcon(
                  onPressed: () => onPreference('interesting'),
                  icon: const Icon(Icons.favorite_border_outlined),
                  label: const Text('Интересно'),
                ),
                OutlinedButton.icon(
                  onPressed: () => onPreference('undecided'),
                  icon: const Icon(Icons.bookmark_border_outlined),
                  label: const Text('Отложить'),
                ),
                OutlinedButton.icon(
                  onPressed: () => onPreference(
                      offer.preference == 'hidden' ? 'undecided' : 'hidden'),
                  icon: Icon(offer.preference == 'hidden'
                      ? Icons.restore_outlined
                      : Icons.block_outlined),
                  label: Text(offer.preference == 'hidden'
                      ? 'Восстановить'
                      : 'В чёрный список'),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _DetailFact(
                    label: 'Срок', value: _deadlineText(offer, DateTime.now())),
                _DetailFact(
                  label: 'Доступность',
                  value: offer.isAvailable
                      ? 'По данным банка доступно'
                      : 'Сейчас недоступно',
                ),
                if (offer.limits.isNotEmpty)
                  _DetailFact(
                      label: 'Лимит', value: offer.limits.first.originalText),
              ],
            ),
            if (offer.requirements.isNotEmpty) ...[
              const SizedBox(height: 20),
              _DetailsSection(
                title: 'Требования и ограничения',
                children: [
                  for (final requirement in offer.requirements)
                    Text('• $requirement'),
                ],
              ),
            ],
            if (offer.steps.isNotEmpty) ...[
              const SizedBox(height: 20),
              _DetailsSection(
                title: 'Как получить',
                children: [
                  for (var index = 0; index < offer.steps.length; index++)
                    Text('${index + 1}. ${offer.steps[index]}'),
                ],
              ),
            ],
            const SizedBox(height: 20),
            Material(
              color: Theme.of(context).colorScheme.tertiaryContainer,
              borderRadius: BorderRadius.circular(12),
              child: const Padding(
                padding: EdgeInsets.all(12),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.info_outline),
                    SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'CashFlow не подключает акцию автоматически. '
                        'Статус подключения в банковском приложении неизвестен.',
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 20),
            _DetailsSection(
              title: 'Полные условия',
              children: [
                SelectableText(offer.conditions.isEmpty
                    ? 'Подробные условия не получены.'
                    : offer.conditions),
              ],
            ),
            const SizedBox(height: 20),
            Text(
              'Данные получены ${_formatDateTime(offer.collectedAt.toLocal())}',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      );
}

class _DetailFact extends StatelessWidget {
  const _DetailFact({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Container(
        constraints: const BoxConstraints(minWidth: 180),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surfaceContainerLow,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: Theme.of(context).textTheme.labelMedium),
            const SizedBox(height: 4),
            Text(value, style: Theme.of(context).textTheme.titleSmall),
          ],
        ),
      );
}

class _DetailsSection extends StatelessWidget {
  const _DetailsSection({required this.title, required this.children});
  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: Theme.of(context)
                .textTheme
                .titleMedium
                ?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 8),
          ...children.map((child) => Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: child,
              )),
        ],
      );
}

class _DetailsError extends StatelessWidget {
  const _DetailsError({required this.onRetry});
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.cloud_off_outlined, size: 40),
              const SizedBox(height: 12),
              const Text('Не удалось загрузить полные условия.',
                  textAlign: TextAlign.center),
              const SizedBox(height: 12),
              FilledButton.icon(
                onPressed: onRetry,
                icon: const Icon(Icons.refresh_outlined),
                label: const Text('Повторить'),
              ),
            ],
          ),
        ),
      );
}

String _ownerName(DataProvider provider, PartnerOffer offer) {
  for (final user in provider.users) {
    if (user.id == offer.cardUserId) return user.name;
  }
  return 'профиль владельца';
}

DateTime? _latestUpdate(List<PartnerOffer> offers) {
  DateTime? latest;
  for (final offer in offers) {
    if (latest == null || offer.collectedAt.isAfter(latest)) {
      latest = offer.collectedAt;
    }
  }
  return latest?.toLocal();
}

String _relativeUpdate(DateTime date, DateTime now) {
  final localNow = now.toLocal();
  if (date.year == localNow.year &&
      date.month == localNow.month &&
      date.day == localNow.day) {
    return 'сегодня, ${date.hour.toString().padLeft(2, '0')}:'
        '${date.minute.toString().padLeft(2, '0')}';
  }
  return _formatDateTime(date);
}

String _deadlineText(PartnerOffer offer, DateTime now) {
  final start = offer.startsAt?.toLocal();
  if (start != null && start.isAfter(now)) {
    final days = _daysUntil(start, now) ?? 0;
    return days == 0
        ? 'Начнётся сегодня'
        : 'Начнётся через ${_daysLabel(days)}';
  }
  final end = offer.endsAt?.toLocal();
  if (end == null) {
    return offer.validityLabel == null
        ? 'Срок не указан в источнике'
        : 'Срок: ${offer.validityLabel}';
  }
  final days = _daysUntil(end, now)!;
  if (days < 0) return 'Завершено';
  if (days == 0) return 'Последний день · до ${_formatDate(end)}';
  return 'Осталось ${_daysLabel(days)} · до ${_formatDate(end)}';
}

bool _isEndingSoon(PartnerOffer offer, DateTime now) {
  final days = _daysUntil(offer.endsAt, now);
  return days != null && days >= 0 && days <= 3;
}

int? _daysUntil(DateTime? value, DateTime now) {
  if (value == null) return null;
  final local = value.toLocal();
  return DateTime(local.year, local.month, local.day)
      .difference(DateTime(now.year, now.month, now.day))
      .inDays;
}

int _preferenceRank(String preference) => preference == 'interesting' ? 0 : 1;

int _compareDeadline(PartnerOffer a, PartnerOffer b) {
  // DateTime's maximum epoch value stays representable by Dart's web runtime.
  const noDeadline = 8640000000000000;
  final aEnd = a.endsAt?.millisecondsSinceEpoch ?? noDeadline;
  final bEnd = b.endsAt?.millisecondsSinceEpoch ?? noDeadline;
  return aEnd.compareTo(bEnd);
}

String _deadlineFilterLabel(_OfferDeadline value) => switch (value) {
      _OfferDeadline.any => 'Любой срок',
      _OfferDeadline.endingSoon => 'Скоро завершатся',
      _OfferDeadline.available => 'Доступны сейчас',
      _OfferDeadline.upcoming => 'Скоро начнутся',
    };

String _sortLabel(_OfferSort value) => switch (value) {
      _OfferSort.smart => 'Сначала интересные',
      _OfferSort.deadline => 'Сначала срочные',
      _OfferSort.updated => 'Сначала обновлённые',
    };

String _offerCountLabel(int count) {
  final lastTwo = count % 100;
  final last = count % 10;
  if (lastTwo >= 11 && lastTwo <= 14) return 'предложений';
  if (last == 1) return 'предложение';
  if (last >= 2 && last <= 4) return 'предложения';
  return 'предложений';
}

String _daysLabel(int days) {
  final lastTwo = days % 100;
  final last = days % 10;
  if (lastTwo >= 11 && lastTwo <= 14) return '$days дней';
  if (last == 1) return '$days день';
  if (last >= 2 && last <= 4) return '$days дня';
  return '$days дней';
}

String _formatDate(DateTime date) => '${date.day.toString().padLeft(2, '0')}.'
    '${date.month.toString().padLeft(2, '0')}.${date.year}';

String _formatDateTime(DateTime date) => '${_formatDate(date)}, '
    '${date.hour.toString().padLeft(2, '0')}:'
    '${date.minute.toString().padLeft(2, '0')}';
