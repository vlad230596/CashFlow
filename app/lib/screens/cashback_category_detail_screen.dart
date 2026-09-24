import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../models/card_model.dart';
import '../models/cashback_category_model.dart';
import '../providers/data_provider.dart';

typedef CashbackCategorySaver = Future<void> Function(
  CashbackCategoryModel category,
);

class CashbackCategoryDetailScreen extends StatefulWidget {
  const CashbackCategoryDetailScreen({
    super.key,
    required this.category,
    this.onOpenPlan,
    this.onSave,
    this.onShellDestinationSelected,
  });

  final CashbackCategoryModel category;
  final VoidCallback? onOpenPlan;
  final CashbackCategorySaver? onSave;
  final ValueChanged<int>? onShellDestinationSelected;

  @override
  State<CashbackCategoryDetailScreen> createState() =>
      _CashbackCategoryDetailScreenState();
}

class _CashbackCategoryDetailScreenState
    extends State<CashbackCategoryDetailScreen> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameController;
  late final TextEditingController _percentController;
  late final TextEditingController _descriptionController;
  late final TextEditingController _maxAmountController;
  late final TextEditingController _minAmountController;
  late DateTime _startDate;
  late DateTime _endDate;
  late int _cardId;
  late String _categoryType;
  bool _editing = false;
  bool _saving = false;
  bool _submitted = false;
  String? _saveError;

  bool get _knownType => const {
        'standard',
        'stackable_bonus',
        'task_bonus',
      }.contains(widget.category.categoryType);

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.category.name);
    _percentController = TextEditingController(
      text: _number(widget.category.cashbackPercent),
    );
    _descriptionController =
        TextEditingController(text: widget.category.description ?? '');
    _maxAmountController = TextEditingController(
      text: widget.category.maxCashbackAmount == null
          ? ''
          : _number(widget.category.maxCashbackAmount!),
    );
    _minAmountController = TextEditingController(
      text: widget.category.minPurchaseAmount == null
          ? ''
          : _number(widget.category.minPurchaseAmount!),
    );
    _startDate = DateUtils.dateOnly(widget.category.startDate);
    _endDate = DateUtils.dateOnly(widget.category.endDate);
    _cardId = widget.category.cardId;
    _categoryType = widget.category.categoryType;
  }

  @override
  void dispose() {
    _nameController.dispose();
    _percentController.dispose();
    _descriptionController.dispose();
    _maxAmountController.dispose();
    _minAmountController.dispose();
    super.dispose();
  }

  double? _parseNumber(String value) {
    final normalized =
        value.replaceAll(RegExp(r'\s+'), '').replaceAll(',', '.');
    return double.tryParse(normalized);
  }

  bool get _dirty {
    return _nameController.text.trim() != widget.category.name ||
        _parseNumber(_percentController.text) !=
            widget.category.cashbackPercent ||
        _descriptionController.text.trim() !=
            (widget.category.description ?? '') ||
        _parseNumber(_maxAmountController.text) !=
            widget.category.maxCashbackAmount ||
        _parseNumber(_minAmountController.text) !=
            widget.category.minPurchaseAmount ||
        _startDate != DateUtils.dateOnly(widget.category.startDate) ||
        _endDate != DateUtils.dateOnly(widget.category.endDate) ||
        _cardId != widget.category.cardId ||
        _categoryType != widget.category.categoryType;
  }

  Future<bool> _confirmDiscard() async {
    if (!_editing || !_dirty) return true;
    return await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Отменить изменения?'),
            content: const Text('Несохранённые данные будут потеряны.'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Продолжить редактирование'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('Отменить изменения'),
              ),
            ],
          ),
        ) ??
        false;
  }

  Future<void> _cancelEditing() async {
    if (!await _confirmDiscard()) return;
    setState(() {
      _editing = false;
      _saveError = null;
      _submitted = false;
    });
  }

  Future<void> _pickDate(bool start) async {
    final initial = start ? _startDate : _endDate;
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(2020),
      lastDate: DateTime(2035),
    );
    if (picked == null || !mounted) return;
    setState(() {
      if (start) {
        _startDate = DateUtils.dateOnly(picked);
      } else {
        _endDate = DateUtils.dateOnly(picked);
      }
    });
  }

  Future<void> _save() async {
    setState(() {
      _submitted = true;
      _saveError = null;
    });
    if (!_formKey.currentState!.validate()) return;
    if (_endDate.isBefore(_startDate)) return;

    setState(() => _saving = true);
    final updated = widget.category.copyWith(
      name: _nameController.text.trim(),
      cashbackPercent: _parseNumber(_percentController.text),
      description: _descriptionController.text.trim(),
      startDate: _startDate,
      endDate: DateTime(
        _endDate.year,
        _endDate.month,
        _endDate.day,
        23,
        59,
        59,
        999,
      ),
      cardId: _cardId,
      categoryType: _categoryType,
      maxCashbackAmount: _parseNumber(_maxAmountController.text),
      minPurchaseAmount: _parseNumber(_minAmountController.text),
      clearMaxCashbackAmount: _maxAmountController.text.trim().isEmpty,
      clearMinPurchaseAmount: _minAmountController.text.trim().isEmpty,
    );
    try {
      final saver = widget.onSave ??
          Provider.of<DataProvider>(context, listen: false)
              .updateCashbackCategory;
      await saver(updated);
      if (!mounted) return;
      setState(() {
        _editing = false;
        _saving = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Изменения сохранены')),
      );
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _saveError = 'Не удалось сохранить изменения. ${error.toString()}';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<DataProvider>();
    final canEdit = provider.canEdit && _knownType;
    final compact = MediaQuery.sizeOf(context).width < 600;

    return PopScope(
      canPop: !_editing || !_dirty,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop || !await _confirmDiscard() || !context.mounted) return;
        Navigator.of(context).pop();
      },
      child: Scaffold(
        appBar: compact
            ? null
            : AppBar(
                title: const Text('Категория по карте'),
                actions: [
                  if (!_editing && canEdit)
                    TextButton.icon(
                      onPressed: () => setState(() => _editing = true),
                      icon: const Icon(Icons.edit_outlined),
                      label: const Text('Редактировать'),
                    ),
                ],
              ),
        bottomNavigationBar: compact
            ? _editing
                ? _buildCompactEditBar()
                : NavigationBar(
                    selectedIndex: 0,
                    onDestinationSelected: _selectShellDestination,
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
                  )
            : null,
        body: SafeArea(
          top: compact,
          child: LayoutBuilder(
            builder: (context, constraints) {
              final expanded = constraints.maxWidth >= 840;
              final medium = constraints.maxWidth >= 600;
              if (!medium) {
                return _editing
                    ? _buildCompactEditor(provider)
                    : _buildCompact(provider, canEdit: canEdit);
              }
              final summary = _SummaryCard(
                category: widget.category,
                provider: provider,
              );
              final content = _editing
                  ? _buildForm(provider, twoColumns: medium)
                  : _buildReadOnly(provider, canEdit: canEdit);

              if (expanded) {
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    SizedBox(
                      width: 360,
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.fromLTRB(24, 24, 16, 32),
                        child: summary,
                      ),
                    ),
                    const VerticalDivider(width: 1),
                    Expanded(child: content),
                  ],
                );
              }

              return CustomScrollView(
                slivers: [
                  SliverPadding(
                    padding: EdgeInsets.fromLTRB(
                      medium ? 32 : 16,
                      16,
                      medium ? 32 : 16,
                      0,
                    ),
                    sliver: SliverToBoxAdapter(child: summary),
                  ),
                  SliverFillRemaining(
                    hasScrollBody: false,
                    child: content,
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  void _selectShellDestination(int index) {
    Navigator.of(context).pop();
    if (index != 0) widget.onShellDestinationSelected?.call(index);
  }

  Widget _buildCompactEditBar() {
    return SafeArea(
      top: false,
      child: Material(
        color: Theme.of(context).colorScheme.surface,
        elevation: 8,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
          child: Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: _saving ? null : _cancelEditing,
                  child: const Text('Отмена'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                flex: 2,
                child: FilledButton(
                  onPressed: _saving ? null : _save,
                  child: _saving
                      ? const SizedBox.square(
                          dimension: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Text('Сохранить изменения'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCompactEditor(DataProvider provider) {
    return ColoredBox(
      color: Theme.of(context).colorScheme.surface,
      child: Column(
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(8, 2, 16, 14),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surface,
              border: Border(
                bottom: BorderSide(
                  color: Theme.of(context).colorScheme.outlineVariant,
                ),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextButton.icon(
                  onPressed: _saving ? null : _cancelEditing,
                  icon: const Icon(Icons.arrow_back, size: 20),
                  label: const Text('К карточке'),
                ),
                Padding(
                  padding: const EdgeInsets.only(left: 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Редактирование',
                        style:
                            Theme.of(context).textTheme.headlineSmall?.copyWith(
                                  color: const Color(0xFF102B52),
                                  fontWeight: FontWeight.w800,
                                ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        'Изменения относятся только к этому предложению',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: _buildForm(
              provider,
              twoColumns: false,
              inlineActions: false,
              compact: true,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCompact(DataProvider provider, {required bool canEdit}) {
    final category = widget.category;
    final card = _findCard(provider, category.cardId);
    final bank = card == null
        ? null
        : provider.banks
            .where((item) => item.id == card.bankId)
            .map((item) => item.name)
            .firstOrNull;
    final owner = card == null
        ? null
        : provider.users
            .where((item) => item.id == card.userId)
            .map((item) => item.name)
            .firstOrNull;
    final cardText = card == null
        ? 'Карта недоступна · ID ${category.cardId}'
        : '${bank ?? 'Банк не указан'} · ${card.lastFourDigits ?? '????'}';
    final subtitle =
        provider.canEdit ? 'Сентябрь 2026' : 'Только просмотр · сентябрь 2026';

    return CustomScrollView(
      slivers: [
        SliverToBoxAdapter(
          child: Container(
            color: Theme.of(context).colorScheme.surface,
            padding: const EdgeInsets.fromLTRB(8, 2, 16, 14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextButton.icon(
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(Icons.arrow_back, size: 20),
                  label: const Text('К выгоде'),
                ),
                Padding(
                  padding: const EdgeInsets.only(left: 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Категория по карте',
                        style:
                            Theme.of(context).textTheme.headlineSmall?.copyWith(
                                  color: const Color(0xFF102B52),
                                  fontWeight: FontWeight.w800,
                                ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        subtitle,
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
          sliver: SliverToBoxAdapter(
            child: Column(
              children: [
                _MobileCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _typeLabel(category.categoryType),
                        style: Theme.of(context).textTheme.labelSmall?.copyWith(
                              color: Theme.of(context)
                                  .colorScheme
                                  .onSurfaceVariant,
                              fontWeight: FontWeight.w800,
                              letterSpacing: .8,
                            ),
                      ),
                      const SizedBox(height: 8),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  category.name,
                                  style: Theme.of(context)
                                      .textTheme
                                      .titleLarge
                                      ?.copyWith(fontWeight: FontWeight.w800),
                                ),
                                const SizedBox(height: 7),
                                Text(
                                  cardText,
                                  style: const TextStyle(
                                    color: Color(0xFF344A65),
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                if (owner != null) ...[
                                  const SizedBox(height: 2),
                                  Text(
                                    owner,
                                    style:
                                        Theme.of(context).textTheme.bodySmall,
                                  ),
                                ],
                              ],
                            ),
                          ),
                          const SizedBox(width: 12),
                          Text(
                            '${_number(category.cashbackPercent)}%',
                            style: Theme.of(context)
                                .textTheme
                                .headlineMedium
                                ?.copyWith(
                                  color: const Color(0xFFCF6500),
                                  fontWeight: FontWeight.w900,
                                ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 15),
                      Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: [
                          _MobileStatusChip(
                            positive: category.isSelected,
                            icon: category.isSelected
                                ? Icons.check
                                : Icons.remove,
                            label:
                                category.isSelected ? 'В плане' : 'Не в плане',
                          ),
                          _MobileStatusChip(
                            positive: category.isBankConfirmed,
                            waiting: !category.isBankConfirmed,
                            icon: category.isBankConfirmed
                                ? Icons.check
                                : Icons.schedule_outlined,
                            label: category.isBankConfirmed
                                ? 'Подтверждено банком'
                                : 'Ждёт банк',
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 13,
                          vertical: 11,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF1F5FA),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              _formatPeriod(
                                  category.startDate, category.endDate),
                              style:
                                  const TextStyle(fontWeight: FontWeight.w800),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              'Период действия предложения',
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 10),
                _MobileCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const _SectionTitle('Условия'),
                      Text(
                        (category.description?.trim().isNotEmpty ?? false)
                            ? category.description!.trim()
                            : 'Банк не указал',
                        style: const TextStyle(
                          color: Color(0xFF40536A),
                          height: 1.55,
                        ),
                      ),
                      const SizedBox(height: 9),
                      _FactRow(
                        label: 'Максимум',
                        value: _moneyOrMissing(category.maxCashbackAmount),
                      ),
                      _FactRow(
                        label: 'Покупка от',
                        value: _moneyOrMissing(category.minPurchaseAmount),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 10),
                _MobileCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const _SectionTitle('План и подтверждение'),
                      _MobileStatusRow(
                        positive: category.isSelected,
                        icon: category.isSelected ? Icons.check : Icons.remove,
                        title: category.isSelected
                            ? 'Добавлено в план'
                            : 'Не добавлено в план',
                        subtitle: category.isSelectionLocked
                            ? 'Выбор зафиксирован банком'
                            : 'Намерение сохранено',
                      ),
                      const SizedBox(height: 10),
                      _MobileStatusRow(
                        positive: category.isBankConfirmed,
                        waiting: !category.isBankConfirmed,
                        icon: category.isBankConfirmed
                            ? Icons.check
                            : Icons.schedule_outlined,
                        title: category.isBankConfirmed
                            ? 'Подтверждено банком'
                            : 'Ждёт подтверждения',
                        subtitle: category.isBankConfirmed
                            ? 'Категория найдена в банковском снимке'
                            : 'Нужен банковский снимок',
                      ),
                      if (!provider.canEdit) ...[
                        const SizedBox(height: 12),
                        Container(
                          padding: const EdgeInsets.all(11),
                          decoration: BoxDecoration(
                            color: const Color(0xFFF1F5F9),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: const Text(
                            'Значения доступны только для просмотра. Изменение данных доступно редактору семейного пространства.',
                            style: TextStyle(
                              color: Color(0xFF51657D),
                              fontSize: 12,
                            ),
                          ),
                        ),
                      ],
                      if (canEdit) ...[
                        const SizedBox(height: 14),
                        FilledButton(
                          onPressed: () => setState(() => _editing = true),
                          child: const Text('Редактировать данные'),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildReadOnly(DataProvider provider, {required bool canEdit}) {
    final category = widget.category;
    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(
        MediaQuery.sizeOf(context).width >= 600 ? 32 : 16,
        24,
        MediaQuery.sizeOf(context).width >= 600 ? 32 : 16,
        40,
      ),
      child: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (!provider.canEdit)
                Text(
                  'Только просмотр',
                  style: Theme.of(context).textTheme.labelLarge,
                ),
              if (provider.canEdit && !_knownType)
                const _InfoBanner(
                  icon: Icons.lock_outline,
                  text:
                      'Неизвестный тип предложения доступен только для просмотра.',
                ),
              const _SectionTitle('Условия'),
              Text(
                (category.description?.trim().isNotEmpty ?? false)
                    ? category.description!.trim()
                    : 'Банк не указал',
              ),
              const SizedBox(height: 16),
              _FactRow(
                label: 'Максимальный кешбэк',
                value: _moneyOrMissing(category.maxCashbackAmount),
              ),
              _FactRow(
                label: 'Минимальная покупка',
                value: _moneyOrMissing(category.minPurchaseAmount),
              ),
              const SizedBox(height: 28),
              const _SectionTitle('План и подтверждение'),
              _StatusRow(
                icon: category.isSelected
                    ? Icons.check_circle_outline
                    : Icons.remove_circle_outline,
                title: category.isSelected ? 'Добавлено в план' : 'Не в плане',
                subtitle: category.isSelectionLocked
                    ? 'Выбор зафиксирован банком'
                    : 'Намерение хранится в локальном плане',
              ),
              const SizedBox(height: 12),
              _StatusRow(
                icon: category.isBankConfirmed
                    ? Icons.verified_outlined
                    : Icons.schedule_outlined,
                title: category.isBankConfirmed
                    ? 'Подтверждено банком'
                    : 'Ждёт подтверждения',
                subtitle: category.isBankConfirmed
                    ? 'Категория найдена в банковском снимке'
                    : 'Нужен свежий банковский снимок',
              ),
              if (widget.onOpenPlan != null) ...[
                const SizedBox(height: 16),
                OutlinedButton.icon(
                  onPressed: widget.onOpenPlan,
                  icon: const Icon(Icons.event_note_outlined),
                  label: const Text('Открыть в плане'),
                ),
              ],
              if (canEdit) ...[
                const SizedBox(height: 24),
                FilledButton.icon(
                  onPressed: () => setState(() => _editing = true),
                  icon: const Icon(Icons.edit_outlined),
                  label: const Text('Редактировать данные'),
                ),
              ],
              const SizedBox(height: 24),
              Text(
                'Технический ID: ${category.id}',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildForm(
    DataProvider provider, {
    required bool twoColumns,
    bool inlineActions = true,
    bool compact = false,
  }) {
    final cardItems = provider.cards
        .where((card) => card.id != null)
        .map(
          (card) => DropdownMenuItem<int>(
            value: card.id,
            child: Text(_cardLabel(provider, card)),
          ),
        )
        .toList();
    final selectedCardExists = cardItems.any((item) => item.value == _cardId);
    Widget labeled(String label, Widget child, {String? helper}) => compact
        ? _CompactLabeledField(label: label, helper: helper, child: child)
        : child;
    InputDecoration decoration(
      String label, {
      String? helper,
      String? counter,
      bool alignLabelWithHint = false,
    }) =>
        InputDecoration(
          labelText: compact ? null : label,
          helperText: compact ? null : helper,
          counterText: counter,
          alignLabelWithHint: alignLabelWithHint,
          border: const OutlineInputBorder(),
        );

    return Form(
      key: _formKey,
      autovalidateMode: _submitted
          ? AutovalidateMode.always
          : AutovalidateMode.onUserInteraction,
      child: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(
          compact ? 16 : (MediaQuery.sizeOf(context).width >= 600 ? 32 : 16),
          compact ? 20 : 24,
          compact ? 16 : (MediaQuery.sizeOf(context).width >= 600 ? 32 : 16),
          compact ? 24 : 32 + MediaQuery.paddingOf(context).bottom,
        ),
        child: Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 760),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (_saveError != null) ...[
                  _InfoBanner(
                    icon: Icons.error_outline,
                    text: _saveError!,
                    actionLabel: 'Повторить',
                    onAction: _save,
                  ),
                  const SizedBox(height: 20),
                ],
                if (_submitted &&
                    (!_formKey.currentState!.validate() ||
                        _endDate.isBefore(_startDate))) ...[
                  const _InfoBanner(
                    icon: Icons.info_outline,
                    text: 'Проверьте отмеченные поля перед сохранением.',
                  ),
                  const SizedBox(height: 20),
                ],
                const _SectionTitle('Основное'),
                _FieldGrid(
                  twoColumns: twoColumns,
                  children: [
                    labeled(
                      'Название *',
                      TextFormField(
                        key: const Key('category-name-field'),
                        controller: _nameController,
                        maxLength: 50,
                        textInputAction: TextInputAction.next,
                        decoration: decoration('Название *', counter: ''),
                        validator: (value) =>
                            value == null || value.trim().isEmpty
                                ? 'Введите название категории'
                                : null,
                      ),
                    ),
                    labeled(
                      'Кешбэк, % *',
                      TextFormField(
                        key: const Key('category-percent-field'),
                        controller: _percentController,
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        inputFormatters: [
                          FilteringTextInputFormatter.allow(
                            RegExp(r'[0-9.,\-]'),
                          ),
                        ],
                        decoration: decoration(
                          'Кешбэк, % *',
                          helper: 'Можно использовать точку или запятую',
                        ),
                        validator: (value) {
                          final number = _parseNumber(value ?? '');
                          if (number == null || !number.isFinite) {
                            return 'Введите число';
                          }
                          if (number < 0) {
                            return 'Значение не может быть отрицательным';
                          }
                          return null;
                        },
                      ),
                      helper: 'Можно использовать точку или запятую',
                    ),
                    labeled(
                      'Тип *',
                      DropdownButtonFormField<String>(
                        initialValue: _categoryType,
                        decoration: decoration('Тип *'),
                        items: const [
                          DropdownMenuItem(
                            value: 'standard',
                            child: Text('Обычная'),
                          ),
                          DropdownMenuItem(
                            value: 'stackable_bonus',
                            child: Text('Дополнительная'),
                          ),
                          DropdownMenuItem(
                            value: 'task_bonus',
                            child: Text('За задание'),
                          ),
                        ],
                        onChanged: (value) =>
                            setState(() => _categoryType = value!),
                      ),
                    ),
                    labeled(
                      'Карта *',
                      DropdownButtonFormField<int>(
                        initialValue: selectedCardExists ? _cardId : null,
                        isExpanded: true,
                        decoration: decoration('Карта *'),
                        items: cardItems,
                        onChanged: (value) => setState(() => _cardId = value!),
                        validator: (value) => value == null
                            ? 'Выберите существующую карту'
                            : null,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 28),
                const _SectionTitle('Период'),
                _FieldGrid(
                  twoColumns: twoColumns,
                  children: [
                    labeled(
                      'Начало *',
                      _DateField(
                        label: 'Начало *',
                        value: _formatNumericDate(_startDate),
                        showLabel: !compact,
                        onTap: () => _pickDate(true),
                      ),
                    ),
                    labeled(
                      'Окончание *',
                      _DateField(
                        label: 'Окончание *',
                        value: _formatNumericDate(_endDate),
                        showLabel: !compact,
                        error: _submitted && _endDate.isBefore(_startDate)
                            ? 'Окончание не может быть раньше начала'
                            : null,
                        onTap: () => _pickDate(false),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 28),
                const _SectionTitle('Условия'),
                labeled(
                  'Описание',
                  TextFormField(
                    controller: _descriptionController,
                    minLines: 3,
                    maxLines: 6,
                    decoration: decoration(
                      'Описание',
                      alignLabelWithHint: true,
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                _FieldGrid(
                  twoColumns: twoColumns,
                  children: [
                    labeled(
                      'Максимальный кешбэк, ₽',
                      _amountField(
                        controller: _maxAmountController,
                        label: 'Максимальный кешбэк, ₽',
                        compact: compact,
                      ),
                      helper: 'Пусто — банк не указал',
                    ),
                    labeled(
                      'Минимальная покупка, ₽',
                      _amountField(
                        controller: _minAmountController,
                        label: 'Минимальная покупка, ₽',
                        compact: compact,
                      ),
                      helper: 'Пусто — банк не указал',
                    ),
                  ],
                ),
                const SizedBox(height: 28),
                const _SectionTitle('План'),
                _InfoBanner(
                  icon: Icons.info_outline,
                  text: widget.category.isSelected
                      ? 'Категория добавлена в план. Назначение изменяется только на экране «План».'
                      : 'Категория не добавлена в план. Назначение изменяется только на экране «План».',
                ),
                if (widget.category.isBankConfirmed) ...[
                  const SizedBox(height: 16),
                  const _InfoBanner(
                    icon: Icons.warning_amber_rounded,
                    text:
                        'Банковское подтверждение будет отозвано после изменения условий.',
                  ),
                ],
                const SizedBox(height: 24),
                Text(
                  'Технический ID: ${widget.category.id}',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                if (inlineActions) ...[
                  const SizedBox(height: 24),
                  Wrap(
                    alignment: WrapAlignment.end,
                    spacing: 12,
                    runSpacing: 12,
                    children: [
                      OutlinedButton(
                        onPressed: _saving ? null : _cancelEditing,
                        child: const Text('Отмена'),
                      ),
                      FilledButton.icon(
                        onPressed: _saving ? null : _save,
                        icon: _saving
                            ? const SizedBox.square(
                                dimension: 18,
                                child:
                                    CircularProgressIndicator(strokeWidth: 2),
                              )
                            : const Icon(Icons.save_outlined),
                        label: Text(
                          _saving ? 'Сохранение…' : 'Сохранить изменения',
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _amountField({
    required TextEditingController controller,
    required String label,
    bool compact = false,
  }) {
    return TextFormField(
      controller: controller,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      inputFormatters: [
        FilteringTextInputFormatter.allow(RegExp(r'[0-9.,\-\s]')),
      ],
      decoration: InputDecoration(
        labelText: compact ? null : label,
        helperText: compact ? null : 'Пусто — банк не указал',
        border: const OutlineInputBorder(),
      ),
      validator: (value) {
        if (value == null || value.trim().isEmpty) return null;
        final number = _parseNumber(value);
        if (number == null || !number.isFinite) return 'Введите число';
        if (number < 0) return 'Значение не может быть отрицательным';
        return null;
      },
    );
  }
}

class _MobileCard extends StatelessWidget {
  const _MobileCard({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(15),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          border: Border.all(color: Theme.of(context).colorScheme.outline),
          borderRadius: BorderRadius.circular(15),
        ),
        child: child,
      );
}

class _MobileStatusChip extends StatelessWidget {
  const _MobileStatusChip({
    required this.positive,
    required this.icon,
    required this.label,
    this.waiting = false,
  });

  final bool positive;
  final bool waiting;
  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    final foreground = waiting
        ? const Color(0xFF8B5208)
        : positive
            ? const Color(0xFF126B50)
            : Theme.of(context).colorScheme.onSurfaceVariant;
    final background = waiting
        ? const Color(0xFFFFF3DC)
        : positive
            ? const Color(0xFFE7F6EF)
            : const Color(0xFFEEF2F6);
    return Container(
      constraints: const BoxConstraints(minHeight: 28),
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(9),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: foreground),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              label,
              style: TextStyle(
                color: foreground,
                fontSize: 12,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _MobileStatusRow extends StatelessWidget {
  const _MobileStatusRow({
    required this.positive,
    required this.icon,
    required this.title,
    required this.subtitle,
    this.waiting = false,
  });

  final bool positive;
  final bool waiting;
  final IconData icon;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    final foreground = waiting
        ? const Color(0xFF8B5208)
        : positive
            ? const Color(0xFF126B50)
            : Theme.of(context).colorScheme.onSurfaceVariant;
    final background = waiting
        ? const Color(0xFFFFF3DC)
        : positive
            ? const Color(0xFFE7F6EF)
            : const Color(0xFFEEF2F6);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 28,
          height: 28,
          decoration: BoxDecoration(
            color: background,
            borderRadius: BorderRadius.circular(9),
          ),
          alignment: Alignment.center,
          child: Icon(icon, size: 16, color: foreground),
        ),
        const SizedBox(width: 9),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 13,
                ),
              ),
              const SizedBox(height: 1),
              Text(subtitle, style: Theme.of(context).textTheme.bodySmall),
            ],
          ),
        ),
      ],
    );
  }
}

class _SummaryCard extends StatelessWidget {
  const _SummaryCard({required this.category, required this.provider});

  final CashbackCategoryModel category;
  final DataProvider provider;

  @override
  Widget build(BuildContext context) {
    final card = _findCard(provider, category.cardId);
    final cardText = card == null
        ? 'Карта недоступна · ID ${category.cardId}'
        : _cardLabel(provider, card);

    return Card(
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              _typeLabel(category.categoryType),
              style: Theme.of(context).textTheme.labelLarge?.copyWith(
                    color: Theme.of(context).colorScheme.primary,
                  ),
            ),
            const SizedBox(height: 10),
            Wrap(
              alignment: WrapAlignment.spaceBetween,
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 20,
              runSpacing: 8,
              children: [
                Text(
                  category.name,
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                ),
                Text(
                  '${_number(category.cashbackPercent)}%',
                  style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                        color: Theme.of(context).colorScheme.primary,
                        fontWeight: FontWeight.w800,
                      ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(cardText),
            const SizedBox(height: 16),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _StatusChip(
                  label: category.isSelected ? 'В плане' : 'Не в плане',
                  icon: category.isSelected
                      ? Icons.check_outlined
                      : Icons.remove_outlined,
                ),
                _StatusChip(
                  label: category.isBankConfirmed
                      ? 'Подтверждено банком'
                      : 'Ждёт подтверждения',
                  icon: category.isBankConfirmed
                      ? Icons.verified_outlined
                      : Icons.schedule_outlined,
                ),
              ],
            ),
            const SizedBox(height: 18),
            Text(
              _formatPeriod(category.startDate, category.endDate),
              style: Theme.of(context).textTheme.titleSmall,
            ),
            const SizedBox(height: 2),
            Text(
              'Период действия предложения',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.label, required this.icon});

  final String label;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Chip(
      avatar: Icon(icon, size: 18),
      label: Text(label),
      visualDensity: VisualDensity.compact,
    );
  }
}

class _StatusRow extends StatelessWidget {
  const _StatusRow({
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  final IconData icon;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      container: true,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ExcludeSemantics(
            child: Icon(icon, color: Theme.of(context).colorScheme.primary),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: Theme.of(context).textTheme.titleSmall),
                const SizedBox(height: 2),
                Text(subtitle),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _InfoBanner extends StatelessWidget {
  const _InfoBanner({
    required this.icon,
    required this.text,
    this.actionLabel,
    this.onAction,
  });

  final IconData icon;
  final String text;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Theme.of(context).colorScheme.secondaryContainer,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ExcludeSemantics(child: Icon(icon)),
            const SizedBox(width: 12),
            Expanded(child: Text(text)),
            if (actionLabel != null) ...[
              const SizedBox(width: 8),
              TextButton(onPressed: onAction, child: Text(actionLabel!)),
            ],
          ],
        ),
      ),
    );
  }
}

class _FactRow extends StatelessWidget {
  const _FactRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(child: Text(label)),
          const SizedBox(width: 16),
          Flexible(
            child: Text(
              value,
              textAlign: TextAlign.end,
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }
}

class _FieldGrid extends StatelessWidget {
  const _FieldGrid({required this.twoColumns, required this.children});

  final bool twoColumns;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    if (!twoColumns) {
      return Column(
        children: [
          for (var i = 0; i < children.length; i++) ...[
            children[i],
            if (i != children.length - 1) const SizedBox(height: 16),
          ],
        ],
      );
    }
    return Wrap(
      spacing: 16,
      runSpacing: 16,
      children: children
          .map(
            (child) => SizedBox(
              width: (760 - 16) / 2,
              child: child,
            ),
          )
          .toList(),
    );
  }
}

class _DateField extends StatelessWidget {
  const _DateField({
    required this.label,
    required this.value,
    required this.onTap,
    this.error,
    this.showLabel = true,
  });

  final String label;
  final String value;
  final VoidCallback onTap;
  final String? error;
  final bool showLabel;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(4),
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: showLabel ? label : null,
          border: const OutlineInputBorder(),
          errorText: error,
          suffixIcon: const Icon(Icons.calendar_today_outlined),
        ),
        child: Text(value),
      ),
    );
  }
}

class _CompactLabeledField extends StatelessWidget {
  const _CompactLabeledField({
    required this.label,
    required this.child,
    this.helper,
  });

  final String label;
  final Widget child;
  final String? helper;

  @override
  Widget build(BuildContext context) {
    final required = label.endsWith(' *');
    final plainLabel = required ? label.substring(0, label.length - 2) : label;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text.rich(
          TextSpan(
            children: [
              TextSpan(text: plainLabel),
              if (required)
                TextSpan(
                  text: ' *',
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
            ],
          ),
          style: Theme.of(context).textTheme.labelMedium?.copyWith(
                color: const Color(0xFF344A64),
                fontWeight: FontWeight.w800,
              ),
        ),
        const SizedBox(height: 5),
        child,
        if (helper != null) ...[
          const SizedBox(height: 4),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 2),
            child: Text(
              helper!,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    fontSize: 11,
                  ),
            ),
          ),
        ],
      ],
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Text(text, style: Theme.of(context).textTheme.titleLarge),
    );
  }
}

CardModel? _findCard(DataProvider provider, int id) {
  for (final card in provider.cards) {
    if (card.id == id) return card;
  }
  return null;
}

String _cardLabel(DataProvider provider, CardModel card) {
  final bank = provider.banks
      .where((item) => item.id == card.bankId)
      .map((item) => item.name)
      .firstOrNull;
  final owner = provider.users
      .where((item) => item.id == card.userId)
      .map((item) => item.name)
      .firstOrNull;
  final base = '${bank ?? 'Банк не указан'} · ${card.lastFourDigits ?? '????'}';
  return owner == null ? base : '$base · $owner';
}

String _typeLabel(String type) {
  return switch (type) {
    'standard' => 'Обычная категория',
    'stackable_bonus' => 'Дополнительная категория',
    'task_bonus' => 'Категория за задание',
    _ => 'Неизвестный тип: $type',
  };
}

String _number(double value) {
  return value == value.roundToDouble()
      ? value.toInt().toString()
      : value.toString().replaceAll('.', ',');
}

String _moneyOrMissing(double? value) {
  if (value == null) return 'Банк не указал';
  final digits = value == value.roundToDouble()
      ? value.toInt().toString()
      : value.toStringAsFixed(2).replaceAll('.', ',');
  return '${digits.replaceAllMapped(RegExp(r'(?<=\d)(?=(\d{3})+(?!\d))'), (_) => ' ')} ₽';
}

String _formatNumericDate(DateTime date) {
  return '${date.day.toString().padLeft(2, '0')}.'
      '${date.month.toString().padLeft(2, '0')}.${date.year}';
}

String _formatPeriod(DateTime start, DateTime end) {
  const months = [
    'января',
    'февраля',
    'марта',
    'апреля',
    'мая',
    'июня',
    'июля',
    'августа',
    'сентября',
    'октября',
    'ноября',
    'декабря',
  ];
  if (start.year == end.year && start.month == end.month) {
    return '${start.day}–${end.day} ${months[start.month - 1]} ${start.year}';
  }
  return '${_formatNumericDate(start)} — ${_formatNumericDate(end)}';
}
