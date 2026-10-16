import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../models/card_model.dart';
import '../models/bank_model.dart';
import '../models/user_model.dart';
import '../models/canonical_category_model.dart';
import '../models/cashback_category_model.dart';
import '../models/mcc_lookup_model.dart';
import '../models/mcc_rule_model.dart';
import '../models/partner_offer_model.dart';
import '../models/subscription_model.dart';
import '../services/subscription_notification_service.dart';
import '../services/mcc_cache_store.dart';
import '../services/mcc_repository.dart';
import '../services/api_client.dart';
import '../services/app_log.dart';
import '../services/timeout_client.dart';
import '../services/import_coordinator.dart';
import '../services/reference_data_store.dart';
import '../services/business_clock.dart';
export '../services/import_coordinator.dart';

enum PrimaryDataPhase { initialLoading, ready, refreshing, failed }

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

class DataProvider with ChangeNotifier {
  DataProvider({
    String? apiBaseUrl,
    FlutterSecureStorage? secureStorage,
    http.Client? httpClient,
    BusinessClock? businessClock,
    MccCacheStore? mccCacheStore,
    SubscriptionNotificationService? subscriptionNotificationService,
    Future<void> Function()? afterFirstFrame,
  })  : apiBaseUrl = apiBaseUrl ?? defaultApiBaseUrl,
        _afterFirstFrame = afterFirstFrame,
        _businessClock = businessClock ?? BusinessClock(),
        _secureStorage = secureStorage ??
            const FlutterSecureStorage(
              aOptions: AndroidOptions(migrateWithBackup: true),
            ),
        _subscriptionNotifications = subscriptionNotificationService ??
            LocalSubscriptionNotificationService() {
    final innerClient = TimeoutClient(
      httpClient ?? http.Client(),
      onFinished: _logRequest,
    );
    _rawClient = innerClient;
    _client = AuthenticatedApiClient(
      innerClient,
      () => _accessToken,
      _clearAuthentication,
      _saveSessionExpiration,
    );
    _mccRepository = MccRepository(
      cache: mccCacheStore ?? MccCacheStore(),
      get: (path, headers) => _client.get(_apiUri(path), headers: headers),
      onChanged: () {
        if (_disposed) return;
        mccCatalog = _mccRepository.catalogue;
        notifyListeners();
      },
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
  final Future<void> Function()? _afterFirstFrame;
  final BusinessClock _businessClock;
  final FlutterSecureStorage _secureStorage;
  late final http.Client _rawClient;
  late final http.Client _client;
  final SubscriptionNotificationService _subscriptionNotifications;
  late final StreamSubscription<int> _notificationTapSubscription;
  String? _accessToken;
  DateTime? _sessionExpiresAt;
  final Map<int, int> _selectionMutationVersions = {};
  final Map<int, int> _preferenceMutationVersions = {};
  int _sessionGeneration = 0;
  int _primaryLoadVersion = 0;
  int _partnerLoadVersion = 0;
  int _subscriptionLoadVersion = 0;
  bool _isCurrentSession(int generation) => generation == _sessionGeneration;

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

  final ReferenceDataStore _references = ReferenceDataStore();
  List<BankModel> get banks => _references.banks;
  set banks(List<BankModel> value) => _references.banks = value;
  List<UserModel> get users => _references.users;
  set users(List<UserModel> value) => _references.users = value;
  List<CardModel> get cards => _references.cards;
  set cards(List<CardModel> value) => _references.cards = value;
  List<CashbackCategoryModel> cashbackCategories = [];
  List<CashbackCategoryModel> activeCashbackCategories = [];
  List<CanonicalCategoryModel> get canonicalCategories =>
      _references.canonicalCategories;
  set canonicalCategories(List<CanonicalCategoryModel> value) =>
      _references.canonicalCategories = value;

  /// MCC reference (code and title) for search; loaded on first use.
  List<MccCodeModel> mccCatalog = [];
  late final MccRepository _mccRepository;
  bool _disposed = false;
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

  static void _logRequest(http.BaseRequest request, int? statusCode,
      Duration elapsed, Object? error) {
    // Path only: query strings and bodies are not diagnostic log material.
    final outcome = [
      if (statusCode != null) '$statusCode',
      if (error != null) 'failed ${error.runtimeType}',
    ].join(' ');
    AppLog.instance.event('HTTP ${request.method} ${request.url.path} '
        '$outcome ${elapsed.inMilliseconds}ms');
  }

  Uri _apiUri(String path) => Uri.parse(
        '${apiBaseUrl.replaceFirst(RegExp(r'/$'), '')}/api/$path',
      );

  Future<void> _clearAuthentication([String? token]) async {
    // A late 401 from an old request must not erase a newer login.
    if (token != null && token != _accessToken) return;
    final subscriptionsCacheKey = _subscriptionsCacheKey;
    _sessionGeneration++;
    _accessToken = null;
    _sessionExpiresAt = null;
    currentAuthUser = null;
    banks = [];
    users = [];
    cards = [];
    cashbackCategories = [];
    activeCashbackCategories = [];
    canonicalCategories = [];
    dataSnapshotUpdatedAt = null;
    mccCatalog = [];
    _mccRepository.clear();
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
    // The web implementation creates its encryption key on the first write.
    // Parallel first writes can each create a different key, making the saved
    // session unreadable after a restart.
    await _secureStorage.write(key: _accessTokenKey, value: token);
    await _secureStorage.write(
      key: _authIdentityKey,
      value: json.encode(user.toJson()),
    );
    if (_sessionExpiresAt != null) {
      await _secureStorage.write(
        key: _sessionExpiresAtKey,
        value: _sessionExpiresAt!.toUtc().toIso8601String(),
      );
    }
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
      // A previously verified identity can open its own local cache without
      // waiting for the server. A token alone still needs online validation.
      if (isAuthenticated) return true;
      return await _validateAuthentication();
    } catch (_) {
      // Keep a previously verified session available from cached data when
      // validation is unavailable. A server 401 still clears it immediately.
      if (isAuthenticated) return true;
      _accessToken = null;
      _sessionExpiresAt = null;
      currentAuthUser = null;
      authError =
          'ÐÐµ ÑƒÐ´Ð°Ð»Ð¾ÑÑŒ Ð²Ð¾ÑÑÑ‚Ð°Ð½Ð¾Ð²Ð¸Ñ‚ÑŒ ÑÐ¾Ñ…Ñ€Ð°Ð½Ñ‘Ð½Ð½ÑƒÑŽ ÑÐµÑÑÐ¸ÑŽ';
      return false;
    }
  }

  Future<bool> _validateAuthentication() async {
    final session = _sessionGeneration;
    try {
      final response = await _client.get(_apiUri('auth/me'));
      if (_disposed || !_isCurrentSession(session)) return false;
      if (response.statusCode != 200) return isAuthenticated;
      currentAuthUser = AuthIdentity.fromJson(
        json.decode(response.body) as Map<String, dynamic>,
      );
      await _persistAuthentication();
      if (_disposed || !_isCurrentSession(session)) return false;
      notifyListeners();
      return true;
    } catch (_) {
      // Transport failure preserves a verified local session; the API client's
      // 401 handler remains authoritative and clears a revoked session.
      return !_disposed && _isCurrentSession(session) && isAuthenticated;
    }
  }

  Future<void> _refreshRestoredSession() async {
    final valid = await _validateAuthentication();
    AppLog.instance.event('startup: session validated=$valid');
    if (!valid) return;
    final refreshed = await fetchAllData();
    AppLog.instance.event('startup: data refreshed=$refreshed');
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
        authError = payload['error'] as String? ?? 'ÐžÑˆÐ¸Ð±ÐºÐ° Ð²Ñ…Ð¾Ð´Ð°';
        notifyListeners();
        return false;
      }
      _sessionGeneration++;
      _accessToken = payload['access_token'] as String;
      _sessionExpiresAt =
          DateTime.tryParse(payload['expires_at'] as String? ?? '');
      currentAuthUser = AuthIdentity.fromJson(
        payload['user'] as Map<String, dynamic>,
      );
      await _persistAuthentication();
      await loadLocalData();
      await _loadSubscriptionsCache();
      await _loadPartnerOffersCache();
      await _loadMccCache();
      notifyListeners();
      await fetchAllData();
      return true;
    } catch (_) {
      authError = 'Ð¡ÐµÑ€Ð²ÐµÑ€ Ð½ÐµÐ´Ð¾ÑÑ‚ÑƒÐ¿ÐµÐ½';
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
      _dateOnly(_cashbackDateOverride ?? _businessClock.today);

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

    await _loadMccCache();
    unawaited(refreshMccSnapshot());
    notifyListeners();
  }

  Future<List<T>> receiveFromServer<T>(
    String endpoint,
    T Function(Map<String, dynamic>) fromJson,
  ) async {
    final response = await _client.get(_apiUri(endpoint));

    if (response.statusCode != 200) {
      throw ApiException(
          endpoint,
          response.statusCode,
          _responseError(
              response, 'ÐÐµ ÑƒÐ´Ð°Ð»Ð¾ÑÑŒ Ð·Ð°Ð³Ñ€ÑƒÐ·Ð¸Ñ‚ÑŒ Ð´Ð°Ð½Ð½Ñ‹Ðµ'));
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
        _responseError(response,
            'ÐÐµ ÑƒÐ´Ð°Ð»Ð¾ÑÑŒ Ð·Ð°Ð³Ñ€ÑƒÐ·Ð¸Ñ‚ÑŒ Ð¿Ñ€Ð°Ð²Ð¸Ð»Ð° MCC'),
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

  Future<Map<String, dynamic>?> previewMccRuleSnapshot(
      Map<String, dynamic> document,
      {int? baseRevisionId}) async {
    final response =
        await _client.post(_apiUri('admin/mcc-rule-snapshots/preview'),
            headers: {'Content-Type': 'application/json'},
            body: json.encode({
              'document': document,
              if (baseRevisionId != null) 'base_revision_id': baseRevisionId
            }));
    if (response.statusCode == 501) return null;
    if (response.statusCode == 404) {
      Map<String, dynamic>? error;
      try {
        error = json.decode(response.body) as Map<String, dynamic>;
      } catch (_) {}
      if (error == null ||
          error['code'] == 'endpoint_not_available' ||
          error['error'] == null) {
        return null;
      }
    }
    if (response.statusCode != 200) {
      throw ApiException(
          'admin/mcc-rule-snapshots/preview',
          response.statusCode,
          _responseError(response,
              'ÐÐµ ÑƒÐ´Ð°Ð»Ð¾ÑÑŒ Ð¿Ñ€Ð¾Ð²ÐµÑ€Ð¸Ñ‚ÑŒ ÑÐ½Ð¸Ð¼Ð¾Ðº MCC'));
    }
    return json.decode(response.body) as Map<String, dynamic>;
  }

  Future<MccRuleRevisionModel> createMccRuleSnapshot(
      Map<String, dynamic> document,
      {Map<String, dynamic>? preview}) async {
    final response = await _client.post(
      _apiUri('admin/mcc-rule-snapshots'),
      headers: {'Content-Type': 'application/json'},
      body: json.encode({
        'document': document,
        if (preview != null)
          'preview': {
            'base_revision_id': preview['base_revision_id'],
            'base_hash': preview['base_hash'],
            'normalized_hash': preview['normalized_hash'],
          }
      }),
    );
    if (response.statusCode != 200 && response.statusCode != 201) {
      throw Exception(
        _responseError(response,
            'ÐÐµ ÑƒÐ´Ð°Ð»Ð¾ÑÑŒ ÑÐ¾Ñ…Ñ€Ð°Ð½Ð¸Ñ‚ÑŒ Ð¿Ñ€Ð°Ð²Ð¸Ð»Ð° MCC'),
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
        _responseError(response,
            'ÐÐµ ÑƒÐ´Ð°Ð»Ð¾ÑÑŒ Ð¾Ð¿ÑƒÐ±Ð»Ð¸ÐºÐ¾Ð²Ð°Ñ‚ÑŒ Ð¿Ñ€Ð°Ð²Ð¸Ð»Ð° MCC'),
      );
    }
    _invalidateMccBindings();
    return MccRuleRevisionModel.fromJson(
      json.decode(response.body) as Map<String, dynamic>,
    );
  }

  int get mccDataRevision => _mccRepository.revision;
  String get mccContextIdentity =>
      '$apiBaseUrl:${currentAuthUser?.id}:${cashbackEffectiveDate.toIso8601String()}';
  bool get mccOfflineReady => _mccRepository.offlineReady;
  DateTime? get mccSnapshotUpdatedAt => _mccRepository.snapshotUpdatedAt;

  void _activateMccContext() => _mccRepository.activate(apiBaseUrl,
      currentAuthUser?.id, cashbackEffectiveDate, _sessionGeneration);

  Future<void> _loadMccCache() async {
    _activateMccContext();
    await _mccRepository.load();
    final catalogue = _mccRepository.catalogue;
    if (catalogue.isNotEmpty) mccCatalog = catalogue;
  }

  Future<void> refreshMccSnapshot() async {
    _activateMccContext();
    try {
      await _mccRepository.refreshSnapshot(force: true);
    } catch (error) {
      debugPrint('Could not refresh offline MCC snapshot: $error');
    }
  }

  Future<List<MccCodeModel>> fetchMccCatalog() async {
    await _loadMccCache();
    final catalogue = await _mccRepository.fetchCatalogue();
    if (catalogue.isNotEmpty) mccCatalog = catalogue;
    return mccCatalog;
  }

  void _invalidateMccBindings() {
    _activateMccContext();
    _mccRepository.invalidateBindings();
  }

  /// How every bank with published rules treats [code] on the cashback date.
  Future<MccLookupModel> lookupMcc(String code) async {
    _activateMccContext();
    final document = await _mccRepository.document('lookups', code);
    return MccLookupModel.fromJson(document!);
  }

  Future<OfferMccRulesModel?> fetchOfferMccRules(int offerId) async {
    _activateMccContext();
    final document = await _mccRepository.document('offer_rules', '$offerId');
    return document == null ? null : OfferMccRulesModel.fromJson(document);
  }

  Future<void> autoImportMccRules(int bankId) async {
    final response = await _client.post(
      _apiUri('admin/banks/$bankId/mcc-rules/auto-import'),
    );
    if (response.statusCode != 200 && response.statusCode != 201) {
      throw Exception(
        _responseError(response,
            'ÐÐ²Ñ‚Ð¾Ð¼Ð°Ñ‚Ð¸Ñ‡ÐµÑÐºÐ°Ñ Ð·Ð°Ð³Ñ€ÑƒÐ·ÐºÐ° Ð¿Ð¾ÐºÐ° Ð½ÐµÐ´Ð¾ÑÑ‚ÑƒÐ¿Ð½Ð°'),
      );
    }
  }

  Future<void> initialize() async {
    final log = AppLog.instance;
    authReady = false;
    log.event('startup: initialize');
    try {
      await _subscriptionNotifications.initialize();
    } catch (error) {
      debugPrint('Could not initialize subscription notifications: $error');
    }
    log.event('startup: notifications initialized');
    await loadLocalData();
    await _synchronizeSubscriptionNotifications();
    log.event('startup: local data loaded');
    final restored = await _restoreAuthentication();
    log.event('startup: session restored=$restored');
    if (restored) {
      await loadLocalData();
      await _loadSubscriptionsCache();
      await _loadPartnerOffersCache();
      await _synchronizeSubscriptionNotifications();
      log.event('startup: account caches loaded '
          'snapshot=${hasUsableDataSnapshot ? dataSnapshotUpdatedAt : 'none'}');
    }
    authReady = true;
    notifyListeners();
    if (restored) {
      // The MCC snapshot can be large; reading it must not delay the first
      // frame. Every MCC consumer awaits the same memoized load.
      unawaited(_loadDeferredMccCache());
      unawaited(_refreshRestoredSession());
    }
  }

  Future<void> _loadDeferredMccCache() async {
    final session = _sessionGeneration;
    try {
      await _afterFirstFrame?.call();
      if (_disposed || !_isCurrentSession(session)) return;
      await _loadMccCache();
      if (_disposed || !_isCurrentSession(session)) return;
      AppLog.instance.event('startup: MCC cache loaded');
      notifyListeners();
    } catch (error) {
      debugPrint('Could not load MCC cache: $error');
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

      if (response.statusCode == 204 || response.statusCode == 200) {
        debugPrint('Delete from server item with id $id from $endpoint');
      } else {
        throw ApiException(
            endpoint,
            response.statusCode,
            _responseError(
                response, 'ÐÐµ ÑƒÐ´Ð°Ð»Ð¾ÑÑŒ ÑƒÐ´Ð°Ð»Ð¸Ñ‚ÑŒ Ð·Ð°Ð¿Ð¸ÑÑŒ'));
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
        throw ApiException(
            endpoint,
            response.statusCode,
            _responseError(
                response, 'ÐÐµ ÑƒÐ´Ð°Ð»Ð¾ÑÑŒ Ð¾Ð±Ð½Ð¾Ð²Ð¸Ñ‚ÑŒ Ð·Ð°Ð¿Ð¸ÑÑŒ'));
      }
    } catch (e) {
      debugPrint('Error updating bank: $e');
      rethrow;
    }
  }

  Future<bool> fetchAllData() async {
    final session = _sessionGeneration;
    final version = ++_primaryLoadVersion;
    bool current() =>
        _isCurrentSession(session) && version == _primaryLoadVersion;
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
      if (!current()) return false;

      final mccBindingsChanged =
          json.encode(cards.map(CardModel.toJson).toList()) !=
                  json.encode(fetchedCards.map(CardModel.toJson).toList()) ||
              json.encode(cashbackCategories
                      .map(CashbackCategoryModel.toJson)
                      .toList()) !=
                  json.encode(fetchedCashbackCategories
                      .map(CashbackCategoryModel.toJson)
                      .toList());
      banks = fetchedBanks;
      users = fetchedUsers;
      cards = fetchedCards;
      activeCashbackCategories = fetchedActiveCashbackCategories;
      cashbackCategories = fetchedCashbackCategories;
      if (mccBindingsChanged) _invalidateMccBindings();

      dataSnapshotUpdatedAt = DateTime.now();
      lastUpdated = dataSnapshotUpdatedAt.toString();
      primaryDataPhase = PrimaryDataPhase.ready;
      await fetchCanonicalCategories();
      if (!current()) return false;
      unawaited(fetchMccCatalog().then<void>((_) {},
          onError: (Object error, StackTrace stack) {
        debugPrint('MCC catalogue unavailable: $error');
      }));
      unawaited(refreshMccSnapshot());
      if (!current()) return false;
      await _saveDataLocally();
      if (!current()) return false;
      await _synchronizeSubscriptionNotifications();
      await fetchSubscriptions();
      if (!current()) return false;
      await fetchPartnerOffers();
      if (!current()) return false;
      notifyListeners();
      return true;
    } catch (e) {
      // Handle errors
      debugPrint('Error fetching data: $e');
      if (!current()) return false;
      primaryDataPhase = PrimaryDataPhase.failed;
      primaryDataError = 'ÐÐµ ÑƒÐ´Ð°Ð»Ð¾ÑÑŒ Ð¾Ð±Ð½Ð¾Ð²Ð¸Ñ‚ÑŒ Ð´Ð°Ð½Ð½Ñ‹Ðµ';
      notifyListeners();
      return false;
    }
  }

  /// Loads the unified category catalogue. Failures keep the cached list, so
  /// an older server without the endpoint only disables canonical grouping.
  Future<void> fetchCanonicalCategories() async {
    final session = _sessionGeneration;
    try {
      final fetched = await receiveFromServer(
        'canonical-categories',
        CanonicalCategoryModel.fromJson,
      );
      if (_isCurrentSession(session)) canonicalCategories = fetched;
    } catch (e) {
      debugPrint('Error fetching canonical categories: $e');
    }
  }

  Future<void> fetchCashbackCategories() async {
    final session = _sessionGeneration;
    try {
      final response = await _client.get(
        _apiUri('cashback'),
        headers: {'Accept': 'application/json'},
      );

      if (response.statusCode == 200) {
        final List<dynamic> data = json.decode(response.body);
        if (!_isCurrentSession(session)) return;
        cashbackCategories =
            data.map((json) => CashbackCategoryModel.fromJson(json)).toList();
        await _saveDataLocally();
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
  //       await _saveCashbacksLocally(data); // Ð¡Ð¾Ñ…Ñ€Ð°Ð½ÑÐµÐ¼ Ð´Ð°Ð½Ð½Ñ‹Ðµ Ð»Ð¾ÐºÐ°Ð»ÑŒÐ½Ð¾
  //       notifyListeners();
  //     } else {
  //       throw Exception('Failed to load data');
  //     }
  //   } catch (e) {
  //     print('Error by loading data: $e');
  //   }
  // }

  String _dataCacheKey(String name) => currentAuthUser == null
      ? name
      : 'data:v1:${Uri.encodeComponent(apiBaseUrl)}:${currentAuthUser!.id}:$name';

  String? _loadedReferenceScope;
  Future<void> loadLocalData() async {
    final scope = _dataCacheKey('banks');
    if (_loadedReferenceScope != null && _loadedReferenceScope != scope) {
      banks = [];
      users = [];
      cards = [];
      cashbackCategories = [];
      activeCashbackCategories = [];
      canonicalCategories = [];
      dataSnapshotUpdatedAt = null;
      lastUpdated = null;
      primaryDataPhase = PrimaryDataPhase.initialLoading;
    }
    _loadedReferenceScope = scope;
    final prefs = await SharedPreferences.getInstance();
    // Remove the pre-user-scoping key from early development builds.
    await prefs.remove('subscriptions');
    if (scope != _dataCacheKey('banks')) return;
    try {
      final cachedBanks = prefs.getString(_dataCacheKey('banks'));
      final cachedUsers = prefs.getString(_dataCacheKey('users'));
      final cachedCards = prefs.getString(_dataCacheKey('cards'));
      final cachedCashbackCategories =
          prefs.getString(_dataCacheKey('cashbackCategories'));
      final cachedActiveCashbackCategories =
          prefs.getString(_dataCacheKey('activeCashbackCategories'));
      final cachedCanonicalCategories =
          prefs.getString(_dataCacheKey('canonicalCategories'));
      final cachedCashbackEffectiveDate =
          prefs.getString('cashbackEffectiveDate');
      final cachedDataSnapshotUpdatedAt =
          prefs.getString(_dataCacheKey('dataSnapshotUpdatedAt'));

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
      if (cachedCanonicalCategories != null) {
        canonicalCategories = (json.decode(cachedCanonicalCategories) as List)
            .map((item) =>
                CanonicalCategoryModel.fromJson(item as Map<String, dynamic>))
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
    // Capture both keys and values before waiting for disk: a new login must
    // never redirect an old snapshot into the new account's cache.
    final values = <String, String>{
      for (final entry in _references.serialize().entries)
        _dataCacheKey(entry.key): entry.value,
      _dataCacheKey('cashbackCategories'): json.encode(
          cashbackCategories.map(CashbackCategoryModel.toJson).toList()),
      _dataCacheKey('activeCashbackCategories'): json.encode(
          activeCashbackCategories.map(CashbackCategoryModel.toJson).toList()),
      if (_subscriptionsCacheKey != null)
        _subscriptionsCacheKey!:
            json.encode(subscriptions.map((item) => item.toJson()).toList()),
      if (dataSnapshotUpdatedAt != null)
        _dataCacheKey('dataSnapshotUpdatedAt'):
            dataSnapshotUpdatedAt!.toIso8601String(),
    };
    final prefs = await SharedPreferences.getInstance();
    await Future.wait(
        values.entries.map((item) => prefs.setString(item.key, item.value)));
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
    final session = _sessionGeneration;
    final version = ++_subscriptionLoadVersion;
    bool current() =>
        _isCurrentSession(session) && version == _subscriptionLoadVersion;
    subscriptionsLoading = true;
    subscriptionsError = null;
    notifyListeners();
    try {
      final fetched = await _receiveSubscriptions(status);
      if (!current()) return false;
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
      if (!current()) return false;
      subscriptionsError = error.toString();
      debugPrint('Error fetching subscriptions: $error');
      return false;
    } finally {
      if (current()) {
        subscriptionsLoading = false;
        notifyListeners();
      }
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
    return authUserId == null ? null : _dataCacheKey('subscriptions');
  }

  Future<void> _loadSubscriptionsCache() async {
    final key = _subscriptionsCacheKey;
    if (key == null) return;
    final cached = (await SharedPreferences.getInstance()).getString(key);
    if (cached == null || key != _subscriptionsCacheKey) return;
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
    return authUserId == null ? null : _dataCacheKey('partnerOffers');
  }

  Future<void> _loadPartnerOffersCache() async {
    final key = _partnerOffersCacheKey;
    if (key == null) return;
    final prefs = await SharedPreferences.getInstance();
    final cached = prefs.getString(key);
    if (cached == null || key != _partnerOffersCacheKey) return;
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
    final value =
        json.encode(partnerOffers.map((offer) => offer.toJson()).toList());
    await (await SharedPreferences.getInstance()).setString(key, value);
  }

  Future<bool> fetchPartnerOffers({String? rating}) async {
    final session = _sessionGeneration;
    final version = ++_partnerLoadVersion;
    bool current() =>
        _isCurrentSession(session) && version == _partnerLoadVersion;
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
          'active_only': 'false',
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
            _responseError(response,
                'ÐÐµ ÑƒÐ´Ð°Ð»Ð¾ÑÑŒ Ð·Ð°Ð³Ñ€ÑƒÐ·Ð¸Ñ‚ÑŒ Ð¿Ñ€ÐµÐ´Ð»Ð¾Ð¶ÐµÐ½Ð¸Ñ'),
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
      if (!current()) return false;
      partnerOffers = fetched;
      _partnerOffersRating = rating;
      if (rating == null) await _savePartnerOffersCache();
      return true;
    } catch (error) {
      if (!current()) return false;
      partnerOffersError =
          'ÐÐµ ÑƒÐ´Ð°Ð»Ð¾ÑÑŒ Ð¾Ð±Ð½Ð¾Ð²Ð¸Ñ‚ÑŒ Ð¿Ñ€ÐµÐ´Ð»Ð¾Ð¶ÐµÐ½Ð¸Ñ';
      debugPrint('Error fetching partner offers: $error');
      if (rating == null) {
        await _loadPartnerOffersCache();
        await _loadMccCache();
        _partnerOffersRating = null;
      }
      return false;
    } finally {
      if (current()) {
        partnerOffersLoading = false;
        notifyListeners();
      }
    }
  }

  Future<PartnerOffer> fetchPartnerOfferDetails(int offerId) async {
    final response = await _client.get(_apiUri('partner-offers/$offerId'));
    if (response.statusCode != 200) {
      throw Exception(
        _responseError(
            response, 'ÐÐµ ÑƒÐ´Ð°Ð»Ð¾ÑÑŒ Ð·Ð°Ð³Ñ€ÑƒÐ·Ð¸Ñ‚ÑŒ ÑƒÑÐ»Ð¾Ð²Ð¸Ñ'),
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
    final session = _sessionGeneration;
    final version = (_preferenceMutationVersions[offerId] ?? 0) + 1;
    _preferenceMutationVersions[offerId] = version;
    bool current() =>
        _isCurrentSession(session) &&
        _preferenceMutationVersions[offerId] == version;
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
          _responseError(
              response, 'ÐÐµ ÑƒÐ´Ð°Ð»Ð¾ÑÑŒ ÑÐ¾Ñ…Ñ€Ð°Ð½Ð¸Ñ‚ÑŒ Ð¾Ñ†ÐµÐ½ÐºÑƒ'),
        );
      }
      if (current() && _partnerOffersRating == null) {
        await _savePartnerOffersCache();
      }
    } catch (_) {
      if (current() && original != null) {
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
    await _saveDataLocally();
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
      await _saveDataLocally();
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
      await _saveDataLocally();
      notifyListeners();
    } catch (e) {
      debugPrint('Error deleting bank: $e');
      rethrow;
    }
  }

  Future<void> _saveUsersLocally() async {
    final key = _dataCacheKey('users');
    final value = json.encode(users.map(UserModel.toJson).toList());
    await (await SharedPreferences.getInstance()).setString(key, value);
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
        await _saveUsersLocally();
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
          await _saveUsersLocally();
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

      if (response.statusCode == 204 || response.statusCode == 200) {
        users.removeWhere((user) => user.id == id);
        await _saveUsersLocally();
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
    _invalidateMccBindings();
    await _saveDataLocally();
    notifyListeners();
  }

  CardModel getCardById(int cardId) =>
      _references.cardsById[cardId] ??
      CardModel(
        id: cardId,
        paymentSystem: '',
        cardType: '',
        lastFourDigits: '????',
      );

  String getCardName(int cardId) {
    final card = getCardById(cardId);
    final userName = _references.usersById[card.userId]?.name;
    final bankName = _references.banksById[card.bankId]?.name;

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
          _invalidateMccBindings();
          cards[index] = CardModel.fromJson(
              json.decode(response.body) as Map<String, dynamic>);
          await _saveDataLocally();
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

      if (response.statusCode == 204 || response.statusCode == 200) {
        cards.removeWhere((card) => card.id == id);
        _invalidateMccBindings();
        await _saveDataLocally();
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
        _invalidateMccBindings();
        await _saveDataLocally();
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
  ) =>
      ImportCoordinator(
        post: (path, body) => _client.post(_apiUri(path),
            headers: {'Content-Type': 'application/json'},
            body: json.encode(body)),
        refresh: () async {
          _invalidateMccBindings();
          return fetchAllData();
        },
      ).run(contents, userId);

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
        _invalidateMccBindings();
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
      if (_selectionMutationVersions[categoryId] == version) {
        _invalidateMccBindings();
        await _saveDataLocally();
      }
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
    _disposed = true;
    _mccRepository.dispose();
    _notificationTapSubscription.cancel();
    _client.close();
    super.dispose();
  }
}
