import 'package:cashflow/services/cashback_import_profile.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('browser profiles use isolated ports and omit VTB for user 2', () {
    final first = cashbackImportProfiles[0];
    final second = cashbackImportProfiles[1];

    expect(first.id, 'user-1');
    expect(first.debugPort, 9223);
    expect(first.banks, contains('vtb'));

    expect(second.id, 'user-2');
    expect(second.debugPort, 9224);
    expect(second.banks, isNot(contains('vtb')));
    expect(
        second.banks, containsAll(['tbank', 'yandex', 'alfa', 'sber', 'ozon']));
  });
}
