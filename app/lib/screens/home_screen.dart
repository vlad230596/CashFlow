import 'package:flutter/material.dart';

import '../services/app_session_type.dart';
import 'cashback_screen.dart';
import 'monthly_cashback_screen.dart';
import 'more_screen.dart';
import 'partner_offers_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key, this.sessionType});

  final AppSessionType? sessionType;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _selectedIndex = 0;

  late final List<Widget> _screens = [
    CashbackScreen(
      onShellDestinationSelected: (value) =>
          setState(() => _selectedIndex = value),
    ),
    MonthlyCashbackScreen(
      onShellDestinationSelected: (value) =>
          setState(() => _selectedIndex = value),
    ),
    const PartnerOffersScreen(),
    MoreScreen(sessionType: widget.sessionType ?? detectAppSessionType()),
  ];

  static const _destinations = [
    _ShellDestination(
      'Выгода',
      Icons.home_outlined,
      Icons.home_rounded,
    ),
    _ShellDestination(
      'План',
      Icons.description_outlined,
      Icons.description_rounded,
    ),
    _ShellDestination(
      'Акции',
      Icons.local_offer_outlined,
      Icons.local_offer_rounded,
    ),
    _ShellDestination('Ещё', Icons.more_horiz, Icons.more_horiz),
  ];

  @override
  Widget build(BuildContext context) => LayoutBuilder(
        builder: (context, constraints) {
          final expanded = constraints.maxWidth >= 840;
          return Scaffold(
            body: Row(
              children: [
                if (expanded)
                  _DesktopRail(
                    selectedIndex: _selectedIndex,
                    onSelected: (value) =>
                        setState(() => _selectedIndex = value),
                  ),
                Expanded(
                  child: IndexedStack(
                    index: _selectedIndex,
                    children: _screens,
                  ),
                ),
              ],
            ),
            bottomNavigationBar: expanded
                ? null
                : NavigationBar(
                    selectedIndex: _selectedIndex,
                    onDestinationSelected: (value) =>
                        setState(() => _selectedIndex = value),
                    destinations: [
                      for (final destination in _destinations)
                        NavigationDestination(
                          key: ValueKey(
                              'shell-destination-${destination.label}'),
                          icon: Icon(destination.icon),
                          selectedIcon: Icon(destination.selectedIcon),
                          label: destination.label,
                        ),
                    ],
                  ),
          );
        },
      );
}

class _DesktopRail extends StatelessWidget {
  const _DesktopRail({required this.selectedIndex, required this.onSelected});

  final int selectedIndex;
  final ValueChanged<int> onSelected;

  @override
  Widget build(BuildContext context) => Container(
        width: 224,
        color: const Color(0xFF102C54),
        padding: const EdgeInsets.fromLTRB(16, 24, 16, 20),
        child: SafeArea(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final dense = constraints.maxHeight < 360;
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Padding(
                    padding: EdgeInsets.fromLTRB(12, 4, 12, dense ? 8 : 24),
                    child: Row(
                      children: [
                        const _BrandMark(),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            'CashFlow',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: dense ? 18 : 22,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  for (var index = 0;
                      index < _HomeScreenState._destinations.length;
                      index++)
                    Padding(
                      padding: EdgeInsets.only(bottom: dense ? 2 : 6),
                      child: _RailButton(
                        destination: _HomeScreenState._destinations[index],
                        selected: selectedIndex == index,
                        dense: dense,
                        onTap: () => onSelected(index),
                      ),
                    ),
                  const Spacer(),
                  if (constraints.maxHeight >= 420) ...[
                    const Divider(color: Color(0x446F91B8)),
                    const Padding(
                      padding: EdgeInsets.fromLTRB(12, 12, 12, 0),
                      child: Text(
                        'Семейное пространство',
                        style: TextStyle(
                          color: Color(0xFFB9CCE4),
                          fontSize: 12,
                        ),
                      ),
                    ),
                  ],
                ],
              );
            },
          ),
        ),
      );
}

class _RailButton extends StatelessWidget {
  const _RailButton({
    required this.destination,
    required this.selected,
    required this.dense,
    required this.onTap,
  });

  final _ShellDestination destination;
  final bool selected;
  final bool dense;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Material(
        color: selected ? const Color(0xFF2B5B91) : Colors.transparent,
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(10),
          child: SizedBox(
            height: dense ? 40 : 50,
            child: Row(
              children: [
                const SizedBox(width: 14),
                Icon(
                  selected ? destination.selectedIcon : destination.icon,
                  color: Colors.white,
                  size: dense ? 20 : 22,
                ),
                const SizedBox(width: 14),
                Text(
                  destination.label,
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
}

class _BrandMark extends StatelessWidget {
  const _BrandMark();

  @override
  Widget build(BuildContext context) => Container(
        width: 34,
        height: 34,
        decoration: BoxDecoration(
          color: const Color(0xFF1D6FE8),
          borderRadius: BorderRadius.circular(10),
        ),
        alignment: Alignment.center,
        child: const Icon(Icons.auto_awesome, color: Colors.white, size: 19),
      );
}

class _ShellDestination {
  const _ShellDestination(this.label, this.icon, this.selectedIcon);

  final String label;
  final IconData icon;
  final IconData selectedIcon;
}
