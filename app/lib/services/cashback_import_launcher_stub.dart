import 'cashback_import_profile.dart';

class CashbackImportFile {
  const CashbackImportFile({required this.name, required this.contents});

  final String name;
  final String contents;
}

Future<CashbackImportFile?> pickCashbackImportFile() async {
  throw UnsupportedError(
    'Выбор файла импорта пока поддерживается только в Windows.',
  );
}

Future<String?> launchCashbackImport(CashbackImportProfile profile) async =>
    'Запуск браузера поддерживается только в локальном Windows-приложении.';
