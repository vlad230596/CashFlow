import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../models/card_model.dart';
import '../models/subscription_model.dart';
import '../providers/data_provider.dart';

class SubscriptionsScreen extends StatefulWidget {
  const SubscriptionsScreen({super.key});

  @override
  State<SubscriptionsScreen> createState() => SubscriptionsScreenState();
}

class SubscriptionsScreenState extends State<SubscriptionsScreen> {
  bool _showArchive = false;
  int? _selectedId;

  Future<void> openSubscription(int id) async {
    var item = context
        .read<DataProvider>()
        .subscriptions
        .where((subscription) => subscription.id == id)
        .firstOrNull;
    if (item == null) {
      try {
        item = await context.read<DataProvider>().fetchSubscription(id);
      } catch (_) {
        return;
      }
    }
    if (!mounted) return;
    setState(() {
      _showArchive = item!.isArchived;
      _selectedId = id;
    });
    if (MediaQuery.sizeOf(context).width < 840) {
      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => SubscriptionDetails(subscription: item!),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) => Consumer<DataProvider>(
        builder: (context, provider, _) {
          final items = (_showArchive
                  ? provider.archivedSubscriptions
                  : provider.activeSubscriptions)
              .toList()
            ..sort((a, b) => a.nextPaymentDate.compareTo(b.nextPaymentDate));
          final selected = _selectedSubscription(items);

          return LayoutBuilder(
            builder: (context, constraints) {
              final expanded = constraints.maxWidth >= 840;
              return Scaffold(
                appBar: AppBar(
                  title: const Text('Подписки'),
                  actions: [
                    IconButton(
                      tooltip:
                          _showArchive ? 'Показать активные' : 'Открыть архив',
                      onPressed: () => setState(() {
                        _showArchive = !_showArchive;
                        _selectedId = null;
                      }),
                      icon: Icon(_showArchive
                          ? Icons.inventory_2
                          : Icons.inventory_2_outlined),
                    ),
                  ],
                ),
                floatingActionButton: _showArchive
                    ? null
                    : FloatingActionButton.extended(
                        onPressed: () => _openEditor(context),
                        icon: const Icon(Icons.add),
                        label: const Text('Добавить'),
                      ),
                body: SafeArea(
                  top: false,
                  child: expanded
                      ? Row(
                          children: [
                            SizedBox(
                              width: 430,
                              child: _SubscriptionList(
                                subscriptions: items,
                                archived: _showArchive,
                                selectedId: selected?.id,
                                onSelected: (item) =>
                                    setState(() => _selectedId = item.id),
                                onAdd: () => _openEditor(context),
                              ),
                            ),
                            const VerticalDivider(width: 1),
                            Expanded(
                              child: selected == null
                                  ? const _DetailPlaceholder()
                                  : SubscriptionDetails(
                                      subscription: selected,
                                      embedded: true,
                                      onChanged: () => setState(() {}),
                                    ),
                            ),
                          ],
                        )
                      : _SubscriptionList(
                          subscriptions: items,
                          archived: _showArchive,
                          onSelected: (item) => Navigator.of(context).push(
                            MaterialPageRoute<void>(
                              builder: (_) => SubscriptionDetails(
                                subscription: item,
                              ),
                            ),
                          ),
                          onAdd: () => _openEditor(context),
                        ),
                ),
              );
            },
          );
        },
      );

  SubscriptionModel? _selectedSubscription(List<SubscriptionModel> items) {
    if (items.isEmpty) return null;
    if (_selectedId == null) return items.first;
    for (final item in items) {
      if (item.id == _selectedId) return item;
    }
    return items.first;
  }

  Future<void> _openEditor(BuildContext context) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => const SubscriptionEditScreen()),
    );
  }
}

class _SubscriptionList extends StatelessWidget {
  const _SubscriptionList({
    required this.subscriptions,
    required this.archived,
    required this.onSelected,
    required this.onAdd,
    this.selectedId,
  });

  final List<SubscriptionModel> subscriptions;
  final bool archived;
  final int? selectedId;
  final ValueChanged<SubscriptionModel> onSelected;
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    if (subscriptions.isEmpty) {
      return _EmptySubscriptions(archived: archived, onAdd: onAdd);
    }
    final now = DateTime.now();
    final groups = _groupSubscriptions(subscriptions, now);
    return RefreshIndicator(
      onRefresh: context.read<DataProvider>().fetchSubscriptions,
      child: CustomScrollView(
        slivers: [
          if (!archived)
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              sliver: SliverToBoxAdapter(
                child: _RenewalSummary(subscriptions: subscriptions),
              ),
            ),
          for (final group in groups.entries) ...[
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(20, 18, 20, 8),
              sliver: SliverToBoxAdapter(
                child: Text(
                  group.key,
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w800,
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                ),
              ),
            ),
            SliverPadding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              sliver: SliverList.separated(
                itemCount: group.value.length,
                separatorBuilder: (context, index) => const SizedBox(height: 8),
                itemBuilder: (context, index) {
                  final item = group.value[index];
                  return _SubscriptionTile(
                    subscription: item,
                    selected: selectedId == item.id,
                    onTap: () => onSelected(item),
                  );
                },
              ),
            ),
          ],
          const SliverPadding(padding: EdgeInsets.only(bottom: 96)),
        ],
      ),
    );
  }
}

class _RenewalSummary extends StatelessWidget {
  const _RenewalSummary({required this.subscriptions});

  final List<SubscriptionModel> subscriptions;

  @override
  Widget build(BuildContext context) {
    final now = _dateOnly(DateTime.now());
    final next = subscriptions.first;
    final totals = <String, double>{};
    for (final item in subscriptions) {
      final days = _dateOnly(item.nextPaymentDate).difference(now).inDays;
      if (days >= 0 && days <= 30) {
        totals.update(item.currency, (value) => value + item.expectedAmount,
            ifAbsent: () => item.expectedAmount);
      }
    }
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Ближайшее списание',
                style: Theme.of(context).textTheme.labelLarge),
            const SizedBox(height: 6),
            Text(
              _money(next.expectedAmount, next.currency),
              style: Theme.of(context).textTheme.headlineMedium,
            ),
            const SizedBox(height: 4),
            Text('${next.name} · ${_date(next.nextPaymentDate)}'),
            const Divider(height: 28),
            Text('В ближайшие 30 дней',
                style: Theme.of(context).textTheme.labelLarge),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: totals.entries
                  .map((entry) => Chip(
                        avatar: const Icon(Icons.payments_outlined, size: 18),
                        label: Text(_money(entry.value, entry.key)),
                      ))
                  .toList(),
            ),
          ],
        ),
      ),
    );
  }
}

class _SubscriptionTile extends StatelessWidget {
  const _SubscriptionTile({
    required this.subscription,
    required this.selected,
    required this.onTap,
  });

  final SubscriptionModel subscription;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final provider = context.read<DataProvider>();
    return Card(
      color: selected
          ? Theme.of(context).colorScheme.primaryContainer
          : Theme.of(context).colorScheme.surface,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              CircleAvatar(
                backgroundColor:
                    Theme.of(context).colorScheme.secondaryContainer,
                child: Icon(subscription.kind == SubscriptionKind.trial
                    ? Icons.hourglass_top_outlined
                    : Icons.autorenew_rounded),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(subscription.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.titleMedium),
                    const SizedBox(height: 4),
                    Text(
                      '${_date(subscription.nextPaymentDate)} · ${_normalizedPrice(subscription)}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _cardLabel(provider, subscription.cardId),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    _money(subscription.expectedAmount, subscription.currency),
                    style: Theme.of(context)
                        .textTheme
                        .titleMedium
                        ?.copyWith(fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 8),
                  const Icon(Icons.chevron_right, size: 20),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class SubscriptionDetails extends StatefulWidget {
  const SubscriptionDetails({
    super.key,
    required this.subscription,
    this.embedded = false,
    this.onChanged,
  });

  final SubscriptionModel subscription;
  final bool embedded;
  final VoidCallback? onChanged;

  @override
  State<SubscriptionDetails> createState() => _SubscriptionDetailsState();
}

class _SubscriptionDetailsState extends State<SubscriptionDetails> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadDetail());
  }

  @override
  void didUpdateWidget(covariant SubscriptionDetails oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.subscription.id != widget.subscription.id) _loadDetail();
  }

  Future<void> _loadDetail() async {
    final id = widget.subscription.id;
    if (id == null || !mounted) return;
    try {
      await context.read<DataProvider>().fetchSubscription(id);
    } catch (_) {
      // Cached list data still gives a useful read-only detail view offline.
    }
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<DataProvider>();
    final subscription = provider.subscriptions
            .where((item) => item.id == widget.subscription.id)
            .firstOrNull ??
        widget.subscription;
    final content = Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 720),
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 40),
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(subscription.name,
                      style: Theme.of(context).textTheme.headlineMedium),
                ),
                if (widget.embedded)
                  IconButton(
                    tooltip: 'Редактировать',
                    onPressed: () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) =>
                            SubscriptionEditScreen(existing: subscription),
                      ),
                    ),
                    icon: const Icon(Icons.edit_outlined),
                  ),
              ],
            ),
            const SizedBox(height: 16),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Следующее списание',
                        style: Theme.of(context).textTheme.labelLarge),
                    const SizedBox(height: 6),
                    Text(
                      _money(
                          subscription.expectedAmount, subscription.currency),
                      style: Theme.of(context).textTheme.headlineLarge,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${_date(subscription.nextPaymentDate)} · ${_normalizedPrice(subscription)}',
                    ),
                    const SizedBox(height: 12),
                    _FactRow(
                      icon: Icons.credit_card_outlined,
                      text: _cardLabel(
                          context.read<DataProvider>(), subscription.cardId),
                    ),
                    if (subscription.lastPayment != null)
                      _FactRow(
                        icon: Icons.history_outlined,
                        text:
                            'Последний платёж ${_date(subscription.lastPayment!.paidAt)}',
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            if (!subscription.isArchived)
              FilledButton.icon(
                onPressed: () => _confirmPayment(context),
                icon: const Icon(Icons.check_circle_outline),
                label: const Text('Подтвердить списание'),
              ),
            const SizedBox(height: 24),
            Text('История платежей',
                style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 8),
            if (subscription.payments.isEmpty)
              const Text('Подтверждённых платежей пока нет.')
            else
              ...subscription.payments.toList().reversed.map(
                    (payment) => ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.receipt_long_outlined),
                      title: Text(_money(payment.amount, payment.currency)),
                      subtitle: Text(
                        '${_date(payment.paidAt)} · ${_cardLabel(context.read<DataProvider>(), payment.cardId)}',
                      ),
                    ),
                  ),
            const SizedBox(height: 16),
            Text('Периоды активности',
                style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 8),
            if (subscription.activePeriods.isEmpty)
              const Text('Текущий период начался при добавлении подписки.')
            else
              ...subscription.activePeriods.toList().reversed.map(
                    (period) => ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.calendar_month_outlined),
                      title: Text(period.endedAt == null
                          ? 'Активна с ${_date(period.startedAt)}'
                          : '${_date(period.startedAt)} — ${_date(period.endedAt!)}'),
                    ),
                  ),
            const SizedBox(height: 24),
            OutlinedButton.icon(
              onPressed: () => subscription.isArchived
                  ? _restore(context)
                  : _archive(context),
              icon: Icon(subscription.isArchived
                  ? Icons.unarchive_outlined
                  : Icons.archive_outlined),
              label: Text(subscription.isArchived
                  ? 'Восстановить подписку'
                  : 'Перенести в архив'),
            ),
          ],
        ),
      ),
    );
    if (widget.embedded) return content;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Подписка'),
        actions: [
          IconButton(
            tooltip: 'Редактировать',
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => SubscriptionEditScreen(existing: subscription),
              ),
            ),
            icon: const Icon(Icons.edit_outlined),
          ),
        ],
      ),
      body: SafeArea(top: false, child: content),
    );
  }

  Future<void> _confirmPayment(BuildContext context) async {
    final amount = TextEditingController(
        text: widget.subscription.expectedAmount.toStringAsFixed(2));
    var date = DateTime.now();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: const Text('Списание прошло?'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: amount,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                inputFormatters: [
                  FilteringTextInputFormatter.allow(RegExp(r'[0-9,.]')),
                ],
                decoration: InputDecoration(
                  labelText:
                      'Фактическая сумма, ${widget.subscription.currency}',
                ),
              ),
              const SizedBox(height: 12),
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Дата платежа'),
                subtitle: Text(_date(date)),
                trailing: const Icon(Icons.calendar_today_outlined),
                onTap: () async {
                  final value = await showDatePicker(
                    context: context,
                    initialDate: date,
                    firstDate: DateTime(2000),
                    lastDate: DateTime(2100),
                  );
                  if (value != null) setState(() => date = value);
                },
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Не сейчас'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('Подтвердить'),
            ),
          ],
        ),
      ),
    );
    if (confirmed != true || !context.mounted) return;
    final value = double.tryParse(amount.text.replaceAll(',', '.'));
    if (value == null || value <= 0) return;
    await context.read<DataProvider>().confirmSubscriptionPayment(
          widget.subscription.id!,
          amount: value,
          paidAt: date,
          cardId: widget.subscription.cardId,
        );
    widget.onChanged?.call();
  }

  Future<void> _archive(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Перенести в архив?'),
        content: const Text(
          'Напоминания отключатся, а история платежей сохранится.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Отмена'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('В архив'),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;
    await context
        .read<DataProvider>()
        .archiveSubscription(widget.subscription.id!);
    if (!context.mounted) return;
    widget.onChanged?.call();
    if (!widget.embedded) Navigator.pop(context);
  }

  Future<void> _restore(BuildContext context) async {
    final date = await showDatePicker(
      context: context,
      initialDate: DateTime.now().add(const Duration(days: 1)),
      firstDate: DateTime.now(),
      lastDate: DateTime(2100),
      helpText: 'Следующее списание',
    );
    if (date == null || !context.mounted) return;
    await context
        .read<DataProvider>()
        .restoreSubscription(widget.subscription.id!, nextPaymentDate: date);
    if (!context.mounted) return;
    widget.onChanged?.call();
    if (!widget.embedded) Navigator.pop(context);
  }
}

class SubscriptionEditScreen extends StatefulWidget {
  const SubscriptionEditScreen({super.key, this.existing});

  final SubscriptionModel? existing;

  @override
  State<SubscriptionEditScreen> createState() => _SubscriptionEditScreenState();
}

class _SubscriptionEditScreenState extends State<SubscriptionEditScreen> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _name;
  late final TextEditingController _amount;
  late final TextEditingController _currency;
  int? _cardId;
  var _kind = SubscriptionKind.subscription;
  var _interval = const BillingInterval(
    count: 1,
    unit: BillingIntervalUnit.months,
  );
  late DateTime _nextDate;
  DateTime? _lastDate;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final item = widget.existing;
    _name = TextEditingController(text: item?.name ?? '');
    _amount = TextEditingController(
        text: item == null ? '' : item.expectedAmount.toStringAsFixed(2));
    _currency = TextEditingController(text: item?.currency ?? 'RUB');
    _cardId = item?.cardId;
    _kind = item?.kind ?? SubscriptionKind.subscription;
    _interval = item?.billingInterval ?? _interval;
    _nextDate =
        item?.nextPaymentDate ?? DateTime.now().add(const Duration(days: 30));
    _lastDate = item?.lastPayment?.paidAt;
  }

  @override
  void dispose() {
    _name.dispose();
    _amount.dispose();
    _currency.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cards = context.watch<DataProvider>().cards;
    _cardId ??= cards.firstOrNull?.id;
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.existing == null
            ? 'Новая подписка'
            : 'Редактирование подписки'),
      ),
      body: SafeArea(
        top: false,
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 680),
            child: Form(
              key: _formKey,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
                children: [
                  TextFormField(
                    controller: _name,
                    autofocus: widget.existing == null,
                    textInputAction: TextInputAction.next,
                    decoration: const InputDecoration(labelText: 'Название'),
                    validator: (value) => value == null || value.trim().isEmpty
                        ? 'Введите название подписки'
                        : null,
                  ),
                  const SizedBox(height: 16),
                  SegmentedButton<SubscriptionKind>(
                    segments: const [
                      ButtonSegment(
                        value: SubscriptionKind.subscription,
                        label: Text('Подписка'),
                        icon: Icon(Icons.autorenew),
                      ),
                      ButtonSegment(
                        value: SubscriptionKind.trial,
                        label: Text('Пробный период'),
                        icon: Icon(Icons.hourglass_top_outlined),
                      ),
                    ],
                    selected: {_kind},
                    onSelectionChanged: (value) =>
                        setState(() => _kind = value.first),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        flex: 2,
                        child: TextFormField(
                          controller: _amount,
                          keyboardType: const TextInputType.numberWithOptions(
                              decimal: true),
                          inputFormatters: [
                            FilteringTextInputFormatter.allow(
                                RegExp(r'[0-9,.]')),
                          ],
                          decoration: const InputDecoration(labelText: 'Сумма'),
                          validator: (value) {
                            final parsed = double.tryParse(
                                (value ?? '').replaceAll(',', '.'));
                            return parsed == null || parsed <= 0
                                ? 'Укажите сумму'
                                : null;
                          },
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: TextFormField(
                          controller: _currency,
                          textCapitalization: TextCapitalization.characters,
                          maxLength: 3,
                          decoration: const InputDecoration(
                            labelText: 'Валюта',
                            counterText: '',
                          ),
                          validator: (value) =>
                              value?.trim().length == 3 ? null : '3 буквы',
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  DropdownButtonFormField<int>(
                    initialValue: _cardId,
                    isExpanded: true,
                    decoration: const InputDecoration(labelText: 'Карта'),
                    items: cards
                        .where((card) => card.id != null)
                        .map((card) => DropdownMenuItem(
                              value: card.id,
                              child: Text(
                                _cardLabelFromCard(
                                    context.read<DataProvider>(), card),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ))
                        .toList(),
                    onChanged: (value) => setState(() => _cardId = value),
                    validator: (value) =>
                        value == null ? 'Выберите карту' : null,
                  ),
                  const SizedBox(height: 20),
                  Text('Период оплаты',
                      style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      _IntervalChoice('Месяц', 1, BillingIntervalUnit.months),
                      _IntervalChoice(
                          '3 месяца', 3, BillingIntervalUnit.months),
                      _IntervalChoice(
                          '6 месяцев', 6, BillingIntervalUnit.months),
                      _IntervalChoice('Год', 1, BillingIntervalUnit.years),
                    ].map((choice) {
                      final selected = _interval.count == choice.count &&
                          _interval.unit == choice.unit;
                      return ChoiceChip(
                        label: Text(choice.label),
                        selected: selected,
                        onSelected: (_) => _setInterval(
                          BillingInterval(
                            count: choice.count,
                            unit: choice.unit,
                          ),
                        ),
                      );
                    }).toList()
                      ..add(
                        ChoiceChip(
                          label: const Text('Другой'),
                          selected: !_isPresetInterval(_interval),
                          onSelected: (_) => _chooseCustomInterval(),
                        ),
                      ),
                  ),
                  const SizedBox(height: 20),
                  _DateField(
                    label: 'Последний актуальный платёж (необязательно)',
                    value: _lastDate,
                    onChanged: (value) => setState(() {
                      _lastDate = value;
                      if (value != null) {
                        _nextDate = _addInterval(value, _interval);
                      }
                    }),
                    allowClear: true,
                  ),
                  const SizedBox(height: 12),
                  _DateField(
                    label: 'Следующее списание',
                    value: _nextDate,
                    onChanged: (value) {
                      if (value != null) setState(() => _nextDate = value);
                    },
                  ),
                  const SizedBox(height: 8),
                  Text(
                    _kind == SubscriptionKind.trial
                        ? 'Напомним за 3 и 1 день.'
                        : _interval.unit == BillingIntervalUnit.years
                            ? 'Напомним за 30, 7 и 1 день.'
                            : 'Напомним за 7 и 1 день.',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  const SizedBox(height: 28),
                  FilledButton(
                    onPressed: _saving ? null : _save,
                    child: _saving
                        ? const SizedBox.square(
                            dimension: 22,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Text('Сохранить'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    final amount = double.parse(_amount.text.replaceAll(',', '.'));
    final previous = widget.existing;
    final item = SubscriptionModel(
      id: previous?.id,
      name: _name.text.trim(),
      kind: _kind,
      expectedAmount: amount,
      currency: _currency.text.trim().toUpperCase(),
      cardId: _cardId!,
      billingInterval: _interval,
      nextPaymentDate: _nextDate,
      reminderDays: _kind == SubscriptionKind.trial
          ? const [3, 1]
          : _interval.unit == BillingIntervalUnit.years
              ? const [30, 7, 1]
              : const [7, 1],
      isArchived: previous?.isArchived ?? false,
      archivedAt: previous?.archivedAt,
      createdAt: previous?.createdAt,
      updatedAt: previous?.updatedAt,
      lastPayment: _lastDate == null
          ? previous?.lastPayment
          : SubscriptionPayment(
              id: previous?.lastPayment?.id,
              subscriptionId: previous?.id,
              paidAt: _lastDate!,
              amount: amount,
              currency: _currency.text.trim().toUpperCase(),
              cardId: _cardId!,
            ),
      payments: previous?.payments ?? const [],
      activePeriods: previous?.activePeriods ?? const [],
    );
    try {
      final provider = context.read<DataProvider>();
      if (previous == null) {
        await provider.createSubscription(item);
        await provider.requestSubscriptionNotificationPermission();
      } else {
        await provider.updateSubscription(item);
      }
      if (mounted) Navigator.pop(context);
    } catch (error) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Не удалось сохранить: $error')),
      );
    }
  }

  void _setInterval(BillingInterval interval) {
    setState(() {
      _interval = interval;
      if (_lastDate != null) {
        _nextDate = _addInterval(_lastDate!, interval);
      }
    });
  }

  Future<void> _chooseCustomInterval() async {
    final countController = TextEditingController(
      text: _isPresetInterval(_interval) ? '1' : _interval.count.toString(),
    );
    var unit = _isPresetInterval(_interval)
        ? BillingIntervalUnit.months
        : _interval.unit;
    final interval = await showDialog<BillingInterval>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) {
          final count = int.tryParse(countController.text);
          return AlertDialog(
            title: const Text('Другой период'),
            content: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: TextField(
                    controller: countController,
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    decoration: const InputDecoration(labelText: 'Каждые'),
                    onChanged: (_) => setDialogState(() {}),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  flex: 2,
                  child: DropdownButtonFormField<BillingIntervalUnit>(
                    initialValue: unit,
                    decoration: const InputDecoration(labelText: 'Единица'),
                    items: const [
                      DropdownMenuItem(
                        value: BillingIntervalUnit.days,
                        child: Text('дней'),
                      ),
                      DropdownMenuItem(
                        value: BillingIntervalUnit.weeks,
                        child: Text('недель'),
                      ),
                      DropdownMenuItem(
                        value: BillingIntervalUnit.months,
                        child: Text('месяцев'),
                      ),
                      DropdownMenuItem(
                        value: BillingIntervalUnit.years,
                        child: Text('лет'),
                      ),
                    ],
                    onChanged: (value) {
                      if (value != null) {
                        setDialogState(() => unit = value);
                      }
                    },
                  ),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: const Text('Отмена'),
              ),
              FilledButton(
                onPressed: count == null || count < 1 || count > 1000
                    ? null
                    : () => Navigator.pop(
                          dialogContext,
                          BillingInterval(count: count, unit: unit),
                        ),
                child: const Text('Готово'),
              ),
            ],
          );
        },
      ),
    );
    countController.dispose();
    if (interval != null && mounted) _setInterval(interval);
  }
}

class _DateField extends StatelessWidget {
  const _DateField({
    required this.label,
    required this.value,
    required this.onChanged,
    this.allowClear = false,
  });

  final String label;
  final DateTime? value;
  final ValueChanged<DateTime?> onChanged;
  final bool allowClear;

  @override
  Widget build(BuildContext context) => ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 2),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(color: Theme.of(context).colorScheme.outline),
        ),
        title: Text(label),
        subtitle: Text(value == null ? 'Не указан' : _date(value!)),
        trailing: allowClear && value != null
            ? IconButton(
                tooltip: 'Очистить дату',
                onPressed: () => onChanged(null),
                icon: const Icon(Icons.close),
              )
            : const Icon(Icons.calendar_today_outlined),
        onTap: () async {
          final result = await showDatePicker(
            context: context,
            initialDate: value ?? DateTime.now(),
            firstDate: DateTime(2000),
            lastDate: DateTime(2100),
          );
          if (result != null) onChanged(result);
        },
      );
}

class _EmptySubscriptions extends StatelessWidget {
  const _EmptySubscriptions({required this.archived, required this.onAdd});

  final bool archived;
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) => ListView(
        padding: const EdgeInsets.all(32),
        children: [
          const SizedBox(height: 80),
          Icon(archived ? Icons.inventory_2_outlined : Icons.notifications_none,
              size: 52, color: Theme.of(context).colorScheme.primary),
          const SizedBox(height: 16),
          Text(
            archived ? 'Архив пуст' : 'Добавьте первую подписку',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 8),
          Text(
            archived
                ? 'Здесь появятся завершённые подписки с сохранённой историей.'
                : 'CashFlow заранее напомнит о следующем списании.',
            textAlign: TextAlign.center,
          ),
          if (!archived) ...[
            const SizedBox(height: 24),
            Center(
              child: FilledButton.icon(
                onPressed: onAdd,
                icon: const Icon(Icons.add),
                label: const Text('Добавить подписку'),
              ),
            ),
          ],
        ],
      );
}

class _DetailPlaceholder extends StatelessWidget {
  const _DetailPlaceholder();

  @override
  Widget build(BuildContext context) => Center(
        child: Text('Выберите подписку',
            style: Theme.of(context).textTheme.titleMedium),
      );
}

class _FactRow extends StatelessWidget {
  const _FactRow({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(top: 8),
        child: Row(
          children: [
            Icon(icon, size: 20),
            const SizedBox(width: 8),
            Expanded(child: Text(text)),
          ],
        ),
      );
}

class _IntervalChoice {
  const _IntervalChoice(this.label, this.count, this.unit);
  final String label;
  final int count;
  final BillingIntervalUnit unit;
}

bool _isPresetInterval(BillingInterval interval) {
  if (interval.unit == BillingIntervalUnit.years) return interval.count == 1;
  return interval.unit == BillingIntervalUnit.months &&
      const {1, 3, 6}.contains(interval.count);
}

Map<String, List<SubscriptionModel>> _groupSubscriptions(
  List<SubscriptionModel> items,
  DateTime now,
) {
  final groups = <String, List<SubscriptionModel>>{};
  final today = _dateOnly(now);
  for (final item in items) {
    final days = _dateOnly(item.nextPaymentDate).difference(today).inDays;
    final label = item.isArchived
        ? 'Архив'
        : days < 0
            ? 'Требует подтверждения'
            : days == 0
                ? 'Сегодня'
                : days <= 7
                    ? 'Ближайшие 7 дней'
                    : days <= 30
                        ? 'Ближайшие 30 дней'
                        : 'Позже';
    groups.putIfAbsent(label, () => []).add(item);
  }
  return groups;
}

String _normalizedPrice(SubscriptionModel item) {
  final months = switch (item.billingInterval.unit) {
    BillingIntervalUnit.days => item.billingInterval.count / 30.4375,
    BillingIntervalUnit.weeks => item.billingInterval.count * 7 / 30.4375,
    BillingIntervalUnit.months => item.billingInterval.count.toDouble(),
    BillingIntervalUnit.years => item.billingInterval.count * 12.0,
  };
  if (months > 1) {
    return '≈ ${_money(item.expectedAmount / months, item.currency)}/мес';
  }
  return '≈ ${_money(item.expectedAmount * 12 / months, item.currency)}/год';
}

DateTime _addInterval(DateTime date, BillingInterval interval) {
  return switch (interval.unit) {
    BillingIntervalUnit.days => date.add(Duration(days: interval.count)),
    BillingIntervalUnit.weeks => date.add(Duration(days: interval.count * 7)),
    BillingIntervalUnit.months =>
      _clampedDate(date.year, date.month + interval.count, date.day),
    BillingIntervalUnit.years =>
      _clampedDate(date.year + interval.count, date.month, date.day),
  };
}

DateTime _clampedDate(int year, int month, int day) {
  final monthStart = DateTime(year, month);
  final lastDay = DateTime(monthStart.year, monthStart.month + 1, 0).day;
  return DateTime(
    monthStart.year,
    monthStart.month,
    day.clamp(1, lastDay),
  );
}

String _cardLabel(DataProvider provider, int cardId) =>
    _cardLabelFromCard(provider, provider.getCardById(cardId));

String _cardLabelFromCard(DataProvider provider, CardModel card) {
  final owner = card.id == null ? 'Карта' : provider.getCardName(card.id!);
  final digits = card.lastFourDigits?.isNotEmpty == true
      ? ' ••${card.lastFourDigits}'
      : '';
  return '$owner$digits';
}

String _money(double amount, String currency) {
  final value = amount == amount.roundToDouble()
      ? amount.toStringAsFixed(0)
      : amount.toStringAsFixed(2).replaceAll('.', ',');
  final symbol = switch (currency.toUpperCase()) {
    'RUB' => '₽',
    'USD' => r'$',
    'EUR' => '€',
    _ => currency.toUpperCase(),
  };
  return '$value $symbol';
}

String _date(DateTime value) =>
    '${value.day.toString().padLeft(2, '0')}.${value.month.toString().padLeft(2, '0')}.${value.year}';

DateTime _dateOnly(DateTime value) =>
    DateTime(value.year, value.month, value.day);
