import 'dart:io';

Future<String?> launchCashbackImport() async {
  if (!Platform.isWindows) {
    return 'Запуск браузера пока поддерживается только в Windows.';
  }

  Directory? directory = Directory.current.absolute;
  File? launcher;
  while (directory != null) {
    final candidate = File(
      '${directory.path}${Platform.pathSeparator}scripts${Platform.pathSeparator}start_cashback_import.ps1',
    );
    if (candidate.existsSync()) {
      launcher = candidate;
      break;
    }
    final parent = directory.parent;
    directory = parent.path == directory.path ? null : parent;
  }

  if (launcher == null) {
    return 'Не найден scripts/start_cashback_import.ps1. Запустите приложение из каталога проекта.';
  }

  try {
    await Process.start(
      'powershell.exe',
      [
        '-NoProfile',
        '-ExecutionPolicy',
        'Bypass',
        '-WindowStyle',
        'Hidden',
        '-File',
        launcher.path,
        '-Profile',
        'user-1',
        '-Banks',
        'tbank,yandex,alfa,sber,ozon,vtb',
      ],
      workingDirectory: launcher.parent.parent.path,
      mode: ProcessStartMode.detached,
    );
    return null;
  } on ProcessException catch (error) {
    return 'Не удалось запустить Chrome: ${error.message}';
  }
}
