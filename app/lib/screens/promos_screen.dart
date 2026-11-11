import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../models/promo_model.dart';
import '../providers/data_provider.dart';
import '../utils/cashflow_formatters.dart';
import 'widgets/keyboard_first_back.dart';
import 'widgets/reminder_days_field.dart';

/// «Промокоды и баллы» (opened from «Ещё»): saved offers, promo codes and
/// points balances, sorted by the soonest expiry.
class PromosScreen extends StatefulWidget {
  const PromosScreen({super.key, this.initialPromoId});

  /// Opens this item's details once the list is shown (reminder tap).
  final int? initialPromoId;

  @override
  State<PromosScreen> createState() => PromosScreenState();
}

const promoStatusLabels = {
  PromoStatus.active: 'Активные',
  PromoStatus.expired: 'Истёкшие',
  PromoStatus.used: 'Использованные',
  PromoStatus.archived: 'Архив',
};

class PromosScreenState extends State<PromosScreen> {
  var _status = PromoStatus.active;

  PromoStatus get status => _status;

  @override
  void initState() {
    super.initState();
    final id = widget.initialPromoId;
    if (id != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) openPromo(id);
      });
    }
  }

  Future<void> openPromo(int id) async {
    final provider = context.read<DataProvider>();
    var item = provider.promos.where((promo) => promo.id == id).firstOrNull;
    if (item == null) {
      try {
        item = await provider.fetchPromo(id);
      } catch (_) {
        return;
      }
    }
    if (!mounted) return;
    setState(() => _status = item!.status(provider.businessToday));
    await _openDetails(item);
  }

  Future<void> _openDetails(PromoModel item) => Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => PromoDetailsScreen(promoKey: item.localKey),
        ),
      );

  Future<void> _openEditor() => Navigator.of(context).push(
        MaterialPageRoute<void>(builder: (_) => const PromoEditScreen()),
      );

  @override
  Widget build(BuildContext context) => Consumer<DataProvider>(
        builder: (context, provider, _) {
          final today = provider.businessToday;
          final items = provider.promosWithStatusToday(_status);
          final counts = {
            for (final status in PromoStatus.values)
              status: provider.promos
                  .where((item) => item.status(today) == status)
                  .length,
          };
          final urgent = _status == PromoStatus.active
              ? items.where((item) => item.isUrgent(today)).length
              : 0;
          return Scaffold(
            appBar: AppBar(
              leading: const KeyboardFirstBackButton(),
              title: const Text('Промокоды и баллы'),
            ),
            floatingActionButton: FloatingActionButton.extended(
              key: const ValueKey('promo-add'),
              heroTag: 'add-promo',
              onPressed: _openEditor,
              icon: const Icon(Icons.add),
              label: const Text('Добавить'),
            ),
            body: SafeArea(
              top: false,
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 760),
                  child: RefreshIndicator(
                    onRefresh: provider.fetchPromos,
                    child: CustomScrollView(
                      physics: const AlwaysScrollableScrollPhysics(),
                      slivers: [
                        SliverToBoxAdapter(
                          child: _StatusFilter(
                            selected: _status,
                            counts: counts,
                            onSelected: (value) =>
                                setState(() => _status = value),
                          ),
                        ),
                        if (provider.promosError != null)
                          SliverToBoxAdapter(
                            child: _Banner(
                              key: const ValueKey('promo-error'),
                              icon: Icons.cloud_off_outlined,
                              text: 'Показаны сохранённые данные. '
                                  '${provider.promosError}',
                            ),
                          ),
                        if (urgent > 0)
                          SliverToBoxAdapter(
                            child: _Banner(
                              key: const ValueKey('promo-urgent-banner'),
                              icon: Icons.local_fire_department_outlined,
                              urgent: true,
                              text: 'Скоро сгорят: $urgent — '
                                  'осталось $promoUrgentDays дн. или меньше',
                            ),
                          ),
                        if (items.isEmpty)
                          SliverFillRemaining(
                            hasScrollBody: false,
                            child: _EmptyPromos(
                              status: _status,
                              onAdd: _openEditor,
                            ),
                          )
                        else
                          SliverPadding(
                            padding: const EdgeInsets.fromLTRB(16, 4, 16, 96),
                            sliver: SliverList.separated(
                              itemCount: items.length,
                              separatorBuilder: (context, index) =>
                                  const SizedBox(height: 8),
                              itemBuilder: (context, index) => PromoTile(
                                item: items[index],
                                today: today,
                                onTap: () => _openDetails(items[index]),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          );
        },
      );
}

class _StatusFilter extends StatelessWidget {
  const _StatusFilter({
    required this.selected,
    required this.counts,
    required this.onSelected,
  });

  final PromoStatus selected;
  final Map<PromoStatus, int> counts;
  final ValueChanged<PromoStatus> onSelected;

  @override
  Widget build(BuildContext context) => SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
        child: Row(
          children: [
            for (final status in PromoStatus.values) ...[
              ChoiceChip(
                key: ValueKey('promo-filter-${status.name}'),
                label: Text(
                  counts[status] == 0
                      ? promoStatusLabels[status]!
                      : '${promoStatusLabels[status]} · ${counts[status]}',
                ),
                selected: status == selected,
                onSelected: (_) => onSelected(status),
              ),
              const SizedBox(width: 8),
            ],
          ],
        ),
      );
}

class _Banner extends StatelessWidget {
  const _Banner({
    super.key,
    required this.icon,
    required this.text,
    this.urgent = false,
  });

  final IconData icon;
  final String text;
  final bool urgent;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final foreground =
        urgent ? scheme.onErrorContainer : scheme.onSurfaceVariant;
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 4, 16, 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color:
            urgent ? scheme.errorContainer : scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(icon, color: foreground),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                color: foreground,
                fontWeight: urgent ? FontWeight.w700 : null,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _EmptyPromos extends StatelessWidget {
  const _EmptyPromos({required this.status, required this.onAdd});

  final PromoStatus status;
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    final text = switch (status) {
      PromoStatus.active => 'Перешлите сюда интересное предложение или '
          'начисленные баллы: вставьте текст сообщения, а приложение '
          'найдёт срок и промокод и напомнит заранее.',
      PromoStatus.expired => 'Истёкших предложений нет.',
      PromoStatus.used => 'Использованных предложений нет.',
      PromoStatus.archived => 'Архив пуст.',
    };
    return Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.confirmation_number_outlined,
            size: 48,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
          const SizedBox(height: 12),
          Text(text, textAlign: TextAlign.center),
          if (status == PromoStatus.active) ...[
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: onAdd,
              icon: const Icon(Icons.content_paste_go_outlined),
              label: const Text('Вставить сообщение'),
            ),
          ],
        ],
      ),
    );
  }
}

String _date(DateTime value) => CashFlowFormatters.calendarDate(value);

String formatPromoPoints(double amount) {
  final whole = amount == amount.roundToDouble();
  final text = whole ? amount.toStringAsFixed(0) : amount.toStringAsFixed(2);
  final parts = text.split('.');
  final digits = parts.first;
  final grouped = StringBuffer();
  for (var index = 0; index < digits.length; index++) {
    if (index > 0 && (digits.length - index) % 3 == 0) grouped.write(' ');
    grouped.write(digits[index]);
  }
  return parts.length == 1 ? '$grouped' : '$grouped,${parts[1]}';
}

/// «Сгорит через 5 дн.», «Истекает сегодня», «Срок не указан», …
String promoExpiryLabel(PromoModel item, DateTime today) {
  switch (item.status(today)) {
    case PromoStatus.archived:
      return 'В архиве';
    case PromoStatus.used:
      final used = item.usedAt;
      return used == null
          ? 'Использовано'
          : 'Использовано ${_date(used.toLocal())}';
    case PromoStatus.expired:
      return '${item.isPoints ? 'Сгорели' : 'Истёк'} ${_date(item.expiresAt!)}';
    case PromoStatus.active:
      final days = item.daysLeft(today);
      if (days == null) return 'Срок не указан';
      if (days == 0) return 'Истекает сегодня';
      if (days == 1) return 'Сгорит завтра';
      return 'Сгорит через $days дн.';
  }
}

/// «Ozon · скидка 500 ₽» / «Пятёрочка · 300 баллов».
String promoSummary(PromoModel item) => [
      if (item.merchant != null) item.merchant!,
      if (item.isPoints && item.pointsAmount != null)
        '${formatPromoPoints(item.pointsAmount!)} ${item.pointsUnit ?? 'баллов'}',
      if (!item.isPoints && item.discount != null) item.discount!,
    ].join(' · ');

Future<void> copyPromoCode(BuildContext context, String code) async {
  await Clipboard.setData(ClipboardData(text: code));
  if (!context.mounted) return;
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text('Промокод $code скопирован')));
}

class PromoTile extends StatelessWidget {
  const PromoTile({
    super.key,
    required this.item,
    required this.today,
    required this.onTap,
  });

  final PromoModel item;
  final DateTime today;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final urgent = item.isUrgent(today);
    final noExpiry = item.expiresAt == null &&
        item.status(today) == PromoStatus.active;
    final summary = promoSummary(item);
    final code = item.promoCode;
    return Card(
      key: ValueKey('promo-tile-${item.localKey}'),
      shape: urgent
          ? RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
              side: BorderSide(color: scheme.error, width: 1.5),
            )
          : null,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 8, 14),
          child: Row(
            children: [
              CircleAvatar(
                backgroundColor:
                    urgent ? scheme.errorContainer : scheme.secondaryContainer,
                child: Icon(
                  item.isPoints
                      ? Icons.stars_outlined
                      : Icons.confirmation_number_outlined,
                  color: urgent ? scheme.onErrorContainer : null,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: textTheme.titleMedium,
                    ),
                    if (summary.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        summary,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: textTheme.bodySmall,
                      ),
                    ],
                    if (code != null) ...[
                      const SizedBox(height: 2),
                      Text(
                        'Код: $code',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: textTheme.bodyMedium?.copyWith(
                          fontFamily: 'monospace',
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        if (urgent || noExpiry) ...[
                          Icon(
                            urgent
                                ? Icons.local_fire_department_outlined
                                : Icons.help_outline,
                            size: 16,
                            color: urgent ? scheme.error : scheme.tertiary,
                          ),
                          const SizedBox(width: 4),
                        ],
                        Flexible(
                          child: Text(
                            promoExpiryLabel(item, today),
                            key: ValueKey('promo-expiry-${item.localKey}'),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: textTheme.bodySmall?.copyWith(
                              color: urgent
                                  ? scheme.error
                                  : noExpiry
                                      ? scheme.tertiary
                                      : null,
                              fontWeight: urgent ? FontWeight.w800 : null,
                            ),
                          ),
                        ),
                      ],
                    ),
                    if (item.isPending) ...[
                      const SizedBox(height: 4),
                      Text(
                        'Сохранено на устройстве, ещё не отправлено',
                        style: textTheme.labelSmall
                            ?.copyWith(color: scheme.tertiary),
                      ),
                    ],
                  ],
                ),
              ),
              if (code != null)
                IconButton(
                  key: ValueKey('promo-copy-${item.localKey}'),
                  tooltip: 'Скопировать промокод',
                  onPressed: () => copyPromoCode(context, code),
                  icon: const Icon(Icons.copy_rounded),
                )
              else
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 8),
                  child: Icon(Icons.chevron_right),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class PromoDetailsScreen extends StatefulWidget {
  const PromoDetailsScreen({super.key, required this.promoKey});

  /// [PromoModel.localKey]; an offline item keeps resolving after it syncs.
  final String promoKey;

  @override
  State<PromoDetailsScreen> createState() => _PromoDetailsScreenState();
}

class _PromoDetailsScreenState extends State<PromoDetailsScreen> {
  bool _busy = false;

  PromoModel? _find(DataProvider provider) =>
      provider.promos
          .where((item) =>
              item.localKey == widget.promoKey ||
              (item.clientId != null &&
                  'client:${item.clientId}' == widget.promoKey))
          .firstOrNull;

  Future<void> _run(Future<void> Function() action) async {
    setState(() => _busy = true);
    try {
      await action();
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Не получилось: $error')),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _delete(DataProvider provider, PromoModel item) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Удалить запись?'),
        content: Text('«${item.title}» будет удалена без возможности '
            'восстановления. Чтобы просто убрать её из списка, используйте '
            'архив.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Отмена'),
          ),
          FilledButton(
            key: const ValueKey('promo-delete-confirm'),
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Удалить'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    await _run(() async {
      await provider.deletePromo(item);
      if (mounted) Navigator.of(context).pop();
    });
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<DataProvider>();
    final item = _find(provider);
    if (item == null) {
      return Scaffold(
        appBar: AppBar(leading: const KeyboardFirstBackButton()),
        body: const Center(child: Text('Запись не найдена')),
      );
    }
    final today = provider.businessToday;
    final status = item.status(today);
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final urgent = item.isUrgent(today);
    final id = item.id;
    final synced = id != null && !item.isPending;
    final code = item.promoCode;
    return Scaffold(
      appBar: AppBar(
        leading: const KeyboardFirstBackButton(),
        title: Text(item.isPoints ? 'Баллы' : 'Промокод'),
      ),
      body: SafeArea(
        top: false,
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 680),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
              children: [
                Text(item.title, style: textTheme.headlineSmall),
                if (item.merchant != null) ...[
                  const SizedBox(height: 4),
                  Text(item.merchant!, style: textTheme.titleMedium),
                ],
                const SizedBox(height: 16),
                Container(
                  key: const ValueKey('promo-detail-status'),
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: urgent
                        ? scheme.errorContainer
                        : scheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        urgent
                            ? Icons.local_fire_department_outlined
                            : status == PromoStatus.active
                                ? Icons.schedule
                                : Icons.history,
                        color: urgent ? scheme.onErrorContainer : null,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          promoExpiryLabel(item, today),
                          style: textTheme.titleSmall?.copyWith(
                            color: urgent ? scheme.onErrorContainer : null,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                if (code != null) ...[
                  const SizedBox(height: 16),
                  Container(
                    padding: const EdgeInsets.fromLTRB(16, 10, 10, 10),
                    decoration: BoxDecoration(
                      border: Border.all(color: scheme.outline),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: SelectableText(
                            code,
                            style: textTheme.titleLarge?.copyWith(
                              fontFamily: 'monospace',
                              fontWeight: FontWeight.w800,
                              letterSpacing: 1.2,
                            ),
                          ),
                        ),
                        FilledButton.tonalIcon(
                          key: const ValueKey('promo-detail-copy'),
                          onPressed: () => copyPromoCode(context, code),
                          icon: const Icon(Icons.copy_rounded),
                          label: const Text('Скопировать'),
                        ),
                      ],
                    ),
                  ),
                ],
                const SizedBox(height: 12),
                if (!item.isPoints && item.discount != null)
                  _Fact('Выгода', item.discount!),
                if (item.isPoints && item.pointsAmount != null)
                  _Fact(
                    'Баллы',
                    '${formatPromoPoints(item.pointsAmount!)} '
                        '${item.pointsUnit ?? 'баллов'}',
                  ),
                if (item.startsAt != null)
                  _Fact('Действует с', _date(item.startsAt!)),
                _Fact(
                  'Действует до',
                  item.expiresAt == null
                      ? 'Не указано'
                      : '${_date(item.expiresAt!)} включительно',
                ),
                _Fact(
                  'Напоминания',
                  item.expiresAt == null
                      ? 'Нет — срок не указан'
                      : ReminderDaysField.summary(
                          item.reminderDays,
                          dueDay: 'В последний день',
                        ),
                ),
                if (item.description != null)
                  _Fact('Условия', item.description!),
                if (item.isPending)
                  Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: Text(
                      'Сохранено только на этом устройстве. Запись '
                      'отправится на сервер при следующем обновлении; '
                      'напоминания появятся после этого.',
                      style:
                          textTheme.bodySmall?.copyWith(color: scheme.tertiary),
                    ),
                  ),
                if (item.sourceText != null) ...[
                  const SizedBox(height: 8),
                  ExpansionTile(
                    key: const ValueKey('promo-source'),
                    tilePadding: EdgeInsets.zero,
                    title: const Text('Исходное сообщение'),
                    children: [
                      Align(
                        alignment: Alignment.centerLeft,
                        child: SelectableText(item.sourceText!),
                      ),
                      const SizedBox(height: 8),
                    ],
                  ),
                ],
                const SizedBox(height: 20),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    if (synced &&
                        (status == PromoStatus.active ||
                            status == PromoStatus.expired))
                      FilledButton.icon(
                        key: const ValueKey('promo-mark-used'),
                        onPressed: _busy
                            ? null
                            : () => _run(() => provider.setPromoUsed(id, true)),
                        icon: const Icon(Icons.check_rounded),
                        label: const Text('Использовано'),
                      ),
                    if (synced && status == PromoStatus.used)
                      OutlinedButton.icon(
                        key: const ValueKey('promo-unuse'),
                        onPressed: _busy
                            ? null
                            : () =>
                                _run(() => provider.setPromoUsed(id, false)),
                        icon: const Icon(Icons.undo_rounded),
                        label: const Text('Вернуть в активные'),
                      ),
                    OutlinedButton.icon(
                      key: const ValueKey('promo-edit'),
                      onPressed: _busy
                          ? null
                          : () => Navigator.of(context).push(
                                MaterialPageRoute<void>(
                                  builder: (_) =>
                                      PromoEditScreen(existing: item),
                                ),
                              ),
                      icon: const Icon(Icons.edit_outlined),
                      label: const Text('Изменить'),
                    ),
                    if (synced)
                      OutlinedButton.icon(
                        key: const ValueKey('promo-archive'),
                        onPressed: _busy
                            ? null
                            : () => _run(() => provider.setPromoArchived(
                                  id,
                                  !item.isArchived,
                                )),
                        icon: Icon(item.isArchived
                            ? Icons.unarchive_outlined
                            : Icons.archive_outlined),
                        label:
                            Text(item.isArchived ? 'Восстановить' : 'В архив'),
                      ),
                    TextButton.icon(
                      key: const ValueKey('promo-delete'),
                      onPressed: _busy ? null : () => _delete(provider, item),
                      icon: const Icon(Icons.delete_outline),
                      label: const Text('Удалить'),
                      style: TextButton.styleFrom(
                        foregroundColor: scheme.error,
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
}

class _Fact extends StatelessWidget {
  const _Fact(this.label, this.value);

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
            ),
            const SizedBox(height: 2),
            Text(value, style: Theme.of(context).textTheme.bodyLarge),
          ],
        ),
      );
}

/// Create or edit an item. [initialText] pre-fills the paste field and
/// parses it immediately: the entry point for a future Android share intent.
class PromoEditScreen extends StatefulWidget {
  const PromoEditScreen({super.key, this.existing, this.initialText});

  final PromoModel? existing;
  final String? initialText;

  @override
  State<PromoEditScreen> createState() => _PromoEditScreenState();
}

class _PromoEditScreenState extends State<PromoEditScreen> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _source;
  late final TextEditingController _title;
  late final TextEditingController _merchant;
  late final TextEditingController _code;
  late final TextEditingController _discount;
  late final TextEditingController _pointsAmount;
  late final TextEditingController _pointsUnit;
  late final TextEditingController _description;
  late PromoKind _kind;
  DateTime? _expiresAt;
  DateTime? _startsAt;
  late List<int> _reminderDays;
  PromoParseResult? _parsed;
  String? _autoTitle;
  bool _parsing = false;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final item = widget.existing;
    _source = TextEditingController(
      text: item?.sourceText ?? widget.initialText ?? '',
    );
    _title = TextEditingController(text: item?.title ?? '');
    _merchant = TextEditingController(text: item?.merchant ?? '');
    _code = TextEditingController(text: item?.promoCode ?? '');
    _discount = TextEditingController(text: item?.discount ?? '');
    _pointsAmount = TextEditingController(
      text: item?.pointsAmount == null
          ? ''
          : formatPromoPoints(item!.pointsAmount!).replaceAll(' ', ''),
    );
    _pointsUnit = TextEditingController(text: item?.pointsUnit ?? 'баллов');
    _description = TextEditingController(text: item?.description ?? '');
    _kind = item?.kind ?? PromoKind.promo;
    _expiresAt = item?.expiresAt;
    _startsAt = item?.startsAt;
    _reminderDays =
        item?.reminderDays.toList() ?? List.of(defaultPromoReminderDays);
    final initialText = widget.initialText?.trim() ?? '';
    if (item == null && initialText.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _parse();
      });
    }
  }

  @override
  void dispose() {
    for (final controller in [
      _source,
      _title,
      _merchant,
      _code,
      _discount,
      _pointsAmount,
      _pointsUnit,
      _description,
    ]) {
      controller.dispose();
    }
    super.dispose();
  }

  Future<void> _pasteFromClipboard() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final text = data?.text ?? '';
    if (!mounted) return;
    if (text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('В буфере обмена нет текста')),
      );
      return;
    }
    setState(() => _source.text = text);
    await _parse();
  }

  Future<void> _parse() async {
    final text = _source.text;
    if (text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Вставьте текст сообщения')),
      );
      return;
    }
    FocusScope.of(context).unfocus();
    setState(() => _parsing = true);
    try {
      final result = await context.read<DataProvider>().parsePromoText(text);
      if (!mounted) return;
      setState(() => _apply(result, text));
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Не удалось разобрать: $error')),
      );
    } finally {
      if (mounted) setState(() => _parsing = false);
    }
  }

  void _apply(PromoParseResult result, String text) {
    _parsed = result;
    if (!result.offline) _kind = result.kind;
    void fill(TextEditingController controller, String? value) {
      if (value != null && value.isNotEmpty) controller.text = value;
    }

    fill(_merchant, result.merchant);
    fill(_code, result.promoCode);
    fill(_discount, result.discount);
    fill(_pointsUnit, result.pointsUnit);
    fill(_description, result.description);
    if (result.pointsAmount != null) {
      _pointsAmount.text =
          formatPromoPoints(result.pointsAmount!).replaceAll(' ', '');
    }
    if (result.expiresAt != null) _expiresAt = result.expiresAt;
    if (result.startsAt != null) _startsAt = result.startsAt;
    final title = result.title ?? _firstLine(text);
    if (_title.text.trim().isEmpty || _title.text == _autoTitle) {
      _title.text = title;
      _autoTitle = title;
    }
  }

  static String _firstLine(String text) {
    final line = text.trim().split('\n').first.trim();
    return line.length <= 60 ? line : '${line.substring(0, 59).trimRight()}…';
  }

  String? _optional(TextEditingController controller) {
    final value = controller.text.trim();
    return value.isEmpty ? null : value;
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    final start = _startsAt, end = _expiresAt;
    if (start != null && end != null && start.isAfter(end)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Дата начала позже даты окончания'),
        ),
      );
      return;
    }
    final previous = widget.existing;
    final points = _kind == PromoKind.points;
    final amountText = _pointsAmount.text.replaceAll(' ', '').trim();
    final item = PromoModel(
      id: previous?.id,
      clientId: previous?.clientId,
      kind: _kind,
      title: _title.text.trim(),
      merchant: _optional(_merchant),
      promoCode: points ? null : _optional(_code),
      discount: points ? null : _optional(_discount),
      pointsAmount: points && amountText.isNotEmpty
          ? double.parse(amountText.replaceAll(',', '.'))
          : null,
      pointsUnit: points ? _optional(_pointsUnit) : null,
      description: _optional(_description),
      // The pasted message is kept verbatim.
      sourceText: _source.text.trim().isEmpty ? null : _source.text,
      startsAt: _startsAt,
      expiresAt: _expiresAt,
      reminderDays: List.unmodifiable(_reminderDays),
      usedAt: previous?.usedAt,
      isUsed: previous?.isUsed ?? false,
      archivedAt: previous?.archivedAt,
      isArchived: previous?.isArchived ?? false,
      createdAt: previous?.createdAt,
      updatedAt: previous?.updatedAt,
      isPending: previous?.isPending ?? false,
    );
    setState(() => _saving = true);
    final provider = context.read<DataProvider>();
    final messenger = ScaffoldMessenger.of(context);
    try {
      final saved = previous == null
          ? await provider.createPromo(item)
          : await provider.updatePromo(item);
      if (previous == null && saved.isPending) {
        messenger.showSnackBar(const SnackBar(
          content: Text('Нет связи с сервером — сохранено на устройстве. '
              'Отправим при следующем обновлении.'),
        ));
      }
      if (!saved.isPending &&
          saved.expiresAt != null &&
          saved.reminderDays.isNotEmpty) {
        await provider.requestPromoNotificationPermission();
      }
      if (mounted) Navigator.pop(context);
    } catch (error) {
      if (!mounted) return;
      setState(() => _saving = false);
      messenger.showSnackBar(
        SnackBar(content: Text('Не удалось сохранить: $error')),
      );
    }
  }

  Future<void> _pickDate({required bool expiry}) async {
    final today = context.read<DataProvider>().businessToday;
    final current = expiry ? _expiresAt : _startsAt;
    final result = await showDatePicker(
      context: context,
      initialDate: current ?? today,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (result == null || !mounted) return;
    final value = DateTime(result.year, result.month, result.day);
    setState(() => expiry ? _expiresAt = value : _startsAt = value);
  }

  @override
  Widget build(BuildContext context) {
    final points = _kind == PromoKind.points;
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        leading: const KeyboardFirstBackButton(),
        title: Text(widget.existing == null ? 'Новая запись' : 'Изменение'),
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
                  TextField(
                    key: const ValueKey('promo-source-text'),
                    controller: _source,
                    minLines: 4,
                    maxLines: 10,
                    keyboardType: TextInputType.multiline,
                    decoration: const InputDecoration(
                      labelText: 'Вставьте текст сообщения',
                      hintText: 'SMS, сообщение из мессенджера или текст '
                          'баннера — найдём срок, промокод и баллы',
                      alignLabelWithHint: true,
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      OutlinedButton.icon(
                        key: const ValueKey('promo-paste'),
                        onPressed: _parsing ? null : _pasteFromClipboard,
                        icon: const Icon(Icons.content_paste_rounded),
                        label: const Text('Вставить из буфера'),
                      ),
                      FilledButton.tonalIcon(
                        key: const ValueKey('promo-parse'),
                        onPressed: _parsing ? null : _parse,
                        icon: _parsing
                            ? const SizedBox.square(
                                dimension: 18,
                                child:
                                    CircularProgressIndicator(strokeWidth: 2),
                              )
                            : const Icon(Icons.auto_fix_high_outlined),
                        label: const Text('Разобрать'),
                      ),
                    ],
                  ),
                  if (_parsed != null) _ParseSummary(result: _parsed!),
                  const SizedBox(height: 20),
                  SegmentedButton<PromoKind>(
                    key: const ValueKey('promo-kind'),
                    segments: const [
                      ButtonSegment(
                        value: PromoKind.promo,
                        icon: Icon(Icons.confirmation_number_outlined),
                        label: Text('Промокод, акция'),
                      ),
                      ButtonSegment(
                        value: PromoKind.points,
                        icon: Icon(Icons.stars_outlined),
                        label: Text('Баллы'),
                      ),
                    ],
                    selected: {_kind},
                    onSelectionChanged: (value) =>
                        setState(() => _kind = value.first),
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    key: const ValueKey('promo-title'),
                    controller: _title,
                    maxLength: 200,
                    textInputAction: TextInputAction.next,
                    decoration: InputDecoration(
                      labelText: 'Название',
                      hintText:
                          points ? 'Баллы Пятёрочки' : 'Скидка 20% на обувь',
                      counterText: '',
                    ),
                    validator: (value) => value == null || value.trim().isEmpty
                        ? 'Введите название'
                        : null,
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    key: const ValueKey('promo-merchant'),
                    controller: _merchant,
                    maxLength: 200,
                    textInputAction: TextInputAction.next,
                    decoration: const InputDecoration(
                      labelText: 'Где (магазин, сервис) — необязательно',
                      counterText: '',
                    ),
                  ),
                  const SizedBox(height: 12),
                  if (points)
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: TextFormField(
                            key: const ValueKey('promo-points-amount'),
                            controller: _pointsAmount,
                            keyboardType: const TextInputType.numberWithOptions(
                              decimal: true,
                            ),
                            inputFormatters: [
                              FilteringTextInputFormatter.allow(
                                RegExp(r'[0-9,. ]'),
                              ),
                            ],
                            decoration:
                                const InputDecoration(labelText: 'Сколько'),
                            validator: (value) {
                              final text =
                                  (value ?? '').replaceAll(' ', '').trim();
                              if (text.isEmpty) return null;
                              final parsed =
                                  double.tryParse(text.replaceAll(',', '.'));
                              return parsed == null || parsed < 0
                                  ? 'Число'
                                  : null;
                            },
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: TextFormField(
                            key: const ValueKey('promo-points-unit'),
                            controller: _pointsUnit,
                            maxLength: 40,
                            decoration: const InputDecoration(
                              labelText: 'Чего',
                              hintText: 'баллов, бонусов, ₽',
                              counterText: '',
                            ),
                          ),
                        ),
                      ],
                    )
                  else ...[
                    TextFormField(
                      key: const ValueKey('promo-code'),
                      controller: _code,
                      maxLength: 100,
                      style: const TextStyle(fontFamily: 'monospace'),
                      decoration: const InputDecoration(
                        labelText: 'Промокод — необязательно',
                        counterText: '',
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      key: const ValueKey('promo-discount'),
                      controller: _discount,
                      maxLength: 100,
                      decoration: const InputDecoration(
                        labelText: 'Выгода — необязательно',
                        hintText: 'скидка 20%, −500 ₽',
                        counterText: '',
                      ),
                    ),
                  ],
                  const SizedBox(height: 16),
                  _DateTile(
                    key: const ValueKey('promo-expires'),
                    label: 'Действует до (последний день)',
                    value: _expiresAt,
                    emptyText: 'Не указано',
                    onTap: () => _pickDate(expiry: true),
                    onClear: () => setState(() => _expiresAt = null),
                  ),
                  if (_expiresAt == null)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(4, 6, 4, 0),
                      child: Text(
                        'Без срока запись попадёт в конец списка, '
                        'напоминаний не будет.',
                        key: const ValueKey('promo-no-expiry-hint'),
                        style: Theme.of(context)
                            .textTheme
                            .bodySmall
                            ?.copyWith(color: scheme.tertiary),
                      ),
                    ),
                  const SizedBox(height: 8),
                  _DateTile(
                    key: const ValueKey('promo-starts'),
                    label: 'Действует с — необязательно',
                    value: _startsAt,
                    emptyText: 'Уже действует',
                    onTap: () => _pickDate(expiry: false),
                    onClear: () => setState(() => _startsAt = null),
                  ),
                  const SizedBox(height: 20),
                  ReminderDaysField(
                    value: _reminderDays,
                    dueDayLabel: 'В последний день',
                    onChanged: (value) => setState(() => _reminderDays = value),
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    key: const ValueKey('promo-description'),
                    controller: _description,
                    minLines: 1,
                    maxLines: 5,
                    maxLength: 4000,
                    decoration: const InputDecoration(
                      labelText: 'Условия, заметка — необязательно',
                      counterText: '',
                    ),
                  ),
                  const SizedBox(height: 28),
                  FilledButton(
                    key: const ValueKey('promo-save'),
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
}

class _ParseSummary extends StatelessWidget {
  const _ParseSummary({required this.result});

  final PromoParseResult result;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final found = [
      if (result.expiresAt != null) 'срок',
      if (result.promoCode != null) 'промокод',
      if (result.merchant != null) 'магазин',
      if (result.discount != null) 'выгода',
      if (result.pointsAmount != null) 'баллы',
    ];
    final lines = [
      if (result.offline)
        'Сервер недоступен — на устройстве распознаются только срок и код.',
      found.isEmpty
          ? 'Ничего не распознано — заполните поля вручную.'
          : 'Найдено: ${found.join(', ')}. Проверьте поля ниже.',
      if (result.expiresAt != null)
        'Срок: до ${_date(result.expiresAt!)}'
            '${result.expiryPhrase == null ? '' : ' («${result.expiryPhrase}»)'}'
            '${result.expiryGuessed ? ' — дата угадана, проверьте' : ''}'
      else
        'Срок не найден — укажите вручную или оставьте пустым.',
    ];
    final warn = result.expiresAt == null || result.expiryGuessed;
    return Container(
      key: const ValueKey('promo-parse-summary'),
      margin: const EdgeInsets.only(top: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: warn ? scheme.tertiaryContainer : scheme.secondaryContainer,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [for (final line in lines) Text(line)],
      ),
    );
  }
}

class _DateTile extends StatelessWidget {
  const _DateTile({
    super.key,
    required this.label,
    required this.value,
    required this.emptyText,
    required this.onTap,
    required this.onClear,
  });

  final String label;
  final DateTime? value;
  final String emptyText;
  final VoidCallback onTap;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) => ListTile(
        contentPadding: const EdgeInsets.only(left: 14, right: 4),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(color: Theme.of(context).colorScheme.outline),
        ),
        title: Text(label),
        subtitle: Text(value == null ? emptyText : _date(value!)),
        trailing: value == null
            ? const Padding(
                padding: EdgeInsets.only(right: 10),
                child: Icon(Icons.calendar_today_outlined),
              )
            : IconButton(
                tooltip: 'Очистить',
                onPressed: onClear,
                icon: const Icon(Icons.close),
              ),
        onTap: onTap,
      );
}
