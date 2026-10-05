import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

class BankIconOption {
  const BankIconOption({
    required this.key,
    required this.label,
    required this.background,
    required this.foreground,
    this.mark,
    this.icon,
    this.logoAsset,
    this.logoOnWhite = false,
  });

  final String key;
  final String label;

  /// Colours, [mark] and [icon] draw the badge when there is no [logoAsset]
  /// or it fails to load.
  final Color background;
  final Color foreground;
  final String? mark;
  final IconData? icon;

  /// Square SVG logo from `assets/banks/`, drawn edge to edge in the badge.
  final String? logoAsset;

  /// The logo sits on white and needs a thin edge on light surfaces.
  final bool logoOnWhite;
}

const bankIconOptions = <BankIconOption>[
  BankIconOption(
    key: 'generic',
    label: 'Банк',
    background: Color(0xFFE7EDF5),
    foreground: Color(0xFF17396D),
    icon: Icons.account_balance_rounded,
  ),
  BankIconOption(
    key: 'tbank',
    label: 'Т-Банк',
    background: Color(0xFFF9DF55),
    foreground: Color(0xFF111111),
    mark: 'Т',
    logoAsset: 'assets/banks/tbank.svg',
  ),
  BankIconOption(
    key: 'alfa',
    label: 'Альфа-Банк',
    background: Color(0xFFEF3124),
    foreground: Colors.white,
    mark: 'A',
    logoAsset: 'assets/banks/alfa.svg',
  ),
  BankIconOption(
    key: 'vtb',
    label: 'ВТБ',
    background: Color(0xFF0A6EC7),
    foreground: Colors.white,
    mark: 'ВТБ',
    logoAsset: 'assets/banks/vtb.svg',
    logoOnWhite: true,
  ),
  BankIconOption(
    key: 'sber',
    label: 'Сбер',
    background: Color(0xFF21A038),
    foreground: Colors.white,
    mark: 'С',
    logoAsset: 'assets/banks/sber.svg',
    logoOnWhite: true,
  ),
  BankIconOption(
    key: 'yandex',
    label: 'Яндекс Банк',
    background: Color(0xFFFFCC00),
    foreground: Color(0xFF111111),
    mark: 'Я',
    logoAsset: 'assets/banks/yandex.svg',
  ),
  BankIconOption(
    key: 'ozon',
    label: 'Ozon Банк',
    background: Color(0xFF005BFF),
    foreground: Colors.white,
    mark: 'O',
    logoAsset: 'assets/banks/ozon.svg',
  ),
];

class UserIconOption {
  const UserIconOption({
    required this.key,
    required this.label,
    required this.icon,
    required this.background,
    required this.foreground,
  });

  final String key;
  final String label;
  final IconData icon;
  final Color background;
  final Color foreground;
}

const userIconOptions = <UserIconOption>[
  UserIconOption(
    key: 'boy',
    label: 'Мальчик',
    icon: Icons.boy_rounded,
    background: Color(0xFFDDEBFF),
    foreground: Color(0xFF1858A8),
  ),
  UserIconOption(
    key: 'girl',
    label: 'Девочка',
    icon: Icons.girl_rounded,
    background: Color(0xFFFFE1EC),
    foreground: Color(0xFFA83A67),
  ),
  UserIconOption(
    key: 'person',
    label: 'Человек',
    icon: Icons.person_rounded,
    background: Color(0xFFE9E5F8),
    foreground: Color(0xFF5F4A96),
  ),
  UserIconOption(
    key: 'family',
    label: 'Семья',
    icon: Icons.family_restroom_rounded,
    background: Color(0xFFE1F3EA),
    foreground: Color(0xFF287557),
  ),
];

/// Short visual marker of a card owner: a coloured circle with a distinct
/// glyph. It is drawn from the bundled Material Icons font, so it renders the
/// same on Web (built with `--no-web-resources-cdn`) and Android without
/// relying on a system or CDN emoji font.
class PersonMarker {
  const PersonMarker({
    required this.label,
    required this.icon,
    required this.background,
    required this.foreground,
  });

  final String label;
  final IconData icon;
  final Color background;
  final Color foreground;
}

/// Temporary per-person markers until people can choose their own. Every
/// person gets a different one, in the stable order of user ids, so cards are
/// easy to tell apart at a glance. Both the glyph and the colour differ.
const personMarkerPalette = <PersonMarker>[
  PersonMarker(
    label: 'Лапка',
    icon: Icons.pets_rounded,
    background: Color(0xFF8D5A3B),
    foreground: Colors.white,
  ),
  PersonMarker(
    label: 'Зайчик',
    icon: Icons.cruelty_free_rounded,
    background: Color(0xFFF07C1E),
    foreground: Colors.white,
  ),
  PersonMarker(
    label: 'Птичка',
    icon: Icons.flutter_dash_rounded,
    background: Color(0xFF1E88E5),
    foreground: Colors.white,
  ),
  PersonMarker(
    label: 'Листик',
    icon: Icons.eco_rounded,
    background: Color(0xFF2E9D4F),
    foreground: Colors.white,
  ),
  PersonMarker(
    label: 'Звезда',
    icon: Icons.star_rounded,
    background: Color(0xFF7E57C2),
    foreground: Colors.white,
  ),
  PersonMarker(
    label: 'Цветок',
    icon: Icons.local_florist_rounded,
    background: Color(0xFFD81B60),
    foreground: Colors.white,
  ),
  PersonMarker(
    label: 'Молния',
    icon: Icons.bolt_rounded,
    background: Color(0xFF00897B),
    foreground: Colors.white,
  ),
  PersonMarker(
    label: 'Сердце',
    icon: Icons.favorite_rounded,
    background: Color(0xFF424242),
    foreground: Colors.white,
  ),
];

/// Marker for a card whose owner is unknown.
const unknownPersonMarker = PersonMarker(
  label: 'Владелец неизвестен',
  icon: Icons.person_rounded,
  background: Color(0xFFB0B7C3),
  foreground: Colors.white,
);

PersonMarker personMarker(int? userId, Iterable<int> allUserIds) {
  if (userId == null) return unknownPersonMarker;
  final ordered = allUserIds.toSet().toList()..sort();
  final index = ordered.indexOf(userId);
  return index < 0
      ? unknownPersonMarker
      : personMarkerPalette[index % personMarkerPalette.length];
}

class PersonMarkerBadge extends StatelessWidget {
  const PersonMarkerBadge({
    super.key,
    required this.marker,
    this.userName,
    this.size = 20,
  });

  final PersonMarker marker;
  final String? userName;
  final double size;

  @override
  Widget build(BuildContext context) => Semantics(
        image: true,
        label: 'Владелец ${userName ?? marker.label}',
        child: ExcludeSemantics(
          child: Container(
            width: size,
            height: size,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: marker.background,
              shape: BoxShape.circle,
            ),
            child: Icon(
              marker.icon,
              size: size * .64,
              color: marker.foreground,
            ),
          ),
        ),
      );
}

BankIconOption bankIconOption(String? key, {String? bankName}) {
  final resolvedKey =
      key?.trim().isNotEmpty == true ? key! : defaultBankIconKey(bankName);
  return bankIconOptions.firstWhere(
    (option) => option.key == resolvedKey,
    orElse: () => bankIconOptions.first,
  );
}

String defaultBankIconKey(String? bankName) {
  final normalized = bankName?.toLowerCase() ?? '';
  if (normalized.contains('т-банк') || normalized.contains('тинькофф')) {
    return 'tbank';
  }
  if (normalized.contains('альфа')) return 'alfa';
  if (normalized.contains('втб')) return 'vtb';
  if (normalized.contains('сбер')) return 'sber';
  if (normalized.contains('яндекс')) return 'yandex';
  if (normalized.contains('ozon') || normalized.contains('озон')) return 'ozon';
  return 'generic';
}

UserIconOption userIconOption(String? key) => userIconOptions.firstWhere(
      (option) => option.key == key,
      orElse: () => userIconOptions.first,
    );

class BankIconBadge extends StatelessWidget {
  const BankIconBadge({
    super.key,
    this.iconKey,
    this.bankName,
    this.size = 36,
  });

  final String? iconKey;
  final String? bankName;
  final double size;

  @override
  Widget build(BuildContext context) {
    final option = bankIconOption(iconKey, bankName: bankName);
    return Semantics(
      image: true,
      label: 'Иконка банка ${bankName ?? option.label}',
      child: ExcludeSemantics(
        child: BankIconMark(option: option, size: size),
      ),
    );
  }
}

/// The picture of a [BankIconBadge]: the bank's logo clipped to a rounded
/// square, or the coloured letter mark when there is no logo or it cannot be
/// loaded.
class BankIconMark extends StatelessWidget {
  const BankIconMark({super.key, required this.option, this.size = 36});

  final BankIconOption option;
  final double size;

  @override
  Widget build(BuildContext context) {
    final asset = option.logoAsset;
    final radius = BorderRadius.circular(size * .28);
    if (asset == null) return _LetterMark(option: option, size: size);
    return SizedBox.square(
      dimension: size,
      child: DecoratedBox(
        position: DecorationPosition.foreground,
        decoration: BoxDecoration(
          borderRadius: radius,
          border: option.logoOnWhite
              ? Border.all(
                  color: Theme.of(context).colorScheme.outlineVariant,
                  width: size < 24 ? .5 : 1,
                )
              : null,
        ),
        child: ClipRRect(
          borderRadius: radius,
          child: SvgPicture.asset(
            asset,
            width: size,
            height: size,
            fit: BoxFit.cover,
            placeholderBuilder: (_) => ColoredBox(
              color: option.logoOnWhite ? Colors.white : option.background,
            ),
            errorBuilder: (_, __, ___) =>
                _LetterMark(option: option, size: size),
          ),
        ),
      ),
    );
  }
}

class _LetterMark extends StatelessWidget {
  const _LetterMark({required this.option, required this.size});

  final BankIconOption option;
  final double size;

  @override
  Widget build(BuildContext context) {
    final mark = option.mark;
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: option.background,
        borderRadius: BorderRadius.circular(size * .28),
      ),
      child: mark == null
          ? Icon(option.icon, size: size * .52, color: option.foreground)
          : Text(
              mark,
              maxLines: 1,
              style: TextStyle(
                color: option.foreground,
                fontSize: mark.length > 1 ? size * .27 : size * .48,
                fontWeight: FontWeight.w900,
                height: 1,
              ),
            ),
    );
  }
}

class UserIconBadge extends StatelessWidget {
  const UserIconBadge({
    super.key,
    this.iconKey,
    this.userName,
    this.size = 28,
  });

  final String? iconKey;
  final String? userName;
  final double size;

  @override
  Widget build(BuildContext context) {
    final option = userIconOption(iconKey);
    return Semantics(
      image: true,
      label: 'Иконка пользователя ${userName ?? option.label}',
      child: ExcludeSemantics(
        child: Container(
          width: size,
          height: size,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: option.background,
            shape: BoxShape.circle,
          ),
          child: Icon(option.icon, size: size * .72, color: option.foreground),
        ),
      ),
    );
  }
}
