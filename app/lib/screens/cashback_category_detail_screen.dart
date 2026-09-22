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
  });

  final CashbackCategoryModel category;
  final VoidCallback? onOpenPlan;
  final CashbackCategorySaver? onSave;

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

  bool get _confirmationWillBeRevoked {
    if (!widget.category.isBankConfirmed) return false;
    return _nameController.text.trim() != widget.category.name ||
        _parseNumber(_percentController.text) !=
            widget.category.cashbackPercent ||
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

    return PopScope(
      canPop: !_editing || !_dirty,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop || !await _confirmDiscard() || !context.mounted) return;
        Navigator.of(context).pop();
      },
      child: Scaffold(
        appBar: AppBar(
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
        body: SafeArea(
          top: false,
          child: LayoutBuilder(
            builder: (context, constraints) {
              final expanded = constraints.maxWidth >= 840;
              final medium = constraints.maxWidth >= 600;
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

  Widget _buildForm(DataProvider provider, {required bool twoColumns}) {
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

    return Form(
      key: _formKey,
      autovalidateMode: _submitted
          ? AutovalidateMode.always
          : AutovalidateMode.onUserInteraction,
      child: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(
          MediaQuery.sizeOf(context).width >= 600 ? 32 : 16,
          24,
          MediaQuery.sizeOf(context).width >= 600 ? 32 : 16,
          32 + MediaQuery.paddingOf(context).bottom,
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
                    TextFormField(
                      key: const Key('category-name-field'),
                      controller: _nameController,
                      maxLength: 50,
                      textInputAction: TextInputAction.next,
                      decoration: const InputDecoration(
                        labelText: 'Название *',
                        border: OutlineInputBorder(),
                      ),
                      validator: (value) =>
                          value == null || value.trim().isEmpty
                              ? 'Введите название категории'
                              : null,
                    ),
                    TextFormField(
                      key: const Key('category-percent-field'),
                      controller: _percentController,
                      keyboardType:
                          const TextInputType.numberWithOptions(decimal: true),
                      inputFormatters: [
                        FilteringTextInputFormatter.allow(RegExp(r'[0-9.,\-]')),
                      ],
                      decoration: const InputDecoration(
                        labelText: 'Кешбэк, % *',
                        border: OutlineInputBorder(),
                        helperText: 'Точка или запятая',
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
                    DropdownButtonFormField<String>(
                      initialValue: _categoryType,
                      decoration: const InputDecoration(
                        labelText: 'Тип *',
                        border: OutlineInputBorder(),
                      ),
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
                    DropdownButtonFormField<int>(
                      initialValue: selectedCardExists ? _cardId : null,
                      isExpanded: true,
                      decoration: const InputDecoration(
                        labelText: 'Карта *',
                        border: OutlineInputBorder(),
                      ),
                      items: cardItems,
                      onChanged: (value) => setState(() => _cardId = value!),
                      validator: (value) =>
                          value == null ? 'Выберите существующую карту' : null,
                    ),
                  ],
                ),
                const SizedBox(height: 28),
                const _SectionTitle('Период'),
                _FieldGrid(
                  twoColumns: twoColumns,
                  children: [
                    _DateField(
                      label: 'Начало *',
                      value: _formatNumericDate(_startDate),
                      onTap: () => _pickDate(true),
                    ),
                    _DateField(
                      label: 'Окончание *',
                      value: _formatNumericDate(_endDate),
                      error: _submitted && _endDate.isBefore(_startDate)
                          ? 'Окончание не может быть раньше начала'
                          : null,
                      onTap: () => _pickDate(false),
                    ),
                  ],
                ),
                const SizedBox(height: 28),
                const _SectionTitle('Условия'),
                TextFormField(
                  controller: _descriptionController,
                  minLines: 3,
                  maxLines: 6,
                  decoration: const InputDecoration(
                    labelText: 'Описание',
                    alignLabelWithHint: true,
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 16),
                _FieldGrid(
                  twoColumns: twoColumns,
                  children: [
                    _amountField(
                      controller: _maxAmountController,
                      label: 'Максимальный кешбэк, ₽',
                    ),
                    _amountField(
                      controller: _minAmountController,
                      label: 'Минимальная покупка, ₽',
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
                if (_confirmationWillBeRevoked) ...[
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
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.save_outlined),
                      label: Text(
                        _saving ? 'Сохранение…' : 'Сохранить изменения',
                      ),
                    ),
                  ],
                ),
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
  }) {
    return TextFormField(
      controller: controller,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      inputFormatters: [
        FilteringTextInputFormatter.allow(RegExp(r'[0-9.,\-\s]')),
      ],
      decoration: InputDecoration(
        labelText: label,
        helperText: 'Пусто — банк не указал',
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
  });

  final String label;
  final String value;
  final VoidCallback onTap;
  final String? error;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(4),
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: label,
          border: const OutlineInputBorder(),
          errorText: error,
          suffixIcon: const Icon(Icons.calendar_today_outlined),
        ),
        child: Text(value),
      ),
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
