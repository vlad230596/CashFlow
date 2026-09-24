import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/card_model.dart';
import '../models/cashback_category_model.dart';
import '../providers/data_provider.dart';
import '../services/app_session_type.dart';
import '../services/cashback_import_launcher.dart';

typedef CashbackFilePicker = Future<CashbackImportFile?> Function();
typedef CashbackDocumentImporter = Future<CashbackImportResult> Function(
  DataProvider provider,
  String contents,
  int userId,
);

/// Read-only proof stage that follows the manual monthly plan.
///
/// The screen deliberately never mutates `isSelected`: confirmation can only
/// arrive through the existing bank snapshot import contract.
class PlanConfirmationScreen extends StatefulWidget {
  const PlanConfirmationScreen({
    super.key,
    this.onBack,
    this.filePicker,
    this.documentImporter,
    this.sessionType,
    this.onShellDestinationSelected,
  });

  final VoidCallback? onBack;
  final CashbackFilePicker? filePicker;
  final CashbackDocumentImporter? documentImporter;
  final AppSessionType? sessionType;
  final ValueChanged<int>? onShellDestinationSelected;

  @override
  State<PlanConfirmationScreen> createState() => _PlanConfirmationScreenState();
}

class _PlanConfirmationScreenState extends State<PlanConfirmationScreen> {
  int? _selectedCardId;
  bool _showCompactDetails = false;
  bool _importing = false;
  bool _hasImportedSnapshot = false;
  DateTime? _lastSuccessfulImport;
  String? _importError;
  final FocusNode _errorFocusNode = FocusNode();
  final ScrollController _overviewController = ScrollController();
  final ScrollController _detailsController = ScrollController();

  @override
  void dispose() {
    _errorFocusNode.dispose();
    _overviewController.dispose();
    _detailsController.dispose();
    super.dispose();
  }

  void _goBack() {
    if (_showCompactDetails) {
      setState(() => _showCompactDetails = false);
      return;
    }
    if (widget.onBack case final onBack?) {
      onBack();
    } else {
      Navigator.maybePop(context);
    }
  }

  void _selectShellDestination(int index) {
    if (index == 1) {
      _goBack();
      return;
    }
    Navigator.maybePop(context).then((_) {
      widget.onShellDestinationSelected?.call(index);
    });
  }

  List<_ConfirmationCard> _plannedCards(DataProvider provider) {
    final grouped = <int, List<CashbackCategoryModel>>{};
    for (final category in provider.cashbackCategories) {
      if (!category.isSelectable || !category.isSelected) continue;
      grouped.putIfAbsent(category.cardId, () => []).add(category);
    }

    final cards = grouped.entries.map((entry) {
      final card = provider.getCardById(entry.key);
      final bankName = provider.banks
          .where((bank) => bank.id == card.bankId)
          .map((bank) => bank.name)
          .firstOrNull;
      final userName = provider.users
          .where((user) => user.id == card.userId)
          .map((user) => user.name)
          .firstOrNull;
      final categories = [...entry.value];
      return _ConfirmationCard(
        card: card,
        bankName: bankName ?? 'Неизвестный банк',
        userName: userName ?? 'Владелец не указан',
        categories: categories,
      );
    }).toList();

    cards.sort((a, b) {
      final completion = a.isComplete == b.isComplete
          ? 0
          : a.isComplete
              ? 1
              : -1;
      if (completion != 0) return completion;
      final aProgress = a.total == 0 ? 0.0 : a.confirmed / a.total;
      final bProgress = b.total == 0 ? 0.0 : b.confirmed / b.total;
      final progressOrder = aProgress.compareTo(bProgress);
      if (progressOrder != 0) return progressOrder;
      return a.title.compareTo(b.title);
    });
    return cards;
  }

  _ConfirmationCard? _selectedCard(List<_ConfirmationCard> cards) {
    if (cards.isEmpty) return null;
    return cards.firstWhere(
      (card) => card.card.id == _selectedCardId,
      orElse: () => cards.first,
    );
  }

  Future<void> _importSnapshot(
    DataProvider provider,
    _ConfirmationCard card,
  ) async {
    final userId = card.card.userId;
    if (userId == null || _importing) return;

    setState(() {
      _importing = true;
      _importError = null;
    });
    try {
      final file = await (widget.filePicker ?? pickCashbackImportFile)();
      if (file == null) {
        if (mounted) setState(() => _importing = false);
        return;
      }
      final importer = widget.documentImporter ??
          (provider, contents, userId) =>
              provider.importCashbackDocument(contents, userId);
      final result = await importer(provider, file.contents, userId);
      if (!mounted) return;
      setState(() {
        _importing = false;
        _hasImportedSnapshot = true;
        _lastSuccessfulImport = DateTime.now();
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Снимок импортирован: банков обновлено ${result.importedBanks}, '
            'пропущено ${result.skippedBanks}',
          ),
        ),
      );
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _importing = false;
        _importError = _readableError(error);
      });
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _errorFocusNode.requestFocus();
      });
    }
  }

  String _readableError(Object error) {
    final message = error.toString().replaceFirst('Exception: ', '').trim();
    if (message.isEmpty) {
      return 'Файл не импортирован. Проверьте JSON и выберите файл снова.';
    }
    return 'Файл не импортирован: $message. Текущий план не изменён.';
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<DataProvider>();
    final cards = _plannedCards(provider);
    final selected = _selectedCard(cards);
    if (selected != null && _selectedCardId == null) {
      _selectedCardId = selected.card.id;
    }

    final confirmed = cards.fold<int>(0, (sum, card) => sum + card.confirmed);
    final total = cards.fold<int>(0, (sum, card) => sum + card.total);

    return LayoutBuilder(
      builder: (context, constraints) {
        final expanded = constraints.maxWidth >= 840;
        final gutter = expanded ? 24.0 : 12.0;
        final period = cards
            .expand((card) => card.categories)
            .map((category) => category.startDate)
            .firstOrNull;
        return PopScope(
          canPop: !_showCompactDetails,
          onPopInvokedWithResult: (didPop, result) {
            if (!didPop && _showCompactDetails) _goBack();
          },
          child: Scaffold(
            appBar: expanded
                ? AppBar(
                    leading: IconButton(
                      tooltip: 'К плану',
                      onPressed: _goBack,
                      icon: const Icon(Icons.arrow_back),
                    ),
                    title: const Text('Подтверждение в банках'),
                    actions: [
                      Padding(
                        padding: const EdgeInsets.only(right: 12),
                        child: Chip(
                          avatar: Icon(
                            provider.canEdit
                                ? Icons.edit_outlined
                                : Icons.visibility,
                            size: 18,
                          ),
                          label: Text(
                            provider.canEdit ? 'Редактор' : 'Только просмотр',
                          ),
                        ),
                      ),
                    ],
                  )
                : null,
            bottomNavigationBar: !expanded && !_showCompactDetails
                ? _ConfirmationBottomNavigation(
                    onSelected: _selectShellDestination,
                  )
                : null,
            body: SafeArea(
              bottom: false,
              child: Column(
                children: [
                  if (!expanded)
                    _MobileConfirmationHeader(
                      details: _showCompactDetails,
                      period: period,
                      canEdit: provider.canEdit,
                      onBack: _goBack,
                    ),
                  if (expanded || !_showCompactDetails) ...[
                    Padding(
                      padding: EdgeInsets.fromLTRB(
                        gutter,
                        expanded ? 12 : 14,
                        gutter,
                        0,
                      ),
                      child: _ProgressBanner(
                        confirmed: confirmed,
                        total: total,
                      ),
                    ),
                    const SizedBox(height: 12),
                  ] else
                    const SizedBox(height: 14),
                  Expanded(
                    child: cards.isEmpty
                        ? const _EmptyPlan()
                        : expanded
                            ? _buildExpanded(
                                provider,
                                cards,
                                selected!,
                                gutter,
                              )
                            : _buildSequential(
                                provider,
                                cards,
                                selected!,
                                gutter,
                              ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildSequential(
    DataProvider provider,
    List<_ConfirmationCard> cards,
    _ConfirmationCard selected,
    double gutter,
  ) {
    if (_showCompactDetails) {
      return _CardDetails(
        card: selected,
        canEdit: provider.canEdit,
        canImport: _canImport,
        importing: _importing,
        importError: _importError,
        errorFocusNode: _errorFocusNode,
        hasImportedSnapshot: _hasImportedSnapshot,
        lastSuccessfulImport: _lastSuccessfulImport,
        onImport: () => _importSnapshot(provider, selected),
        onShowHelp: () => _showImportHelp(selected),
        scrollController: _detailsController,
        padding: EdgeInsets.fromLTRB(gutter, 0, gutter, 24),
        includeSummary: true,
      );
    }
    return ListView.separated(
      key: const PageStorageKey('confirmation-card-overview'),
      controller: _overviewController,
      padding: EdgeInsets.fromLTRB(gutter, 0, gutter, 24),
      itemCount: cards.length + 1,
      separatorBuilder: (_, __) => const SizedBox(height: 10),
      itemBuilder: (context, index) {
        if (index == cards.length) {
          return _SnapshotNote(lastSuccessfulImport: _lastSuccessfulImport);
        }
        final card = cards[index];
        return _CardOverviewTile(
          card: card,
          onTap: () {
            if (!card.isComplete && MediaQuery.sizeOf(context).width < 600) {
              _showSnapshotSheet(provider, card);
              return;
            }
            setState(() {
              _selectedCardId = card.card.id;
              _showCompactDetails = true;
            });
          },
        );
      },
    );
  }

  Widget _buildExpanded(
    DataProvider provider,
    List<_ConfirmationCard> cards,
    _ConfirmationCard selected,
    double gutter,
  ) {
    return Padding(
      padding: EdgeInsets.fromLTRB(gutter, 0, gutter, 24),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            width: 260,
            child: _Panel(
              child: ListView.separated(
                padding: const EdgeInsets.all(10),
                itemCount: cards.length,
                separatorBuilder: (_, __) => const SizedBox(height: 8),
                itemBuilder: (context, index) {
                  final card = cards[index];
                  return _CardOverviewTile(
                    card: card,
                    selected: card.card.id == selected.card.id,
                    dense: true,
                    onTap: () => setState(() {
                      _selectedCardId = card.card.id;
                      _importError = null;
                    }),
                  );
                },
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: _Panel(
              child: _CardDetails(
                card: selected,
                canEdit: provider.canEdit,
                canImport: _canImport,
                importing: _importing,
                importError: _importError,
                errorFocusNode: _errorFocusNode,
                hasImportedSnapshot: _hasImportedSnapshot,
                lastSuccessfulImport: _lastSuccessfulImport,
                onImport: () => _importSnapshot(provider, selected),
                onShowHelp: () => _showImportHelp(selected),
                scrollController: _detailsController,
                padding: const EdgeInsets.all(16),
              ),
            ),
          ),
          const SizedBox(width: 12),
          SizedBox(
            width: 244,
            child: _Panel(
              child: _MonthSummary(
                cards: cards,
                hasImportedSnapshot: _hasImportedSnapshot,
                lastSuccessfulImport: _lastSuccessfulImport,
              ),
            ),
          ),
        ],
      ),
    );
  }

  bool get _canImport =>
      (widget.sessionType ?? detectAppSessionType()).canImportCashbackFile;

  void _showSnapshotSheet(
    DataProvider provider,
    _ConfirmationCard card,
  ) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      builder: (sheetContext) => SafeArea(
        top: false,
        child: Padding(
          padding: EdgeInsets.fromLTRB(
            18,
            22,
            18,
            18 + MediaQuery.viewInsetsOf(sheetContext).bottom,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Импортировать снимок',
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
              ),
              const SizedBox(height: 8),
              Text(
                'Получите свежий JSON через существующий сценарий импорта '
                'и выберите файл. CashFlow не активирует категории в '
                'приложении банка.',
                style: const TextStyle(color: _ConfirmationPalette.muted),
              ),
              const SizedBox(height: 14),
              DecoratedBox(
                decoration: BoxDecoration(
                  color: Colors.white,
                  border: Border.all(color: _ConfirmationPalette.outline),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        card.title,
                        style: const TextStyle(fontWeight: FontWeight.w800),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Подтверждено ${card.confirmed} из ${card.total}',
                        style: const TextStyle(
                          color: _ConfirmationPalette.muted,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 14),
              FilledButton(
                onPressed: provider.canEdit && _canImport && !_importing
                    ? () {
                        Navigator.pop(sheetContext);
                        _importSnapshot(provider, card);
                      }
                    : null,
                child: const Text('Выбрать JSON-файл'),
              ),
              if (!_canImport) ...[
                const SizedBox(height: 8),
                const Text(
                  'Выбор JSON-файла доступен в Windows-приложении.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: _ConfirmationPalette.muted,
                    fontSize: 12,
                  ),
                ),
              ],
              const SizedBox(height: 8),
              OutlinedButton(
                onPressed: () => Navigator.pop(sheetContext),
                child: const Text('Отмена'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showImportHelp(_ConfirmationCard card) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (sheetContext) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Как подтвердить выбор',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 12),
              const Text(
                'Экспортируйте свежий JSON-снимок через существующее '
                'браузерное расширение, затем выберите файл здесь. CashFlow '
                'не активирует категории в приложении банка.',
              ),
              const SizedBox(height: 12),
              Text(card.title,
                  style: const TextStyle(fontWeight: FontWeight.w700)),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: () => Navigator.pop(sheetContext),
                child: const Text('Понятно'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ConfirmationCard {
  const _ConfirmationCard({
    required this.card,
    required this.bankName,
    required this.userName,
    required this.categories,
  });

  final CardModel card;
  final String bankName;
  final String userName;
  final List<CashbackCategoryModel> categories;

  int get confirmed => categories.where((item) => item.isBankConfirmed).length;
  int get total => categories.length;
  bool get isComplete => total > 0 && confirmed == total;
  String get title => '$bankName · ${card.lastFourDigits ?? '••••'}';
}

abstract final class _ConfirmationPalette {
  static const navy = Color(0xFF102F59);
  static const blue = Color(0xFF216DF3);
  static const blueDark = Color(0xFF12376A);
  static const blueLight = Color(0xFF2874DF);
  static const success = Color(0xFF087F5B);
  static const successBackground = Color(0xFFE7F6EF);
  static const warning = Color(0xFF9A5700);
  static const warningBackground = Color(0xFFFFF3DC);
  static const error = Color(0xFFB42318);
  static const errorBackground = Color(0xFFFFF0EE);
  static const muted = Color(0xFF58708F);
  static const outline = Color(0xFFCFDAEA);
}

class _MobileConfirmationHeader extends StatelessWidget {
  const _MobileConfirmationHeader({
    required this.details,
    required this.period,
    required this.canEdit,
    required this.onBack,
  });

  final bool details;
  final DateTime? period;
  final bool canEdit;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: DecoratedBox(
        decoration: const BoxDecoration(
          color: Colors.white,
          border: Border(
            bottom: BorderSide(color: _ConfirmationPalette.outline),
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(8, 20, 14, 14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextButton.icon(
                onPressed: onBack,
                icon: const Icon(Icons.chevron_left, size: 22),
                label: Text(details ? 'Карты' : 'План'),
                style: TextButton.styleFrom(
                  foregroundColor: _ConfirmationPalette.blue,
                  minimumSize: const Size(48, 48),
                  padding: const EdgeInsets.symmetric(horizontal: 6),
                  textStyle: const TextStyle(fontWeight: FontWeight.w800),
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 6),
                child: Text(
                  details ? 'Подтверждения' : 'Подтверждение',
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                        color: _ConfirmationPalette.navy,
                        fontWeight: FontWeight.w800,
                      ),
                ),
              ),
              const SizedBox(height: 3),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 6),
                child: Text(
                  '${period == null ? 'Текущий месяц' : _formatMonth(period!)} · '
                  '${canEdit ? 'редактор' : 'только просмотр'}',
                  style: const TextStyle(
                    color: _ConfirmationPalette.muted,
                    fontSize: 12,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ConfirmationBottomNavigation extends StatelessWidget {
  const _ConfirmationBottomNavigation({required this.onSelected});

  final ValueChanged<int> onSelected;

  @override
  Widget build(BuildContext context) {
    return NavigationBar(
      selectedIndex: 1,
      onDestinationSelected: onSelected,
      destinations: const [
        NavigationDestination(
          icon: Icon(Icons.home_outlined),
          selectedIcon: Icon(Icons.home_rounded),
          label: 'Выгода',
        ),
        NavigationDestination(
          icon: Icon(Icons.description_outlined),
          selectedIcon: Icon(Icons.description_rounded),
          label: 'План',
        ),
        NavigationDestination(
          icon: Icon(Icons.local_offer_outlined),
          selectedIcon: Icon(Icons.local_offer_rounded),
          label: 'Акции',
        ),
        NavigationDestination(
          icon: Icon(Icons.more_horiz),
          label: 'Ещё',
        ),
      ],
    );
  }
}

class _ProgressBanner extends StatelessWidget {
  const _ProgressBanner({required this.confirmed, required this.total});

  final int confirmed;
  final int total;

  @override
  Widget build(BuildContext context) {
    final progress = total == 0 ? 0.0 : confirmed / total;
    return Semantics(
      liveRegion: true,
      label: '$confirmed из $total категорий подтверждено банком',
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [
              _ConfirmationPalette.blueDark,
              _ConfirmationPalette.blueLight,
            ],
          ),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final compact = constraints.maxWidth < 600;
              final copy = Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'План — это ещё не активация',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          color: Colors.white,
                          fontWeight: FontWeight.w800,
                        ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Подтверждение появляется только после импорта снимка из банков.',
                    style: const TextStyle(color: Color(0xFFDEEBFF)),
                  ),
                ],
              );
              final indicator = SizedBox(
                width: compact ? null : 240,
                child: Row(
                  children: [
                    Expanded(
                      child: LinearProgressIndicator(
                        value: progress,
                        minHeight: 8,
                        borderRadius: BorderRadius.circular(8),
                        color: Colors.white,
                        backgroundColor: const Color(0xFF78A7E7),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Text(
                      '$confirmed из $total',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            color: Colors.white,
                            fontWeight: FontWeight.w800,
                          ),
                    ),
                  ],
                ),
              );
              if (compact) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [copy, const SizedBox(height: 14), indicator],
                );
              }
              return Row(
                children: [
                  Expanded(child: copy),
                  const SizedBox(width: 24),
                  indicator
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

class _CardOverviewTile extends StatelessWidget {
  const _CardOverviewTile({
    required this.card,
    required this.onTap,
    this.selected = false,
    this.dense = false,
  });

  final _ConfirmationCard card;
  final VoidCallback onTap;
  final bool selected;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final complete = card.isComplete;
    final partial = !complete && card.confirmed > 0;
    final status = complete
        ? 'Готово'
        : partial
            ? 'Есть расхождение'
            : 'Ждёт снимка';
    final kind = complete
        ? _StatusKind.success
        : partial
            ? _StatusKind.error
            : _StatusKind.warning;
    final action = complete
        ? 'Посмотреть подтверждения'
        : partial
            ? 'Как обновить снимок'
            : 'Импортировать снимок';
    return Card(
      margin: EdgeInsets.zero,
      color: selected ? scheme.secondaryContainer : null,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: selected
            ? BorderSide(color: scheme.secondary, width: 2)
            : BorderSide(color: scheme.outlineVariant),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: EdgeInsets.all(dense ? 12 : 14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          card.title,
                          style: const TextStyle(fontWeight: FontWeight.w800),
                        ),
                      ),
                      const SizedBox(width: 8),
                      _StatusPill(
                        label: status,
                        kind: kind,
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    '${card.userName} · подтверждено ${card.confirmed} из ${card.total}',
                    style: TextStyle(color: scheme.onSurfaceVariant),
                  ),
                ],
              ),
            ),
            if (!dense) ...[
              const Divider(height: 1),
              ConstrainedBox(
                constraints: const BoxConstraints(minHeight: 48),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          action,
                          style: const TextStyle(
                            color: _ConfirmationPalette.navy,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                      const Icon(Icons.chevron_right, size: 20),
                    ],
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _CardDetails extends StatelessWidget {
  const _CardDetails({
    required this.card,
    required this.canEdit,
    required this.canImport,
    required this.importing,
    required this.importError,
    required this.errorFocusNode,
    required this.hasImportedSnapshot,
    required this.lastSuccessfulImport,
    required this.onImport,
    required this.onShowHelp,
    required this.scrollController,
    required this.padding,
    this.includeSummary = false,
  });

  final _ConfirmationCard card;
  final bool canEdit;
  final bool canImport;
  final bool importing;
  final String? importError;
  final FocusNode errorFocusNode;
  final bool hasImportedSnapshot;
  final DateTime? lastSuccessfulImport;
  final VoidCallback onImport;
  final VoidCallback onShowHelp;
  final ScrollController scrollController;
  final EdgeInsets padding;
  final bool includeSummary;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ListView(
      key: ValueKey('confirmation-details-${card.card.id}'),
      controller: scrollController,
      padding: padding,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                card.title,
                style: Theme.of(context).textTheme.titleLarge,
              ),
            ),
            const SizedBox(width: 8),
            _StatusPill(
              label: card.isComplete ? 'Готово' : 'Есть расхождение',
              kind: card.isComplete ? _StatusKind.success : _StatusKind.error,
            ),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          '${card.userName} · подтверждено ${card.confirmed} из ${card.total}',
          style: TextStyle(color: scheme.onSurfaceVariant),
        ),
        const SizedBox(height: 14),
        if (!canEdit)
          _InfoBox(
            icon: Icons.visibility_outlined,
            text: 'Только просмотр. У вашей учётной записи нет права '
                'импортировать банковский снимок.',
          ),
        _InfoBox(
          icon: Icons.info_outline,
          text: 'Категории ниже уже находятся в плане. Импорт снимка '
              'подтверждает факт выбора, но не меняет план.',
        ),
        if (importError != null)
          Semantics(
            liveRegion: true,
            label: importError,
            child: Focus(
              focusNode: errorFocusNode,
              child: Card(
                color: scheme.errorContainer,
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Снимок не импортирован',
                        style: TextStyle(
                          color: scheme.onErrorContainer,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        importError!,
                        style: TextStyle(color: scheme.onErrorContainer),
                      ),
                      if (canEdit && canImport)
                        TextButton(
                          onPressed: onImport,
                          child: const Text('Выбрать файл снова'),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        const SizedBox(height: 4),
        for (final category in card.categories) ...[
          _CategoryConfirmationTile(
            category: category,
            hasImportedSnapshot: hasImportedSnapshot,
            lastSuccessfulImport: lastSuccessfulImport,
          ),
          const SizedBox(height: 10),
        ],
        const SizedBox(height: 6),
        if (canEdit) ...[
          FilledButton(
            onPressed: canImport && !importing ? onImport : null,
            child: importing
                ? const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      SizedBox.square(
                        dimension: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                      SizedBox(width: 8),
                      Text('Импортируем…'),
                    ],
                  )
                : const Text('Импортировать снимок'),
          ),
          if (!canImport) ...[
            const SizedBox(height: 8),
            Text(
              'Выбор JSON-файла доступен в Windows-приложении.',
              style: TextStyle(color: scheme.onSurfaceVariant),
            ),
          ],
          const SizedBox(height: 8),
        ],
        OutlinedButton(
          onPressed: onShowHelp,
          child: const Text('Как получить JSON'),
        ),
        if (includeSummary) ...[
          const SizedBox(height: 20),
          const _InfoBox(
            icon: Icons.history,
            text: 'Подтверждение хранится отдельно от плана. Свежий '
                'банковский снимок может обновить его, не меняя выбранные '
                'категории.',
          ),
        ],
      ],
    );
  }
}

class _CategoryConfirmationTile extends StatelessWidget {
  const _CategoryConfirmationTile({
    required this.category,
    required this.hasImportedSnapshot,
    required this.lastSuccessfulImport,
  });

  final CashbackCategoryModel category;
  final bool hasImportedSnapshot;
  final DateTime? lastSuccessfulImport;

  @override
  Widget build(BuildContext context) {
    final confirmed = category.isBankConfirmed;
    final mismatch = !confirmed && hasImportedSnapshot;
    final status = confirmed
        ? 'Подтверждено банком'
        : mismatch
            ? 'Не найдено в снимке'
            : 'Ждёт снимка';
    final kind = confirmed
        ? _StatusKind.success
        : mismatch
            ? _StatusKind.error
            : _StatusKind.warning;
    final icon = confirmed
        ? Icons.check
        : mismatch
            ? Icons.error_outline
            : Icons.schedule;
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ExcludeSemantics(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: SizedBox.square(
                  dimension: 24,
                  child: Icon(
                    icon,
                    size: 16,
                    color: switch (kind) {
                      _StatusKind.success => _ConfirmationPalette.success,
                      _StatusKind.warning => _ConfirmationPalette.warning,
                      _StatusKind.error => _ConfirmationPalette.error,
                    },
                  ),
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(category.name,
                      style: const TextStyle(fontWeight: FontWeight.w800)),
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      const Chip(
                        visualDensity: VisualDensity.compact,
                        label: Text('В плане'),
                      ),
                      _StatusPill(label: status, kind: kind),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    confirmed
                        ? 'Банковский снимок подтвердил выбор'
                        : mismatch
                            ? 'Последний импорт не подтвердил выбор'
                            : 'Импортируйте свежий банковский снимок',
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Text(
              _formatPercent(category.cashbackPercent),
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                color: const Color(0xFFD36A00),
                fontWeight: FontWeight.w900,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

enum _StatusKind { success, warning, error }

class _StatusPill extends StatelessWidget {
  const _StatusPill({
    required this.label,
    required this.kind,
  });

  final String label;
  final _StatusKind kind;

  @override
  Widget build(BuildContext context) {
    final (background, foreground) = switch (kind) {
      _StatusKind.success => (
          _ConfirmationPalette.successBackground,
          _ConfirmationPalette.success
        ),
      _StatusKind.warning => (
          _ConfirmationPalette.warningBackground,
          _ConfirmationPalette.warning
        ),
      _StatusKind.error => (
          _ConfirmationPalette.errorBackground,
          _ConfirmationPalette.error
        ),
    };
    return Semantics(
      label: label,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: background,
          borderRadius: BorderRadius.circular(999),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 176),
            child: Text(
              label,
              softWrap: true,
              style: TextStyle(
                color: foreground,
                fontSize: 11,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _MonthSummary extends StatelessWidget {
  const _MonthSummary({
    required this.cards,
    required this.hasImportedSnapshot,
    required this.lastSuccessfulImport,
  });

  final List<_ConfirmationCard> cards;
  final bool hasImportedSnapshot;
  final DateTime? lastSuccessfulImport;

  @override
  Widget build(BuildContext context) {
    final total = cards.fold<int>(0, (sum, card) => sum + card.total);
    final confirmed = cards.fold<int>(0, (sum, card) => sum + card.confirmed);
    final remaining = total - confirmed;
    return ListView(
      padding: const EdgeInsets.all(14),
      children: [
        Text('Сводка месяца', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 12),
        _Metric(label: 'Подтверждено снимком', value: confirmed),
        _Metric(
          label: hasImportedSnapshot ? 'Расхождения' : 'Ожидает снимка',
          value: remaining,
        ),
        const SizedBox(height: 12),
        const Divider(),
        const SizedBox(height: 8),
        const Text('Источник подтверждения',
            style: TextStyle(fontWeight: FontWeight.w800)),
        const SizedBox(height: 6),
        const Text(
          'Только успешно импортированный банковский снимок. План сам по себе не является доказательством.',
        ),
        const SizedBox(height: 12),
        _SnapshotNote(lastSuccessfulImport: lastSuccessfulImport),
      ],
    );
  }
}

class _Metric extends StatelessWidget {
  const _Metric({required this.label, required this.value});

  final String label;
  final int value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Expanded(child: Text(label)),
          Text('$value', style: Theme.of(context).textTheme.titleMedium),
        ],
      ),
    );
  }
}

class _SnapshotNote extends StatelessWidget {
  const _SnapshotNote({required this.lastSuccessfulImport});

  final DateTime? lastSuccessfulImport;

  @override
  Widget build(BuildContext context) {
    return _InfoBox(
      icon: Icons.history,
      text: lastSuccessfulImport == null
          ? 'В этой сессии ещё не было успешного импорта. Свежий снимок '
              'может отозвать устаревшее подтверждение, но не изменит план.'
          : 'Последний успешный импорт: ${_formatTime(lastSuccessfulImport!)}. '
              'План сохранён отдельно от подтверждений.',
    );
  }
}

class _InfoBox extends StatelessWidget {
  const _InfoBox({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      color: scheme.surfaceContainerHighest,
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ExcludeSemantics(child: Icon(icon, size: 20)),
            const SizedBox(width: 10),
            Expanded(child: Text(text)),
          ],
        ),
      ),
    );
  }
}

class _Panel extends StatelessWidget {
  const _Panel({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
        borderRadius: BorderRadius.circular(16),
      ),
      child: ClipRRect(borderRadius: BorderRadius.circular(16), child: child),
    );
  }
}

class _EmptyPlan extends StatelessWidget {
  const _EmptyPlan();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.fact_check_outlined, size: 48),
            const SizedBox(height: 12),
            Text('В плане пока нет категорий',
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 6),
            const Text(
                'Вернитесь к плану и выберите категории для подтверждения.'),
          ],
        ),
      ),
    );
  }
}

String _formatPercent(double value) {
  final amount = value == value.roundToDouble()
      ? value.toInt().toString()
      : value.toStringAsFixed(1).replaceAll('.', ',');
  return '$amount%';
}

String _formatMonth(DateTime value) {
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
  return '${months[value.month - 1]} ${value.year}';
}

String _formatTime(DateTime value) =>
    '${value.hour.toString().padLeft(2, '0')}:'
    '${value.minute.toString().padLeft(2, '0')}';
