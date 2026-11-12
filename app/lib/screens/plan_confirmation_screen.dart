import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/card_model.dart';
import '../models/cashback_category_model.dart';
import '../providers/data_provider.dart';
import '../services/app_session_type.dart';
import '../services/card_context.dart';
import '../services/cashback_import_launcher.dart';
import '../services/cashback_import_session.dart';
import '../services/cashback_selection_plan.dart';
import '../utils/cashback_period.dart';
import '../utils/cashflow_formatters.dart';
import 'widgets/cashback_json_import.dart';

export 'widgets/cashback_json_import.dart'
    show CashbackFilePicker, CashbackDocumentImporter;

/// Opens the browser profile, optionally with the selection plan checklist.
typedef CashbackBrowserLauncher = Future<String?> Function(
  CashbackImportProfile profile, {
  String? selectionPlan,
});

/// Confirmation of the monthly plan, in two explicit stages:
///
/// 1. the owner selects categories in each bank (the browser profile opens
///    with the plan as a checklist; the bank's own offer may differ);
/// 2. «Проверить выбор» re-reads the bank: the downloaded JSON is imported
///    through the shared import and the screen shows what the bank confirmed.
///
/// A category selected in the bank outside the plan is an accepted outcome:
/// the import adds it to the plan and the screen says so neutrally. Planned
/// categories the bank did not confirm can be dropped from the plan in one
/// tap («Принять выбор банка»). Confirmation itself only ever comes from an
/// imported bank snapshot.
class PlanConfirmationScreen extends StatefulWidget {
  const PlanConfirmationScreen({
    super.key,
    this.onBack,
    this.period,
    this.filePicker,
    this.documentImporter,
    this.browserLauncher,
    this.sessionType,
    this.onShellDestinationSelected,
  });

  final VoidCallback? onBack;
  final CashbackPeriod? period;
  final CashbackFilePicker? filePicker;
  final CashbackDocumentImporter? documentImporter;
  final CashbackBrowserLauncher? browserLauncher;
  final AppSessionType? sessionType;
  final ValueChanged<int>? onShellDestinationSelected;

  @override
  State<PlanConfirmationScreen> createState() => _PlanConfirmationScreenState();
}

class _PlanConfirmationScreenState extends State<PlanConfirmationScreen> {
  int? _selectedCardId;
  bool _showCompactDetails = false;

  /// Owner whose bank JSON is being imported right now.
  int? _checkingUserId;
  int? _launchingUserId;
  final Set<int> _removingCategoryIds = {};

  /// Owners re-read in this session, with the time of the last check.
  final Map<int, DateTime> _checkedAt = {};

  /// Planned category ids per card before the first check of this session;
  /// what the bank confirmed beyond them was chosen there on the spot.
  final Map<int, Set<int>> _plannedBeforeCheck = {};
  String? _checkError;
  int? _checkErrorUserId;
  final FocusNode _errorFocusNode = FocusNode();
  final ScrollController _overviewController = ScrollController();
  final ScrollController _detailsController = ScrollController();

  CashbackPeriod get _period =>
      widget.period ?? CashbackPeriod.month(DateTime.now());

  AppSessionType get _session => widget.sessionType ?? detectAppSessionType();

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
    final grouped =
        selectedCategoriesByCard(provider.cashbackCategories, _period);
    final contexts = CardContextCatalog(
        cards: provider.cards, banks: provider.banks, users: provider.users);
    final cards = grouped.entries.map((entry) {
      final context = contexts.forId(entry.key);
      final card = context.card;
      return _ConfirmationCard(
        card: card,
        bankName: context.bankName ?? 'Неизвестный банк',
        userName: context.ownerName ?? 'Владелец не указан',
        categories: [...entry.value]
          ..sort((a, b) => b.cashbackPercent.compareTo(a.cashbackPercent)),
        plannedBeforeCheck: _plannedBeforeCheck[entry.key],
        checkedAt: _checkedAt[card.userId],
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

  CashbackImportProfile? _profileFor(DataProvider provider, int? userId) {
    if (userId == null) return null;
    for (final profile in cashbackImportProfiles) {
      if (cashbackImportProfileUser(profile, provider.users)?.id == userId) {
        return profile;
      }
    }
    return null;
  }

  /// Stage 1 (and the first half of stage 2): the owner's browser profile
  /// with the plan as a checklist. Launching an already open profile only
  /// brings it forward.
  Future<void> _openBrowser(
    DataProvider provider,
    _ConfirmationCard card,
  ) async {
    final userId = card.card.userId;
    final profile = _profileFor(provider, userId);
    if (profile == null || _launchingUserId != null) return;
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _launchingUserId = userId);
    String? error;
    try {
      await CashbackImportSession.rememberProfile(profile);
      final plan = buildCashbackSelectionPlan(
        now: DateTime.now(),
        period: _period,
        banks: provider.banks,
        users: provider.users,
        cards: provider.cards,
        categories: provider.cashbackCategories,
        requestedBankIds: profile.banks,
        userId: userId,
      );
      error = await (widget.browserLauncher ?? launchCashbackImport)(
        profile,
        selectionPlan: jsonEncode(plan),
      );
    } catch (exception) {
      error = 'Не удалось открыть браузер: $exception';
    }
    if (!mounted) return;
    setState(() => _launchingUserId = null);
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          error ??
              '${profile.label} открыт. Справа — чек-лист плана; выбирайте '
                  'в банке то, что удобно.',
        ),
      ),
    );
  }

  /// Stage 2: imports the JSON the profile downloaded and remembers what was
  /// planned before, so the result can tell bank choices apart.
  Future<void> _checkSelection(
    DataProvider provider,
    _ConfirmationCard card,
  ) async {
    final userId = card.card.userId;
    if (userId == null || _checkingUserId != null) return;
    final ownerCardIds = {
      for (final item in provider.cards)
        if (item.userId == userId && item.id != null) item.id!,
    };
    final plannedNow = {
      for (final entry in selectedCategoriesByCard(
        provider.cashbackCategories,
        _period,
      ).entries)
        if (ownerCardIds.contains(entry.key))
          entry.key: {for (final category in entry.value) category.id},
    };

    setState(() {
      _checkingUserId = userId;
      _checkError = null;
      _checkErrorUserId = null;
    });
    try {
      final result = await importCashbackJsonFile(
        context,
        provider,
        userId: userId,
        pickFile: widget.filePicker,
        importer: widget.documentImporter,
      );
      if (!mounted) return;
      setState(() {
        _checkingUserId = null;
        if (result != null) {
          _checkedAt[userId] = DateTime.now();
          for (final cardId in ownerCardIds) {
            _plannedBeforeCheck.putIfAbsent(
              cardId,
              () => plannedNow[cardId] ?? <int>{},
            );
          }
        }
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _checkingUserId = null;
        _checkError = _readableError(error);
        _checkErrorUserId = userId;
      });
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _errorFocusNode.requestFocus();
      });
    }
  }

  /// Follows the bank: drops planned categories it did not confirm.
  Future<void> _removeFromPlan(
    DataProvider provider,
    Iterable<CashbackCategoryModel> categories,
  ) async {
    final ids = categories.map((category) => category.id).toList();
    if (ids.isEmpty) return;
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _removingCategoryIds.addAll(ids));
    try {
      for (final id in ids) {
        await provider.toggleCategorySelection(id, false);
      }
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            ids.length == 1
                ? 'Категория убрана из плана'
                : 'Убрано из плана: ${ids.length}',
          ),
        ),
      );
    } catch (error) {
      messenger.showSnackBar(
        SnackBar(content: Text('Не удалось изменить план: $error')),
      );
    } finally {
      if (mounted) setState(() => _removingCategoryIds.removeAll(ids));
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
                      period: _period.start,
                      canEdit: provider.canEdit,
                      onBack: _goBack,
                    ),
                  // On phones the banner scrolls with the card list.
                  if (expanded) ...[
                    Padding(
                      padding: EdgeInsets.fromLTRB(gutter, 12, gutter, 0),
                      child: _StagesBanner(
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
                            ? _buildExpanded(provider, cards, selected!, gutter)
                            : _buildSequential(
                                provider,
                                cards,
                                selected!,
                                gutter,
                                _StagesBanner(
                                  confirmed: confirmed,
                                  total: total,
                                ),
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

  Widget _details(
    DataProvider provider,
    _ConfirmationCard card, {
    required EdgeInsets padding,
    bool includeSummary = false,
  }) {
    final userId = card.card.userId;
    return _CardDetails(
      card: card,
      canEdit: provider.canEdit,
      canImport: _session.canImportCashbackFile,
      canLaunchBrowser: _session.canLaunchCashbackBrowser &&
          _profileFor(provider, userId) != null,
      profileLabel: _profileFor(provider, userId)?.label,
      checking: userId != null && _checkingUserId == userId,
      launching: userId != null && _launchingUserId == userId,
      removingCategoryIds: _removingCategoryIds,
      checkError: _checkErrorUserId == userId ? _checkError : null,
      errorFocusNode: _errorFocusNode,
      onOpenBrowser: () => _openBrowser(provider, card),
      onCheck: () => _checkSelection(provider, card),
      onRemove: (categories) => _removeFromPlan(provider, categories),
      scrollController: _detailsController,
      padding: padding,
      includeSummary: includeSummary,
    );
  }

  Widget _buildSequential(
    DataProvider provider,
    List<_ConfirmationCard> cards,
    _ConfirmationCard selected,
    double gutter,
    Widget banner,
  ) {
    if (_showCompactDetails) {
      return _details(
        provider,
        selected,
        padding: EdgeInsets.fromLTRB(gutter, 0, gutter, 24),
        includeSummary: true,
      );
    }
    return ListView.separated(
      key: const PageStorageKey('confirmation-card-overview'),
      controller: _overviewController,
      padding: EdgeInsets.fromLTRB(gutter, 0, gutter, 24),
      itemCount: cards.length + 2,
      separatorBuilder: (_, __) => const SizedBox(height: 10),
      itemBuilder: (context, index) {
        if (index == 0) return banner;
        if (index == cards.length + 1) {
          return _SnapshotNote(lastCheck: _lastCheck);
        }
        final card = cards[index - 1];
        return _CardOverviewTile(
          card: card,
          onTap: () => setState(() {
            _selectedCardId = card.card.id;
            _showCompactDetails = true;
          }),
        );
      },
    );
  }

  DateTime? get _lastCheck => _checkedAt.values.fold<DateTime?>(
        null,
        (latest, time) =>
            latest == null || time.isAfter(latest) ? time : latest,
      );

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
                    onTap: () => setState(() => _selectedCardId = card.card.id),
                  );
                },
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: _Panel(
              child: _details(
                provider,
                selected,
                padding: const EdgeInsets.all(16),
              ),
            ),
          ),
          const SizedBox(width: 12),
          SizedBox(
            width: 244,
            child: _Panel(
              child: _MonthSummary(cards: cards, lastCheck: _lastCheck),
            ),
          ),
        ],
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
    this.plannedBeforeCheck,
    this.checkedAt,
  });

  final CardModel card;
  final String bankName;
  final String userName;
  final List<CashbackCategoryModel> categories;
  final Set<int>? plannedBeforeCheck;
  final DateTime? checkedAt;

  int get confirmed => categories.where((item) => item.isBankConfirmed).length;
  int get total => categories.length;
  bool get isComplete => total > 0 && confirmed == total;
  bool get isChecked => checkedAt != null;
  String get title => '$bankName · ${card.lastFourDigits ?? '••••'}';

  /// Selected in the bank on the spot and added to the plan by the check.
  bool chosenInBank(CashbackCategoryModel category) =>
      category.isBankConfirmed &&
      plannedBeforeCheck != null &&
      !plannedBeforeCheck!.contains(category.id);

  List<CashbackCategoryModel> get unconfirmed =>
      categories.where((item) => !item.isBankConfirmed).toList();

  int get chosenInBankCount => categories.where(chosenInBank).length;
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
  static const info = Color(0xFF1D4F91);
  static const infoBackground = Color(0xFFE8F0FC);
  static const neutral = Color(0xFF475467);
  static const neutralBackground = Color(0xFFEEF1F5);
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
  final DateTime period;
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
                  details ? 'Выбор по карте' : 'Подтверждение',
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
                  '${_formatMonth(period)} · '
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

/// The two stages and the month's progress.
class _StagesBanner extends StatelessWidget {
  const _StagesBanner({required this.confirmed, required this.total});

  final int confirmed;
  final int total;

  @override
  Widget build(BuildContext context) {
    final progress = total == 0 ? 0.0 : confirmed / total;
    const stepStyle = TextStyle(color: Color(0xFFDEEBFF));
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
                    'Два шага: выбрать и проверить',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          color: Colors.white,
                          fontWeight: FontWeight.w800,
                        ),
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    '1 · Выберите категории в банке. Можно и не по плану — '
                    'выбор банка главнее.',
                    style: stepStyle,
                  ),
                  const SizedBox(height: 2),
                  const Text(
                    '2 · «Проверить выбор» перечитает банк и покажет, что '
                    'подтверждено.',
                    style: stepStyle,
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

(String, _StatusKind) _cardStatus(_ConfirmationCard card) {
  if (card.isComplete) return ('Подтверждено', _StatusKind.success);
  if (card.isChecked) {
    return ('Проверено · ${card.confirmed} из ${card.total}', _StatusKind.info);
  }
  if (card.confirmed > 0) return ('Подтверждено частично', _StatusKind.info);
  return ('Ждёт проверки', _StatusKind.warning);
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
    final (status, kind) = _cardStatus(card);
    final action =
        card.isComplete ? 'Посмотреть подтверждения' : 'Выбрать и проверить';
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
                      _StatusPill(label: status, kind: kind),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    '${card.userName} · подтверждено ${card.confirmed} из '
                    '${card.total}',
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
    required this.canLaunchBrowser,
    required this.profileLabel,
    required this.checking,
    required this.launching,
    required this.removingCategoryIds,
    required this.checkError,
    required this.errorFocusNode,
    required this.onOpenBrowser,
    required this.onCheck,
    required this.onRemove,
    required this.scrollController,
    required this.padding,
    this.includeSummary = false,
  });

  final _ConfirmationCard card;
  final bool canEdit;
  final bool canImport;
  final bool canLaunchBrowser;
  final String? profileLabel;
  final bool checking;
  final bool launching;
  final Set<int> removingCategoryIds;
  final String? checkError;
  final FocusNode errorFocusNode;
  final VoidCallback onOpenBrowser;
  final VoidCallback onCheck;
  final ValueChanged<List<CashbackCategoryModel>> onRemove;
  final ScrollController scrollController;
  final EdgeInsets padding;
  final bool includeSummary;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final (status, kind) = _cardStatus(card);
    final unconfirmed = card.unconfirmed;
    final browserButton = OutlinedButton.icon(
      key: const ValueKey('confirmation-open-browser'),
      onPressed: canLaunchBrowser && !launching ? onOpenBrowser : null,
      icon: launching
          ? const SizedBox.square(
              dimension: 16,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : const Icon(Icons.open_in_browser, size: 18),
      label: Text(launching ? 'Открываем…' : 'Открыть браузер с планом'),
    );
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
            _StatusPill(label: status, kind: kind),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          '${card.userName} · подтверждено ${card.confirmed} из ${card.total}',
          style: TextStyle(color: scheme.onSurfaceVariant),
        ),
        const SizedBox(height: 14),
        if (!canEdit)
          const _InfoBox(
            icon: Icons.visibility_outlined,
            text: 'Только просмотр. У вашей учётной записи нет права '
                'импортировать банковский снимок и менять план.',
          ),
        _StageSection(
          number: 1,
          title: 'Выбрать категории в банке',
          done: card.isComplete,
          children: [
            Text(
              'Откройте браузер${profileLabel == null ? '' : ' «$profileLabel»'}'
              ': справа появится чек-лист плана. Выбирайте в банке то, что '
              'удобно. Если банк предложил другое и вы выбрали на месте — '
              'это нормально, проверка добавит выбор банка в план.',
            ),
            const SizedBox(height: 10),
            Align(alignment: Alignment.centerLeft, child: browserButton),
            if (!canLaunchBrowser)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(
                  'Браузер с планом открывается из Windows-приложения.',
                  style: TextStyle(
                    color: scheme.onSurfaceVariant,
                    fontSize: 12,
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 10),
        _StageSection(
          number: 2,
          title: 'Проверить выбор',
          done: card.isComplete,
          children: [
            const Text(
              'Перечитайте банк: в расширении нажмите «Проверить '
              'подтверждение в банках» и «Скачать JSON», затем «Проверить '
              'выбор» здесь. Проверять можно сколько угодно раз.',
            ),
            if (card.checkedAt != null) ...[
              const SizedBox(height: 6),
              Text(
                'Последняя проверка: ${_formatTime(card.checkedAt!)}',
                style: TextStyle(
                  color: scheme.onSurfaceVariant,
                  fontSize: 12,
                ),
              ),
            ],
            const SizedBox(height: 10),
            if (canEdit)
              Align(
                alignment: Alignment.centerLeft,
                child: FilledButton.icon(
                  key: const ValueKey('confirmation-check'),
                  onPressed: canImport && !checking ? onCheck : null,
                  icon: checking
                      ? const SizedBox.square(
                          dimension: 16,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Icon(Icons.fact_check_outlined, size: 18),
                  label: Text(
                    checking
                        ? 'Проверяем…'
                        : card.isChecked
                            ? 'Проверить ещё раз'
                            : 'Проверить выбор',
                  ),
                ),
              ),
            if (canEdit && !canImport)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(
                  'Выбор JSON-файла доступен в Windows-приложении.',
                  style: TextStyle(
                    color: scheme.onSurfaceVariant,
                    fontSize: 12,
                  ),
                ),
              ),
          ],
        ),
        if (checkError != null) ...[
          const SizedBox(height: 10),
          Semantics(
            liveRegion: true,
            label: checkError,
            child: Focus(
              focusNode: errorFocusNode,
              child: Card(
                margin: EdgeInsets.zero,
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
                        checkError!,
                        style: TextStyle(color: scheme.onErrorContainer),
                      ),
                      if (canEdit && canImport)
                        TextButton(
                          onPressed: onCheck,
                          child: const Text('Выбрать файл снова'),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
        const SizedBox(height: 16),
        Text(
          card.isChecked ? 'Результат проверки' : 'Категории в плане',
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 8),
        if (card.isChecked && card.chosenInBankCount > 0)
          _InfoBox(
            icon: Icons.add_task,
            text: 'Выбрано в банке на месте: ${card.chosenInBankCount}. '
                'Эти категории уже добавлены в план.',
          ),
        for (final category in card.categories) ...[
          _CategoryConfirmationTile(
            category: category,
            checked: card.isChecked,
            chosenInBank: card.chosenInBank(category),
            canEdit: canEdit,
            removing: removingCategoryIds.contains(category.id),
            onRemove: () => onRemove([category]),
          ),
          const SizedBox(height: 10),
        ],
        if (card.isChecked && canEdit && unconfirmed.isNotEmpty) ...[
          _InfoBox(
            icon: Icons.swap_horiz,
            text: 'Банк не подтвердил ${unconfirmed.length} из плана. Если в '
                'банке выбрано другое, примите выбор банка — эти категории '
                'уйдут из плана, подтверждённые останутся.',
          ),
          Align(
            alignment: Alignment.centerLeft,
            child: OutlinedButton.icon(
              key: const ValueKey('confirmation-adopt-bank'),
              onPressed: unconfirmed.any(
                (category) => removingCategoryIds.contains(category.id),
              )
                  ? null
                  : () => onRemove(unconfirmed),
              icon: const Icon(Icons.done_all, size: 18),
              label: const Text('Принять выбор банка'),
            ),
          ),
        ],
        if (includeSummary) ...[
          const SizedBox(height: 20),
          const _InfoBox(
            icon: Icons.history,
            text: 'Подтверждение приходит только из импортированного '
                'банковского снимка. Свежая проверка может обновить его.',
          ),
        ],
      ],
    );
  }
}

class _StageSection extends StatelessWidget {
  const _StageSection({
    required this.number,
    required this.title,
    required this.done,
    required this.children,
  });

  final int number;
  final String title;
  final bool done;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border.all(color: scheme.outlineVariant),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ExcludeSemantics(
              child: CircleAvatar(
                radius: 13,
                backgroundColor: done
                    ? _ConfirmationPalette.successBackground
                    : _ConfirmationPalette.infoBackground,
                child: done
                    ? const Icon(
                        Icons.check,
                        size: 16,
                        color: _ConfirmationPalette.success,
                      )
                    : Text(
                        '$number',
                        style: const TextStyle(
                          color: _ConfirmationPalette.info,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'Шаг $number. $title',
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 6),
                  ...children,
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CategoryConfirmationTile extends StatelessWidget {
  const _CategoryConfirmationTile({
    required this.category,
    required this.checked,
    required this.chosenInBank,
    required this.canEdit,
    required this.removing,
    required this.onRemove,
  });

  final CashbackCategoryModel category;
  final bool checked;
  final bool chosenInBank;
  final bool canEdit;
  final bool removing;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final confirmed = category.isBankConfirmed;
    final (status, kind, icon, note) = chosenInBank
        ? (
            'Выбрано в банке',
            _StatusKind.info,
            Icons.add_task,
            'Выбрано на месте в банке и добавлено в план',
          )
        : confirmed
            ? (
                'Подтверждено банком',
                _StatusKind.success,
                Icons.check,
                'Банк подтвердил выбор',
              )
            : checked
                ? (
                    'Банк не подтвердил',
                    _StatusKind.neutral,
                    Icons.remove,
                    'В банке не выбрано или ещё ждёт подтверждения',
                  )
                : (
                    'Ждёт проверки',
                    _StatusKind.warning,
                    Icons.schedule,
                    'Выберите в банке, затем «Проверить выбор»',
                  );
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
                  child: Icon(icon, size: 16, color: kind.foreground),
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
                      Chip(
                        visualDensity: VisualDensity.compact,
                        label: Text(chosenInBank ? 'Из банка' : 'В плане'),
                      ),
                      _StatusPill(label: status, kind: kind),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    note,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                      fontSize: 12,
                    ),
                  ),
                  if (checked && !confirmed && canEdit)
                    TextButton(
                      onPressed: removing ? null : onRemove,
                      style: TextButton.styleFrom(
                        padding: EdgeInsets.zero,
                        visualDensity: VisualDensity.compact,
                      ),
                      child: Text(removing ? 'Убираем…' : 'Убрать из плана'),
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

/// No kind means «wrong»: a bank choice that differs from the plan is neutral.
enum _StatusKind {
  success(
    _ConfirmationPalette.successBackground,
    _ConfirmationPalette.success,
  ),
  warning(
    _ConfirmationPalette.warningBackground,
    _ConfirmationPalette.warning,
  ),
  info(_ConfirmationPalette.infoBackground, _ConfirmationPalette.info),
  neutral(
    _ConfirmationPalette.neutralBackground,
    _ConfirmationPalette.neutral,
  );

  const _StatusKind(this.background, this.foreground);

  final Color background;
  final Color foreground;
}

class _StatusPill extends StatelessWidget {
  const _StatusPill({
    required this.label,
    required this.kind,
  });

  final String label;
  final _StatusKind kind;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: label,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: kind.background,
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
                color: kind.foreground,
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
  const _MonthSummary({required this.cards, required this.lastCheck});

  final List<_ConfirmationCard> cards;
  final DateTime? lastCheck;

  @override
  Widget build(BuildContext context) {
    final total = cards.fold<int>(0, (sum, card) => sum + card.total);
    final confirmed = cards.fold<int>(0, (sum, card) => sum + card.confirmed);
    final chosenInBank =
        cards.fold<int>(0, (sum, card) => sum + card.chosenInBankCount);
    return ListView(
      padding: const EdgeInsets.all(14),
      children: [
        Text('Сводка месяца', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 12),
        _Metric(label: 'Подтверждено банком', value: confirmed),
        _Metric(label: 'Ждёт подтверждения', value: total - confirmed),
        if (chosenInBank > 0)
          _Metric(label: 'Выбрано в банке на месте', value: chosenInBank),
        const SizedBox(height: 12),
        const Divider(),
        const SizedBox(height: 8),
        const Text('Источник подтверждения',
            style: TextStyle(fontWeight: FontWeight.w800)),
        const SizedBox(height: 6),
        const Text(
          'Только импортированный банковский снимок. План сам по себе не '
          'является доказательством, а выбор банка главнее плана.',
        ),
        const SizedBox(height: 12),
        _SnapshotNote(lastCheck: lastCheck),
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
  const _SnapshotNote({required this.lastCheck});

  final DateTime? lastCheck;

  @override
  Widget build(BuildContext context) {
    return _InfoBox(
      icon: Icons.history,
      text: lastCheck == null
          ? 'В этой сессии выбор ещё не проверяли. Проверка перечитывает '
              'банк и может отозвать устаревшее подтверждение.'
          : 'Последняя проверка: ${_formatTime(lastCheck!)}.',
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

String _formatPercent(double value) => CashFlowFormatters.percent(value);
String _formatMonth(DateTime value) => CashFlowFormatters.month(value);
String _formatTime(DateTime value) => CashFlowFormatters.time(value);
