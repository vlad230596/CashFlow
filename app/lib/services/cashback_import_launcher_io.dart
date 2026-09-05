import 'dart:convert';
import 'dart:io';

import 'cashback_import_profile.dart';

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

Future<String?> launchCashbackImport(CashbackImportProfile profile) async {
  if (!Platform.isWindows) {
    return 'Запуск браузера пока поддерживается только в Windows.';
  }

  final launcher = _findCashbackImportLauncher();

  if (launcher == null) {
    return 'Не найден scripts/start_cashback_import.ps1. Запустите приложение из каталога проекта.';
  }

  try {
    final result = await Process.run(
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
        profile.id,
        '-DebugPort',
        profile.debugPort.toString(),
        '-Banks',
        profile.banks.join(','),
      ],
      workingDirectory: launcher.parent.parent.path,
      stdoutEncoding: utf8,
      stderrEncoding: utf8,
    );
    if (result.exitCode != 0) {
      final stderr = result.stderr.toString().trim();
      final stdout = result.stdout.toString().trim();
      final details = stderr.isNotEmpty
          ? stderr
          : stdout.isNotEmpty
              ? stdout
              : 'PowerShell завершил работу с кодом ${result.exitCode}.';
      return 'Не удалось запустить Chrome: $details';
    }
    return null;
  } on ProcessException catch (error) {
    return 'Не удалось запустить Chrome: ${error.message}';
  }
}

File? _findCashbackImportLauncher() {
  final separator = Platform.pathSeparator;
  final startDirectories = <Directory>{
    Directory.current.absolute,
    File(Platform.resolvedExecutable).absolute.parent,
  };
  final visitedDirectories = <String>{};

  for (final startDirectory in startDirectories) {
    Directory? directory = startDirectory;
    while (directory != null && visitedDirectories.add(directory.path)) {
      final candidates = [
        File(
          '${directory.path}${separator}scripts${separator}start_cashback_import.ps1',
        ),
        File(
          '${directory.path}${separator}app${separator}scripts${separator}start_cashback_import.ps1',
        ),
      ];
      for (final candidate in candidates) {
        if (candidate.existsSync()) return candidate;
      }

      final parent = directory.parent;
      directory = parent.path == directory.path ? null : parent;
    }
  }

  return null;
}
