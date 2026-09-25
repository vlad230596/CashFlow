import 'package:flutter/material.dart';

import '../../models/cashback_category_model.dart';
import '../../providers/data_provider.dart';
import '../../utils/category_info.dart';
import '../../utils/identity_icons.dart';
import '../cashback_category_detail_screen.dart';
import 'cashback_limits_label.dart';

class BenefitItemData {
  const BenefitItemData({
    required this.category,
    required this.cardLabel,
    this.bankName,
    this.bankIconKey,
    this.userName,
    this.userIconKey,
    this.lastFourDigits,
  });

  final CashbackCategoryModel category;
  final String cardLabel;
  final String? bankName;
  final String? bankIconKey;
  final String? userName;
  final String? userIconKey;
  final String? lastFourDigits;
}

class BenefitMccSearchResult {
  const BenefitMccSearchResult({
    required this.code,
    required this.name,
    required this.description,
  });

  final String code;
  final String name;
  final String description;
}

class BenefitMerchantSearchResult {
  const BenefitMerchantSearchResult({
    required this.name,
    required this.description,
    required this.initials,
    this.highlighted = false,
    this.color = const Color(0xFF2467CC),
    this.purchaseResult,
  });

  final String name;
  final String description;
  final String initials;
  final bool highlighted;
  final Color color;
  final BenefitPurchaseResult? purchaseResult;
}

class BenefitPurchaseResult {
  const BenefitPurchaseResult({
    required this.title,
    required this.merchantName,
    required this.subtitle,
    required this.evidence,
    required this.best,
    required this.alternatives,
    required this.risk,
  });

  final String title;
  final String merchantName;
  final String subtitle;
  final List<String> evidence;
  final BenefitPurchaseOption best;
  final List<BenefitPurchaseOption> alternatives;
  final String risk;
}

class BenefitPurchaseOption {
  const BenefitPurchaseOption({
    required this.bankMark,
    required this.cardLabel,
    required this.cardSubtitle,
    required this.rate,
    required this.categoryName,
    required this.categorySubtitle,
    this.limitLabel,
    this.matchLabel,
    this.matchIsPositive = true,
    this.reason,
    this.chainLabel,
    this.bankColor = const Color(0xFF17396D),
  });

  final String bankMark;
  final String cardLabel;
  final String cardSubtitle;
  final String rate;
  final String categoryName;
  final String categorySubtitle;
  final String? limitLabel;
  final String? matchLabel;
  final bool matchIsPositive;
  final String? reason;
  final String? chainLabel;
  final Color bankColor;
}

class BenefitStatesView extends StatefulWidget {
  const BenefitStatesView({
    super.key,
    required this.phase,
    required this.hasUsableSnapshot,
    required this.items,
    required this.onRefresh,
    this.mccResults = const [],
    this.merchantResults = const [],
    this.snapshotUpdatedAt,
    this.onShellDestinationSelected,
    this.onInternalDetailChanged,
  });

  final PrimaryDataPhase phase;
  final bool hasUsableSnapshot;
  final DateTime? snapshotUpdatedAt;
  final List<BenefitItemData> items;
  final List<BenefitMccSearchResult> mccResults;
  final List<BenefitMerchantSearchResult> merchantResults;
  final Future<void> Function() onRefresh;
  final ValueChanged<int>? onShellDestinationSelected;
  final ValueChanged<bool>? onInternalDetailChanged;

  @override
  State<BenefitStatesView> createState() => _BenefitStatesViewState();
}

class _BenefitStatesViewState extends State<BenefitStatesView> {
  late final TextEditingController _searchController;
  final _searchFocusNode = FocusNode();
  int? _selectedId;
  BenefitPurchaseResult? _selectedPurchaseResult;
  String? _selectedMerchantName;
  bool _showAllCategories = false;

  @override
  void initState() {
    super.initState();
    _searchController = TextEditingController();
    _searchController.addListener(_onQueryChanged);
  }

  @override
  void didUpdateWidget(covariant BenefitStatesView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_selectedId != null &&
        !widget.items.any((item) => item.category.id == _selectedId)) {
      _selectedId = null;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) widget.onInternalDetailChanged?.call(false);
      });
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
      if (_selectedMerchantName != null &&
          _searchController.text != _selectedMerchantName) {
        _selectedMerchantName = null;
        _selectedPurchaseResult = null;
      }
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

  List<BenefitMccSearchResult> get _filteredMccResults {
    final query = _searchController.text.trim().toLowerCase();
    if (query.isEmpty) return const [];
    return widget.mccResults;
  }

  List<BenefitMerchantSearchResult> get _filteredMerchantResults {
    final query = _searchController.text.trim().toLowerCase();
    if (query.isEmpty) return const [];
    return widget.merchantResults;
  }

  BenefitItemData? get _selectedItem {
    for (final item in widget.items) {
      if (item.category.id == _selectedId) return item;
    }
    return null;
  }

  void _clearQuery() {
    _selectedMerchantName = null;
    _selectedPurchaseResult = null;
    _searchController.clear();
    _searchFocusNode.requestFocus();
  }

  void _selectMerchant(BenefitMerchantSearchResult merchant) {
    final result = merchant.purchaseResult;
    if (result == null) return;
    _selectedMerchantName = merchant.name;
    _selectedPurchaseResult = result;
    _searchController.value = TextEditingValue(
      text: merchant.name,
      selection: TextSelection.collapsed(offset: merchant.name.length),
    );
    _searchFocusNode.unfocus();
    if (MediaQuery.sizeOf(context).width < 840) {
      widget.onInternalDetailChanged?.call(true);
    }
  }

  void _selectItem(BenefitItemData item) {
    setState(() => _selectedId = item.category.id);
    if (MediaQuery.sizeOf(context).width < 840) {
      widget.onInternalDetailChanged?.call(true);
    }
  }

  bool get _hasInternalDetail =>
      _selectedId != null || _selectedPurchaseResult != null;

  void _closeInternalDetail() {
    setState(() {
      _selectedId = null;
      _selectedPurchaseResult = null;
      _selectedMerchantName = null;
    });
    widget.onInternalDetailChanged?.call(false);
  }

  @override
  Widget build(BuildContext context) {
    final hasData = widget.hasUsableSnapshot;
    final initialLoading =
        widget.phase == PrimaryDataPhase.initialLoading && !hasData;
    final failedWithoutData =
        widget.phase == PrimaryDataPhase.failed && !hasData;

    return PopScope(
      canPop: !_hasInternalDetail,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && _hasInternalDetail) _closeInternalDetail();
      },
      child: SafeArea(
        top: true,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _Header(isRefreshing: widget.phase == PrimaryDataPhase.refreshing),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
              child: TextField(
                key: const Key('benefit-search'),
                controller: _searchController,
                focusNode: _searchFocusNode,
                enabled: !initialLoading && !failedWithoutData,
                textInputAction: TextInputAction.search,
                decoration: InputDecoration(
                  hintText: 'Что хотите купить?',
                  helperText: _selectedPurchaseResult != null
                      ? 'Магазин · результат по текущему плану'
                      : _searchController.text.trim().isEmpty
                          ? 'Категория, MCC-код или конкретный магазин'
                          : 'Найдено в категориях, MCC и магазинах',
                  prefixIcon: const Icon(Icons.search_outlined),
                  suffixIcon: _searchController.text.isEmpty
                      ? null
                      : IconButton(
                          tooltip: 'Очистить запрос',
                          onPressed: _clearQuery,
                          icon: const Icon(Icons.close),
                        ),
                  border: const OutlineInputBorder(),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(
                      color: Theme.of(context).colorScheme.primary,
                      width: 2,
                    ),
                  ),
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
      ),
    );
  }

  Widget _buildReadyContent(double width) {
    final filtered = _filteredItems;
    final query = _searchController.text.trim();
    final filteredMcc = _filteredMccResults;
    final filteredMerchants = _filteredMerchantResults;
    if (filtered.isEmpty && filteredMcc.isEmpty && filteredMerchants.isEmpty) {
      if (query.isNotEmpty) {
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
              onSelected: _selectItem,
            ),
          ),
          const VerticalDivider(width: 1),
          Expanded(
            child: _selectedItem == null
                ? const _DetailPrompt()
                : _BenefitDetail(
                    item: _selectedItem!,
                    tiedItems: _tiedLeaders(_selectedItem!),
                    onShellDestinationSelected:
                        widget.onShellDestinationSelected,
                  ),
          ),
        ],
      );
    }

    if (_selectedPurchaseResult != null) {
      return _CompactPurchaseResult(
        key: const Key('benefit-compact-purchase-result'),
        result: _selectedPurchaseResult!,
      );
    }

    if (_selectedItem != null) {
      return _BenefitDetail(
        key: const Key('benefit-compact-detail'),
        item: _selectedItem!,
        tiedItems: _tiedLeaders(_selectedItem!),
        onShellDestinationSelected: widget.onShellDestinationSelected,
        onBack: _closeInternalDetail,
      );
    }

    final largeText = MediaQuery.textScalerOf(context).scale(1) >= 1.5;
    if (width < 600 && !largeText) {
      if (query.isNotEmpty) {
        return _CompactSearchResults(
          key: const Key('benefit-compact-search-results'),
          categories: filtered,
          mccResults: filteredMcc,
          merchantResults: filteredMerchants,
          onMerchantSelected: _selectMerchant,
          onCategorySelected: _selectItem,
        );
      }
      return _CompactBenefitOverview(
        key: const Key('benefit-compact-list'),
        items: filtered,
        merchantResults: widget.merchantResults,
        onMerchantSelected: _selectMerchant,
        onSelected: _selectItem,
        showAllCategories: _showAllCategories,
        onToggleShowAll: () => setState(
          () => _showAllCategories = !_showAllCategories,
        ),
      );
    }
    return _BenefitList(
      key: const Key('benefit-compact-list'),
      items: filtered,
      columns: width >= 600 ? 2 : 1,
      onSelected: _selectItem,
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

class _CompactPurchaseResult extends StatelessWidget {
  const _CompactPurchaseResult({super.key, required this.result});

  final BenefitPurchaseResult result;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return ListView(
      padding: const EdgeInsets.fromLTRB(13, 12, 13, 20),
      children: [
        Container(
          padding: const EdgeInsets.fromLTRB(11, 10, 11, 9),
          decoration: BoxDecoration(
            color: colors.surface,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                result.title,
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
              ),
              const SizedBox(height: 2),
              Text(
                result.subtitle,
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: colors.onSurfaceVariant,
                    ),
              ),
              if (result.evidence.isNotEmpty) ...[
                const SizedBox(height: 7),
                Wrap(
                  spacing: 5,
                  runSpacing: 5,
                  children: [
                    for (final evidence in result.evidence)
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 7,
                          vertical: 5,
                        ),
                        decoration: BoxDecoration(
                          color: colors.primaryContainer,
                          borderRadius: BorderRadius.circular(7),
                        ),
                        child: Text(
                          evidence,
                          style:
                              Theme.of(context).textTheme.labelSmall?.copyWith(
                                    color: colors.primary,
                                    fontSize: 9,
                                    fontWeight: FontWeight.w800,
                                  ),
                        ),
                      ),
                  ],
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 8),
        _BestPurchaseCard(
          merchantName: result.merchantName,
          option: result.best,
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: Text(
                'Другие варианты',
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
              ),
            ),
            Text(
              'Все карты',
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: colors.primary,
                    fontWeight: FontWeight.w800,
                  ),
            ),
          ],
        ),
        const SizedBox(height: 7),
        Container(
          decoration: BoxDecoration(
            color: colors.surface,
            border: Border.all(color: colors.outlineVariant),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            children: [
              for (var index = 0;
                  index < result.alternatives.length;
                  index++) ...[
                if (index > 0) Divider(height: 1, color: colors.outlineVariant),
                _AlternativePurchaseRow(option: result.alternatives[index]),
              ],
            ],
          ),
        ),
        const SizedBox(height: 9),
        Container(
          padding: const EdgeInsets.fromLTRB(10, 9, 10, 9),
          decoration: BoxDecoration(
            color: const Color(0xFFFFF3DF),
            borderRadius: BorderRadius.circular(8),
            border: const Border(
              left: BorderSide(color: Color(0xFFD77A00), width: 3),
            ),
          ),
          child: Text(
            result.risk,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: const Color(0xFF805319),
                  fontSize: 9,
                  height: 1.3,
                ),
          ),
        ),
      ],
    );
  }
}

class _BestPurchaseCard extends StatelessWidget {
  const _BestPurchaseCard({
    required this.merchantName,
    required this.option,
  });

  final String merchantName;
  final BenefitPurchaseOption option;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(13),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF12366E), Color(0xFF2874D5)],
          ),
          borderRadius: BorderRadius.circular(15),
          boxShadow: const [
            BoxShadow(
              color: Color(0x241B5BB4),
              blurRadius: 18,
              offset: Offset(0, 8),
            ),
          ],
        ),
        child: DefaultTextStyle.merge(
          style: const TextStyle(color: Colors.white),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'ЛУЧШИЙ ИЗВЕСТНЫЙ ВАРИАНТ',
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w800,
                  letterSpacing: .35,
                  color: Color(0xFFDCEAFF),
                ),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  _BankMark(option: option, size: 34),
                  const SizedBox(width: 9),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          option.cardLabel,
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        Text(
                          option.cardSubtitle,
                          style: const TextStyle(
                            fontSize: 10,
                            color: Color(0xFFDCEAFF),
                          ),
                        ),
                      ],
                    ),
                  ),
                  Text(
                    option.rate,
                    style: const TextStyle(
                      fontSize: 26,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 9),
              Container(
                padding: const EdgeInsets.all(9),
                decoration: BoxDecoration(
                  color: const Color(0x22FFFFFF),
                  borderRadius: BorderRadius.circular(9),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            option.categoryName,
                            style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          Text(
                            option.categorySubtitle,
                            style: const TextStyle(
                              fontSize: 9,
                              color: Color(0xFFDCEAFF),
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (option.limitLabel != null)
                      Text(
                        option.limitLabel!,
                        style: const TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 9),
              _PurchaseChain(
                merchantName: merchantName,
                mccLabel: _firstEvidenceCode(option.reason),
                categoryName: option.categoryName,
                bankLabel: option.chainLabel ?? option.bankMark,
              ),
              if (option.reason?.isNotEmpty ?? false) ...[
                const SizedBox(height: 9),
                Text(
                  option.reason!,
                  style: const TextStyle(
                    fontSize: 10,
                    height: 1.35,
                    color: Color(0xFFDCEAFF),
                  ),
                ),
              ],
            ],
          ),
        ),
      );
}

String _firstEvidenceCode(String? reason) {
  final match = RegExp(r'MCC\s+\d{4}').firstMatch(reason ?? '');
  return match?.group(0) ?? 'MCC';
}

class _PurchaseChain extends StatelessWidget {
  const _PurchaseChain({
    required this.merchantName,
    required this.mccLabel,
    required this.categoryName,
    required this.bankLabel,
  });

  final String merchantName;
  final String mccLabel;
  final String categoryName;
  final String bankLabel;

  @override
  Widget build(BuildContext context) => Row(
        children: [
          Expanded(child: _ChainPill(merchantName)),
          const _ChainArrow(),
          Expanded(child: _ChainPill(mccLabel)),
          const _ChainArrow(),
          Expanded(child: _ChainPill(categoryName)),
          const _ChainArrow(),
          Expanded(child: _ChainPill(bankLabel)),
        ],
      );
}

class _ChainPill extends StatelessWidget {
  const _ChainPill(this.label);
  final String label;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 5),
        decoration: BoxDecoration(
          color: const Color(0x19FFFFFF),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          textAlign: TextAlign.center,
          style: const TextStyle(
            color: Color(0xFFDBE9FF),
            fontSize: 8,
            fontWeight: FontWeight.w700,
          ),
        ),
      );
}

class _ChainArrow extends StatelessWidget {
  const _ChainArrow();

  @override
  Widget build(BuildContext context) => const Padding(
        padding: EdgeInsets.symmetric(horizontal: 3),
        child: Text('→', style: TextStyle(color: Color(0x99DBE9FF))),
      );
}

class _AlternativePurchaseRow extends StatelessWidget {
  const _AlternativePurchaseRow({required this.option});
  final BenefitPurchaseOption option;

  @override
  Widget build(BuildContext context) => ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 62),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          child: Row(
            children: [
              _BankMark(option: option, size: 32),
              const SizedBox(width: 9),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      option.cardLabel,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.labelLarge?.copyWith(
                            fontWeight: FontWeight.w800,
                          ),
                    ),
                    Text(
                      option.categoryName,
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                            color:
                                Theme.of(context).colorScheme.onSurfaceVariant,
                          ),
                    ),
                    if (option.matchLabel != null)
                      Text(
                        option.matchLabel!,
                        style: Theme.of(context).textTheme.labelSmall?.copyWith(
                              color: option.matchIsPositive
                                  ? const Color(0xFF168154)
                                  : const Color(0xFFB94343),
                              fontSize: 9,
                              fontWeight: FontWeight.w800,
                            ),
                      ),
                  ],
                ),
              ),
              Text(
                option.rate,
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      color: const Color(0xFFD77A00),
                      fontWeight: FontWeight.w900,
                    ),
              ),
            ],
          ),
        ),
      );
}

class _BankMark extends StatelessWidget {
  const _BankMark({required this.option, required this.size});
  final BenefitPurchaseOption option;
  final double size;

  @override
  Widget build(BuildContext context) => ExcludeSemantics(
        child: Container(
          width: size,
          height: size,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: option.bankColor,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(
            option.bankMark,
            style: TextStyle(
              color: Colors.white,
              fontSize: option.bankMark.length > 2 ? 9 : 11,
              fontWeight: FontWeight.w900,
            ),
          ),
        ),
      );
}

class _CompactSearchResults extends StatelessWidget {
  const _CompactSearchResults({
    super.key,
    required this.categories,
    required this.mccResults,
    required this.merchantResults,
    required this.onCategorySelected,
    required this.onMerchantSelected,
  });

  final List<BenefitItemData> categories;
  final List<BenefitMccSearchResult> mccResults;
  final List<BenefitMerchantSearchResult> merchantResults;
  final ValueChanged<BenefitItemData> onCategorySelected;
  final ValueChanged<BenefitMerchantSearchResult> onMerchantSelected;

  @override
  Widget build(BuildContext context) => ListView(
        padding: const EdgeInsets.fromLTRB(13, 0, 13, 20),
        children: [
          if (categories.isNotEmpty) ...[
            const _SearchGroupHeader(
              title: 'КАТЕГОРИИ',
              hint: 'САМЫЙ ПРЯМОЙ ЗАПРОС',
            ),
            for (final item in categories)
              _SearchResultRow(
                badge: 'КАТ',
                badgeColor: const Color(0xFF279164),
                title: item.category.name,
                subtitle: 'Сравнить все выбранные категории с таким названием',
                kind: 'Категория',
                onTap: () => onCategorySelected(item),
              ),
          ],
          if (mccResults.isNotEmpty) ...[
            const _SearchGroupHeader(
              title: 'MCC-КОДЫ',
              hint: 'ТОЧНЕЕ КАТЕГОРИИ',
            ),
            for (final item in mccResults)
              _SearchResultRow(
                badge: item.code,
                badgeColor: const Color(0xFF687D97),
                title: item.name,
                subtitle: item.description,
                kind: 'MCC',
              ),
          ],
          if (merchantResults.isNotEmpty) ...[
            const _SearchGroupHeader(
              title: 'МАГАЗИНЫ',
              hint: 'ПОЛНАЯ ЦЕПОЧКА',
            ),
            for (final item in merchantResults)
              _SearchResultRow(
                badge: item.initials,
                badgeColor: item.color,
                title: item.name,
                subtitle: item.description,
                kind: 'Магазин',
                highlighted: item.highlighted,
                onTap: item.purchaseResult == null
                    ? null
                    : () => onMerchantSelected(item),
              ),
          ],
          if (mccResults.isNotEmpty || merchantResults.isNotEmpty) ...[
            const SizedBox(height: 2),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: const Color(0xFFEDF3FB),
                borderRadius: BorderRadius.circular(9),
              ),
              child: Text(
                'Чем конкретнее исходные данные, тем точнее сравнение. '
                'Для магазина результат учитывает историю MCC и показывает '
                'неопределённость.',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: const Color(0xFF526780),
                      fontSize: 10,
                      height: 1.3,
                    ),
              ),
            ),
          ],
        ],
      );
}

class _SearchGroupHeader extends StatelessWidget {
  const _SearchGroupHeader({required this.title, required this.hint});

  final String title;
  final String hint;

  @override
  Widget build(BuildContext context) => SizedBox(
        height: 31,
        child: Row(
          children: [
            Expanded(
              child: Text(
                title,
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: const Color(0xFF5E6E84),
                      fontWeight: FontWeight.w800,
                      letterSpacing: .35,
                    ),
              ),
            ),
            Text(
              hint,
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: const Color(0xFF5E6E84),
                    fontSize: 9,
                    fontWeight: FontWeight.w800,
                    letterSpacing: .2,
                  ),
            ),
          ],
        ),
      );
}

class _SearchResultRow extends StatelessWidget {
  const _SearchResultRow({
    required this.badge,
    required this.badgeColor,
    required this.title,
    required this.subtitle,
    required this.kind,
    this.highlighted = false,
    this.onTap,
  });

  final String badge;
  final Color badgeColor;
  final String title;
  final String subtitle;
  final String kind;
  final bool highlighted;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Card(
      margin: const EdgeInsets.only(bottom: 6),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: highlighted ? colors.primary : colors.outlineVariant,
          width: highlighted ? 2 : 1,
        ),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 56),
          child: Padding(
            padding: EdgeInsets.fromLTRB(
              highlighted ? 8 : 9,
              8,
              highlighted ? 8 : 9,
              8,
            ),
            child: Row(
              children: [
                ExcludeSemantics(
                  child: Container(
                    width: 36,
                    height: 36,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: badgeColor,
                      borderRadius: BorderRadius.circular(9),
                    ),
                    child: Text(
                      badge,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 10,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 9),
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.labelLarge?.copyWith(
                              fontSize: 12,
                              fontWeight: FontWeight.w800,
                            ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        subtitle,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.labelSmall?.copyWith(
                              color: colors.onSurfaceVariant,
                              fontSize: 9,
                              height: 1.15,
                            ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 7),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 7, vertical: 5),
                  decoration: BoxDecoration(
                    color: colors.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(7),
                  ),
                  child: Text(
                    kind,
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          color: const Color(0xFF607087),
                          fontSize: 9,
                          fontWeight: FontWeight.w800,
                        ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.isRefreshing});
  final bool isRefreshing;

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final largeText = MediaQuery.textScalerOf(context).scale(1) > 1.5;
    const months = [
      'Январь',
      'Февраль',
      'Март',
      'Апрель',
      'Май',
      'Июнь',
      'Июль',
      'Август',
      'Сентябрь',
      'Октябрь',
      'Ноябрь',
      'Декабрь',
    ];
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
      child: Flex(
        direction: largeText ? Axis.vertical : Axis.horizontal,
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment:
            largeText ? CrossAxisAlignment.start : CrossAxisAlignment.center,
        children: [
          Flexible(
            fit: FlexFit.loose,
            child: Semantics(
              header: true,
              label: isRefreshing ? 'Выгода, данные обновляются' : 'Выгода',
              child: ExcludeSemantics(
                child: Text(
                  'Выгода',
                  style: Theme.of(context).textTheme.headlineMedium,
                ),
              ),
            ),
          ),
          SizedBox(width: largeText ? 0 : 12, height: largeText ? 6 : 0),
          if (!largeText) const Spacer(),
          DecoratedBox(
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
              child: Text(
                '${months[now.month - 1]} ${now.year}',
                style: Theme.of(context).textTheme.labelMedium,
              ),
            ),
          ),
        ],
      ),
    );
  }
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

class _CompactBenefitOverview extends StatelessWidget {
  const _CompactBenefitOverview({
    super.key,
    required this.items,
    required this.merchantResults,
    required this.onMerchantSelected,
    required this.onSelected,
    required this.showAllCategories,
    required this.onToggleShowAll,
  });

  final List<BenefitItemData> items;
  final List<BenefitMerchantSearchResult> merchantResults;
  final ValueChanged<BenefitMerchantSearchResult> onMerchantSelected;
  final ValueChanged<BenefitItemData> onSelected;
  final bool showAllCategories;
  final VoidCallback onToggleShowAll;

  @override
  Widget build(BuildContext context) {
    final grouped = <String, List<BenefitItemData>>{};
    for (final item in items) {
      grouped.putIfAbsent(item.category.name, () => []).add(item);
    }
    final groups = grouped.values.toList()
      ..sort((a, b) => b
          .map((item) => item.category.cashbackPercent)
          .reduce((left, right) => left > right ? left : right)
          .compareTo(a
              .map((item) => item.category.cashbackPercent)
              .reduce((left, right) => left > right ? left : right)));

    final recentMerchants = merchantResults.take(2).toList();
    final visibleGroupCount =
        showAllCategories || groups.length <= 4 ? groups.length : 4;
    return CustomScrollView(
      key: const PageStorageKey('benefit-compact-overview-scroll'),
      slivers: [
        SliverToBoxAdapter(
          child: _OverviewSectionHeader(
            title: 'Категории',
            action: groups.length > 4
                ? showAllCategories
                    ? 'Свернуть'
                    : 'Показать все ${groups.length}'
                : null,
            onAction: groups.length > 4 ? onToggleShowAll : null,
          ),
        ),
        SliverPadding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          sliver: SliverGrid(
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              crossAxisSpacing: 8,
              mainAxisSpacing: 8,
              mainAxisExtent: 88,
            ),
            delegate: SliverChildBuilderDelegate(
              (context, index) => _CompactCategoryCard(
                items: groups[index],
                onTap: () => onSelected(groups[index].first),
              ),
              childCount: visibleGroupCount,
            ),
          ),
        ),
        if (recentMerchants.isNotEmpty) ...[
          const SliverToBoxAdapter(child: SizedBox(height: 8)),
          const SliverToBoxAdapter(
            child: _OverviewSectionHeader(
              title: 'Недавние магазины',
              action: 'История',
            ),
          ),
          SliverPadding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            sliver: SliverList.separated(
              itemCount: recentMerchants.length,
              separatorBuilder: (_, __) => const SizedBox(height: 6),
              itemBuilder: (context, index) {
                final merchant = recentMerchants[index];
                return _RecentMerchantRow(
                  merchant: merchant,
                  onTap: merchant.purchaseResult == null
                      ? null
                      : () => onMerchantSelected(merchant),
                );
              },
            ),
          ),
        ],
        const SliverToBoxAdapter(child: SizedBox(height: 24)),
      ],
    );
  }
}

class _OverviewSectionHeader extends StatelessWidget {
  const _OverviewSectionHeader({
    required this.title,
    this.action,
    this.onAction,
  });

  final String title;
  final String? action;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(17, 2, 17, 8),
        child: Row(
          children: [
            Expanded(
              child: Text(
                title,
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
              ),
            ),
            if (action != null)
              TextButton(
                key: const Key('benefit-toggle-all-categories'),
                onPressed: onAction,
                style: TextButton.styleFrom(
                  minimumSize: const Size(48, 48),
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                ),
                child: Text(action!),
              ),
          ],
        ),
      );
}

class _RecentMerchantRow extends StatelessWidget {
  const _RecentMerchantRow({required this.merchant, this.onTap});

  final BenefitMerchantSearchResult merchant;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Card(
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: colors.outlineVariant),
      ),
      child: InkWell(
        onTap: onTap,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 56),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            child: Row(
              children: [
                ExcludeSemantics(
                  child: Container(
                    width: 36,
                    height: 36,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: merchant.color,
                      borderRadius: BorderRadius.circular(9),
                    ),
                    child: Text(
                      merchant.initials,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 10,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 9),
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        merchant.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.labelLarge?.copyWith(
                              fontWeight: FontWeight.w800,
                            ),
                      ),
                      const SizedBox(height: 1),
                      Text(
                        merchant.description,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.labelSmall?.copyWith(
                              color: colors.onSurfaceVariant,
                            ),
                      ),
                    ],
                  ),
                ),
                if (onTap != null) ...[
                  const SizedBox(width: 8),
                  Icon(
                    Icons.chevron_right_rounded,
                    color: colors.primary,
                    size: 22,
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

class _CompactCategoryCard extends StatelessWidget {
  const _CompactCategoryCard({required this.items, required this.onTap});

  final List<BenefitItemData> items;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final category = items.first.category;
    final color = CategoryInfo.getCategoryColor(category.name);
    final sorted = [...items]..sort((a, b) =>
        b.category.cashbackPercent.compareTo(a.category.cashbackPercent));
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 30,
                    height: 30,
                    decoration: BoxDecoration(
                      color: color,
                      borderRadius: BorderRadius.circular(9),
                    ),
                    child: Icon(
                      CategoryInfo.getCategoryIcon(category.name),
                      color: Colors.white,
                      size: 18,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          category.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style:
                              Theme.of(context).textTheme.labelLarge?.copyWith(
                                    fontWeight: FontWeight.w800,
                                  ),
                        ),
                        Text(
                          '${items.length} ${_cardsWord(items.length)}',
                          style:
                              Theme.of(context).textTheme.labelSmall?.copyWith(
                                    color: Theme.of(context)
                                        .colorScheme
                                        .onSurfaceVariant,
                                  ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const Spacer(),
              Column(
                children: [
                  for (final item in sorted.take(2)) ...[
                    _CompactCardIdentity(
                      item: item,
                      accentColor: color,
                      showLastFourDigits: items.length == 1,
                    ),
                    if (item != sorted.take(2).last) const SizedBox(height: 3),
                  ],
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CompactCardIdentity extends StatelessWidget {
  const _CompactCardIdentity({
    required this.item,
    required this.accentColor,
    required this.showLastFourDigits,
  });

  final BenefitItemData item;
  final Color accentColor;
  final bool showLastFourDigits;

  @override
  Widget build(BuildContext context) {
    final bankName = item.bankName ?? _bankNameFromCardLabel(item.cardLabel);
    final userName = item.userName ?? 'Владелец';
    final digits = item.lastFourDigits;
    final suffix =
        showLastFourDigits && digits?.isNotEmpty == true ? ' · •$digits' : '';
    return Semantics(
      label: '$bankName, $userName$suffix, '
          '${_formatPercent(item.category.cashbackPercent)} процентов',
      child: ExcludeSemantics(
        child: Container(
          height: 24,
          padding: const EdgeInsets.symmetric(horizontal: 4),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(7),
          ),
          child: Row(
            children: [
              BankIconBadge(
                iconKey: item.bankIconKey,
                bankName: bankName,
                size: 18,
              ),
              const SizedBox(width: 3),
              UserIconBadge(
                iconKey: item.userIconKey,
                userName: userName,
                size: 18,
              ),
              const SizedBox(width: 4),
              Expanded(
                child: Text(
                  '$bankName · $userName$suffix',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        fontSize: 9,
                        fontWeight: FontWeight.w700,
                      ),
                ),
              ),
              const SizedBox(width: 3),
              Text(
                '${_formatPercent(item.category.cashbackPercent)}%',
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: accentColor,
                      fontWeight: FontWeight.w900,
                    ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

String _cardsWord(int count) {
  final mod100 = count % 100;
  final mod10 = count % 10;
  if (mod100 >= 11 && mod100 <= 14) return 'карт';
  if (mod10 == 1) return 'карта';
  if (mod10 >= 2 && mod10 <= 4) return 'карты';
  return 'карт';
}

String _bankNameFromCardLabel(String label) {
  final digits = RegExp(r'[•·]?\s*\d{4}\s*$');
  return label.replaceFirst(digits, '').trim();
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
            : BorderSide(color: Theme.of(context).colorScheme.outlineVariant),
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
                    Row(
                      children: [
                        BankIconBadge(
                          iconKey: item.bankIconKey,
                          bankName: item.bankName,
                          size: 22,
                        ),
                        const SizedBox(width: 4),
                        UserIconBadge(
                          iconKey: item.userIconKey,
                          userName: item.userName,
                          size: 22,
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            item.cardLabel,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ),
                      ],
                    ),
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
    this.onShellDestinationSelected,
  });

  final BenefitItemData item;
  final List<BenefitItemData> tiedItems;
  final VoidCallback? onBack;
  final ValueChanged<int>? onShellDestinationSelected;

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
          _DetailCard(
            item: current,
            onShellDestinationSelected: onShellDestinationSelected,
          ),
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
  const _DetailCard({
    required this.item,
    this.onShellDestinationSelected,
  });

  final BenefitItemData item;
  final ValueChanged<int>? onShellDestinationSelected;

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
                BankIconBadge(
                  iconKey: item.bankIconKey,
                  bankName: item.bankName,
                  size: 32,
                ),
                const SizedBox(width: 6),
                UserIconBadge(
                  iconKey: item.userIconKey,
                  userName: item.userName,
                  size: 32,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    item.cardLabel,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
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
                      onShellDestinationSelected: onShellDestinationSelected,
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
