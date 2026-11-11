import 'package:flutter/material.dart';

import '../models/planned_payment_model.dart';
import 'planned_payments_screen.dart';
import 'subscriptions_screen.dart';

/// Sections of the «Платежи» destination.
enum PaymentsSection { subscriptions, recurring, oneOff }

/// «Платежи»: subscriptions, recurring and one-off payments behind one
/// segmented switch. Each section keeps its own state while hidden.
class PaymentsHubScreen extends StatefulWidget {
  const PaymentsHubScreen({super.key});

  @override
  State<PaymentsHubScreen> createState() => PaymentsHubScreenState();
}

class PaymentsHubScreenState extends State<PaymentsHubScreen> {
  var _section = PaymentsSection.subscriptions;
  final _subscriptionsKey = GlobalKey<SubscriptionsScreenState>();
  final _recurringKey = GlobalKey<PlannedPaymentsScreenState>();
  final _oneOffKey = GlobalKey<PlannedPaymentsScreenState>();

  PaymentsSection get section => _section;

  void selectSection(PaymentsSection section) {
    if (section == _section) return;
    setState(() => _section = section);
  }

  Future<void> openSubscription(int id) async {
    selectSection(PaymentsSection.subscriptions);
    await _afterFrame();
    await _subscriptionsKey.currentState?.openSubscription(id);
  }

  Future<void> openPayment(int id, PlannedPaymentKind? kind) async {
    final recurring = kind != PlannedPaymentKind.oneOff;
    selectSection(
        recurring ? PaymentsSection.recurring : PaymentsSection.oneOff);
    await _afterFrame();
    await (recurring ? _recurringKey : _oneOffKey)
        .currentState
        ?.openPayment(id);
  }

  Future<void> _afterFrame() {
    final completer = WidgetsBinding.instance.endOfFrame;
    WidgetsBinding.instance.scheduleFrame();
    return completer;
  }

  @override
  Widget build(BuildContext context) {
    final switcher = _SectionSwitch(
      selected: _section,
      onChanged: selectSection,
    );
    return IndexedStack(
      index: _section.index,
      children: [
        SubscriptionsScreen(
          key: _subscriptionsKey,
          title: 'Платежи',
          appBarBottom: switcher,
        ),
        PlannedPaymentsScreen(
          key: _recurringKey,
          kind: PlannedPaymentKind.recurring,
          appBarBottom: switcher,
        ),
        PlannedPaymentsScreen(
          key: _oneOffKey,
          kind: PlannedPaymentKind.oneOff,
          appBarBottom: switcher,
        ),
      ],
    );
  }
}

class _SectionSwitch extends StatelessWidget implements PreferredSizeWidget {
  const _SectionSwitch({required this.selected, required this.onChanged});

  final PaymentsSection selected;
  final ValueChanged<PaymentsSection> onChanged;

  @override
  Size get preferredSize => const Size.fromHeight(56);

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
        child: SizedBox(
          width: double.infinity,
          child: SegmentedButton<PaymentsSection>(
            key: const ValueKey('payments-section-switch'),
            showSelectedIcon: false,
            style: const ButtonStyle(
              visualDensity: VisualDensity.compact,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            segments: const [
              ButtonSegment(
                value: PaymentsSection.subscriptions,
                label: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text('Подписки', maxLines: 1),
                ),
              ),
              ButtonSegment(
                value: PaymentsSection.recurring,
                label: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text('Регулярные', maxLines: 1),
                ),
              ),
              ButtonSegment(
                value: PaymentsSection.oneOff,
                label: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text('Разовые', maxLines: 1),
                ),
              ),
            ],
            selected: {selected},
            onSelectionChanged: (value) => onChanged(value.first),
          ),
        ),
      );
}
