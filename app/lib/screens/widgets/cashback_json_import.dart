import 'package:flutter/material.dart';

import '../../providers/data_provider.dart';
import '../../services/cashback_import_launcher.dart';
import '../../services/cashback_import_session.dart';

/// Picks a downloaded bank JSON and imports it for the owner of the browser
/// profile opened last; asks for the owner only when no profile was opened.
Future<void> importCashbackJson(
  BuildContext context,
  DataProvider provider,
) async {
  final messenger = ScaffoldMessenger.of(context);
  try {
    final file = await pickCashbackImportFile();
    if (file == null || !context.mounted) return;
    final profile = await CashbackImportSession.lastProfile();
    final owner = profile == null
        ? null
        : cashbackImportProfileUser(profile, provider.users);
    if (!context.mounted) return;
    final userId = owner?.id ?? await _selectImportUser(context, provider);
    if (userId == null || !context.mounted) return;
    final result = await provider.importCashbackDocument(file.contents, userId);
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          '${owner == null ? '' : '${owner.name}: '}'
          'импортировано банков: ${result.importedBanks}; '
          'создано: ${result.created}, обновлено: ${result.updated}; '
          'партнёрских предложений создано: '
          '${result.createdPartnerOffers}, обновлено: '
          '${result.updatedPartnerOffers}.',
        ),
      ),
    );
  } catch (error) {
    messenger.showSnackBar(
      SnackBar(content: Text('Не удалось импортировать JSON: $error')),
    );
  }
}

Future<int?> _selectImportUser(
  BuildContext context,
  DataProvider provider,
) async {
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
