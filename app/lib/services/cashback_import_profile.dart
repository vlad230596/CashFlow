class CashbackImportProfile {
  const CashbackImportProfile({
    required this.id,
    required this.label,
    required this.debugPort,
    required this.banks,
  });

  final String id;
  final String label;
  final int debugPort;
  final List<String> banks;
}

const cashbackImportProfiles = <CashbackImportProfile>[
  CashbackImportProfile(
    id: 'user-1',
    label: 'Профиль 1 (с ВТБ)',
    debugPort: 9223,
    banks: ['tbank', 'yandex', 'alfa', 'sber', 'ozon', 'vtb'],
  ),
  CashbackImportProfile(
    id: 'user-2',
    label: 'Профиль 2 (без ВТБ)',
    debugPort: 9224,
    banks: ['tbank', 'yandex', 'alfa', 'sber', 'ozon'],
  ),
];
