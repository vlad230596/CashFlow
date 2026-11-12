import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'mcc_cache_storage.dart';

/// Account-scoped copy of the partner-offer catalogue (about 1.3 MB of JSON).
///
/// It used to live in SharedPreferences, where on Windows every write rewrites
/// the whole `shared_preferences.json` synchronously and stalled frames for
/// 250–600 ms. It now uses the same atomic record storage as MCC snapshots:
/// application-support files `partner-offers-v1/` on native platforms and the
/// IndexedDB database `cashflow-partner-offers-v1` on the web. Keys stay the
/// scoped preference keys (`data:v1:<url>:<user>:partnerOffers`).
class PartnerOfferCacheStore {
  PartnerOfferCacheStore({MccStorage? storage}) : _storage = storage;

  static const storageName = 'partner-offers-v1';

  MccStorage? _storage;
  MccStorage get _records => _storage ??= createNamedStorage(storageName);

  /// Returns the stored catalogue. A copy still left in SharedPreferences is
  /// moved once: it is deleted from preferences only after the dedicated
  /// write succeeded, so a failing store never loses the cache.
  Future<String?> read(String key) async {
    try {
      final stored = await _records.read(key);
      if (stored != null) return stored;
    } catch (error) {
      debugPrint('Could not read the partner-offer cache: $error');
    }
    final prefs = await SharedPreferences.getInstance();
    final legacy = prefs.getString(key);
    if (legacy == null) return null;
    try {
      await _records.write(key, legacy);
      await prefs.remove(key);
    } catch (error) {
      debugPrint('Partner offers stay in preferences for now: $error');
    }
    return legacy;
  }

  /// Never falls back to SharedPreferences: a failed write keeps the previous
  /// record and costs one fresh download, not a stalled frame.
  Future<void> write(String key, String value) async {
    try {
      await _records.write(key, value);
    } catch (error) {
      debugPrint('Could not save the partner-offer cache: $error');
      return;
    }
    // A save can precede the first read of an old installation; the newer
    // record supersedes the preference copy. containsKey is in memory.
    final prefs = await SharedPreferences.getInstance();
    if (prefs.containsKey(key)) await prefs.remove(key);
  }
}
