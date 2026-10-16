import '../models/bank_model.dart';
import '../models/card_model.dart';
import '../models/user_model.dart';

/// A card's reference data is resolved once per screen snapshot.
class CardContextCatalog {
  CardContextCatalog(
      {required Iterable<CardModel> cards,
      required Iterable<BankModel> banks,
      required Iterable<UserModel> users})
      : _cards = {
          for (final card in cards)
            if (card.id != null) card.id!: card
        },
        _banks = {
          for (final bank in banks)
            if (bank.id != null) bank.id!: bank
        },
        _users = {for (final user in users) user.id: user};
  final Map<int, CardModel> _cards;
  final Map<int, BankModel> _banks;
  final Map<int, UserModel> _users;
  CardContext forId(int cardId) => forCard(_cards[cardId] ??
      CardModel(
          id: cardId, paymentSystem: '', cardType: '', lastFourDigits: '????'));
  CardContext forCard(CardModel card) => CardContext(
      card: card, bank: _banks[card.bankId], owner: _users[card.userId]);
}

class CardContext {
  const CardContext({required this.card, this.bank, this.owner});
  final CardModel card;
  final BankModel? bank;
  final UserModel? owner;
  String? get bankName => bank?.name;
  String? get bankIconKey => bank?.iconKey;
  String? get ownerName => owner?.name;
  String? get ownerIconKey => owner?.iconKey;
  String get ownerAndBankLabel => bankName == null && ownerName == null
      ? 'Unknown card'
      : [if (ownerName != null) ownerName!, if (bankName != null) bankName!]
          .join(' ');
  String get benefitLabel =>
      '$ownerAndBankLabel · •${card.lastFourDigits ?? '????'}';
  String get subscriptionLabel {
    final title = card.id == null ? 'Карта' : ownerAndBankLabel;
    final digits = card.lastFourDigits?.isNotEmpty == true
        ? ' ••${card.lastFourDigits}'
        : '';
    return '$title$digits';
  }
}
