import 'package:flutter/material.dart';

class BankIconOption {
  const BankIconOption({
    required this.key,
    required this.label,
    required this.background,
    required this.foreground,
    this.mark,
    this.icon,
  });

  final String key;
  final String label;
  final Color background;
  final Color foreground;
  final String? mark;
  final IconData? icon;
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
  ),
  BankIconOption(
    key: 'alfa',
    label: 'Альфа-Банк',
    background: Color(0xFFEF3124),
    foreground: Colors.white,
    mark: 'A',
  ),
  BankIconOption(
    key: 'vtb',
    label: 'ВТБ',
    background: Color(0xFF0A6EC7),
    foreground: Colors.white,
    mark: 'ВТБ',
  ),
  BankIconOption(
    key: 'sber',
    label: 'Сбер',
    background: Color(0xFF21A038),
    foreground: Colors.white,
    mark: 'С',
  ),
  BankIconOption(
    key: 'yandex',
    label: 'Яндекс Банк',
    background: Color(0xFFFFCC00),
    foreground: Color(0xFF111111),
    mark: 'Я',
  ),
  BankIconOption(
    key: 'ozon',
    label: 'Ozon Банк',
    background: Color(0xFF005BFF),
    foreground: Colors.white,
    mark: 'O',
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
    final mark = option.mark;
    return Semantics(
      image: true,
      label: 'Иконка банка ${bankName ?? option.label}',
      child: ExcludeSemantics(
        child: Container(
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
