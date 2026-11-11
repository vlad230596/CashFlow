import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../models/card_model.dart';
import '../models/planned_payment_model.dart';
import '../models/subscription_model.dart';
import '../providers/data_provider.dart';
import '../services/card_context.dart';
import '../services/payment_schedule.dart';
import '../utils/cashflow_formatters.dart';
import 'widgets/keyboard_first_back.dart';
import 'widgets/reminder_days_field.dart';

/// Recurring («Регулярные») or one-off («Разовые») payments with due dates.
class PlannedPaymentsScreen extends StatefulWidget {
  const PlannedPaymentsScreen({
    super.key,
    required this.kind,
    this.title = 'Платежи',
    this.appBarBottom,
  });

  final PlannedPaymentKind kind;
  final String title;
  final PreferredSizeWidget? appBarBottom;

  @override
  State<PlannedPaymentsScreen> createState() => PlannedPaymentsScreenState();
}

class PlannedPaymentsScreenState extends State<PlannedPaymentsScreen> {
  bool _showHistory = false;
  int? _selectedId;

  bool get _oneOff => widget.kind == PlannedPaymentKind.oneOff;

  Future<void> openPayment(int id) async {
    final provider = context.read<DataProvider>();
    var item = provider.plannedPayments
        .where((payment) => payment.id == id)
        .firstOrNull;
    if (item == null) {
      try {
        item = await provider.fetchPlannedPayment(id);
      } catch (_) {
        return;
      }
    }
    if (!mounted) return;
    setState(() {
      _showHistory = !item!.isOpen;
      _selectedId = id;
    });
    if (MediaQuery.sizeOf(context).width < 840) {
      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => PlannedPaymentDetails(payment: item!),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) => Consumer<DataProvider>(
        builder: (context, provider, _) {
          final items = _showHistory
              ? provider.closedPayments(widget.kind)
              : provider.openPayments(widget.kind);
          final selected = _selected(items);
          final today = provider.businessToday;
          return LayoutBuilder(builder: (context, constraints) {
            final expanded = constraints.maxWidth >= 840;
            final list = _PaymentList(
              kind: widget.kind,
              payments: items,
              history: _showHistory,
              today: today,
              selectedId: expanded ? selected?.id : null,
              onSelected: (item) => expanded
                  ? setState(() => _selectedId = item.id)
                  : Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => PlannedPaymentDetails(payment: item),
                      ),
                    ),
              onAdd: () => _openEditor(context),
            );
            return Scaffold(
              appBar: AppBar(
                title: Text(widget.title),
                bottom: widget.appBarBottom,
                actions: [
                  IconButton(
                    tooltip: _showHistory
                        ? 'Показать текущие'
                        : (_oneOff ? 'Оплаченные и архив' : 'Архив'),
                    onPressed: () => setState(() {
                      _showHistory = !_showHistory;
                      _selectedId = null;
                    }),
                    icon: Icon(_showHistory
                        ? Icons.inventory_2
                        : Icons.inventory_2_outlined),
                  ),
                ],
              ),
              floatingActionButton: _showHistory
                  ? null
                  : FloatingActionButton.extended(
                      heroTag: 'add-payment-${widget.kind.apiName}',
                      onPressed: () => _openEditor(context),
                      icon: const Icon(Icons.add),
                      label: const Text('Добавить'),
                    ),
              body: SafeArea(
                top: false,
                child: expanded
                    ? Row(
                        children: [
                          SizedBox(width: 430, child: list),
                          const VerticalDivider(width: 1),
                          Expanded(
                            child: selected == null
                                ? Center(
                                    child: Text(
                                      'Выберите платёж',
                                      style: Theme.of(context)
                                          .textTheme
                                          .titleMedium,
                                    ),
                                  )
                                : PlannedPaymentDetails(
                                    payment: selected,
                                    embedded: true,
                                    onChanged: () => setState(() {}),
                                  ),
                          ),
                        ],
                      )
                    : list,
              ),
            );
          });
        },
      );

  PlannedPaymentModel? _selected(List<PlannedPaymentModel> items) {
    if (items.isEmpty) return null;
    return items.where((item) => item.id == _selectedId).firstOrNull ??
        items.first;
  }

  Future<void> _openEditor(BuildContext context) => Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => PlannedPaymentEditScreen(kind: widget.kind),
        ),
      );
}

class _PaymentList extends StatelessWidget {
  const _PaymentList({
    required this.kind,
    required this.payments,
    required this.history,
    required this.today,
    required this.onSelected,
    required this.onAdd,
    this.selectedId,
  });

  final PlannedPaymentKind kind;
  final List<PlannedPaymentModel> payments;
  final bool history;
  final DateTime today;
  final int? selectedId;
  final ValueChanged<PlannedPaymentModel> onSelected;
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    final provider = context.read<DataProvider>();
    if (payments.isEmpty) {
      return RefreshIndicator(
        onRefresh: provider.fetchPlannedPayments,
        child: _EmptyPayments(kind: kind, history: history, onAdd: onAdd),
      );
    }
    final groups = groupPaymentsByDueDate(payments, today);
    return RefreshIndicator(
      onRefresh: provider.fetchPlannedPayments,
      child: CustomScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: [
          if (!history)
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              sliver: SliverToBoxAdapter(
                child: _DueSummary(payments: payments, today: today),
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
                        color: group.key == overdueGroupLabel
                            ? Theme.of(context).colorScheme.error
                            : Theme.of(context).colorScheme.onSurfaceVariant,
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
                  return _PaymentTile(
                    payment: item,
                    today: today,
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

const overdueGroupLabel = 'Просрочено';

/// Groups by urgency relative to the Moscow business [today].
Map<String, List<PlannedPaymentModel>> groupPaymentsByDueDate(
  List<PlannedPaymentModel> items,
  DateTime today,
) {
  const order = [
    overdueGroupLabel,
    'Сегодня',
    'Ближайшие 7 дней',
    'Ближайшие 30 дней',
    'Позже',
    'Оплаченные',
    'Архив',
  ];
  final groups = <String, List<PlannedPaymentModel>>{};
  for (final item in items) {
    final days = item.daysUntilDue(today);
    final label = item.isArchived
        ? 'Архив'
        : item.isCompleted
            ? 'Оплаченные'
            : days < 0
                ? overdueGroupLabel
                : days == 0
                    ? 'Сегодня'
                    : days <= 7
                        ? 'Ближайшие 7 дней'
                        : days <= 30
                            ? 'Ближайшие 30 дней'
                            : 'Позже';
    groups.putIfAbsent(label, () => []).add(item);
  }
  return {
    for (final label in order)
      if (groups.containsKey(label)) label: groups[label]!,
  };
}

class _DueSummary extends StatelessWidget {
  const _DueSummary({required this.payments, required this.today});

  final List<PlannedPaymentModel> payments;
  final DateTime today;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final overdue = payments.where((item) => item.isOverdue(today)).toList();
    final upcoming =
        payments.where((item) => !item.isOverdue(today)).firstOrNull;
    final totals = <String, double>{};
    for (final item in payments) {
      if (item.daysUntilDue(today) <= 30) {
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
            if (overdue.isNotEmpty) ...[
              Container(
                key: const ValueKey('payments-overdue-banner'),
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: scheme.errorContainer,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  children: [
                    Icon(Icons.warning_amber_rounded,
                        color: scheme.onErrorContainer),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'Просрочено: ${overdue.length} · '
                        '${_moneyTotals(overdue)}',
                        style: TextStyle(
                          color: scheme.onErrorContainer,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),
            ],
            if (upcoming != null) ...[
              Text('Ближайший срок',
                  style: Theme.of(context).textTheme.labelLarge),
              const SizedBox(height: 6),
              Text(
                _money(upcoming.expectedAmount, upcoming.currency),
                style: Theme.of(context).textTheme.headlineMedium,
              ),
              const SizedBox(height: 4),
              Text('${upcoming.name} · до ${_date(upcoming.nextDueDate)}'),
              const Divider(height: 28),
            ],
            Text('К оплате в ближайшие 30 дней',
                style: Theme.of(context).textTheme.labelLarge),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final entry in totals.entries)
                  Chip(
                    avatar: const Icon(Icons.payments_outlined, size: 18),
                    label: Text(_money(entry.value, entry.key)),
                  ),
                if (totals.isEmpty) const Text('Ничего'),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _PaymentTile extends StatelessWidget {
  const _PaymentTile({
    required this.payment,
    required this.today,
    required this.selected,
    required this.onTap,
  });

  final PlannedPaymentModel payment;
  final DateTime today;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final overdue = payment.isOverdue(today);
    final status = dueStatusLabel(payment, today);
    return Card(
      key: ValueKey('payment-tile-${payment.id}'),
      color: selected ? scheme.primaryContainer : scheme.surface,
      shape: overdue
          ? RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
              side: BorderSide(color: scheme.error, width: 1.5),
            )
          : null,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              CircleAvatar(
                backgroundColor:
                    overdue ? scheme.errorContainer : scheme.secondaryContainer,
                child: Icon(
                  overdue
                      ? Icons.priority_high_rounded
                      : payment.isCompleted
                          ? Icons.check_rounded
                          : payment.isRecurring
                              ? Icons.event_repeat_outlined
                              : Icons.event_outlined,
                  color: overdue ? scheme.onErrorContainer : null,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(payment.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.titleMedium),
                    const SizedBox(height: 4),
                    Text(
                      [
                        'до ${_date(payment.nextDueDate)}',
                        if (payment.interval != null)
                          scheduleLabel(payment.interval!),
                      ].join(' · '),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    if (status != null) ...[
                      const SizedBox(height: 4),
                      Text(
                        status,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: overdue ? scheme.error : null,
                              fontWeight: overdue ? FontWeight.w700 : null,
                            ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    _money(payment.expectedAmount, payment.currency),
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

/// "Просрочено на 3 дн." / "Сегодня" / "Завтра" / null for later payments.
String? dueStatusLabel(PlannedPaymentModel payment, DateTime today) {
  if (payment.isArchived) return 'В архиве';
  if (payment.isCompleted) {
    final paidAt = payment.lastRecord?.paidAt;
    return paidAt == null ? 'Оплачено' : 'Оплачено ${_date(paidAt)}';
  }
  final days = payment.daysUntilDue(today);
  if (days < 0) return 'Просрочено на ${-days} дн.';
  if (days == 0) return 'Срок оплаты сегодня';
  if (days == 1) return 'Срок оплаты завтра';
  return null;
}

String scheduleLabel(BillingInterval interval) {
  final count = interval.count;
  return switch (interval.unit) {
    BillingIntervalUnit.months when count == 1 => 'ежемесячно',
    BillingIntervalUnit.months when count == 3 => 'ежеквартально',
    BillingIntervalUnit.years when count == 1 => 'ежегодно',
    BillingIntervalUnit.weeks when count == 1 => 'еженедельно',
    BillingIntervalUnit.days => 'каждые $count дн.',
    BillingIntervalUnit.weeks => 'каждые $count нед.',
    BillingIntervalUnit.months => 'каждые $count мес.',
    BillingIntervalUnit.years => 'каждые $count г.',
  };
}

class PlannedPaymentDetails extends StatefulWidget {
  const PlannedPaymentDetails({
    super.key,
    required this.payment,
    this.embedded = false,
    this.onChanged,
  });

  final PlannedPaymentModel payment;
  final bool embedded;
  final VoidCallback? onChanged;

  @override
  State<PlannedPaymentDetails> createState() => _PlannedPaymentDetailsState();
}

class _PlannedPaymentDetailsState extends State<PlannedPaymentDetails> {
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadDetail());
  }

  @override
  void didUpdateWidget(covariant PlannedPaymentDetails oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.payment.id != widget.payment.id) _loadDetail();
  }

  Future<void> _loadDetail() async {
    final id = widget.payment.id;
    if (id == null || !mounted) return;
    try {
      await context.read<DataProvider>().fetchPlannedPayment(id);
    } catch (_) {
      // Cached data still gives a useful read-only view offline.
    }
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<DataProvider>();
    final payment = provider.plannedPayments
            .where((item) => item.id == widget.payment.id)
            .firstOrNull ??
        widget.payment;
    final today = provider.businessToday;
    final scheme = Theme.of(context).colorScheme;
    final overdue = payment.isOverdue(today);
    final status = dueStatusLabel(payment, today);
    final records = payment.records.isNotEmpty
        ? payment.records
        : [if (payment.lastRecord != null) payment.lastRecord!];
    final latestRecordId = payment.lastRecord?.id;

    final content = Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 720),
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 40),
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(payment.name,
                      style: Theme.of(context).textTheme.headlineMedium),
                ),
                if (widget.embedded) _editButton(payment),
              ],
            ),
            const SizedBox(height: 16),
            Card(
              shape: overdue
                  ? RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                      side: BorderSide(color: scheme.error, width: 1.5),
                    )
                  : null,
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                        payment.isCompleted ? 'Срок оплаты был' : 'Оплатить до',
                        style: Theme.of(context).textTheme.labelLarge),
                    const SizedBox(height: 6),
                    Text(
                      _money(payment.expectedAmount, payment.currency),
                      style: Theme.of(context).textTheme.headlineLarge,
                    ),
                    const SizedBox(height: 4),
                    Text([
                      _date(payment.nextDueDate),
                      if (payment.interval != null)
                        scheduleLabel(payment.interval!),
                    ].join(' · ')),
                    if (status != null) ...[
                      const SizedBox(height: 8),
                      Text(
                        status,
                        key: const ValueKey('payment-due-status'),
                        style: TextStyle(
                          color: overdue ? scheme.error : null,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                    const SizedBox(height: 12),
                    _FactRow(
                      icon: Icons.credit_card_outlined,
                      text: payment.cardId == null
                          ? 'Карта не указана'
                          : _cardLabel(provider, payment.cardId!),
                    ),
                    _FactRow(
                      icon: Icons.notifications_outlined,
                      text: ReminderDaysField.summary(payment.reminderDays),
                    ),
                    if (payment.note != null && payment.note!.isNotEmpty)
                      _FactRow(icon: Icons.notes_outlined, text: payment.note!),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            if (payment.isOpen)
              FilledButton.icon(
                key: const ValueKey('payment-mark-paid'),
                onPressed: _busy ? null : () => _markPaid(payment),
                icon: const Icon(Icons.check_circle_outline),
                label: const Text('Отметить оплаченным'),
              ),
            const SizedBox(height: 24),
            Text('История оплат',
                style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 8),
            if (records.isEmpty)
              const Text('Оплат пока не было.')
            else
              for (final record in records)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.receipt_long_outlined),
                  title: Text(_money(record.amount, record.currency)),
                  subtitle: Text(
                    'Оплачено ${_date(record.paidAt)} · срок ${_date(record.dueDate)}'
                    '${record.cardId == null ? '' : ' · ${_cardLabel(provider, record.cardId!)}'}',
                  ),
                  trailing: record.id != null &&
                          record.id == latestRecordId &&
                          !payment.isArchived
                      ? IconButton(
                          tooltip: 'Отменить оплату',
                          onPressed:
                              _busy ? null : () => _undo(payment, record),
                          icon: const Icon(Icons.undo),
                        )
                      : null,
                ),
            const SizedBox(height: 24),
            OutlinedButton.icon(
              onPressed: _busy
                  ? null
                  : () => payment.isArchived
                      ? _restore(payment)
                      : _archive(payment),
              icon: Icon(payment.isArchived
                  ? Icons.unarchive_outlined
                  : Icons.archive_outlined),
              label: Text(payment.isArchived
                  ? 'Восстановить платёж'
                  : 'Перенести в архив'),
            ),
            const SizedBox(height: 8),
            TextButton.icon(
              onPressed: _busy ? null : () => _delete(payment),
              style: TextButton.styleFrom(foregroundColor: scheme.error),
              icon: const Icon(Icons.delete_outline),
              label: const Text('Удалить'),
            ),
          ],
        ),
      ),
    );
    if (widget.embedded) return content;
    return Scaffold(
      appBar: AppBar(
        title:
            Text(payment.isRecurring ? 'Регулярный платёж' : 'Разовый платёж'),
        actions: [_editButton(payment)],
      ),
      body: SafeArea(top: false, child: content),
    );
  }

  Widget _editButton(PlannedPaymentModel payment) => IconButton(
        tooltip: 'Редактировать',
        onPressed: () => Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) =>
                PlannedPaymentEditScreen(kind: payment.kind, existing: payment),
          ),
        ),
        icon: const Icon(Icons.edit_outlined),
      );

  Future<void> _run(Future<void> Function() action) async {
    setState(() => _busy = true);
    try {
      await action();
      widget.onChanged?.call();
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Не удалось выполнить действие: $error')),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _markPaid(PlannedPaymentModel payment) async {
    final provider = context.read<DataProvider>();
    final today = provider.businessToday;
    final amount = TextEditingController(
      text: payment.expectedAmount.toStringAsFixed(2),
    );
    var date = today;
    final next = payment.dueDateAfterPayment;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Платёж оплачен?'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(
                controller: amount,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                inputFormatters: [
                  FilteringTextInputFormatter.allow(RegExp(r'[0-9,.]')),
                ],
                decoration: InputDecoration(
                  labelText: 'Сумма, ${payment.currency}',
                ),
              ),
              const SizedBox(height: 12),
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Дата оплаты'),
                subtitle: Text(_date(date)),
                trailing: const Icon(Icons.calendar_today_outlined),
                onTap: () async {
                  final value = await showDatePicker(
                    context: context,
                    initialDate: date,
                    firstDate: DateTime(2000),
                    lastDate: today,
                  );
                  if (value != null) setDialogState(() => date = value);
                },
              ),
              Text(
                next == null
                    ? 'Разовый платёж будет завершён.'
                    : 'Следующий срок: ${_date(next)}.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Отмена'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('Оплачено'),
            ),
          ],
        ),
      ),
    );
    final value = double.tryParse(amount.text.replaceAll(',', '.'));
    amount.dispose();
    if (confirmed != true || !mounted || value == null || value <= 0) return;
    await _run(() => provider.markPlannedPaymentPaid(
          payment.id!,
          paidAt: date,
          amount: value,
        ));
  }

  Future<void> _undo(
    PlannedPaymentModel payment,
    PlannedPaymentRecord record,
  ) async {
    final confirmed = await _confirm(
      'Отменить оплату?',
      'Срок ${_date(record.dueDate)} снова станет неоплаченным.',
      'Отменить оплату',
    );
    if (!confirmed || !mounted) return;
    final provider = context.read<DataProvider>();
    await _run(
        () => provider.undoPlannedPaymentRecord(payment.id!, record.id!));
  }

  Future<void> _archive(PlannedPaymentModel payment) async {
    final confirmed = await _confirm(
      'Перенести в архив?',
      'Напоминания отключатся, история оплат сохранится.',
      'В архив',
    );
    if (!confirmed || !mounted) return;
    final provider = context.read<DataProvider>();
    await _run(() => provider.archivePlannedPayment(payment.id!));
    if (mounted && !widget.embedded) Navigator.pop(context);
  }

  Future<void> _restore(PlannedPaymentModel payment) async {
    final provider = context.read<DataProvider>();
    await _run(() => provider.restorePlannedPayment(payment.id!));
  }

  Future<void> _delete(PlannedPaymentModel payment) async {
    final confirmed = await _confirm(
      'Удалить платёж?',
      'Платёж и вся история его оплат будут удалены без возможности '
          'восстановления. Чтобы сохранить историю, перенесите его в архив.',
      'Удалить',
    );
    if (!confirmed || !mounted) return;
    final provider = context.read<DataProvider>();
    await _run(() => provider.deletePlannedPayment(payment.id!));
    if (mounted && !widget.embedded) Navigator.pop(context);
  }

  Future<bool> _confirm(String title, String body, String action) async =>
      await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: Text(title),
          content: Text(body),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Отмена'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: Text(action),
            ),
          ],
        ),
      ) ??
      false;
}

class PlannedPaymentEditScreen extends StatefulWidget {
  const PlannedPaymentEditScreen({
    super.key,
    required this.kind,
    this.existing,
  });

  final PlannedPaymentKind kind;
  final PlannedPaymentModel? existing;

  @override
  State<PlannedPaymentEditScreen> createState() =>
      _PlannedPaymentEditScreenState();
}

class _PlannedPaymentEditScreenState extends State<PlannedPaymentEditScreen> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _name;
  late final TextEditingController _amount;
  late final TextEditingController _currency;
  late final TextEditingController _note;
  int? _cardId;
  var _interval = const BillingInterval(
    count: 1,
    unit: BillingIntervalUnit.months,
  );
  late DateTime _dueDate;
  late DateTime _anchorDate;
  bool _monthEnd = false;
  late List<int> _reminderDays;
  bool _saving = false;

  bool get _recurring => widget.kind == PlannedPaymentKind.recurring;

  @override
  void initState() {
    super.initState();
    final item = widget.existing;
    final today = context.read<DataProvider>().businessToday;
    _name = TextEditingController(text: item?.name ?? '');
    _amount = TextEditingController(
        text: item == null ? '' : item.expectedAmount.toStringAsFixed(2));
    _currency = TextEditingController(text: item?.currency ?? 'RUB');
    _note = TextEditingController(text: item?.note ?? '');
    _cardId = item?.cardId;
    _interval = item?.interval ?? _interval;
    _dueDate = item?.nextDueDate ?? today.add(const Duration(days: 7));
    _anchorDate = item?.anchorDate ?? _dueDate;
    _monthEnd = item != null &&
        _recurring &&
        _anchorDate.day == 31 &&
        isLastDayOfMonth(_dueDate);
    _reminderDays =
        item?.reminderDays.toList() ?? List.of(defaultPaymentReminderDays);
  }

  @override
  void dispose() {
    _name.dispose();
    _amount.dispose();
    _currency.dispose();
    _note.dispose();
    super.dispose();
  }

  DateTime? get _monthEndAnchor => monthEndAnchor(_dueDate, _interval);

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<DataProvider>();
    final cards = provider.cards.where((card) => card.id != null).toList();
    final canMonthEnd =
        _recurring && _dueDate.day != 31 && _monthEndAnchor != null;
    final upcoming = _recurring
        ? PaymentSchedule(anchor: _effectiveAnchor, interval: _interval)
            .between(_dueDate, DateTime(_dueDate.year + 5), limit: 3)
        : const <DateTime>[];
    return Scaffold(
      appBar: AppBar(
        leading: const KeyboardFirstBackButton(),
        title: Text(widget.existing == null
            ? (_recurring ? 'Новый регулярный платёж' : 'Новый разовый платёж')
            : 'Редактирование платежа'),
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
                    key: const ValueKey('payment-name'),
                    controller: _name,
                    autofocus: widget.existing == null,
                    textInputAction: TextInputAction.next,
                    decoration: InputDecoration(
                      labelText: 'Название',
                      hintText: _recurring ? 'Детский сад' : 'Страховка',
                    ),
                    validator: (value) => value == null || value.trim().isEmpty
                        ? 'Введите название'
                        : null,
                  ),
                  const SizedBox(height: 16),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        flex: 2,
                        child: TextFormField(
                          key: const ValueKey('payment-amount'),
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
                  DropdownButtonFormField<int?>(
                    initialValue: cards.any((card) => card.id == _cardId)
                        ? _cardId
                        : null,
                    isExpanded: true,
                    decoration: const InputDecoration(
                        labelText: 'Карта (необязательно)'),
                    items: [
                      const DropdownMenuItem<int?>(
                        value: null,
                        child: Text('Без карты'),
                      ),
                      for (final card in cards)
                        DropdownMenuItem<int?>(
                          value: card.id,
                          child: Text(
                            _cardLabelFromCard(provider, card),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                    ],
                    onChanged: (value) => setState(() => _cardId = value),
                  ),
                  if (_recurring) ...[
                    const SizedBox(height: 20),
                    Text('Периодичность',
                        style: Theme.of(context).textTheme.titleMedium),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        for (final choice in const [
                          ('Месяц', 1, BillingIntervalUnit.months),
                          ('3 месяца', 3, BillingIntervalUnit.months),
                          ('Год', 1, BillingIntervalUnit.years),
                          ('Неделя', 1, BillingIntervalUnit.weeks),
                        ])
                          ChoiceChip(
                            label: Text(choice.$1),
                            selected: _interval.count == choice.$2 &&
                                _interval.unit == choice.$3,
                            onSelected: (_) => _setInterval(BillingInterval(
                              count: choice.$2,
                              unit: choice.$3,
                            )),
                          ),
                        ChoiceChip(
                          label: const Text('Другая'),
                          selected: !_isPreset(_interval),
                          onSelected: (_) => _chooseCustomInterval(),
                        ),
                      ],
                    ),
                  ],
                  const SizedBox(height: 20),
                  _DateTile(
                    key: const ValueKey('payment-due-date'),
                    label: _recurring ? 'Ближайший срок оплаты' : 'Оплатить до',
                    value: _dueDate,
                    onChanged: (value) => setState(() {
                      _dueDate = value;
                      _anchorDate = value;
                      _monthEnd = _monthEnd && _monthEndAnchor != null;
                    }),
                  ),
                  if (canMonthEnd)
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('В последний день месяца'),
                      subtitle: const Text(
                          'Срок всегда в конце месяца: 28/29, 30 или 31 число'),
                      value: _monthEnd,
                      onChanged: (value) => setState(() => _monthEnd = value),
                    ),
                  if (upcoming.length > 1)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text(
                        'Следующие сроки: ${upcoming.skip(1).map(_date).join(', ')}…',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ),
                  const SizedBox(height: 20),
                  ReminderDaysField(
                    value: _reminderDays,
                    onChanged: (value) => setState(() => _reminderDays = value),
                    footer: provider.supportsReminders
                        ? const _ExactReminderHint()
                        : null,
                  ),
                  const SizedBox(height: 20),
                  TextFormField(
                    controller: _note,
                    minLines: 1,
                    maxLines: 4,
                    maxLength: 2000,
                    decoration: const InputDecoration(
                      labelText: 'Заметка (необязательно)',
                      counterText: '',
                    ),
                  ),
                  const SizedBox(height: 28),
                  FilledButton(
                    key: const ValueKey('payment-save'),
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

  /// The schedule anchor to save: an existing anchor is kept while it still
  /// produces the chosen due date; "last day of month" anchors on a 31st.
  DateTime get _effectiveAnchor {
    if (!_recurring) return _dueDate;
    final valid = !_anchorDate.isAfter(_dueDate) &&
        PaymentSchedule(anchor: _anchorDate, interval: _interval)
            .isOccurrence(_dueDate);
    if (_monthEnd) {
      return valid && _anchorDate.day == 31
          ? _anchorDate
          : (_monthEndAnchor ?? _dueDate);
    }
    final dayBased = _interval.unit == BillingIntervalUnit.days ||
        _interval.unit == BillingIntervalUnit.weeks;
    return valid && (dayBased || _anchorDate.day == _dueDate.day)
        ? _anchorDate
        : _dueDate;
  }

  void _setInterval(BillingInterval interval) => setState(() {
        _interval = interval;
        _monthEnd = _monthEnd && _monthEndAnchor != null;
      });

  Future<void> _chooseCustomInterval() async {
    final count = TextEditingController(
      text: _isPreset(_interval) ? '2' : _interval.count.toString(),
    );
    var unit =
        _isPreset(_interval) ? BillingIntervalUnit.months : _interval.unit;
    final result = await showDialog<BillingInterval>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) {
          final parsed = int.tryParse(count.text);
          return AlertDialog(
            title: const Text('Другая периодичность'),
            content: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: TextField(
                    controller: count,
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
                      if (value != null) setDialogState(() => unit = value);
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
                onPressed: parsed == null || parsed < 1 || parsed > 1000
                    ? null
                    : () => Navigator.pop(
                          dialogContext,
                          BillingInterval(count: parsed, unit: unit),
                        ),
                child: const Text('Готово'),
              ),
            ],
          );
        },
      ),
    );
    count.dispose();
    if (result != null && mounted) _setInterval(result);
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    final previous = widget.existing;
    final note = _note.text.trim();
    final item = PlannedPaymentModel(
      id: previous?.id,
      name: _name.text.trim(),
      kind: widget.kind,
      expectedAmount: double.parse(_amount.text.replaceAll(',', '.')),
      currency: _currency.text.trim().toUpperCase(),
      cardId: _cardId,
      note: note.isEmpty ? null : note,
      interval: _recurring ? _interval : null,
      anchorDate: _effectiveAnchor,
      nextDueDate: _dueDate,
      reminderDays: List.unmodifiable(_reminderDays),
    );
    final provider = context.read<DataProvider>();
    try {
      if (previous == null) {
        await provider.createPlannedPayment(item);
        if (item.reminderDays.isNotEmpty) {
          await provider.requestPaymentNotificationPermission();
        }
      } else {
        await provider.updatePlannedPayment(item);
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

  static bool _isPreset(BillingInterval interval) => switch (interval.unit) {
        BillingIntervalUnit.months => const {1, 3}.contains(interval.count),
        BillingIntervalUnit.years ||
        BillingIntervalUnit.weeks =>
          interval.count == 1,
        BillingIntervalUnit.days => false,
      };
}

/// Offers exact alarms when Android only allows inexact reminders.
class _ExactReminderHint extends StatefulWidget {
  const _ExactReminderHint();

  @override
  State<_ExactReminderHint> createState() => _ExactReminderHintState();
}

class _ExactReminderHintState extends State<_ExactReminderHint> {
  late Future<bool> _exact =
      context.read<DataProvider>().canScheduleExactReminders();

  @override
  Widget build(BuildContext context) => FutureBuilder<bool>(
        future: _exact,
        builder: (context, snapshot) {
          if (snapshot.data != false) return const SizedBox.shrink();
          return Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: () => setState(() {
                  _exact = context
                      .read<DataProvider>()
                      .requestExactReminderPermission();
                }),
                icon: const Icon(Icons.alarm_on_outlined),
                label: const Text('Напоминать точно в 10:00'),
              ),
            ),
          );
        },
      );
}

class _DateTile extends StatelessWidget {
  const _DateTile({
    super.key,
    required this.label,
    required this.value,
    required this.onChanged,
  });

  final String label;
  final DateTime value;
  final ValueChanged<DateTime> onChanged;

  @override
  Widget build(BuildContext context) => ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 2),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(color: Theme.of(context).colorScheme.outline),
        ),
        title: Text(label),
        subtitle: Text(_date(value)),
        trailing: const Icon(Icons.calendar_today_outlined),
        onTap: () async {
          final result = await showDatePicker(
            context: context,
            initialDate: value,
            firstDate: DateTime(2000),
            lastDate: DateTime(2100),
          );
          if (result != null) onChanged(dateOnly(result));
        },
      );
}

class _EmptyPayments extends StatelessWidget {
  const _EmptyPayments({
    required this.kind,
    required this.history,
    required this.onAdd,
  });

  final PlannedPaymentKind kind;
  final bool history;
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    final recurring = kind == PlannedPaymentKind.recurring;
    return ListView(
      padding: const EdgeInsets.all(32),
      children: [
        const SizedBox(height: 80),
        Icon(
          history
              ? Icons.inventory_2_outlined
              : recurring
                  ? Icons.event_repeat_outlined
                  : Icons.event_outlined,
          size: 52,
          color: Theme.of(context).colorScheme.primary,
        ),
        const SizedBox(height: 16),
        Text(
          history
              ? (recurring ? 'Архив пуст' : 'Оплаченных платежей пока нет')
              : (recurring
                  ? 'Добавьте регулярный платёж'
                  : 'Добавьте разовый платёж'),
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.titleLarge,
        ),
        const SizedBox(height: 8),
        Text(
          history
              ? 'Здесь появятся завершённые платежи с историей оплат.'
              : recurring
                  ? 'Например, детский сад до 25 числа каждого месяца — '
                      'напомним накануне.'
                  : 'Например, оплатить страховку до 13 ноября — '
                      'напомним накануне.',
          textAlign: TextAlign.center,
        ),
        if (!history) ...[
          const SizedBox(height: 24),
          Center(
            child: FilledButton.icon(
              onPressed: onAdd,
              icon: const Icon(Icons.add),
              label: const Text('Добавить платёж'),
            ),
          ),
        ],
      ],
    );
  }
}

class _FactRow extends StatelessWidget {
  const _FactRow({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(top: 8),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, size: 20),
            const SizedBox(width: 8),
            Expanded(child: Text(text)),
          ],
        ),
      );
}

String _cardLabel(DataProvider provider, int cardId) =>
    _cardLabelFromCard(provider, provider.getCardById(cardId));

String _cardLabelFromCard(DataProvider provider, CardModel card) =>
    CardContextCatalog(
            cards: provider.cards, banks: provider.banks, users: provider.users)
        .forCard(card)
        .subscriptionLabel;

String _moneyTotals(List<PlannedPaymentModel> payments) {
  final totals = <String, double>{};
  for (final item in payments) {
    totals.update(item.currency, (value) => value + item.expectedAmount,
        ifAbsent: () => item.expectedAmount);
  }
  return totals.entries
      .map((entry) => _money(entry.value, entry.key))
      .join(' + ');
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

String _date(DateTime value) => CashFlowFormatters.calendarDate(value);
