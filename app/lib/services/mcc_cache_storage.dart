import 'mcc_cache_storage_stub.dart'
    if (dart.library.io) 'mcc_cache_storage_io.dart'
    if (dart.library.js_interop) 'mcc_cache_storage_web.dart' as platform;

/// Each write replaces one record atomically; a failed write preserves its value.
abstract interface class MccStorage {
  Future<String?> read(String key);
  Future<void> write(String key, String value);
  Future<void> remove(String key);
  Future<Set<String>> keys();
}

MccStorage createMccStorage() => platform.createStorage();

/// Explicit test dependency. Production never silently falls back to memory.
class MemoryMccStorage implements MccStorage {
  final Map<String, String> values = {};
  @override
  Future<String?> read(String key) async => values[key];
  @override
  Future<void> write(String key, String value) async => values[key] = value;
  @override
  Future<void> remove(String key) async => values.remove(key);
  @override
  Future<Set<String>> keys() async => values.keys.toSet();
}
