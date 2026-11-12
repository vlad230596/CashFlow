import 'package:flutter/material.dart';

import '../../models/user_model.dart';
import '../../providers/data_provider.dart';
import '../../services/cashback_import_launcher.dart';
import '../../services/cashback_import_session.dart';

typedef CashbackFilePicker = Future<CashbackImportFile?> Function();
typedef CashbackDocumentImporter = Future<CashbackImportResult> Function(
  DataProvider provider,
  String contents,
  int userId,
);

/// Picks a downloaded bank JSON and imports it for the owner of the browser
/// profile opened last; asks for the owner only when no profile was opened.
/// Reports the outcome in a snackbar and returns the result (null when the
/// owner cancelled or the import failed).
Future<CashbackImportResult?> importCashbackJson(
  BuildContext context,
  DataProvider provider,
) async {
  final messenger = ScaffoldMessenger.of(context);
  try {
    return await importCashbackJsonFile(context, provider);
  } catch (error) {
    messenger.showSnackBar(
      SnackBar(content: Text('Не удалось импортировать JSON: $error')),
    );
    return null;
  }
}

/// The same import without the error snackbar: errors are thrown so a screen
/// can show them in place. [userId] fixes the owner (for example the owner of
/// the card being checked); otherwise the remembered browser profile decides.
Future<CashbackImportResult?> importCashbackJsonFile(
  BuildContext context,
  DataProvider provider, {
  int? userId,
  CashbackFilePicker? pickFile,
  CashbackDocumentImporter? importer,
}) async {
  final messenger = ScaffoldMessenger.of(context);
  final file = await (pickFile ?? pickCashbackImportFile)();
  if (file == null || !context.mounted) return null;
  final owner = userId != null
      ? provider.users.where((user) => user.id == userId).firstOrNull
      : await _rememberedOwner(provider);
  if (!context.mounted) return null;
  final ownerId =
      userId ?? owner?.id ?? await _selectImportUser(context, provider);
  if (ownerId == null || !context.mounted) return null;
  final result = await (importer ?? _importDocument)(
    provider,
    file.contents,
    ownerId,
  );
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
  return result;
}

Future<CashbackImportResult> _importDocument(
  DataProvider provider,
  String contents,
  int userId,
) =>
    provider.importCashbackDocument(contents, userId);

Future<UserModel?> _rememberedOwner(DataProvider provider) async {
  final profile = await CashbackImportSession.lastProfile();
  return profile == null
      ? null
      : cashbackImportProfileUser(profile, provider.users);
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
