/// Card balances synchronized by the CashFlow server from ZenMoney.
///
/// Every balance carries [CardBalance.fetchedAt], the moment the server
/// obtained it from ZenMoney. The app never shows a balance without it.
library;

double _amount(Object? value) =>
    double.tryParse(value?.toString().replaceAll(',', '.') ?? '') ?? 0;

DateTime? _instant(Object? value) =>
    value is String && value.isNotEmpty ? DateTime.tryParse(value) : null;

/// Integration states reported by `GET /api/card-balances`.
enum CardBalanceStatus {
  /// `CASHFLOW_SECRETS_KEY` is missing on the server.
  notConfigured,

  /// The administrator has not entered a ZenMoney token.
  noToken,

  /// A token was saved and the first fetch has not completed.
  pending,
  ok,

  /// The last attempt failed (network, ZenMoney error); older data is kept.
  error,

  /// ZenMoney rejected the token, or it cannot be decrypted: re-enter it.
  tokenInvalid;

  static CardBalanceStatus parse(Object? value) => switch (value) {
        'not_configured' => notConfigured,
        'no_token' => noToken,
        'pending' => pending,
        'ok' => ok,
        'error' => error,
        'token_invalid' => tokenInvalid,
        _ => notConfigured,
      };

  String get apiValue => switch (this) {
        notConfigured => 'not_configured',
        noToken => 'no_token',
        pending => 'pending',
        ok => 'ok',
        error => 'error',
        tokenInvalid => 'token_invalid',
      };

  /// Whether balances can exist at all (otherwise the UI shows nothing).
  bool get isEnabled => this != notConfigured && this != noToken;
}

class CardBalance {
  const CardBalance({
    required this.cardId,
    required this.accountId,
    required this.balance,
    required this.fetchedAt,
    this.accountTitle,
    this.accountType,
    this.creditLimit = 0,
    double? available,
    this.currency,
  }) : available = available ?? balance;

  final int cardId;
  final String accountId;
  final String? accountTitle;

  /// ZenMoney account type: `ccard`, `checking`, `cash`, …
  final String? accountType;

  /// Own money on the account; negative on a credit card means debt.
  final double balance;
  final double creditLimit;

  /// What can be spent now: balance plus the unused credit limit.
  final double available;

  /// ISO code from ZenMoney (`RUB`, `USD`, …).
  final String? currency;

  /// When the server obtained this balance from ZenMoney.
  final DateTime fetchedAt;

  bool get isCredit => creditLimit > 0;

  factory CardBalance.fromJson(Map<String, dynamic> json) => CardBalance(
        cardId: (json['card_id'] as num).toInt(),
        accountId: json['account_id'].toString(),
        accountTitle: json['account_title'] as String?,
        accountType: json['account_type'] as String?,
        balance: _amount(json['balance']),
        creditLimit: _amount(json['credit_limit']),
        available:
            json['available'] == null ? null : _amount(json['available']),
        currency: json['currency'] as String?,
        fetchedAt: _instant(json['fetched_at'])!,
      );

  Map<String, dynamic> toJson() => {
        'card_id': cardId,
        'account_id': accountId,
        'account_title': accountTitle,
        'account_type': accountType,
        'balance': balance.toStringAsFixed(2),
        'credit_limit': creditLimit.toStringAsFixed(2),
        'available': available.toStringAsFixed(2),
        'currency': currency,
        'fetched_at': fetchedAt.toUtc().toIso8601String(),
      };
}

class CardBalancesSnapshot {
  const CardBalancesSnapshot({
    required this.status,
    this.balances = const [],
    this.lastSuccessAt,
    this.lastAttemptAt,
    this.lastErrorKind,
    this.lastErrorMessage,
    this.refreshing = false,
    this.refreshOutcome,
  });

  final CardBalanceStatus status;
  final List<CardBalance> balances;
  final DateTime? lastSuccessAt;
  final DateTime? lastAttemptAt;
  final String? lastErrorKind;
  final String? lastErrorMessage;
  final bool refreshing;

  /// What this response's request did: `refreshed`, `failed`, `not_due`,
  /// `busy` or `unavailable`. Not cached.
  final String? refreshOutcome;

  CardBalance? forCard(int? cardId) {
    if (cardId == null || !status.isEnabled) return null;
    for (final balance in balances) {
      if (balance.cardId == cardId) return balance;
    }
    return null;
  }

  factory CardBalancesSnapshot.fromJson(Map<String, dynamic> json) {
    final integration =
        json['integration'] as Map<String, dynamic>? ?? const {};
    final error = integration['last_error'] as Map<String, dynamic>?;
    return CardBalancesSnapshot(
      status: CardBalanceStatus.parse(integration['status']),
      balances: [
        for (final item in json['balances'] as List? ?? const [])
          if (item is Map<String, dynamic> &&
              _instant(item['fetched_at']) != null)
            CardBalance.fromJson(item),
      ],
      lastSuccessAt: _instant(integration['last_success_at']),
      lastAttemptAt: _instant(integration['last_attempt_at']),
      lastErrorKind: error?['kind'] as String?,
      lastErrorMessage: error?['message'] as String?,
      refreshing: integration['refreshing'] == true,
      refreshOutcome: integration['refresh_outcome'] as String?,
    );
  }

  Map<String, dynamic> toJson() => {
        'integration': {
          'status': status.apiValue,
          'last_success_at': lastSuccessAt?.toUtc().toIso8601String(),
          'last_attempt_at': lastAttemptAt?.toUtc().toIso8601String(),
          'last_error': lastErrorKind == null
              ? null
              : {'kind': lastErrorKind, 'message': lastErrorMessage},
        },
        'balances': balances.map((item) => item.toJson()).toList(),
      };
}

/// A balance prepared for display: it is shown muted when it may be outdated.
class CardBalanceView {
  const CardBalanceView({
    required this.balance,
    this.offline = false,
    this.notUpdating = false,
  });

  final CardBalance balance;

  /// The app could not reach CashFlow and shows its cached copy.
  final bool offline;

  /// The server cannot currently refresh from ZenMoney (error / bad token).
  final bool notUpdating;

  /// Balances older than this are shown as outdated.
  static const staleAfter = Duration(hours: 6);

  bool isStale(DateTime now) =>
      offline || notUpdating || now.difference(balance.fetchedAt) > staleAfter;
}

/// Account list and per-card suggestions for the mapping screen (editor+).
class ZenmoneyAccountOption {
  const ZenmoneyAccountOption({
    required this.id,
    required this.title,
    this.type,
    this.companyTitle,
    this.currency,
    this.syncIds = const [],
    this.balance = 0,
    this.available = 0,
    this.creditLimit = 0,
    this.archived = false,
    this.missing = false,
    this.fetchedAt,
  });

  final String id;
  final String title;
  final String? type;
  final String? companyTitle;
  final String? currency;
  final List<String> syncIds;
  final double balance;
  final double available;
  final double creditLimit;
  final bool archived;
  final bool missing;
  final DateTime? fetchedAt;

  factory ZenmoneyAccountOption.fromJson(Map<String, dynamic> json) =>
      ZenmoneyAccountOption(
        id: json['id'].toString(),
        title: json['title'] as String? ?? 'Счёт',
        type: json['type'] as String?,
        companyTitle: json['company_title'] as String?,
        currency: json['currency'] as String?,
        syncIds: [
          for (final item in json['sync_ids'] as List? ?? const [])
            item.toString()
        ],
        balance: _amount(json['balance']),
        available: _amount(json['available']),
        creditLimit: _amount(json['credit_limit']),
        archived: json['archived'] == true,
        missing: json['missing'] == true,
        fetchedAt: _instant(json['fetched_at']),
      );
}

class CardAccountSuggestion {
  const CardAccountSuggestion({required this.accountId, this.bankMatch});

  final String accountId;

  /// True/false when both banks are known, otherwise null.
  final bool? bankMatch;
}

class CardAccountMapping {
  const CardAccountMapping({
    required this.cardId,
    this.hasLink = false,
    this.accountId,
    this.source,
    this.suggestions = const [],
    this.ambiguous = false,
  });

  final int cardId;

  /// A link row exists; with a null [accountId] it means "no account".
  final bool hasLink;
  final String? accountId;

  /// `auto` or `manual`.
  final String? source;
  final List<CardAccountSuggestion> suggestions;
  final bool ambiguous;

  factory CardAccountMapping.fromJson(Map<String, dynamic> json) {
    final link = json['link'] as Map<String, dynamic>?;
    return CardAccountMapping(
      cardId: (json['card_id'] as num).toInt(),
      hasLink: link != null,
      accountId: link?['account_id'] as String?,
      source: link?['source'] as String?,
      suggestions: [
        for (final item in json['suggestions'] as List? ?? const [])
          if (item is Map<String, dynamic>)
            CardAccountSuggestion(
              accountId: item['account_id'].toString(),
              bankMatch: item['bank_match'] as bool?,
            ),
      ],
      ambiguous: json['ambiguous'] == true,
    );
  }
}

class CardBalanceMapping {
  const CardBalanceMapping({
    required this.status,
    this.accounts = const [],
    this.cards = const [],
  });

  final CardBalancesSnapshot status;
  final List<ZenmoneyAccountOption> accounts;
  final List<CardAccountMapping> cards;

  factory CardBalanceMapping.fromJson(Map<String, dynamic> json) =>
      CardBalanceMapping(
        status: CardBalancesSnapshot.fromJson({
          'integration': json['integration'],
        }),
        accounts: [
          for (final item in json['accounts'] as List? ?? const [])
            ZenmoneyAccountOption.fromJson(item as Map<String, dynamic>),
        ],
        cards: [
          for (final item in json['cards'] as List? ?? const [])
            CardAccountMapping.fromJson(item as Map<String, dynamic>),
        ],
      );
}

/// Admin view of the integration (`GET /api/admin/zenmoney`); never a token.
class ZenmoneySettings {
  const ZenmoneySettings({
    required this.status,
    required this.configured,
    required this.tokenSet,
    this.tokenSetAt,
    this.lastSuccessAt,
    this.lastAttemptAt,
    this.lastErrorKind,
    this.lastErrorMessage,
  });

  final CardBalanceStatus status;
  final bool configured;
  final bool tokenSet;
  final DateTime? tokenSetAt;
  final DateTime? lastSuccessAt;
  final DateTime? lastAttemptAt;
  final String? lastErrorKind;
  final String? lastErrorMessage;

  factory ZenmoneySettings.fromJson(Map<String, dynamic> json) {
    final error = json['last_error'] as Map<String, dynamic>?;
    return ZenmoneySettings(
      status: CardBalanceStatus.parse(json['status']),
      configured: json['configured'] == true,
      tokenSet: json['token_set'] == true,
      tokenSetAt: _instant(json['token_set_at']),
      lastSuccessAt: _instant(json['last_success_at']),
      lastAttemptAt: _instant(json['last_attempt_at']),
      lastErrorKind: error?['kind'] as String?,
      lastErrorMessage: error?['message'] as String?,
    );
  }
}
