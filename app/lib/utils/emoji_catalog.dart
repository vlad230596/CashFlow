import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

const emojiGroupLabels = <int, String>{
  0: 'Лица и эмоции',
  1: 'Люди и жесты',
  2: 'Компоненты',
  3: 'Животные и природа',
  4: 'Еда и напитки',
  5: 'Путешествия и места',
  6: 'Увлечения',
  7: 'Предметы',
  8: 'Символы',
  9: 'Флаги',
};

String normalizeEmojiSearch(String value) =>
    value.trim().toLowerCase().replaceAll('ё', 'е');

class EmojiEntry {
  EmojiEntry.fromJson(Map<String, dynamic> json)
      : emoji = json['emoji'] as String,
        label = json['label'] as String,
        group = json['group'] as int,
        asset = json['asset'] as String,
        searchText = normalizeEmojiSearch(
          '${json['emoji']} ${json['label']} '
          '${(json['keywords'] as List<dynamic>).join(' ')}',
        );

  final String emoji;
  final String label;
  final int group;
  final String asset;
  final String searchText;

  String get iconKey => 'emoji:$emoji';
  String get assetPath => 'assets/emoji/svg/$asset.svg';

  bool matches(String query) => normalizeEmojiSearch(query)
      .split(RegExp(r'\s+'))
      .every(searchText.contains);
}

class EmojiCatalog {
  static Future<List<EmojiEntry>>? _entries;
  static bool _licensesRegistered = false;

  static Future<List<EmojiEntry>> load() {
    if (!_licensesRegistered) {
      _licensesRegistered = true;
      LicenseRegistry.addLicense(() async* {
        yield LicenseEntryWithLineBreaks(
            ['Twemoji'],
            'Twemoji 17.0.3. Copyright Twitter, Inc. and other contributors. '
            'Unmodified graphics. https://github.com/jdecked/twemoji\n\n'
            '${await rootBundle.loadString('assets/emoji/TWEMOJI-LICENSE.txt')}');
        yield LicenseEntryWithLineBreaks(
            ['Emojibase'],
            'Emojibase 17.0.0. https://github.com/milesj/emojibase\n\n'
            '${await rootBundle.loadString('assets/emoji/EMOJIBASE-LICENSE.txt')}');
      });
    }
    return _entries ??= _load();
  }

  static Future<List<EmojiEntry>> _load() async {
    try {
      final data =
          jsonDecode(await rootBundle.loadString('assets/emoji/catalog.json'))
              as List<dynamic>;
      return List.unmodifiable(data.map(
        (entry) => EmojiEntry.fromJson(entry as Map<String, dynamic>),
      ));
    } catch (_) {
      _entries = null;
      rethrow;
    }
  }
}

String userEmoji(String? iconKey) {
  if (iconKey != null && iconKey.startsWith('emoji:')) {
    return iconKey.substring(6);
  }
  return switch (iconKey) {
    'boy' => '👨',
    'girl' => '👩',
    'family' => '👪',
    _ => '👤',
  };
}

String userEmojiAsset(String? iconKey) {
  final emoji = userEmoji(iconKey);
  final runes = emoji.runes.where((rune) =>
      rune != 0xfe0f || (emoji.contains('\u200d') && emoji != '👁️‍🗨️'));
  return 'assets/emoji/svg/${runes.map((rune) => rune.toRadixString(16)).join('-')}.svg';
}
