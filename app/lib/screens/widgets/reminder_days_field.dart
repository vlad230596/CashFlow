import 'package:flutter/material.dart';

/// Editable set of "remind N days before" values as filter chips.
class ReminderDaysField extends StatelessWidget {
  const ReminderDaysField({
    super.key,
    required this.value,
    required this.onChanged,
    this.options = const [0, 1, 2, 3, 7, 14, 30],
    this.allowEmpty = true,
    this.footer,
  });

  final List<int> value;
  final ValueChanged<List<int>> onChanged;
  final List<int> options;

  /// When false, the last selected chip cannot be cleared.
  final bool allowEmpty;
  final Widget? footer;

  static String label(int days) => switch (days) {
        0 => 'В день оплаты',
        1 => 'За 1 день',
        _ => 'За $days дн.',
      };

  static String summary(List<int> days) {
    if (days.isEmpty) return 'Без напоминаний';
    final sorted = days.toSet().toList()..sort((a, b) => b.compareTo(a));
    return sorted.map(label).join(', ');
  }

  @override
  Widget build(BuildContext context) {
    final selected = value.toSet();
    final choices = {...options, ...selected}.toList()..sort();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Напоминания', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final days in choices)
              FilterChip(
                key: ValueKey('reminder-day-$days'),
                label: Text(label(days)),
                selected: selected.contains(days),
                onSelected: (enabled) {
                  final next = {...selected};
                  if (enabled) {
                    next.add(days);
                  } else {
                    if (!allowEmpty && next.length == 1) return;
                    next.remove(days);
                  }
                  onChanged(next.toList()..sort((a, b) => b.compareTo(a)));
                },
              ),
          ],
        ),
        const SizedBox(height: 6),
        Text(
          selected.isEmpty
              ? 'Напоминаний не будет.'
              : 'Напомним в 10:00: ${summary(value).toLowerCase()}.',
          style: Theme.of(context).textTheme.bodySmall,
        ),
        if (footer != null) footer!,
      ],
    );
  }
}
