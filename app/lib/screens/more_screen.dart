import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../config/app_build_info.dart';
import '../providers/data_provider.dart';
import '../services/app_session_type.dart';
import '../services/cashback_import_launcher.dart';
import 'admin/admin_hub_screen.dart';
import 'settings/banks_settings.dart';
import 'settings/cards_settings.dart';
import 'settings/mcc_rules_settings_screen.dart';
import 'settings/users_settings.dart';

class MoreScreen extends StatefulWidget {
  const MoreScreen({
    super.key,
    this.sessionType,
    this.now,
  });

  final AppSessionType? sessionType;
  final DateTime Function()? now;

  @override
  State<MoreScreen> createState() => _MoreScreenState();
}

class _MoreScreenState extends State<MoreScreen> {
  bool _refreshing = false;
  bool _refreshFailed = false;

  DateTime get _now => widget.now?.call() ?? DateTime.now();

  Future<void> _refresh(DataProvider provider) async {
    if (_refreshing) return;
    setState(() {
      _refreshing = true;
      _refreshFailed = false;
    });
    final updated = await provider.fetchAllData();
    if (!mounted) return;
    setState(() {
      _refreshing = false;
      _refreshFailed = !updated;
    });
    if (updated) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Данные обновлены')),
      );
    }
  }

  Future<CashbackImportProfile?> _selectBrowserProfile(
    DataProvider provider,
  ) {
    final users = [...provider.users]..sort((a, b) => a.id.compareTo(b.id));
    return showDialog<CashbackImportProfile>(
      context: context,
      builder: (dialogContext) => SimpleDialog(
        title: const Text('Выберите профиль браузера'),
        children: [
          for (final profile in cashbackImportProfiles)
            SimpleDialogOption(
              onPressed: () => Navigator.pop(dialogContext, profile),
              child: ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.person_outline),
                title: Text(
                  profile.userSlot < users.length
                      ? users[profile.userSlot].name
                      : profile.label,
                ),
                subtitle: Text(
                  '${profile.label} · '
                  '${profile.banks.contains('vtb') ? 'все банки' : 'без ВТБ'}',
                ),
              ),
            ),
        ],
      ),
    );
  }

  Future<void> _launchCashbackBrowser(DataProvider provider) async {
    final profile = await _selectBrowserProfile(provider);
    if (profile == null || !mounted) return;
    final error = await launchCashbackImport(profile);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          error ??
              '${profile.label} открыт. Авторизуйтесь в банках и скачайте JSON.',
        ),
      ),
    );
  }

  Future<int?> _selectImportUser(DataProvider provider) async {
    if (provider.users.isEmpty) return null;
    if (provider.users.length == 1) return provider.users.single.id;
    var selectedUserId = provider.users.first.id;
    return showDialog<int>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Кому импортировать категории?'),
        content: StatefulBuilder(
          builder: (context, setDialogState) => DropdownButtonFormField<int>(
            initialValue: selectedUserId,
            decoration: const InputDecoration(
              labelText: 'Владелец карт',
              border: OutlineInputBorder(),
            ),
            items: [
              for (final user in provider.users)
                DropdownMenuItem(value: user.id, child: Text(user.name)),
            ],
            onChanged: (value) {
              if (value != null) {
                setDialogState(() => selectedUserId = value);
              }
            },
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Отмена'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, selectedUserId),
            child: const Text('Импортировать'),
          ),
        ],
      ),
    );
  }

  Future<void> _importCashback(DataProvider provider) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      final file = await pickCashbackImportFile();
      if (file == null || !mounted) return;
      final userId = await _selectImportUser(provider);
      if (userId == null || !mounted) return;
      final result = await provider.importCashbackDocument(
        file.contents,
        userId,
      );
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            'Импортировано банков: ${result.importedBanks}; '
            'создано: ${result.created}, обновлено: ${result.updated}; '
            'партнёрских предложений создано: '
            '${result.createdPartnerOffers}, обновлено: '
            '${result.updatedPartnerOffers}.',
          ),
        ),
      );
    } catch (error) {
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(content: Text('Не удалось импортировать JSON: $error')),
      );
    }
  }

  Future<void> _pickCashbackDate(DataProvider provider) async {
    final selected = await showDatePicker(
      context: context,
      initialDate: provider.cashbackEffectiveDate,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
    );
    if (selected != null) await provider.setCashbackEffectiveDate(selected);
  }

  void _open(Widget screen) {
    Navigator.push(context, MaterialPageRoute(builder: (_) => screen));
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<DataProvider>();
    final sessionType = widget.sessionType ?? detectAppSessionType();
    final showWindowsTools =
        sessionType == AppSessionType.windows && provider.canEdit;

    return LayoutBuilder(
      builder: (context, constraints) {
        final twoColumns = constraints.maxWidth >= 900;
        final horizontalPadding = constraints.maxWidth >= 600 ? 32.0 : 16.0;
        return ColoredBox(
          color: Theme.of(context).colorScheme.surfaceContainerLowest,
          child: SafeArea(
            top: false,
            child: SingleChildScrollView(
              padding: EdgeInsets.fromLTRB(
                horizontalPadding,
                24,
                horizontalPadding,
                32,
              ),
              child: Align(
                alignment: Alignment.topCenter,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 1120),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _Header(provider: provider),
                      const SizedBox(height: 24),
                      if (twoColumns)
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              child: Column(
                                children: [
                                  _dataPanel(provider, showWindowsTools),
                                  const SizedBox(height: 20),
                                  _parametersPanel(provider),
                                  const SizedBox(height: 20),
                                  const _FutureFamilyCard(),
                                ],
                              ),
                            ),
                            const SizedBox(width: 20),
                            Expanded(
                              child: Column(
                                children: [
                                  if (provider.isAdmin) ...[
                                    _managementPanel(provider),
                                    const SizedBox(height: 20),
                                  ],
                                  _accountPanel(provider),
                                ],
                              ),
                            ),
                          ],
                        )
                      else ...[
                        _dataPanel(provider, showWindowsTools),
                        if (provider.isAdmin) ...[
                          const SizedBox(height: 20),
                          _managementPanel(provider),
                        ],
                        const SizedBox(height: 20),
                        _parametersPanel(provider),
                        const SizedBox(height: 20),
                        const _FutureFamilyCard(),
                        const SizedBox(height: 20),
                        _accountPanel(provider),
                      ],
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

  Widget _dataPanel(DataProvider provider, bool showWindowsTools) {
    return _Panel(
      title: 'Данные',
      subtitle: showWindowsTools
          ? 'Обновление с сервера и локальные Windows-инструменты'
          : 'Обновление данных с сервера',
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: _RefreshCard(
            refreshing: _refreshing,
            failed: _refreshFailed,
            lastUpdated: _formatLastUpdated(provider.lastUpdated),
            onRefresh: () => _refresh(provider),
          ),
        ),
        if (showWindowsTools) ...[
          _HubRow(
            icon: Icons.download_for_offline_outlined,
            title: 'Запросить кешбэк',
            subtitle: 'Открыть банки в локальном Chrome',
            badge: 'Windows',
            onTap: () => _launchCashbackBrowser(provider),
          ),
          _HubRow(
            icon: Icons.upload_file_outlined,
            title: 'Импортировать JSON',
            subtitle: 'Категории и партнёрские акции',
            badge: 'Windows',
            onTap: () => _importCashback(provider),
          ),
        ],
      ],
    );
  }

  Widget _managementPanel(DataProvider provider) {
    return _Panel(
      title: 'Управление данными',
      subtitle: 'Доступно администратору',
      children: [
        _HubRow(
          icon: Icons.admin_panel_settings_outlined,
          title: 'Центр управления',
          subtitle: 'Все административные разделы',
          onTap: () => _open(const AdminHubScreen()),
        ),
        _HubRow(
          icon: Icons.people_outline,
          title: 'Владельцы карт',
          subtitle: 'Кому принадлежат карты',
          value: '${provider.users.length}',
          onTap: () => _open(const UsersSettingsScreen()),
        ),
        _HubRow(
          icon: Icons.credit_card_outlined,
          title: 'Карты',
          subtitle: 'Банк и владелец',
          value: '${provider.cards.length}',
          onTap: () => _open(const CardsSettingsScreen()),
        ),
        _HubRow(
          icon: Icons.account_balance_outlined,
          title: 'Банки',
          subtitle: 'Справочник банков',
          value: '${provider.banks.length}',
          onTap: () => _open(const BanksSettingsScreen()),
        ),
        _HubRow(
          icon: Icons.rule_folder_outlined,
          title: 'Правила MCC',
          subtitle: 'Ревизии и публикация',
          onTap: () => _open(const MccRulesSettingsScreen()),
        ),
      ],
    );
  }

  Widget _parametersPanel(DataProvider provider) {
    return _Panel(
      title: 'Параметры расчёта',
      children: [
        _HubRow(
          icon: Icons.event_outlined,
          title: 'Расчётная дата кешбэка',
          subtitle: provider.usesCurrentCashbackDate
              ? 'Используется текущая дата'
              : 'Исторический режим',
          value: _formatDate(provider.cashbackEffectiveDate),
          onTap: () => _pickCashbackDate(provider),
        ),
        if (!provider.usesCurrentCashbackDate)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: () => provider.setCashbackEffectiveDate(null),
                icon: const Icon(Icons.today_outlined),
                label: const Text('Использовать сегодня'),
              ),
            ),
          ),
      ],
    );
  }

  Widget _accountPanel(DataProvider provider) {
    final identity = provider.currentAuthUser;
    return _Panel(
      title: 'Аккаунт и приложение',
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: Column(
            children: [
              _Fact(
                label: 'Пользователь',
                value: '${identity?.username ?? '—'} · '
                    '${_roleLabel(identity?.role)}',
              ),
              _Fact(label: 'Сервер', value: provider.serverIp),
              const _Fact(label: 'Версия', value: appVersionLabel),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                height: 48,
                child: OutlinedButton.icon(
                  key: const ValueKey('logoutButton'),
                  onPressed: provider.logout,
                  icon: const Icon(Icons.logout),
                  label: const Text('Выйти из аккаунта'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Theme.of(context).colorScheme.error,
                    side: BorderSide(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  String _formatLastUpdated(String? value) {
    if (value == null) return 'ещё не обновлялись';
    final parsed = DateTime.tryParse(value);
    if (parsed == null) return value;
    final local = parsed.toLocal();
    final today = _now;
    final time = '${local.hour.toString().padLeft(2, '0')}:'
        '${local.minute.toString().padLeft(2, '0')}';
    if (local.year == today.year &&
        local.month == today.month &&
        local.day == today.day) {
      return 'сегодня в $time';
    }
    return '${_formatDate(local)} в $time';
  }

  String _formatDate(DateTime date) => '${date.day.toString().padLeft(2, '0')}.'
      '${date.month.toString().padLeft(2, '0')}.${date.year}';

  String _roleLabel(String? role) => switch (role) {
        'admin' => 'Администратор',
        'editor' => 'Редактор',
        'viewer' => 'Просмотр',
        _ => 'Роль не указана',
      };
}

class _Header extends StatelessWidget {
  const _Header({required this.provider});

  final DataProvider provider;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Ещё', style: Theme.of(context).textTheme.headlineMedium),
              const SizedBox(height: 4),
              Text(
                'Данные, справочники и параметры приложения',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 16),
        Tooltip(
          message: 'Аккаунт ${provider.currentAuthUser?.username ?? ''}',
          child: CircleAvatar(
            child: Text(_initials(provider.currentAuthUser?.username)),
          ),
        ),
      ],
    );
  }

  static String _initials(String? username) {
    final value = username?.trim();
    if (value == null || value.isEmpty) return '—';
    return value.characters.first.toUpperCase();
  }
}

class _Panel extends StatelessWidget {
  const _Panel({required this.title, required this.children, this.subtitle});

  final String title;
  final String? subtitle;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Material(
      color: colors.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(color: colors.outlineVariant),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 16, 18, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: Theme.of(context).textTheme.titleMedium),
                if (subtitle != null) ...[
                  const SizedBox(height: 4),
                  Text(
                    subtitle!,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: colors.onSurfaceVariant,
                        ),
                  ),
                ],
              ],
            ),
          ),
          ...children,
        ],
      ),
    );
  }
}

class _RefreshCard extends StatelessWidget {
  const _RefreshCard({
    required this.refreshing,
    required this.failed,
    required this.lastUpdated,
    required this.onRefresh,
  });

  final bool refreshing;
  final bool failed;
  final String lastUpdated;
  final VoidCallback onRefresh;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final largeText = MediaQuery.textScalerOf(context).scale(1) >= 1.5;
    final status = Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(
          failed ? Icons.cloud_off_outlined : Icons.cloud_done_outlined,
          color: failed ? colors.onErrorContainer : colors.onPrimaryContainer,
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                failed ? 'Не удалось обновить' : 'Данные обновлены',
                style: Theme.of(context).textTheme.titleSmall,
              ),
              const SizedBox(height: 2),
              Text(
                failed ? 'Показываем сохранённые данные' : lastUpdated,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ),
        ),
      ],
    );
    final button = FilledButton.icon(
      key: const ValueKey('refreshButton'),
      onPressed: refreshing ? null : onRefresh,
      icon: refreshing
          ? const SizedBox.square(
              dimension: 18,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : Icon(failed ? Icons.replay : Icons.refresh),
      label: Text(failed ? 'Повторить' : 'Обновить'),
    );
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: failed ? colors.errorContainer : colors.primaryContainer,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (largeText) ...[
            status,
            const SizedBox(height: 12),
            button,
          ] else
            Row(
              children: [
                Expanded(child: status),
                const SizedBox(width: 8),
                button,
              ],
            ),
          if (failed) ...[
            const SizedBox(height: 8),
            Text(
              'Последнее успешное обновление: $lastUpdated',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ],
      ),
    );
  }
}

class _HubRow extends StatelessWidget {
  const _HubRow({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.value,
    this.badge,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  final String? value;
  final String? badge;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final largeText = MediaQuery.textScalerOf(context).scale(1) >= 1.5;
    final trailing = Row(
      mainAxisSize: largeText ? MainAxisSize.max : MainAxisSize.min,
      children: [
        if (badge != null && largeText)
          Flexible(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: colors.tertiaryContainer,
                borderRadius: BorderRadius.circular(8),
              ),
              child:
                  Text(badge!, style: Theme.of(context).textTheme.labelSmall),
            ),
          )
        else if (badge != null)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: colors.tertiaryContainer,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(badge!, style: Theme.of(context).textTheme.labelSmall),
          )
        else if (value != null && largeText)
          Flexible(
            child: Text(
              value!,
              style: Theme.of(context).textTheme.labelLarge,
              overflow: TextOverflow.ellipsis,
            ),
          )
        else if (value != null)
          Text(value!, style: Theme.of(context).textTheme.labelLarge),
        const SizedBox(width: 4),
        const ExcludeSemantics(child: Icon(Icons.chevron_right)),
      ],
    );
    return Semantics(
      button: true,
      child: InkWell(
        onTap: onTap,
        canRequestFocus: true,
        child: Container(
          constraints: const BoxConstraints(minHeight: 64),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          decoration: BoxDecoration(
            border: Border(top: BorderSide(color: colors.outlineVariant)),
          ),
          child: Row(
            children: [
              ExcludeSemantics(
                child: Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: colors.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(icon, size: 22),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: Theme.of(context).textTheme.titleSmall),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: colors.onSurfaceVariant,
                          ),
                    ),
                    if (largeText) ...[
                      const SizedBox(height: 8),
                      trailing,
                    ],
                  ],
                ),
              ),
              if (!largeText) ...[
                const SizedBox(width: 8),
                trailing,
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _Fact extends StatelessWidget {
  const _Fact({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(
            color: Theme.of(context).colorScheme.outlineVariant,
          ),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          const SizedBox(width: 16),
          Flexible(
            child: Text(
              value,
              textAlign: TextAlign.end,
              overflow: TextOverflow.ellipsis,
              maxLines: 2,
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }
}

class _FutureFamilyCard extends StatelessWidget {
  const _FutureFamilyCard();

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Semantics(
      label: 'Семейное пространство появится позже',
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: colors.surfaceContainerLow,
          border: Border.all(color: colors.outlineVariant),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const ExcludeSemantics(child: Icon(Icons.group_outlined)),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Семейное пространство · позже',
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Приглашения и семейные роли ещё не реализованы.',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: colors.onSurfaceVariant,
                        ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
