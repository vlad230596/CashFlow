import 'dart:async';

import 'package:flutter/foundation.dart';

import 'app_log_storage_stub.dart'
    if (dart.library.io) 'app_log_storage_io.dart' as platform;

/// Destination of persisted log lines; the web build keeps none.
abstract class AppLogStorage {
  Future<void> append(String lines);
}

/// A small persisted diagnostic log: startup stages and request timings.
///
/// Lines carry wall-clock time and milliseconds since the process started, so
/// a slow launch can be reconstructed after logcat has rotated. Never log
/// tokens, passwords, response bodies or personal data here.
class AppLog {
  /// Without [storage] lines only reach `debugPrint` (tests, tools).
  AppLog({AppLogStorage? storage, Stopwatch? sinceStart})
      : _storage = storage,
        _sinceStart = sinceStart ?? (Stopwatch()..start());

  /// The application log file of this platform, if it has one.
  AppLog.persistent({Stopwatch? sinceStart})
      : this(storage: platform.createAppLogStorage(), sinceStart: sinceStart);

  /// Replaced by `main()` with a persistent log.
  static AppLog instance = AppLog();

  final AppLogStorage? _storage;
  final Stopwatch _sinceStart;
  final List<String> _pending = [];
  Future<void> _writes = Future.value();
  bool _flushScheduled = false;

  void event(String message) {
    final line = '${DateTime.now().toIso8601String()} '
        '+${_sinceStart.elapsedMilliseconds}ms $message';
    debugPrint('[CashFlow] $line');
    if (_storage == null) return;
    _pending.add(line);
    if (_flushScheduled) return;
    _flushScheduled = true;
    // Batch lines emitted in the same turn into one file append.
    scheduleMicrotask(flush);
  }

  Future<void> flush() {
    _flushScheduled = false;
    if (_pending.isEmpty) return _writes;
    final lines = '${_pending.join('\n')}\n';
    _pending.clear();
    _writes = _writes.then((_) => _storage!.append(lines)).catchError(
        (Object error) => debugPrint('App log write failed: $error'));
    return _writes;
  }
}
