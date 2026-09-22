import 'package:flutter/material.dart';

import '../../models/cashback_category_model.dart';
import '../../providers/data_provider.dart';
import '../../utils/category_info.dart';
import '../cashback_category_detail_screen.dart';
import 'cashback_limits_label.dart';

class BenefitItemData {
  const BenefitItemData({required this.category, required this.cardLabel});

  final CashbackCategoryModel category;
  final String cardLabel;
}

class BenefitStatesView extends StatefulWidget {
  const BenefitStatesView({
    super.key,
    required this.phase,
    required this.hasUsableSnapshot,
    required this.items,
    required this.onRefresh,
    this.snapshotUpdatedAt,
  });

  final PrimaryDataPhase phase;
  final bool hasUsableSnapshot;
  final DateTime? snapshotUpdatedAt;
  final List<BenefitItemData> items;
  final Future<void> Function() onRefresh;

  @override
  State<BenefitStatesView> createState() => _BenefitStatesViewState();
}

class _BenefitStatesViewState extends State<BenefitStatesView> {
  final _searchController = TextEditingController();
  final _searchFocusNode = FocusNode();
  int? _selectedId;

  @override
  void initState() {
    super.initState();
    _searchController.addListener(_onQueryChanged);
  }

  @override
  void didUpdateWidget(covariant BenefitStatesView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_selectedId != null &&
        !widget.items.any((item) => item.category.id == _selectedId)) {
      _selectedId = null;
    }
  }

  @override
  void dispose() {
    _searchController
      ..removeListener(_onQueryChanged)
      ..dispose();
    _searchFocusNode.dispose();
    super.dispose();
  }

  void _onQueryChanged() {
    setState(() {
      if (_selectedId != null &&
          !_filteredItems.any((item) => item.category.id == _selectedId)) {
        _selectedId = null;
      }
    });
  }

  List<BenefitItemData> get _filteredItems {
    final query = _searchController.text.trim().toLowerCase();
    final result = widget.items.where((item) {
      if (query.isEmpty) return true;
      final category = item.category;
      return category.name.toLowerCase().contains(query) ||
          (category.description?.toLowerCase().contains(query) ?? false) ||
          item.cardLabel.toLowerCase().contains(query);
    }).toList();
    result.sort((a, b) =>
        b.category.cashbackPercent.compareTo(a.category.cashbackPercent));
    return result;
  }

  BenefitItemData? get _selectedItem {
    for (final item in widget.items) {
      if (item.category.id == _selectedId) return item;
    }
    return null;
  }

  void _clearQuery() {
    _searchController.clear();
    _searchFocusNode.requestFocus();
  }

  @override
  Widget build(BuildContext context) {
    final hasData = widget.hasUsableSnapshot;
    final initialLoading =
        widget.phase == PrimaryDataPhase.initialLoading && !hasData;
    final failedWithoutData =
        widget.phase == PrimaryDataPhase.failed && !hasData;

    return SafeArea(
      top: false,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _Header(isRefreshing: widget.phase == PrimaryDataPhase.refreshing),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
            child: TextField(
              key: const Key('benefit-search'),
              controller: _searchController,
              focusNode: _searchFocusNode,
              enabled: !initialLoading && !failedWithoutData,
              textInputAction: TextInputAction.search,
              decoration: InputDecoration(
                labelText: 'Категория или карта',
                hintText: 'Например, аптеки или •1234',
                prefixIcon: const Icon(Icons.search_outlined),
                suffixIcon: _searchController.text.isEmpty
                    ? null
                    : IconButton(
                        tooltip: 'Очистить запрос',
                        onPressed: _clearQuery,
                        icon: const Icon(Icons.close),
                      ),
                border: const OutlineInputBorder(),
              ),
            ),
          ),
          if (widget.phase == PrimaryDataPhase.refreshing)
            const LinearProgressIndicator(
              key: Key('benefit-refresh-progress'),
              semanticsLabel: 'Обновляем данные',
            ),
          if (widget.phase == PrimaryDataPhase.failed && hasData)
            _StaleBanner(
              updatedAt: widget.snapshotUpdatedAt,
              onRetry: widget.onRefresh,
            ),
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) {
                if (initialLoading) return const _LoadingState();
                if (failedWithoutData) {
                  return _ErrorState(onRetry: widget.onRefresh);
                }
                return _buildReadyContent(constraints.maxWidth);
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildReadyContent(double width) {
    final filtered = _filteredItems;
    if (filtered.isEmpty) {
      if (_searchController.text.trim().isNotEmpty) {
        return _EmptySearchState(onClear: _clearQuery);
      }
      return const _NoCategoriesState();
    }

    if (width >= 840) {
      return Row(
        key: const Key('benefit-expanded-layout'),
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            width: 380,
            child: _BenefitList(
              items: filtered,
              selectedId: _selectedId,
              onSelected: (item) =>
                  setState(() => _selectedId = item.category.id),
            ),
          ),
          const VerticalDivider(width: 1),
          Expanded(
            child: _selectedItem == null
                ? const _DetailPrompt()
                : _BenefitDetail(
                    item: _selectedItem!,
                    tiedItems: _tiedLeaders(_selectedItem!),
                  ),
          ),
        ],
      );
    }

    if (_selectedItem != null) {
      return _BenefitDetail(
        key: const Key('benefit-compact-detail'),
        item: _selectedItem!,
        tiedItems: _tiedLeaders(_selectedItem!),
        onBack: () => setState(() => _selectedId = null),
      );
    }

    return _BenefitList(
      key: const Key('benefit-compact-list'),
      items: filtered,
      columns: width >= 600 ? 2 : 1,
      onSelected: (item) => setState(() => _selectedId = item.category.id),
    );
  }

  List<BenefitItemData> _tiedLeaders(BenefitItemData selected) {
    final sameCategory = widget.items
        .where((item) =>
            item.category.name.toLowerCase() ==
            selected.category.name.toLowerCase())
        .toList();
    if (sameCategory.length < 2) return const [];
    final maxRate = sameCategory
        .map((item) => item.category.cashbackPercent)
        .reduce((a, b) => a > b ? a : b);
    final leaders = sameCategory
        .where((item) => item.category.cashbackPercent == maxRate)
        .toList();
    return leaders.length > 1 ? leaders : const [];
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.isRefreshing});
  final bool isRefreshing;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
        child: Semantics(
          header: true,
          label: isRefreshing ? 'Выгода, данные обновляются' : 'Выгода',
          child: Text(
            'Выгода',
            style: Theme.of(context)
                .textTheme
                .headlineMedium
                ?.copyWith(fontWeight: FontWeight.w700),
          ),
        ),
      );
}

class _LoadingState extends StatelessWidget {
  const _LoadingState();

  @override
  Widget build(BuildContext context) => Semantics(
        key: const Key('benefit-loading-state'),
        container: true,
        liveRegion: true,
        label: 'Загружаем карты и категории',
        child: ExcludeSemantics(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
            children: [
              const Row(
                children: [
                  SizedBox.square(
                    dimension: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                  SizedBox(width: 12),
                  Expanded(child: Text('Загружаем карты и категории')),
                ],
              ),
              const SizedBox(height: 16),
              for (var index = 0; index < 3; index++) ...[
                const _SkeletonCard(),
                const SizedBox(height: 8),
              ],
            ],
          ),
        ),
      );
}

class _SkeletonCard extends StatelessWidget {
  const _SkeletonCard();

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.surfaceContainerHighest;
    return Container(
      height: 88,
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(16),
      ),
    );
  }
}

class _StaleBanner extends StatelessWidget {
  const _StaleBanner({required this.updatedAt, required this.onRetry});
  final DateTime? updatedAt;
  final Future<void> Function() onRetry;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final updatedText = updatedAt == null
        ? 'Показаны сохранённые данные.'
        : 'Показана сохранённая копия от ${_formatSnapshot(updatedAt!)}.';
    return Semantics(
      container: true,
      liveRegion: true,
      child: Container(
        key: const Key('benefit-stale-banner'),
        margin: const EdgeInsets.fromLTRB(16, 0, 16, 12),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: colors.tertiaryContainer,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.warning_amber_outlined,
                color: colors.onTertiaryContainer),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Данные могли устареть',
                      style: Theme.of(context).textTheme.titleSmall),
                  Text(updatedText),
                ],
              ),
            ),
            const SizedBox(width: 8),
            TextButton(onPressed: onRetry, child: const Text('Повторить')),
          ],
        ),
      ),
    );
  }
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.onRetry});
  final Future<void> Function() onRetry;

  @override
  Widget build(BuildContext context) => Semantics(
        key: const Key('benefit-error-state'),
        container: true,
        liveRegion: true,
        label:
            'Не удалось загрузить данные. Проверьте соединение и повторите попытку.',
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ExcludeSemantics(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.cloud_off_outlined,
                      size: 48, color: Theme.of(context).colorScheme.error),
                  const SizedBox(height: 16),
                  Text('Не удалось загрузить данные',
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.titleLarge),
                  const SizedBox(height: 8),
                  const Text(
                    'Проверьте соединение и повторите попытку. '
                    'Сохранённой копии на этом устройстве нет.',
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 16),
                  FilledButton.icon(
                    onPressed: onRetry,
                    icon: const Icon(Icons.refresh_outlined),
                    label: const Text('Повторить'),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
}

class _EmptySearchState extends StatelessWidget {
  const _EmptySearchState({required this.onClear});
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) => Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.search_off_outlined, size: 48),
              const SizedBox(height: 16),
              Text('Ничего не нашли',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 8),
              const Text(
                'Проверьте название категории, банк или последние '
                'четыре цифры карты.',
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              OutlinedButton(
                onPressed: onClear,
                child: const Text('Очистить запрос'),
              ),
            ],
          ),
        ),
      );
}

class _NoCategoriesState extends StatelessWidget {
  const _NoCategoriesState();

  @override
  Widget build(BuildContext context) => const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text(
            'На выбранный период активных категорий пока нет.',
            textAlign: TextAlign.center,
          ),
        ),
      );
}

class _BenefitList extends StatelessWidget {
  const _BenefitList({
    super.key,
    required this.items,
    required this.onSelected,
    this.selectedId,
    this.columns = 1,
  });

  final List<BenefitItemData> items;
  final ValueChanged<BenefitItemData> onSelected;
  final int? selectedId;
  final int columns;

  @override
  Widget build(BuildContext context) {
    if (columns > 1) {
      final textScale = MediaQuery.textScalerOf(context).scale(1);
      return GridView.builder(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 2,
          crossAxisSpacing: 12,
          mainAxisSpacing: 12,
          mainAxisExtent: 116 * textScale.clamp(1, 2),
        ),
        itemCount: items.length,
        itemBuilder: (context, index) => _BenefitListCard(
          item: items[index],
          selected: items[index].category.id == selectedId,
          onTap: () => onSelected(items[index]),
        ),
      );
    }
    return ListView.separated(
      key: const PageStorageKey('benefit-master-list'),
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      itemCount: items.length,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (context, index) => _BenefitListCard(
        item: items[index],
        selected: items[index].category.id == selectedId,
        onTap: () => onSelected(items[index]),
      ),
    );
  }
}

class _BenefitListCard extends StatelessWidget {
  const _BenefitListCard({
    required this.item,
    required this.selected,
    required this.onTap,
  });

  final BenefitItemData item;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final category = item.category;
    final categoryColor = CategoryInfo.getCategoryColor(category.name);
    return Card(
      clipBehavior: Clip.antiAlias,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        side: selected
            ? BorderSide(color: Theme.of(context).colorScheme.primary, width: 2)
            : BorderSide.none,
        borderRadius: BorderRadius.circular(16),
      ),
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              ExcludeSemantics(
                child: Icon(CategoryInfo.getCategoryIcon(category.name),
                    color: categoryColor, size: 28),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(category.name,
                        style: Theme.of(context).textTheme.titleMedium),
                    const SizedBox(height: 4),
                    Text(item.cardLabel,
                        style: Theme.of(context).textTheme.bodySmall),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Text(
                '${category.isStackableBonus ? '+' : ''}'
                '${_formatPercent(category.cashbackPercent)}%',
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      color: categoryColor,
                      fontWeight: FontWeight.w800,
                    ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DetailPrompt extends StatelessWidget {
  const _DetailPrompt();

  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.touch_app_outlined,
                  size: 48, color: Theme.of(context).colorScheme.primary),
              const SizedBox(height: 16),
              Text('Выберите категорию',
                  style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 8),
              const Text(
                'Справа появятся карта, процент и известные условия.',
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      );
}

class _BenefitDetail extends StatelessWidget {
  const _BenefitDetail({
    super.key,
    required this.item,
    required this.tiedItems,
    this.onBack,
  });

  final BenefitItemData item;
  final List<BenefitItemData> tiedItems;
  final VoidCallback? onBack;

  @override
  Widget build(BuildContext context) {
    final category = item.category;
    final shownItems = tiedItems.isEmpty ? [item] : tiedItems;
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
      children: [
        if (onBack != null)
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: onBack,
              icon: const Icon(Icons.arrow_back),
              label: const Text('К результатам'),
            ),
          ),
        Semantics(
          header: true,
          child: Text(
            tiedItems.isEmpty ? category.name : 'Одинаковая выгода',
            style: Theme.of(context)
                .textTheme
                .headlineSmall
                ?.copyWith(fontWeight: FontWeight.w700),
          ),
        ),
        const SizedBox(height: 6),
        Text(
          tiedItems.isEmpty
              ? 'Доступный вариант по активным категориям'
              : 'Несколько карт дают одинаковый максимальный процент. '
                  'Проверьте условия каждой — победитель не назначен.',
        ),
        const SizedBox(height: 16),
        for (final current in shownItems) ...[
          _DetailCard(item: current),
          const SizedBox(height: 12),
        ],
        if (category.description?.trim().isNotEmpty ?? false) ...[
          const SizedBox(height: 8),
          Text('Условия', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 6),
          Text(category.description!),
        ],
        const SizedBox(height: 20),
        Material(
          color: Theme.of(context).colorScheme.surfaceContainerLow,
          borderRadius: BorderRadius.circular(12),
          child: const Padding(
            padding: EdgeInsets.all(12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ExcludeSemantics(child: Icon(Icons.info_outline)),
                SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Результат справочный и не меняет выбранный план.',
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _DetailCard extends StatelessWidget {
  const _DetailCard({required this.item});
  final BenefitItemData item;

  @override
  Widget build(BuildContext context) {
    final category = item.category;
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Text(item.cardLabel,
                      style: Theme.of(context).textTheme.titleMedium),
                ),
                const SizedBox(width: 12),
                Text(
                  '${_formatPercent(category.cashbackPercent)}%',
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                        color: Theme.of(context).colorScheme.primary,
                        fontWeight: FontWeight.w800,
                      ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute<void>(
                    builder: (_) => CashbackCategoryDetailScreen(
                      category: category,
                    ),
                  ),
                ),
                icon: const Icon(Icons.open_in_new_outlined),
                label: const Text('Открыть карточку категории'),
              ),
            ),
            CashbackLimitsLabel(
              maxCashbackAmount: category.maxCashbackAmount,
              minPurchaseAmount: category.minPurchaseAmount,
              fontSize: 13,
            ),
          ],
        ),
      ),
    );
  }
}

String _formatPercent(double value) =>
    value == value.roundToDouble() ? value.toInt().toString() : '$value';

String _formatSnapshot(DateTime value) {
  final local = value.toLocal();
  return '${local.day.toString().padLeft(2, '0')}.'
      '${local.month.toString().padLeft(2, '0')}.${local.year}, '
      '${local.hour.toString().padLeft(2, '0')}:'
      '${local.minute.toString().padLeft(2, '0')}';
}
