import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../providers/data_provider.dart';
import '../settings/banks_settings.dart';
import '../settings/cards_settings.dart';
import '../settings/mcc_rules_settings_screen.dart';
import '../settings/users_settings.dart';
import '../widgets/admin_system_states.dart';
import '../widgets/versioned_app_bar_title.dart';

class AdminHubScreen extends StatelessWidget {
  const AdminHubScreen({super.key, this.onReturnToBenefit});

  final VoidCallback? onReturnToBenefit;

  void _open(BuildContext context, Widget screen) {
    Navigator.push(
      context,
      MaterialPageRoute<void>(builder: (_) => screen),
    );
  }

  void _returnToBenefit(BuildContext context) {
    if (onReturnToBenefit != null) {
      onReturnToBenefit!();
      return;
    }
    Navigator.maybePop(context);
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<DataProvider>();
    if (!provider.isAdmin) {
      return Scaffold(
        appBar: AppBar(
          title: const VersionedAppBarTitle(title: 'Управление'),
        ),
        body: AdminAccessDeniedState(
          onReturn: () => _returnToBenefit(context),
        ),
      );
    }

    final destinations = <_AdminDestination>[
      _AdminDestination(
        label: 'Банки',
        description: 'Названия и описания',
        meta: '${provider.banks.length}',
        icon: Icons.account_balance_outlined,
        screen: const BanksSettingsScreen(),
      ),
      _AdminDestination(
        label: 'Участники',
        description: 'Владельцы семейных карт',
        meta: '${provider.users.length}',
        icon: Icons.group_outlined,
        screen: const UsersSettingsScreen(),
      ),
      _AdminDestination(
        label: 'Карты',
        description: 'Банк, участник и реквизиты',
        meta: '${provider.cards.length}',
        icon: Icons.credit_card_outlined,
        screen: const CardsSettingsScreen(),
      ),
      const _AdminDestination(
        label: 'Правила MCC',
        description: 'Черновики и опубликованные ревизии',
        meta: 'Выберите банк',
        icon: Icons.rule_outlined,
        screen: MccRulesSettingsScreen(),
      ),
    ];

    return Scaffold(
      appBar: AppBar(
        title: const VersionedAppBarTitle(title: 'Управление'),
      ),
      body: LayoutBuilder(
        builder: (context, constraints) {
          final overview = _AdminOverview(
            destinations: destinations,
            onOpen: (destination) => _open(context, destination.screen),
          );
          if (constraints.maxWidth < 840) {
            return Align(
              alignment: Alignment.topCenter,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 760),
                child: overview,
              ),
            );
          }
          return Row(
            children: [
              NavigationRail(
                selectedIndex: 0,
                labelType: NavigationRailLabelType.all,
                onDestinationSelected: (index) {
                  if (index == 0) return;
                  _open(context, destinations[index - 1].screen);
                },
                destinations: const [
                  NavigationRailDestination(
                    icon: Icon(Icons.dashboard_outlined),
                    selectedIcon: Icon(Icons.dashboard),
                    label: Text('Обзор'),
                  ),
                  NavigationRailDestination(
                    icon: Icon(Icons.account_balance_outlined),
                    label: Text('Банки'),
                  ),
                  NavigationRailDestination(
                    icon: Icon(Icons.group_outlined),
                    label: Text('Участники'),
                  ),
                  NavigationRailDestination(
                    icon: Icon(Icons.credit_card_outlined),
                    label: Text('Карты'),
                  ),
                  NavigationRailDestination(
                    icon: Icon(Icons.rule_outlined),
                    label: Text('Правила MCC'),
                  ),
                ],
              ),
              const VerticalDivider(width: 1),
              Expanded(child: overview),
            ],
          );
        },
      ),
    );
  }
}

class _AdminOverview extends StatelessWidget {
  const _AdminOverview({required this.destinations, required this.onOpen});

  final List<_AdminDestination> destinations;
  final ValueChanged<_AdminDestination> onOpen;

  @override
  Widget build(BuildContext context) {
    return CustomScrollView(
      key: const PageStorageKey('admin-hub-overview'),
      slivers: [
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(24, 24, 24, 12),
          sliver: SliverToBoxAdapter(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Обзор',
                  style: Theme.of(context).textTheme.headlineMedium,
                ),
                const SizedBox(height: 8),
                Text(
                  'Справочники семьи и банковские правила',
                  style: Theme.of(context).textTheme.bodyLarge,
                ),
              ],
            ),
          ),
        ),
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
          sliver: SliverLayoutBuilder(
            builder: (context, constraints) {
              final columns = constraints.crossAxisExtent >= 700 ? 2 : 1;
              final cardWidth = columns == 1
                  ? constraints.crossAxisExtent
                  : (constraints.crossAxisExtent - 12) / 2;
              return SliverToBoxAdapter(
                child: Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: [
                    for (final destination in destinations)
                      SizedBox(
                        width: cardWidth,
                        child: _DestinationCard(
                          destination: destination,
                          onTap: () => onOpen(destination),
                        ),
                      ),
                  ],
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

class _DestinationCard extends StatelessWidget {
  const _DestinationCard({required this.destination, required this.onTap});

  final _AdminDestination destination;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 148),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(destination.icon, size: 28),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        destination.label,
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        destination.meta,
                        style: Theme.of(context).textTheme.labelLarge,
                      ),
                      const SizedBox(height: 8),
                      Text(destination.description),
                      const SizedBox(height: 16),
                      const Align(
                        alignment: Alignment.bottomRight,
                        child: Icon(Icons.chevron_right),
                      ),
                    ],
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

class _AdminDestination {
  const _AdminDestination({
    required this.label,
    required this.description,
    required this.meta,
    required this.icon,
    required this.screen,
  });

  final String label;
  final String description;
  final String meta;
  final IconData icon;
  final Widget screen;
}
