import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/card_balance_model.dart';
import '../../providers/data_provider.dart';
import '../../services/card_context.dart';
import '../../utils/cashflow_formatters.dart';
import '../../utils/identity_icons.dart';
import '../widgets/keyboard_first_back.dart';

/// ZenMoney connection (admin enters the token) and the card → account
/// mapping (editor+ confirms or changes suggestions).
class CardBalancesSettingsScreen extends StatefulWidget {
  const CardBalancesSettingsScreen({super.key});

  @override
  State<CardBalancesSettingsScreen> createState() =>
      _CardBalancesSettingsScreenState();
}

/// Dropdown value for an explicit "this card has no ZenMoney account".
const _noAccount = '';

class _CardBalancesSettingsScreenState
    extends State<CardBalancesSettingsScreen> {
  CardBalanceMapping? _mapping;
  ZenmoneySettings? _settings;
  String? _error;
  bool _loading = true;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final provider = context.read<DataProvider>();
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final mapping = await provider.cardBalanceApi.mapping();
      final settings =
          provider.isAdmin ? await provider.cardBalanceApi.settings() : null;
      if (!mounted) return;
      setState(() {
        _mapping = mapping;
        _settings = settings;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = 'Не удалось загрузить данные: $error');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _run(Future<void> Function() action, String done) async {
    if (_busy) return;
    final provider = context.read<DataProvider>();
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _busy = true);
    try {
      await action();
      await provider.fetchCardBalances();
      await _load();
      messenger.showSnackBar(SnackBar(content: Text(done)));
    } catch (error) {
      messenger.showSnackBar(SnackBar(content: Text('$error')));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _refresh() => _run(
        () => context.read<DataProvider>().fetchCardBalances(force: true),
        'Запрос к ZenMoney выполнен',
      );

  Future<void> _enterToken() async {
    final controller = TextEditingController();
    final token = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Токен ZenMoney'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Токен хранится на сервере в зашифрованном виде и больше '
              'не показывается. Он общий для всех пользователей CashFlow.',
            ),
            const SizedBox(height: 12),
            TextField(
              key: const Key('zenmoney-token-field'),
              controller: controller,
              obscureText: true,
              autocorrect: false,
              enableSuggestions: false,
              decoration: const InputDecoration(
                labelText: 'Токен',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Отмена'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text.trim()),
            child: const Text('Сохранить'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (token == null || token.isEmpty || !mounted) return;
    await _run(
      () async {
        final settings =
            await context.read<DataProvider>().cardBalanceApi.setToken(token);
        _settings = settings;
      },
      'Токен сохранён',
    );
  }

  Future<void> _deleteToken() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Удалить токен?'),
        content: const Text(
          'Балансы перестанут обновляться и пропадут из приложения. '
          'Сопоставление карт сохранится.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Отмена'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Удалить'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    await _run(
      () => context.read<DataProvider>().cardBalanceApi.deleteToken(),
      'Токен удалён',
    );
  }

  Future<void> _setLink(int cardId, String? value) => _run(
        () => context
            .read<DataProvider>()
            .cardBalanceApi
            .setLink(cardId, value == _noAccount ? null : value),
        'Сопоставление сохранено',
      );

  Future<void> _resetLink(int cardId) => _run(
        () => context.read<DataProvider>().cardBalanceApi.resetLink(cardId),
        'Будет выбрано автоматически при следующем обновлении',
      );

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<DataProvider>();
    final body = !provider.canEdit
        ? const Center(child: Text('Доступно редактору и администратору'))
        : _loading && _mapping == null
            ? const Center(child: CircularProgressIndicator())
            : RefreshIndicator(
                onRefresh: _refresh,
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
                  children: [
                    if (_error != null)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: Text(
                          _error!,
                          style: TextStyle(
                              color: Theme.of(context).colorScheme.error),
                        ),
                      ),
                    if (_mapping != null)
                      _StatusCard(
                        status: _mapping!.status,
                        settings: _settings,
                        isAdmin: provider.isAdmin,
                        busy: _busy,
                        onEnterToken: _enterToken,
                        onDeleteToken: _deleteToken,
                      ),
                    if (_mapping != null &&
                        _mapping!.status.status.isEnabled) ...[
                      const SizedBox(height: 16),
                      Text('Карты',
                          style: Theme.of(context).textTheme.titleMedium),
                      const SizedBox(height: 4),
                      Text(
                        'Счёт подбирается по последним цифрам карты и банку. '
                        'Однозначное совпадение выбирается автоматически — '
                        'проверьте и при необходимости измените.',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                      const SizedBox(height: 8),
                      ..._cardRows(provider),
                    ],
                  ],
                ),
              );
    return Scaffold(
      appBar: AppBar(
        leading: const KeyboardFirstBackButton(),
        title: const Text('Балансы из ZenMoney'),
        actions: [
          if (provider.canEdit)
            IconButton(
              tooltip: 'Обновить из ZenMoney',
              onPressed: _busy ? null : _refresh,
              icon: const Icon(Icons.sync),
            ),
        ],
      ),
      body: SafeArea(top: false, child: body),
    );
  }

  List<Widget> _cardRows(DataProvider provider) {
    final mapping = _mapping!;
    final catalog = CardContextCatalog(
      cards: provider.cards,
      banks: provider.banks,
      users: provider.users,
    );
    final accounts = {for (final item in mapping.accounts) item.id: item};
    return [
      for (final entry in mapping.cards)
        _CardMappingTile(
          key: ValueKey('zenmoney-card-${entry.cardId}'),
          cardContext: catalog.forId(entry.cardId),
          entry: entry,
          accounts: mapping.accounts,
          selected: entry.accountId == null ? null : accounts[entry.accountId],
          busy: _busy,
          onChanged: (value) => _setLink(entry.cardId, value),
          onReset: entry.hasLink ? () => _resetLink(entry.cardId) : null,
        ),
    ];
  }
}

String _statusText(CardBalancesSnapshot status) {
  final now = DateTime.now();
  final success = status.lastSuccessAt;
  final updated =
      success == null ? '' : ' Данные ${freshnessLabel(success, now)}.';
  return switch (status.status) {
    CardBalanceStatus.notConfigured =>
      'На сервере не задан ключ шифрования CASHFLOW_SECRETS_KEY — '
          'интеграция выключена.',
    CardBalanceStatus.noToken => 'Токен ZenMoney не введён.',
    CardBalanceStatus.pending => 'Токен сохранён, данные ещё не загружены.',
    CardBalanceStatus.ok => 'Подключено.$updated',
    CardBalanceStatus.error =>
      'Последнее обновление не удалось (${status.lastErrorMessage ?? 'ошибка'}).'
          '$updated',
    CardBalanceStatus.tokenInvalid =>
      'ZenMoney не принимает токен — введите новый.$updated',
  };
}

class _StatusCard extends StatelessWidget {
  const _StatusCard({
    required this.status,
    required this.settings,
    required this.isAdmin,
    required this.busy,
    required this.onEnterToken,
    required this.onDeleteToken,
  });

  final CardBalancesSnapshot status;
  final ZenmoneySettings? settings;
  final bool isAdmin;
  final bool busy;
  final VoidCallback onEnterToken;
  final VoidCallback onDeleteToken;

  @override
  Widget build(BuildContext context) {
    final problem = status.status == CardBalanceStatus.error ||
        status.status == CardBalanceStatus.tokenInvalid;
    final tokenSet = settings?.tokenSet ?? status.status.isEnabled;
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  problem ? Icons.warning_amber_outlined : Icons.link_outlined,
                  color: problem
                      ? const Color(0xFF9A5A00)
                      : Theme.of(context).colorScheme.primary,
                ),
                const SizedBox(width: 8),
                Text('Подключение',
                    style: Theme.of(context).textTheme.titleMedium),
              ],
            ),
            const SizedBox(height: 8),
            Text(_statusText(status), key: const Key('zenmoney-status')),
            if (isAdmin &&
                status.status != CardBalanceStatus.notConfigured) ...[
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  FilledButton.icon(
                    key: const Key('zenmoney-enter-token'),
                    onPressed: busy ? null : onEnterToken,
                    icon: const Icon(Icons.key_outlined),
                    label: Text(tokenSet ? 'Заменить токен' : 'Ввести токен'),
                  ),
                  if (tokenSet)
                    OutlinedButton.icon(
                      onPressed: busy ? null : onDeleteToken,
                      icon: const Icon(Icons.delete_outline),
                      label: const Text('Удалить токен'),
                    ),
                ],
              ),
            ],
            if (!isAdmin && !status.status.isEnabled)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  'Токен вводит администратор.',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _CardMappingTile extends StatelessWidget {
  const _CardMappingTile({
    super.key,
    required this.cardContext,
    required this.entry,
    required this.accounts,
    required this.selected,
    required this.busy,
    required this.onChanged,
    this.onReset,
  });

  final CardContext cardContext;
  final CardAccountMapping entry;
  final List<ZenmoneyAccountOption> accounts;
  final ZenmoneyAccountOption? selected;
  final bool busy;
  final ValueChanged<String?> onChanged;
  final VoidCallback? onReset;

  String _accountLabel(ZenmoneyAccountOption account) => [
        account.title,
        if (account.companyTitle?.isNotEmpty == true) account.companyTitle!,
        if (account.syncIds.isNotEmpty) '•${account.syncIds.join(', ')}',
        if (account.archived) 'в архиве',
        if (account.missing) 'удалён в ZenMoney',
      ].join(' · ');

  @override
  Widget build(BuildContext context) {
    final digits = cardContext.card.lastFourDigits?.trim();
    final suggested = {for (final item in entry.suggestions) item.accountId};
    final value = entry.hasLink ? (entry.accountId ?? _noAccount) : null;
    final hint = entry.ambiguous
        ? 'Подходит несколько счетов — выберите'
        : entry.suggestions.isEmpty
            ? 'Не сопоставлено'
            : 'Предложено, не выбрано';
    final account = selected;
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                BankIconBadge(
                  iconKey: cardContext.bankIconKey,
                  bankName: cardContext.bankName,
                  size: 28,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    [
                      cardContext.ownerAndBankLabel,
                      if (digits?.isNotEmpty == true) '•$digits',
                    ].join(' · '),
                    style: Theme.of(context)
                        .textTheme
                        .titleSmall
                        ?.copyWith(fontWeight: FontWeight.w700),
                  ),
                ),
                if (entry.source == 'auto')
                  const Chip(
                    visualDensity: VisualDensity.compact,
                    label: Text('авто'),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            DropdownButtonFormField<String>(
              // Rebuilt from server data after every change.
              key: ValueKey('zenmoney-select-${entry.cardId}-$value'),
              initialValue: value,
              isExpanded: true,
              hint: Text(hint),
              decoration: const InputDecoration(
                isDense: true,
                border: OutlineInputBorder(),
                labelText: 'Счёт ZenMoney',
              ),
              items: [
                const DropdownMenuItem(
                  value: _noAccount,
                  child: Text('Нет счёта — не показывать баланс'),
                ),
                for (final option in accounts)
                  DropdownMenuItem(
                    value: option.id,
                    child: Text(
                      '${suggested.contains(option.id) ? '★ ' : ''}'
                      '${_accountLabel(option)}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
              ],
              onChanged: busy ? null : onChanged,
            ),
            if (account != null) ...[
              const SizedBox(height: 6),
              Text(
                [
                  account.creditLimit > 0
                      ? 'доступно ${moneyLabel(account.available, account.currency)}'
                          ' (лимит ${moneyLabel(account.creditLimit, account.currency)})'
                      : moneyLabel(account.balance, account.currency),
                  if (account.fetchedAt != null)
                    freshnessLabel(account.fetchedAt!, DateTime.now()),
                ].join(' · '),
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
            if (onReset != null)
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton(
                  onPressed: busy ? null : onReset,
                  child: const Text('Выбирать автоматически'),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
