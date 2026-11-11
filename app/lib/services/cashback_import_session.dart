import 'package:shared_preferences/shared_preferences.dart';

import '../models/user_model.dart';
import 'cashback_import_profile.dart';

/// Remembers the browser profile opened last, so importing the JSON that
/// profile downloaded does not ask a second time whose banks it holds.
class CashbackImportSession {
  static const _lastProfileKey = 'cashbackImport.lastProfileId';

  static Future<void> rememberProfile(CashbackImportProfile profile) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_lastProfileKey, profile.id);
  }

  static Future<CashbackImportProfile?> lastProfile() async {
    final prefs = await SharedPreferences.getInstance();
    final id = prefs.getString(_lastProfileKey);
    for (final profile in cashbackImportProfiles) {
      if (profile.id == id) return profile;
    }
    return null;
  }
}

/// Profiles map to card owners by slot in id order, as the launch dialogs show.
UserModel? cashbackImportProfileUser(
  CashbackImportProfile profile,
  Iterable<UserModel> users,
) {
  final ordered = [...users]..sort((a, b) => a.id.compareTo(b.id));
  return profile.userSlot < ordered.length ? ordered[profile.userSlot] : null;
}
