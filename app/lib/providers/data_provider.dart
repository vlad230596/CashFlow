import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../models/card_model.dart';
import '../models/bank_model.dart';
import '../models/user_model.dart';
import '../models/cashback_category_model.dart';
import '../models/mcc_rule_model.dart';
import '../models/partner_offer_model.dart';
import '../models/subscription_model.dart';
import '../services/subscription_notification_service.dart';

enum PrimaryDataPhase { initialLoading, ready, refreshing, failed }

class CashbackImportResult {
  const CashbackImportResult({
    required this.created,
    required this.updated,
    required this.importedBanks,
    required this.skippedBanks,
    this.createdPartnerOffers = 0,
    this.updatedPartnerOffers = 0,
  });

  final int created;
  final int updated;
  final int importedBanks;
  final int skippedBanks;
  final int createdPartnerOffers;
  final int updatedPartnerOffers;

  factory CashbackImportResult.fromJson(Map<String, dynamic> json) {
    return CashbackImportResult(
      created: json['created'] as int? ?? 0,
      updated: json['updated'] as int? ?? 0,
      importedBanks: (json['imported_banks'] as List?)?.length ?? 0,
      skippedBanks: (json['skipped'] as List?)?.length ?? 0,
      createdPartnerOffers: json['created_partner_offers'] as int? ?? 0,
      updatedPartnerOffers: json['updated_partner_offers'] as int? ?? 0,
    );
  }
}

class AuthIdentity {
  const AuthIdentity({
    required this.id,
    required this.username,
    required this.role,
  });

  final int id;
  final String username;
  final String role;

  factory AuthIdentity.fromJson(Map<String, dynamic> json) => AuthIdentity(
        id: json['id'] as int,
        username: json['username'] as String,
        role: json['role'] as String,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'username': username,
        'role': role,
      };
}

class _AuthenticatedClient extends http.BaseClient {
  _AuthenticatedClient(
    this._inner,
    this._token,
    this._onUnauthorized,
    this._onSessionExpiration,
  );

  final http.Client _inner;
  final String? Function() _token;
  final Future<void> Function(String? token) _onUnauthorized;
  final Future<void> Function(String? token, String expiresAt)
      _onSessionExpiration;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final token = _token();
    if (token != null) {
      request.headers['Authorization'] = 'Bearer $token';
    }
    final response = await _inner.send(request);
    if (response.statusCode == 401) {
      await _onUnauthorized(token);
    } else {
      final expiresAt = response.headers.entries
          .where(
            (header) =>
                header.key.toLowerCase() == 'x-cashflow-session-expires-at',
          )
          .map((header) => header.value)
          .firstOrNull;
      if (expiresAt != null) {
        await _onSessionExpiration(token, expiresAt);
      }
    }
    return response;
  }

  @override
  void close() => _inner.close();
}

class DataProvider with ChangeNotifier {
  DataProvider({
    String? apiBaseUrl,
    FlutterSecureStorage? secureStorage,
    http.Client? httpClient,
    SubscriptionNotificationService? subscriptionNotificationService,
  })  : apiBaseUrl = apiBaseUrl ?? defaultApiBaseUrl,
        _secureStorage = secureStorage ??
            const FlutterSecureStorage(
              aOptions: AndroidOptions(migrateWithBackup: true),
            ),
        _subscriptionNotifications = subscriptionNotificationService ??
            LocalSubscriptionNotificationService() {
    final innerClient = httpClient ?? http.Client();
    _rawClient = innerClient;
    _client = _AuthenticatedClient(
      innerClient,
      () => _accessToken,
      _clearAuthentication,
      _saveSessionExpiration,
    );
    _notificationTapSubscription =
        _subscriptionNotifications.notificationTaps.listen((id) {
      pendingSubscriptionNotificationId = id;
      notifyListeners();
    });
  }

  static const _configuredApiBaseUrl = String.fromEnvironment(
    'CASHFLOW_API_URL',
  );
  static String get defaultApiBaseUrl => _configuredApiBaseUrl.isNotEmpty
      ? _configuredApiBaseUrl
      : 'https://cash-flow-app.duckdns.org:8443';
  static const _accessTokenKey = 'cashflowAccessToken';
  static const _authIdentityKey = 'cashflowAuthIdentity';
  static const _sessionExpiresAtKey = 'cashflowSessionExpiresAt';

  final String apiBaseUrl;
  final FlutterSecureStorage _secureStorage;
  late final http.Client _rawClient;
  late final http.Client _client;
  final SubscriptionNotificationService _subscriptionNotifications;
  late final StreamSubscription<int> _notificationTapSubscription;
  String? _accessToken;
  DateTime? _sessionExpiresAt;
  final Map<int, int> _selectionMutationVersions = {};
  AuthIdentity? currentAuthUser;
  bool authReady = true;
  String? authError;

  // Only the server can revoke a session. Device time and a cached expiration
  // must not send a previously verified user back to login while offline.
  bool get isAuthenticated => _accessToken != null && currentAuthUser != null;
  bool get canEdit =>
      currentAuthUser?.role == 'editor' || currentAuthUser?.role == 'admin';
  bool get isAdmin => currentAuthUser?.role == 'admin';
  String get serverIp => Uri.parse(apiBaseUrl).authority;

  List<BankModel> banks = [];
  List<UserModel> users = [];
  List<CardModel> cards = [];
  List<CashbackCategoryModel> cashbackCategories = [];
  List<CashbackCategoryModel> activeCashbackCategories = [];
  List<PartnerOffer> partnerOffers = [];
  List<SubscriptionModel> subscriptions = [];
  PrimaryDataPhase primaryDataPhase = PrimaryDataPhase.initialLoading;
  String? primaryDataError;
  DateTime? dataSnapshotUpdatedAt;
  bool partnerOffersLoading = false;
  String? partnerOffersError;
  bool subscriptionsLoading = false;
  String? subscriptionsError;
  int? pendingSubscriptionNotificationId;
  String? _partnerOffersRating;
  String? lastUpdated;
  DateTime? _cashbackDateOverride;

  bool get hasUsableDataSnapshot =>
      dataSnapshotUpdatedAt != null ||
      banks.isNotEmpty ||
      users.isNotEmpty ||
      cards.isNotEmpty ||
      cashbackCategories.isNotEmpty ||
      activeCashbackCategories.isNotEmpty;

  List<SubscriptionModel> get activeSubscriptions => subscriptions
      .where((subscription) => !subscription.isArchived)
      .toList(growable: false)
    ..sort(
        (left, right) => left.nextPaymentDate.compareTo(right.nextPaymentDate));

  List<SubscriptionModel> get archivedSubscriptions => subscriptions
      .where((subscription) => subscription.isArchived)
      .toList(growable: false);

  Uri _apiUri(String path) => Uri.parse(
        '${apiBaseUrl.replaceFirst(RegExp(r'/$'), '')}/api/$path',
      );

  Future<void> _clearAuthentication([String? token]) async {
    // A late 401 from an old request must not erase a newer login.
    if (token != null && token != _accessToken) return;
    final subscriptionsCacheKey = _subscriptionsCacheKey;
    _accessToken = null;
    _sessionExpiresAt = null;
    currentAuthUser = null;
    partnerOffers = [];
    partnerOffersError = null;
    subscriptions = [];
    subscriptionsError = null;
    try {
      await Future.wait([
        _secureStorage.delete(key: _accessTokenKey),
        _secureStorage.delete(key: _authIdentityKey),
        _secureStorage.delete(key: _sessionExpiresAtKey),
        if (subscriptionsCacheKey != null)
          _removeSubscriptionsCache(subscriptionsCacheKey),
        _synchronizeSubscriptionNotifications(),
      ]);
    } finally {
      notifyListeners();
    }
  }

  Future<void> _persistAuthentication() async {
    final user = currentAuthUser;
    final token = _accessToken;
    if (user == null || token == null) return;
    await Future.wait([
      _secureStorage.write(key: _accessTokenKey, value: token),
      _secureStorage.write(
        key: _authIdentityKey,
        value: json.encode(user.toJson()),
      ),
      if (_sessionExpiresAt != null)
        _secureStorage.write(
          key: _sessionExpiresAtKey,
          value: _sessionExpiresAt!.toUtc().toIso8601String(),
        ),
    ]);
  }

  Future<void> _saveSessionExpiration(String? token, String value) async {
    final parsed = DateTime.tryParse(value);
    // Ignore late responses from an older login and out-of-order responses.
    if (token == null ||
        token != _accessToken ||
        parsed == null ||
        (_sessionExpiresAt != null && !parsed.isAfter(_sessionExpiresAt!))) {
      return;
    }
    _sessionExpiresAt = parsed;
    try {
      await _secureStorage.write(
        key: _sessionExpiresAtKey,
        value: parsed.toUtc().toIso8601String(),
      );
    } catch (error) {
      // A storage hiccup must not turn a successful API request into a failure.
      debugPrint('Could not persist the extended session expiration: $error');
    }
  }

  Future<bool> _restoreAuthentication() async {
    try {
      final stored = await Future.wait([
        _secureStorage.read(key: _accessTokenKey),
        _secureStorage.read(key: _authIdentityKey),
        _secureStorage.read(key: _sessionExpiresAtKey),
      ]);
      _accessToken = stored[0];
      if (_accessToken == null) return false;

      final cachedIdentity = stored[1];
      if (cachedIdentity != null) {
        currentAuthUser = AuthIdentity.fromJson(
          json.decode(cachedIdentity) as Map<String, dynamic>,
        );
      }
      _sessionExpiresAt = DateTime.tryParse(stored[2] ?? '');

      final response = await _client.get(_apiUri('auth/me'));
      if (response.statusCode != 200) return isAuthenticated;
      currentAuthUser = AuthIdentity.fromJson(
        json.decode(response.body) as Map<String, dynamic>,
      );
      await _persistAuthentication();
      return true;
    } catch (_) {
      // Keep a previously verified session available from cached data when
      // validation is unavailable. A server 401 still clears it immediately.
      if (isAuthenticated) return true;
      _accessToken = null;
      _sessionExpiresAt = null;
      currentAuthUser = null;
      authError = 'Не удалось восстановить сохранённую сессию';
      return false;
    }
  }

  Future<bool> login(String username, String password) async {
    authError = null;
    try {
      final response = await _rawClient.post(
        _apiUri('auth/login'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({'username': username, 'password': password}),
      );
      final payload = json.decode(response.body) as Map<String, dynamic>;
      if (response.statusCode != 200) {
        authError = payload['error'] as String? ?? 'Ошибка входа';
        notifyListeners();
        return false;
      }
      _accessToken = payload['access_token'] as String;
      _sessionExpiresAt =
          DateTime.tryParse(payload['expires_at'] as String? ?? '');
      currentAuthUser = AuthIdentity.fromJson(
        payload['user'] as Map<String, dynamic>,
      );
      await _persistAuthentication();
      await _loadSubscriptionsCache();
      await _loadPartnerOffersCache();
      notifyListeners();
      await fetchAllData();
      return true;
    } catch (_) {
      authError = 'Сервер недоступен';
      notifyListeners();
      return false;
    }
  }

  Future<void> logout() async {
    try {
      if (_accessToken != null) {
        await _client.post(_apiUri('auth/logout'));
      }
    } finally {
      await _clearAuthentication();
    }
  }

  DateTime get cashbackEffectiveDate =>
      _dateOnly(_cashbackDateOverride ?? DateTime.now());

  bool get usesCurrentCashbackDate => _cashbackDateOverride == null;

  List<CashbackCategoryModel> get effectiveActiveCashbackCategories {
    final source = cashbackCategories.isNotEmpty
        ? cashbackCategories
        : activeCashbackCategories;

    return source.where((category) {
      final effectiveDate = cashbackEffectiveDate;
      final startDate = _dateOnly(category.startDate);
      final endDate = _dateOnly(category.endDate);

      return category.isActive &&
          !effectiveDate.isBefore(startDate) &&
          effectiveDate.isBefore(endDate);
    }).toList();
  }

  static DateTime _dateOnly(DateTime date) =>
      DateTime(date.year, date.month, date.day);

  Future<void> setCashbackEffectiveDate(DateTime? date) async {
    _cashbackDateOverride = date == null ? null : _dateOnly(date);

    final prefs = await SharedPreferences.getInstance();
    if (_cashbackDateOverride == null) {
      await prefs.remove('cashbackEffectiveDate');
    } else {
      await prefs.setString(
        'cashbackEffectiveDate',
        _cashbackDateOverride!.toIso8601String(),
      );
    }

    notifyListeners();
  }

  Future<List<T>> receiveFromServer<T>(
    String endpoint,
    T Function(Map<String, dynamic>) fromJson,
  ) async {
    final response = await _client.get(_apiUri(endpoint));

    if (response.statusCode != 200) {
      throw Exception('Failed to load $endpoint: ${response.statusCode}');
    }

    final result = (json.decode(response.body) as List)
        .map((item) => fromJson(item))
        .toList();
    return result;
  }

  String _responseError(http.Response response, String fallback) {
    try {
      final payload = json.decode(response.body) as Map<String, dynamic>;
      return payload['error'] as String? ?? fallback;
    } catch (_) {
      return fallback;
    }
  }

  Future<List<MccRuleRevisionModel>> fetchMccRuleRevisions(int bankId) async {
    final response = await _client.get(
      _apiUri('admin/mcc-rule-revisions?bank_id=$bankId'),
    );
    if (response.statusCode != 200) {
      throw Exception(
        _responseError(response, 'Не удалось загрузить правила MCC'),
      );
    }
    return (json.decode(response.body) as List)
        .map(
          (item) => MccRuleRevisionModel.fromJson(
            item as Map<String, dynamic>,
          ),
        )
        .toList();
  }

  Future<MccRuleRevisionModel> createMccRuleSnapshot(
    Map<String, dynamic> document,
  ) async {
    final response = await _client.post(
      _apiUri('admin/mcc-rule-snapshots'),
      headers: {'Content-Type': 'application/json'},
      body: json.encode({'document': document}),
    );
    if (response.statusCode != 200 && response.statusCode != 201) {
      throw Exception(
        _responseError(response, 'Не удалось сохранить правила MCC'),
      );
    }
    return MccRuleRevisionModel.fromJson(
      json.decode(response.body) as Map<String, dynamic>,
    );
  }

  Future<MccRuleRevisionModel> publishMccRuleRevision(int revisionId) async {
    final response = await _client.post(
      _apiUri('admin/mcc-rule-revisions/$revisionId/publish'),
    );
    if (response.statusCode != 200) {
      throw Exception(
        _responseError(response, 'Не удалось опубликовать правила MCC'),
      );
    }
    return MccRuleRevisionModel.fromJson(
      json.decode(response.body) as Map<String, dynamic>,
    );
  }

  Future<void> autoImportMccRules(int bankId) async {
    final response = await _client.post(
      _apiUri('admin/banks/$bankId/mcc-rules/auto-import'),
    );
    if (response.statusCode != 200 && response.statusCode != 201) {
      throw Exception(
        _responseError(response, 'Автоматическая загрузка пока недоступна'),
      );
    }
  }

  Future<void> initialize() async {
    authReady = false;
    try {
      await _subscriptionNotifications.initialize();
    } catch (error) {
      debugPrint('Could not initialize subscription notifications: $error');
    }
    await loadLocalData();
    await _synchronizeSubscriptionNotifications();
    final restored = await _restoreAuthentication();
    if (restored) {
      await _loadSubscriptionsCache();
      await _loadPartnerOffersCache();
      await _synchronizeSubscriptionNotifications();
    }
    authReady = true;
    notifyListeners();
    if (restored) {
      unawaited(fetchAllData());
    }
  }

  Future<T> addItemToServer<T>(
      String endpoint,
      T item,
      T Function(Map<String, dynamic>) fromJson,
      Map<String, dynamic> Function(T) toJson) async {
    try {
      final response = await _client.post(
        _apiUri(endpoint),
        headers: {'Content-Type': 'application/json'},
        body: json.encode(toJson(item)),
      );

      if (response.statusCode == 201) {
        final newItem = fromJson(json.decode(response.body));
        return newItem;
      } else {
        throw Exception('Failed to add item');
      }
    } catch (e) {
      debugPrint('Error adding item: $e');
      rethrow;
    }
  }

  Future<void> deleteItemFromServer(String endpoint, int id) async {
    try {
      final response = await _client.delete(
        _apiUri('$endpoint/$id'),
      );

      if (response.statusCode == 204) {
        debugPrint('Delete from server item with id $id from $endpoint');
      } else {
        throw Exception('Failed to delete bank');
      }
    } catch (e) {
      debugPrint('Error deleting bank: $e');
      rethrow;
    }
  }

  Future<T> updateItemOnServer<T>(
      String endpoint,
      int id,
      T item,
      T Function(Map<String, dynamic>) fromJson,
      Map<String, dynamic> Function(T) toJson) async {
    try {
      final response = await _client.put(
        _apiUri('$endpoint/$id'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode(toJson(item)),
      );

      if (response.statusCode == 200) {
        return fromJson(json.decode(response.body));
      } else {
        throw Exception('Failed to update bank');
      }
    } catch (e) {
      debugPrint('Error updating bank: $e');
      rethrow;
    }
  }

  Future<bool> fetchAllData() async {
    primaryDataPhase = hasUsableDataSnapshot
        ? PrimaryDataPhase.refreshing
        : PrimaryDataPhase.initialLoading;
    primaryDataError = null;
    notifyListeners();
    try {
      final fetchedBanks = await receiveFromServer("banks", BankModel.fromJson);
      final fetchedUsers = await receiveFromServer("users", UserModel.fromJson);
      final fetchedCards = await receiveFromServer("cards", CardModel.fromJson);
      final fetchedActiveCashbackCategories = await receiveFromServer(
        "active_cashback",
        CashbackCategoryModel.fromJson,
      );
      final fetchedCashbackCategories = await receiveFromServer(
        "cashback",
        CashbackCategoryModel.fromJson,
      );
      final fetchedSubscriptions = await _receiveSubscriptions('all');

      banks = fetchedBanks;
      users = fetchedUsers;
      cards = fetchedCards;
      activeCashbackCategories = fetchedActiveCashbackCategories;
      cashbackCategories = fetchedCashbackCategories;
      subscriptions = fetchedSubscriptions
          .map(_mergeCachedSubscriptionDetails)
          .toList(growable: false);
      dataSnapshotUpdatedAt = DateTime.now();
      lastUpdated = dataSnapshotUpdatedAt.toString();
      primaryDataPhase = PrimaryDataPhase.ready;
      await _saveDataLocally();
      await _synchronizeSubscriptionNotifications();
      await fetchPartnerOffers();
      notifyListeners();
      return true;
    } catch (e) {
      // Handle errors
      debugPrint('Error fetching data: $e');
      primaryDataPhase = PrimaryDataPhase.failed;
      primaryDataError = 'Не удалось обновить данные';
      notifyListeners();
      return false;
    }
  }

  Future<void> fetchCashbackCategories() async {
    try {
      final response = await _client.get(
        _apiUri('cashback'),
        headers: {'Accept': 'application/json'},
      );

      if (response.statusCode == 200) {
        final List<dynamic> data = json.decode(response.body);
        cashbackCategories =
            data.map((json) => CashbackCategoryModel.fromJson(json)).toList();
        notifyListeners();
      } else {
        throw Exception('Failed to load categories: ${response.statusCode}');
      }
    } catch (e) {
      debugPrint('Error fetching cashback categories: $e');
      rethrow;
    }
  }

  // Future<void> fetchCashbacks() async {
  //   try {
  //     final response = await http.get(Uri.parse('http://$serverIp/api/active_cashback'));
  //     print('response status: ${response.statusCode}');
  //     print('response body: ${response.body}');
  //     if (response.statusCode == 200) {
  //       final List<dynamic> data = json.decode(response.body);
  //       _cashbacks = data.map((json) => CashbackModel.fromJson(json)).toList();
  //       print('Server returned: $data');
  //       await _saveCashbacksLocally(data); // Сохраняем данные локально
  //       notifyListeners();
  //     } else {
  //       throw Exception('Failed to load data');
  //     }
  //   } catch (e) {
  //     print('Error by loading data: $e');
  //   }
  // }

  Future<void> loadLocalData() async {
    final prefs = await SharedPreferences.getInstance();
    // Remove the pre-user-scoping key from early development builds.
    await prefs.remove('subscriptions');
    try {
      final cachedBanks = prefs.getString('banks');
      final cachedUsers = prefs.getString('users');
      final cachedCards = prefs.getString('cards');
      final cachedCashbackCategories = prefs.getString('cashbackCategories');
      final cachedActiveCashbackCategories =
          prefs.getString('activeCashbackCategories');
      final cachedCashbackEffectiveDate =
          prefs.getString('cashbackEffectiveDate');
      final cachedDataSnapshotUpdatedAt =
          prefs.getString('dataSnapshotUpdatedAt');

      if (cachedDataSnapshotUpdatedAt != null) {
        dataSnapshotUpdatedAt = DateTime.tryParse(cachedDataSnapshotUpdatedAt);
        lastUpdated = dataSnapshotUpdatedAt?.toString();
      }

      if (cachedCashbackEffectiveDate != null) {
        _cashbackDateOverride =
            _dateOnly(DateTime.parse(cachedCashbackEffectiveDate));
      }

      if (cachedBanks != null) {
        banks = (json.decode(cachedBanks) as List)
            .map((item) => BankModel.fromJson(item as Map<String, dynamic>))
            .toList();
      }
      if (cachedUsers != null) {
        users = (json.decode(cachedUsers) as List)
            .map((item) => UserModel.fromJson(item as Map<String, dynamic>))
            .toList();
      }
      if (cachedCards != null) {
        cards = (json.decode(cachedCards) as List)
            .map((item) => CardModel.fromJson(item as Map<String, dynamic>))
            .toList();
      }
      if (cachedCashbackCategories != null) {
        cashbackCategories = (json.decode(cachedCashbackCategories) as List)
            .map((item) =>
                CashbackCategoryModel.fromJson(item as Map<String, dynamic>))
            .toList();
      }
      if (cachedActiveCashbackCategories != null) {
        activeCashbackCategories = (json.decode(cachedActiveCashbackCategories)
                as List)
            .map((item) =>
                CashbackCategoryModel.fromJson(item as Map<String, dynamic>))
            .toList();
      }
      if (hasUsableDataSnapshot) {
        primaryDataPhase = PrimaryDataPhase.ready;
      }
      notifyListeners();
    } catch (e) {
      debugPrint('Error loadLocalData: $e');
    }
  }

  Future<void> _saveDataLocally() async {
    final prefs = await SharedPreferences.getInstance();
    prefs.setString('banks',
        json.encode(banks.map((bank) => BankModel.toJson(bank)).toList()));
    prefs.setString('users',
        json.encode(users.map((user) => UserModel.toJson(user)).toList()));
    prefs.setString('cards',
        json.encode(cards.map((card) => CardModel.toJson(card)).toList()));
    prefs.setString(
        'cashbackCategories',
        json.encode(cashbackCategories
            .map((cashbackCategory) =>
                CashbackCategoryModel.toJson(cashbackCategory))
            .toList()));
    prefs.setString(
        'activeCashbackCategories',
        json.encode(activeCashbackCategories
            .map((cashbackCategory) =>
                CashbackCategoryModel.toJson(cashbackCategory))
            .toList()));
    final subscriptionsCacheKey = _subscriptionsCacheKey;
    if (subscriptionsCacheKey != null) {
      prefs.setString(
        subscriptionsCacheKey,
        json.encode(
          subscriptions
              .map((subscription) => subscription.toJson())
              .toList(growable: false),
        ),
      );
    }
    if (dataSnapshotUpdatedAt != null) {
      prefs.setString(
        'dataSnapshotUpdatedAt',
        dataSnapshotUpdatedAt!.toIso8601String(),
      );
    }
  }

  Future<List<SubscriptionModel>> _receiveSubscriptions(String status) async {
    final response = await _client.get(
      _apiUri('subscriptions?status=$status'),
    );
    if (response.statusCode != 200) {
      throw Exception(
        _responseError(response, 'Failed to load subscriptions'),
      );
    }
    final payload = json.decode(response.body);
    final items = payload is List
        ? payload
        : (payload as Map<String, dynamic>)['items'] as List? ?? const [];
    return items
        .map((item) => SubscriptionModel.fromJson(item as Map<String, dynamic>))
        .toList(growable: false);
  }

  Future<bool> fetchSubscriptions({String status = 'all'}) async {
    subscriptionsLoading = true;
    subscriptionsError = null;
    notifyListeners();
    try {
      final fetched = await _receiveSubscriptions(status);
      final merged =
          fetched.map(_mergeCachedSubscriptionDetails).toList(growable: false);
      if (status == 'all') {
        subscriptions = merged;
      } else {
        final archived = status == 'archived';
        subscriptions = [
          ...subscriptions.where(
            (subscription) => subscription.isArchived != archived,
          ),
          ...merged,
        ];
      }
      await _saveDataLocally();
      await _synchronizeSubscriptionNotifications();
      return true;
    } catch (error) {
      subscriptionsError = error.toString();
      debugPrint('Error fetching subscriptions: $error');
      return false;
    } finally {
      subscriptionsLoading = false;
      notifyListeners();
    }
  }

  Future<SubscriptionModel> fetchSubscription(int id) async {
    return fetchSubscriptionDetail(id);
  }

  Future<SubscriptionModel> fetchSubscriptionDetail(int id) async {
    final response = await _client.get(_apiUri('subscriptions/$id'));
    if (response.statusCode != 200) {
      throw Exception(
        _responseError(response, 'Failed to load subscription'),
      );
    }
    final subscription = SubscriptionModel.fromJson(
      json.decode(response.body) as Map<String, dynamic>,
    );
    await _storeSubscription(subscription);
    return subscription;
  }

  SubscriptionModel _mergeCachedSubscriptionDetails(
    SubscriptionModel subscription,
  ) {
    final existing =
        subscriptions.where((item) => item.id == subscription.id).firstOrNull;
    if (existing == null) return subscription;
    return subscription.copyWith(
      payments: subscription.payments.isEmpty
          ? existing.payments
          : subscription.payments,
      activePeriods: subscription.activePeriods.isEmpty
          ? existing.activePeriods
          : subscription.activePeriods,
    );
  }

  Future<SubscriptionModel> createSubscription(
    SubscriptionModel subscription,
  ) async {
    final response = await _client.post(
      _apiUri('subscriptions'),
      headers: {'Content-Type': 'application/json'},
      body: json.encode(
        subscription.toMutationJson(includeLastPayment: true),
      ),
    );
    if (response.statusCode != 201) {
      throw Exception(
        _responseError(response, 'Failed to create subscription'),
      );
    }
    final created = SubscriptionModel.fromJson(
      json.decode(response.body) as Map<String, dynamic>,
    );
    await _storeSubscription(created);
    return created;
  }

  Future<SubscriptionModel> updateSubscription(
    SubscriptionModel subscription,
  ) async {
    final id = subscription.id;
    if (id == null) {
      throw ArgumentError('A saved subscription is required for update');
    }
    final response = await _client.put(
      _apiUri('subscriptions/$id'),
      headers: {'Content-Type': 'application/json'},
      body: json.encode(subscription.toMutationJson()),
    );
    if (response.statusCode != 200) {
      throw Exception(
        _responseError(response, 'Failed to update subscription'),
      );
    }
    final updated = SubscriptionModel.fromJson(
      json.decode(response.body) as Map<String, dynamic>,
    );
    await _storeSubscription(updated);
    return updated;
  }

  Future<SubscriptionModel> archiveSubscription(int id) async {
    final response = await _client.post(
      _apiUri('subscriptions/$id/archive'),
    );
    if (response.statusCode != 200) {
      throw Exception(
        _responseError(response, 'Failed to archive subscription'),
      );
    }
    final archived = SubscriptionModel.fromJson(
      json.decode(response.body) as Map<String, dynamic>,
    );
    await _storeSubscription(archived);
    await _subscriptionNotifications.cancelSubscription(id);
    return archived;
  }

  Future<SubscriptionModel> restoreSubscription(
    int id, {
    required DateTime nextPaymentDate,
    int? cardId,
    double? expectedAmount,
    String? currency,
  }) async {
    final response = await _client.post(
      _apiUri('subscriptions/$id/restore'),
      headers: {'Content-Type': 'application/json'},
      body: json.encode({
        'next_payment_date': _subscriptionApiDate(nextPaymentDate),
        if (cardId != null) 'card_id': cardId,
        if (expectedAmount != null)
          'expected_amount': expectedAmount.toStringAsFixed(2),
        if (currency != null) 'currency': currency,
      }),
    );
    if (response.statusCode != 200) {
      throw Exception(
        _responseError(response, 'Failed to restore subscription'),
      );
    }
    final restored = SubscriptionModel.fromJson(
      json.decode(response.body) as Map<String, dynamic>,
    );
    await _storeSubscription(restored);
    return restored;
  }

  Future<SubscriptionModel> confirmSubscriptionPayment(
    int id, {
    required DateTime paidAt,
    double? amount,
    String? currency,
    int? cardId,
  }) async {
    final response = await _client.post(
      _apiUri('subscriptions/$id/payments'),
      headers: {'Content-Type': 'application/json'},
      body: json.encode({
        'paid_at': _subscriptionApiDate(paidAt),
        if (amount != null) 'amount': amount.toStringAsFixed(2),
        if (currency != null) 'currency': currency,
        if (cardId != null) 'card_id': cardId,
      }),
    );
    if (response.statusCode != 201) {
      throw Exception(
        _responseError(response, 'Failed to confirm subscription payment'),
      );
    }
    final updated = SubscriptionModel.fromJson(
      json.decode(response.body) as Map<String, dynamic>,
    );
    await _storeSubscription(updated);
    return updated;
  }

  Future<bool> requestSubscriptionNotificationPermission() async {
    if (!subscriptions.any((subscription) => subscription.id != null)) {
      return false;
    }
    return _subscriptionNotifications.requestPermission();
  }

  int? consumePendingSubscriptionNotificationId() {
    final result = pendingSubscriptionNotificationId ??
        _subscriptionNotifications.consumePendingSubscriptionId();
    pendingSubscriptionNotificationId = null;
    if (result != null) notifyListeners();
    return result;
  }

  Future<void> _storeSubscription(SubscriptionModel subscription) async {
    final id = subscription.id;
    if (id == null) return;
    final index = subscriptions.indexWhere((item) => item.id == id);
    if (index == -1) {
      subscriptions = [...subscriptions, subscription];
    } else {
      subscriptions = [...subscriptions]..[index] = subscription;
    }
    await _saveDataLocally();
    await _synchronizeSubscriptionNotifications();
    notifyListeners();
  }

  Future<void> _synchronizeSubscriptionNotifications() async {
    try {
      await _subscriptionNotifications.synchronize(subscriptions);
    } catch (error) {
      debugPrint('Could not schedule subscription notifications: $error');
    }
  }

  static String _subscriptionApiDate(DateTime value) {
    final local = value.toLocal();
    return '${local.year.toString().padLeft(4, '0')}-'
        '${local.month.toString().padLeft(2, '0')}-'
        '${local.day.toString().padLeft(2, '0')}';
  }

  String? get _subscriptionsCacheKey {
    final authUserId = currentAuthUser?.id;
    return authUserId == null ? null : 'subscriptions:$authUserId';
  }

  Future<void> _loadSubscriptionsCache() async {
    final key = _subscriptionsCacheKey;
    if (key == null) return;
    final cached = (await SharedPreferences.getInstance()).getString(key);
    if (cached == null) return;
    try {
      subscriptions = (json.decode(cached) as List)
          .map((item) =>
              SubscriptionModel.fromJson(item as Map<String, dynamic>))
          .toList();
    } catch (error) {
      debugPrint('Could not load subscriptions cache: $error');
    }
  }

  Future<void> _removeSubscriptionsCache(String key) async {
    await (await SharedPreferences.getInstance()).remove(key);
  }

  String? get _partnerOffersCacheKey {
    final authUserId = currentAuthUser?.id;
    return authUserId == null ? null : 'partnerOffers:$authUserId';
  }

  Future<void> _loadPartnerOffersCache() async {
    final key = _partnerOffersCacheKey;
    if (key == null) return;
    final prefs = await SharedPreferences.getInstance();
    final cached = prefs.getString(key);
    if (cached == null) return;
    try {
      partnerOffers = (json.decode(cached) as List)
          .map((item) => PartnerOffer.fromJson(item as Map<String, dynamic>))
          .toList();
    } catch (error) {
      debugPrint('Error loading cached partner offers: $error');
    }
  }

  Future<void> _savePartnerOffersCache() async {
    final key = _partnerOffersCacheKey;
    if (key == null) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      key,
      json.encode(partnerOffers.map((offer) => offer.toJson()).toList()),
    );
  }

  Future<bool> fetchPartnerOffers({String? rating}) async {
    partnerOffersLoading = true;
    partnerOffersError = null;
    notifyListeners();
    try {
      const pageSize = 100;
      var offset = 0;
      var total = 0;
      final fetched = <PartnerOffer>[];
      do {
        final parameters = <String, String>{
          'limit': '$pageSize',
          'offset': '$offset',
          if (rating != null) 'rating': rating,
        };
        final uri = _apiUri('partner-offers').replace(
          queryParameters: parameters,
        );
        final response = await _client.get(uri);
        if (response.statusCode != 200) {
          throw Exception(
            _responseError(response, 'Не удалось загрузить предложения'),
          );
        }
        final payload = json.decode(response.body) as Map<String, dynamic>;
        final page = (payload['items'] as List)
            .map((item) => PartnerOffer.fromJson(item as Map<String, dynamic>))
            .toList();
        fetched.addAll(page);
        total = payload['total'] as int? ?? fetched.length;
        offset += page.length;
        if (page.isEmpty) break;
      } while (offset < total);
      partnerOffers = fetched;
      _partnerOffersRating = rating;
      if (rating == null) await _savePartnerOffersCache();
      return true;
    } catch (error) {
      partnerOffersError = 'Не удалось обновить предложения';
      debugPrint('Error fetching partner offers: $error');
      if (rating == null) {
        await _loadPartnerOffersCache();
        _partnerOffersRating = null;
      }
      return false;
    } finally {
      partnerOffersLoading = false;
      notifyListeners();
    }
  }

  Future<PartnerOffer> fetchPartnerOfferDetails(int offerId) async {
    final response = await _client.get(_apiUri('partner-offers/$offerId'));
    if (response.statusCode != 200) {
      throw Exception(
        _responseError(response, 'Не удалось загрузить условия'),
      );
    }
    return PartnerOffer.fromJson(
      json.decode(response.body) as Map<String, dynamic>,
    );
  }

  Future<void> updatePartnerOfferPreference(
    int offerId,
    String rating,
  ) async {
    const allowed = {'interesting', 'undecided', 'hidden'};
    if (!allowed.contains(rating)) {
      throw ArgumentError.value(rating, 'rating');
    }
    final index = partnerOffers.indexWhere((offer) => offer.id == offerId);
    final original = index == -1 ? null : partnerOffers[index];
    if (original != null) {
      partnerOffers[index] = original.copyWith(preference: rating);
      notifyListeners();
    }
    try {
      final response = await _client.put(
        _apiUri('partner-offers/$offerId/preference'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({'rating': rating}),
      );
      if (response.statusCode != 200) {
        throw Exception(
          _responseError(response, 'Не удалось сохранить оценку'),
        );
      }
      if (_partnerOffersRating == null) await _savePartnerOffersCache();
    } catch (_) {
      if (original != null) {
        final rollback =
            partnerOffers.indexWhere((offer) => offer.id == offerId);
        if (rollback != -1) partnerOffers[rollback] = original;
        notifyListeners();
      }
      rethrow;
    }
  }

  Future<void> addBank(
    String name,
    String description, {
    String iconKey = 'generic',
  }) async {
    final item =
        BankModel(name: name, description: description, iconKey: iconKey);
    final result = await addItemToServer(
        "banks", item, BankModel.fromJson, BankModel.toJson);
    banks.add(result);
    notifyListeners();
  }

  Future<void> updateBank(
    int id,
    String name,
    String description, {
    String iconKey = 'generic',
  }) async {
    try {
      final updated = await updateItemOnServer(
          'banks',
          id,
          BankModel(name: name, description: description, iconKey: iconKey),
          BankModel.fromJson,
          BankModel.toJson);
      banks[banks.indexWhere((bank) => bank.id == id)] = updated;
      notifyListeners();
    } catch (e) {
      debugPrint('Error updating bank: $e');
      rethrow;
    }
  }

  Future<void> deleteBank(int id) async {
    try {
      await deleteItemFromServer('banks', id);
      banks.removeWhere((bank) => bank.id == id);
      notifyListeners();
    } catch (e) {
      debugPrint('Error deleting bank: $e');
      rethrow;
    }
  }

  Future<void> addUser(String name, {String iconKey = 'boy'}) async {
    try {
      final response = await _client.post(
        _apiUri('users'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({
          'name': name,
          'icon_key': iconKey,
        }),
      );

      if (response.statusCode == 201) {
        final newUser = UserModel.fromJson(
          json.decode(response.body) as Map<String, dynamic>,
        );
        users.add(newUser);
        notifyListeners();
      } else {
        throw Exception('Failed to add user');
      }
    } catch (e) {
      debugPrint('Error adding user: $e');
      rethrow;
    }
  }

  Future<void> updateUser(
    int id,
    String name, {
    String iconKey = 'boy',
  }) async {
    try {
      final response = await _client.put(
        _apiUri('users/$id'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({
          'name': name,
          'icon_key': iconKey,
        }),
      );

      if (response.statusCode == 200) {
        final index = users.indexWhere((user) => user.id == id);
        if (index != -1) {
          users[index] = UserModel.fromJson(
            json.decode(response.body) as Map<String, dynamic>,
          );
          notifyListeners();
        }
      } else {
        throw Exception('Failed to update user');
      }
    } catch (e) {
      debugPrint('Error updating user: $e');
      rethrow;
    }
  }

  Future<void> deleteUser(int id) async {
    try {
      final response = await _client.delete(
        _apiUri('users/$id'),
      );

      if (response.statusCode == 204) {
        users.removeWhere((user) => user.id == id);
        notifyListeners();
      } else {
        throw Exception('Failed to delete user');
      }
    } catch (e) {
      debugPrint('Error deleting user: $e');
      rethrow;
    }
  }

  Future<void> addCard(
    String paymentSystem,
    String cardType,
    String lastFourDigits,
    int bankId,
    int userId,
  ) async {
    final item = CardModel(
        paymentSystem: paymentSystem,
        cardType: cardType,
        lastFourDigits: lastFourDigits,
        bankId: bankId,
        userId: userId);
    final result = await addItemToServer(
        "cards", item, CardModel.fromJson, CardModel.toJson);
    cards.add(result);
    notifyListeners();
  }

  CardModel getCardById(int cardId) {
    return cards.firstWhere(
      (card) => card.id == cardId,
      orElse: () => CardModel(
        id: cardId,
        paymentSystem: '',
        cardType: '',
        lastFourDigits: '????',
      ),
    );
  }

  String getCardName(int cardId) {
    final card = getCardById(cardId);
    final userName = users
        .where((user) => user.id == card.userId)
        .map((user) => user.name)
        .firstOrNull;
    final bankName = banks
        .where((bank) => bank.id == card.bankId)
        .map((bank) => bank.name)
        .firstOrNull;

    if (userName == null && bankName == null) {
      return 'Unknown card';
    }

    return [
      if (userName != null) userName,
      if (bankName != null) bankName,
    ].join(' ');
  }

  Future<void> updateCard(
    int id,
    String paymentSystem,
    String cardType,
    String lastFourDigits,
    int bankId,
    int userId,
  ) async {
    try {
      final response = await _client.put(
        _apiUri('cards/$id'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({
          'payment_system': paymentSystem,
          'card_type': cardType,
          'last_four_digits': lastFourDigits,
          'bank_id': bankId,
          'user_id': userId,
        }),
      );

      if (response.statusCode == 200) {
        final index = cards.indexWhere((card) => card.id == id);
        if (index != -1) {
          cards[index] = CardModel(
            id: id,
            paymentSystem: paymentSystem,
            cardType: cardType,
            lastFourDigits: lastFourDigits,
            bankId: bankId,
            userId: userId,
          );
          notifyListeners();
        }
      } else {
        throw Exception('Failed to update card');
      }
    } catch (e) {
      debugPrint('Error updating card: $e');
      rethrow;
    }
  }

  Future<void> deleteCard(int id) async {
    try {
      final response = await _client.delete(
        _apiUri('cards/$id'),
      );

      if (response.statusCode == 204) {
        cards.removeWhere((card) => card.id == id);
        notifyListeners();
      } else {
        throw Exception('Failed to delete card');
      }
    } catch (e) {
      debugPrint('Error deleting card: $e');
      rethrow;
    }
  }

  Future<void> addCashbackCategory(
    String name,
    double cashbackPercent,
    int cardId,
    DateTime startDate,
    DateTime endDate, {
    String? description,
    String categoryType = 'standard',
    double? maxCashbackAmount,
    double? minPurchaseAmount,
  }) {
    return addCashbackCategoryQuietly(
      name,
      cashbackPercent,
      cardId,
      startDate,
      endDate,
      description: description,
      categoryType: categoryType,
      maxCashbackAmount: maxCashbackAmount,
      minPurchaseAmount: minPurchaseAmount,
      notify: true,
    );
  }

  Future<void> addCashbackCategoryQuietly(
    String name,
    double cashbackPercent,
    int cardId,
    DateTime startDate,
    DateTime endDate, {
    required bool notify,
    String? description,
    String categoryType = 'standard',
    double? maxCashbackAmount,
    double? minPurchaseAmount,
  }) async {
    try {
      final response = await _client.post(
        _apiUri('cashback'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({
          'name': name,
          'cashback_percent': cashbackPercent,
          'card_id': cardId,
          'start_date': startDate.toIso8601String(),
          'end_date': endDate.toIso8601String(),
          'is_selected': false,
          'description': description,
          'category_type': categoryType,
          'max_cashback_amount': maxCashbackAmount,
          'min_purchase_amount': minPurchaseAmount,
        }),
      );

      if (response.statusCode == 201) {
        final newCategory =
            CashbackCategoryModel.fromJson(json.decode(response.body));
        cashbackCategories.add(newCategory);
        if (notify) {
          notifyListeners();
        }
      } else {
        throw Exception('Failed to add category: ${response.statusCode}');
      }
    } catch (e) {
      debugPrint('Error adding cashback category: $e');
      rethrow;
    }
  }

  void notifyCashbackCategoriesChanged() {
    notifyListeners();
  }

  Future<CashbackImportResult> importCashbackDocument(
    String contents,
    int userId,
  ) async {
    final decoded = json.decode(contents);
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('JSON должен содержать объект импорта');
    }

    final response = await _client.post(
      _apiUri('cashback/import'),
      headers: {'Content-Type': 'application/json'},
      body: json.encode({
        'document': decoded,
        'user_id': userId,
      }),
    );

    final responseData = json.decode(response.body);
    if (response.statusCode != 200) {
      final message =
          responseData is Map<String, dynamic> ? responseData['error'] : null;
      throw Exception(message ?? 'Ошибка импорта: ${response.statusCode}');
    }

    final result = CashbackImportResult.fromJson(
      responseData as Map<String, dynamic>,
    );
    final partnerResponse = await _client.post(
      _apiUri('partner-offers/import'),
      headers: {'Content-Type': 'application/json'},
      body: json.encode({
        'document': decoded,
        'card_user_id': userId,
      }),
    );
    final partnerData = json.decode(partnerResponse.body);
    if (partnerResponse.statusCode != 200) {
      final message =
          partnerData is Map<String, dynamic> ? partnerData['error'] : null;
      throw Exception(
        'Категории импортированы, но предложения сохранить не удалось: '
        '${message ?? partnerResponse.statusCode}',
      );
    }
    final partnerResult = partnerData as Map<String, dynamic>;
    final refreshed = await fetchAllData();
    if (!refreshed) {
      throw Exception('Импорт выполнен, но обновить данные не удалось');
    }
    return CashbackImportResult(
      created: result.created,
      updated: result.updated,
      importedBanks: result.importedBanks,
      skippedBanks: result.skippedBanks,
      createdPartnerOffers: partnerResult['created_offers'] as int? ?? 0,
      updatedPartnerOffers: partnerResult['updated_offers'] as int? ?? 0,
    );
  }

  Future<void> updateCashbackCategory(
    CashbackCategoryModel category,
  ) async {
    try {
      final response = await _client.put(
        _apiUri('cashback/${category.id}'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode(CashbackCategoryModel.toJson(category)),
      );

      if (response.statusCode == 200) {
        final updatedCategory =
            CashbackCategoryModel.fromJson(json.decode(response.body));
        final index =
            cashbackCategories.indexWhere((c) => c.id == updatedCategory.id);
        if (index != -1) {
          cashbackCategories[index] = updatedCategory;
        } else {
          cashbackCategories.add(updatedCategory);
        }

        final activeIndex = activeCashbackCategories
            .indexWhere((c) => c.id == updatedCategory.id);
        if (activeIndex != -1) {
          if (updatedCategory.isActive) {
            activeCashbackCategories[activeIndex] = updatedCategory;
          } else {
            activeCashbackCategories.removeAt(activeIndex);
          }
        } else if (updatedCategory.isActive) {
          activeCashbackCategories.add(updatedCategory);
        }

        await _saveDataLocally();
        notifyListeners();
      } else {
        throw Exception('Failed to update category: ${response.statusCode}');
      }
    } catch (e) {
      debugPrint('Error updating cashback category: $e');
      rethrow;
    }
  }

  Future<void> toggleCategorySelection(int categoryId, bool isSelected) async {
    final index = cashbackCategories.indexWhere((c) => c.id == categoryId);
    if (index == -1) {
      throw StateError('Cashback category $categoryId was not found');
    }

    final original = cashbackCategories[index];
    final optimistic = original.copyWith(
      isSelected: isSelected,
      isBankConfirmed:
          original.isSelected == isSelected && original.isBankConfirmed,
    );
    final version = (_selectionMutationVersions[categoryId] ?? 0) + 1;
    _selectionMutationVersions[categoryId] = version;
    cashbackCategories[index] = optimistic;
    _syncActiveCategory(optimistic);
    notifyListeners();

    try {
      final response = await _client.put(
        _apiUri('cashback/$categoryId'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({'is_selected': isSelected}),
      );

      if (response.statusCode != 200) {
        throw Exception('Failed to update category: ${response.statusCode}');
      }
      await _saveDataLocally();
    } catch (e) {
      if (_selectionMutationVersions[categoryId] == version) {
        final rollbackIndex =
            cashbackCategories.indexWhere((c) => c.id == categoryId);
        if (rollbackIndex != -1) cashbackCategories[rollbackIndex] = original;
        _syncActiveCategory(original);
        notifyListeners();
      }
      debugPrint('Error toggling category selection: $e');
      rethrow;
    }
  }

  void _syncActiveCategory(CashbackCategoryModel category) {
    final activeIndex =
        activeCashbackCategories.indexWhere((item) => item.id == category.id);
    if (category.isActive) {
      if (activeIndex == -1) {
        activeCashbackCategories.add(category);
      } else {
        activeCashbackCategories[activeIndex] = category;
      }
    } else if (activeIndex != -1) {
      activeCashbackCategories.removeAt(activeIndex);
    }
  }

  @override
  void dispose() {
    _notificationTapSubscription.cancel();
    _client.close();
    super.dispose();
  }
}
