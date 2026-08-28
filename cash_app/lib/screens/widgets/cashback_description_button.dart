import 'package:flutter/material.dart';

class CashbackDescriptionButton extends StatelessWidget {
  const CashbackDescriptionButton({
    super.key,
    required this.categoryName,
    this.description,
    this.iconSize = 16,
  });

  final String categoryName;
  final String? description;
  final double iconSize;

  @override
  Widget build(BuildContext context) {
    final text = description?.trim();
    if (text == null || text.isEmpty) return const SizedBox.shrink();

    return Tooltip(
      message: text,
      waitDuration: const Duration(milliseconds: 350),
      child: Semantics(
        button: true,
        label: 'Описание категории $categoryName',
        child: IconButton(
          icon: Icon(Icons.help_outline, size: iconSize),
          visualDensity: VisualDensity.compact,
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
          onPressed: () => showDialog<void>(
            context: context,
            builder: (dialogContext) => AlertDialog(
              title: Text(categoryName),
              content: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 520),
                child: SingleChildScrollView(child: SelectableText(text)),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(dialogContext),
                  child: const Text('Закрыть'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
