import 'package:cashflow/models/bank_model.dart';
import 'package:cashflow/models/card_model.dart';
import 'package:cashflow/models/user_model.dart';
import 'package:cashflow/services/card_context.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('resolves card identity once and preserves presentation variants', () {
    final catalog = CardContextCatalog(
        cards: [CardModel(id: 3, bankId: 1, userId: 2, lastFourDigits: '1234')],
        banks: [BankModel(id: 1, name: 'Банк', iconKey: 'sber')],
        users: [UserModel(id: 2, name: 'Анна', iconKey: 'person')]);
    final context = catalog.forId(3);
    expect(context.bankName, 'Банк');
    expect(context.ownerName, 'Анна');
    expect(context.bankIconKey, 'sber');
    expect(context.benefitLabel, 'Анна Банк · •1234');
    expect(context.subscriptionLabel, 'Анна Банк ••1234');
  });
  test('missing card reference uses existing fallback', () {
    final context =
        CardContextCatalog(cards: [], banks: [], users: []).forId(99);
    expect(context.card.id, 99);
    expect(context.ownerAndBankLabel, 'Unknown card');
    expect(context.benefitLabel, 'Unknown card · •????');
  });
}
