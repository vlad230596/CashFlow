import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:timezone/data/latest.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;

import '../models/subscription_model.dart';
import 'subscription_notification_runtime.dart';

abstract class SubscriptionNotificationService {
  Stream<int> get notificationTaps;

  Future<void> initialize();

  Future<bool> requestPermission();

  Future<void> synchronize(Iterable<SubscriptionModel> subscriptions);

  Future<void> cancelSubscription(int subscriptionId);

  int? consumePendingSubscriptionId();
}

class LocalSubscriptionNotificationService
    implements SubscriptionNotificationService {
  LocalSubscriptionNotificationService({
    FlutterLocalNotificationsPlugin? plugin,
  }) : _plugin = plugin ?? FlutterLocalNotificationsPlugin();

  static const _notificationIdBase = 700000000;
  static const _idsPerSubscription = 64;
  static const _notificationIdLimit = 2000000000;
  static const _channelId = 'subscription_renewals';

  final FlutterLocalNotificationsPlugin _plugin;
  final StreamController<int> _notificationTaps =
      StreamController<int>.broadcast();
  bool _initialized = false;
  int? _pendingSubscriptionId;

  bool get _supportsNotifications =>
      !kIsWeb &&
      !isFlutterTestEnvironment &&
      defaultTargetPlatform == TargetPlatform.android;

  @override
  Stream<int> get notificationTaps => _notificationTaps.stream;

  @override
  Future<void> initialize() async {
    if (_initialized || !_supportsNotifications) return;
    tz_data.initializeTimeZones();
    try {
      final zone = await FlutterTimezone.getLocalTimezone();
      tz.setLocalLocation(tz.getLocation(zone.identifier));
    } catch (error) {
      debugPrint('Could not determine the local timezone: $error');
    }

    const settings = InitializationSettings(
      android: AndroidInitializationSettings('@mipmap/ic_launcher'),
    );
    await _plugin.initialize(
      settings,
      onDidReceiveNotificationResponse: _handleNotificationResponse,
    );
    final launchDetails = await _plugin.getNotificationAppLaunchDetails();
    if (launchDetails?.didNotificationLaunchApp ?? false) {
      _recordPayload(launchDetails?.notificationResponse?.payload);
    }
    _initialized = true;
  }

  void _handleNotificationResponse(NotificationResponse response) {
    _recordPayload(response.payload);
  }

  void _recordPayload(String? payload) {
    if (payload == null) return;
    final id = int.tryParse(payload);
    if (id == null) return;
    _pendingSubscriptionId = id;
    _notificationTaps.add(id);
  }

  @override
  int? consumePendingSubscriptionId() {
    final result = _pendingSubscriptionId;
    _pendingSubscriptionId = null;
    return result;
  }

  @override
  Future<bool> requestPermission() async {
    if (!_supportsNotifications) return false;
    await initialize();
    return await _plugin
            .resolvePlatformSpecificImplementation<
                AndroidFlutterLocalNotificationsPlugin>()
            ?.requestNotificationsPermission() ??
        false;
  }

  @override
  Future<void> synchronize(
    Iterable<SubscriptionModel> subscriptions,
  ) async {
    if (!_supportsNotifications) return;
    await initialize();
    final pending = await _plugin.pendingNotificationRequests();
    for (final request in pending) {
      if (_isSubscriptionNotification(request.id)) {
        await _plugin.cancel(request.id);
      }
    }

    for (final subscription in subscriptions) {
      if (!subscription.isArchived && subscription.id != null) {
        await _scheduleSubscription(subscription);
      }
    }
  }

  @override
  Future<void> cancelSubscription(int subscriptionId) async {
    if (!_supportsNotifications) return;
    await initialize();
    for (var slot = 0; slot < _idsPerSubscription; slot++) {
      await _plugin.cancel(_notificationId(subscriptionId, slot));
    }
  }

  Future<void> _scheduleSubscription(SubscriptionModel subscription) async {
    final now = tz.TZDateTime.now(tz.local);
    final reminderDays = subscription.effectiveReminderDays.toSet().toList()
      ..sort((left, right) => right.compareTo(left));
    for (var slot = 0;
        slot < reminderDays.length && slot < _idsPerSubscription;
        slot++) {
      final paymentDate = subscription.nextPaymentDate.toLocal();
      final notificationDate = DateTime(
        paymentDate.year,
        paymentDate.month,
        paymentDate.day,
        10,
      ).subtract(Duration(days: reminderDays[slot]));
      final scheduled = tz.TZDateTime(
        tz.local,
        notificationDate.year,
        notificationDate.month,
        notificationDate.day,
        notificationDate.hour,
      );
      if (!scheduled.isAfter(now)) continue;

      await _plugin.zonedSchedule(
        _notificationId(subscription.id!, slot),
        'Скоро продление: ${subscription.name}',
        '${_formatAmount(subscription.expectedAmount)} '
            '${subscription.currency} спишется через '
            '${reminderDays[slot]} дн.',
        scheduled,
        const NotificationDetails(
          android: AndroidNotificationDetails(
            _channelId,
            'Продления подписок',
            channelDescription: 'Напоминания о предстоящих списаниях',
            importance: Importance.high,
            priority: Priority.high,
          ),
        ),
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
        payload: subscription.id.toString(),
      );
    }
  }

  static bool _isSubscriptionNotification(int id) =>
      id >= _notificationIdBase && id < _notificationIdLimit;

  static int _notificationId(int subscriptionId, int slot) =>
      _notificationIdBase +
      (subscriptionId.abs() % 20000000) * _idsPerSubscription +
      slot;

  static String _formatAmount(double amount) => amount == amount.roundToDouble()
      ? amount.toStringAsFixed(0)
      : amount.toStringAsFixed(2);
}
