import 'dart:convert';
import 'dart:io';

class CashbackImportFile {
  const CashbackImportFile({required this.name, required this.contents});

  final String name;
  final String contents;
}

Future<CashbackImportFile?> pickCashbackImportFile() async {
  if (!Platform.isWindows) {
    throw UnsupportedError(
        'Выбор файла импорта пока поддерживается только в Windows.');
  }

  const script = r'''
Add-Type -AssemblyName System.Windows.Forms
$dialog = New-Object System.Windows.Forms.OpenFileDialog
$dialog.Title = 'Выберите выгрузку CashFlow'
$dialog.Filter = 'CashFlow JSON (*.json)|*.json|Все файлы (*.*)|*.*'
$dialog.InitialDirectory = [Environment]::GetFolderPath('UserProfile') + '\Downloads'
if ($dialog.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
  [Console]::OutputEncoding = [System.Text.Encoding]::UTF8
  Write-Output $dialog.FileName
}
''';

  final result = await Process.run(
    'powershell.exe',
    ['-NoProfile', '-Sta', '-Command', script],
    stdoutEncoding: utf8,
  );
  if (result.exitCode != 0) {
    throw ProcessException(
      'powershell.exe',
      const [],
      result.stderr.toString().trim(),
      result.exitCode,
    );
  }

  final path = result.stdout.toString().trim();
  if (path.isEmpty) return null;
  final file = File(path);
  return CashbackImportFile(
    name: file.uri.pathSegments.last,
    contents: await file.readAsString(),
  );
}

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
