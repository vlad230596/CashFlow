import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:timezone/data/latest.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;

import 'subscription_notification_runtime.dart';

/// An entity family that schedules local reminders.
///
/// Each kind owns a disjoint block of Android notification ids
/// (`block * blockSize` .. `(block + 1) * blockSize - 1`) and a typed tap
/// payload `"<key>:<entityId>"`. To add a kind (e.g. expiring promo codes):
/// add a constant with an unused [block] and its own channel, append it to
/// [values], map entities to [ReminderSpec]s, and call
/// `ReminderNotificationService.synchronize(kind, specs)`. Never reuse or
/// renumber a block: ids already scheduled on devices would collide.
class ReminderKind {
  const ReminderKind._({
    required this.key,
    required this.block,
    required this.channelId,
    required this.channelName,
    required this.channelDescription,
  });

  final String key;
  final int block;
  final String channelId;
  final String channelName;
  final String channelDescription;

  static const subscription = ReminderKind._(
    key: 'subscription',
    block: 1,
    channelId: 'subscription_renewals',
    channelName: 'Продления подписок',
    channelDescription: 'Напоминания о предстоящих списаниях',
  );

  static const payment = ReminderKind._(
    key: 'payment',
    block: 2,
    channelId: 'payment_due_dates',
    channelName: 'Сроки платежей',
    channelDescription: 'Напоминания об оплате регулярных и разовых платежей',
  );

  // Block 3 is reserved for promo codes / expiring bonuses.

  static const values = [subscription, payment];

  /// Ids per kind block; blocks 1..6 fit below the legacy range.
  static const blockSize = 100000000;

  /// Notification slots per entity (one per distinct reminder day).
  static const slotsPerEntity = 32;
  static const entitiesPerBlock = blockSize ~/ slotsPerEntity;

  int get idBase => block * blockSize;

  bool ownsId(int id) => id >= idBase && id < idBase + blockSize;

  int notificationId(int entityId, int slot) {
    RangeError.checkValueInInterval(slot, 0, slotsPerEntity - 1, 'slot');
    return idBase + (entityId.abs() % entitiesPerBlock) * slotsPerEntity + slot;
  }

  static ReminderKind? byKey(String key) {
    for (final kind in values) {
      if (kind.key == key) return kind;
    }
    return null;
  }

  @override
  String toString() => 'ReminderKind($key)';
}

/// Legacy subscription ids (before typed kinds): 700000000 + id * 64 + slot,
/// payload = bare subscription id. They are cancelled on subscription sync.
const legacySubscriptionIdStart = 700000000;
const legacySubscriptionIdEnd = 2000000000;

bool isLegacySubscriptionNotificationId(int id) =>
    id >= legacySubscriptionIdStart && id < legacySubscriptionIdEnd;

/// What a tapped notification points at.
@immutable
class ReminderTarget {
  const ReminderTarget(this.kind, this.entityId);

  final ReminderKind kind;
  final int entityId;

  String get payload => '${kind.key}:$entityId';

  /// Parses `"<kind>:<id>"`; a bare integer is a legacy subscription payload.
  static ReminderTarget? parse(String? payload) {
    if (payload == null || payload.isEmpty) return null;
    final separator = payload.indexOf(':');
    if (separator < 0) {
      final legacyId = int.tryParse(payload);
      return legacyId == null
          ? null
          : ReminderTarget(ReminderKind.subscription, legacyId);
    }
    final kind = ReminderKind.byKey(payload.substring(0, separator));
    final id = int.tryParse(payload.substring(separator + 1));
    if (kind == null || id == null) return null;
    return ReminderTarget(kind, id);
  }

  @override
  bool operator ==(Object other) =>
      other is ReminderTarget &&
      other.kind == kind &&
      other.entityId == entityId;

  @override
  int get hashCode => Object.hash(kind.key, entityId);

  @override
  String toString() => 'ReminderTarget($payload)';
}

/// Reminder input for one entity: its civil due date and lead days.
class ReminderSpec {
  const ReminderSpec({
    required this.entityId,
    required this.dueDate,
    required this.reminderDays,
    required this.title,
    required this.body,
  });

  final int entityId;
  final DateTime dueDate;
  final List<int> reminderDays;
  final String Function(int daysBefore) title;
  final String Function(int daysBefore) body;
}

class PlannedReminder {
  const PlannedReminder({
    required this.id,
    required this.target,
    required this.fireAt,
    required this.daysBefore,
    required this.title,
    required this.body,
  });

  final int id;
  final ReminderTarget target;

  /// Wall-clock date and time in the device timezone.
  final DateTime fireAt;
  final int daysBefore;
  final String title;
  final String body;

  String get payload => target.payload;
}

/// Pure scheduling math: which notifications to create for [specs].
class ReminderPlanner {
  const ReminderPlanner({this.hour = 10});

  /// Local hour of day at which reminders fire.
  final int hour;

  List<PlannedReminder> plan(
    ReminderKind kind,
    Iterable<ReminderSpec> specs,
    DateTime now,
  ) {
    final result = <PlannedReminder>[];
    for (final spec in specs) {
      final days = spec.reminderDays.where((day) => day >= 0).toSet().toList()
        ..sort((left, right) => right.compareTo(left));
      for (var slot = 0;
          slot < days.length && slot < ReminderKind.slotsPerEntity;
          slot++) {
        final fireAt = DateTime(
          spec.dueDate.year,
          spec.dueDate.month,
          spec.dueDate.day - days[slot],
          hour,
        );
        if (!fireAt.isAfter(now)) continue;
        result.add(PlannedReminder(
          id: kind.notificationId(spec.entityId, slot),
          target: ReminderTarget(kind, spec.entityId),
          fireAt: fireAt,
          daysBefore: days[slot],
          title: spec.title(days[slot]),
          body: spec.body(days[slot]),
        ));
      }
    }
    return result;
  }
}

abstract class ReminderNotificationService {
  /// Whether this platform schedules local reminders at all (Android only).
  bool get supportsReminders;

  Stream<ReminderTarget> get notificationTaps;

  Future<void> initialize();

  Future<bool> requestPermission();

  /// Whether reminders can fire at their exact time (Android exact alarms).
  Future<bool> canScheduleExactReminders();

  /// Opens the system exact-alarm setting when needed; returns the new state.
  Future<bool> requestExactReminderPermission();

  /// Replaces every scheduled reminder of [kind] with those for [specs].
  Future<void> synchronize(ReminderKind kind, Iterable<ReminderSpec> specs);

  Future<void> cancel(ReminderKind kind, int entityId);

  ReminderTarget? consumePendingTarget();
}

class LocalReminderNotificationService implements ReminderNotificationService {
  LocalReminderNotificationService({
    FlutterLocalNotificationsPlugin? plugin,
    ReminderPlanner planner = const ReminderPlanner(),
  })  : _plugin = plugin ?? FlutterLocalNotificationsPlugin(),
        _planner = planner;

  final FlutterLocalNotificationsPlugin _plugin;
  final ReminderPlanner _planner;
  final StreamController<ReminderTarget> _notificationTaps =
      StreamController<ReminderTarget>.broadcast();
  final Map<ReminderKind, Future<void>> _queues = {};
  bool _initialized = false;
  ReminderTarget? _pendingTarget;

  bool get _supportsNotifications =>
      !kIsWeb &&
      !isFlutterTestEnvironment &&
      defaultTargetPlatform == TargetPlatform.android;

  @override
  bool get supportsReminders => _supportsNotifications;

  AndroidFlutterLocalNotificationsPlugin? get _android =>
      _plugin.resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>();

  @override
  Stream<ReminderTarget> get notificationTaps => _notificationTaps.stream;

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
      onDidReceiveNotificationResponse: (response) =>
          _recordPayload(response.payload),
    );
    final launchDetails = await _plugin.getNotificationAppLaunchDetails();
    if (launchDetails?.didNotificationLaunchApp ?? false) {
      _recordPayload(launchDetails?.notificationResponse?.payload);
    }
    _initialized = true;
  }

  void _recordPayload(String? payload) {
    final target = ReminderTarget.parse(payload);
    if (target == null) return;
    _pendingTarget = target;
    _notificationTaps.add(target);
  }

  @override
  ReminderTarget? consumePendingTarget() {
    final result = _pendingTarget;
    _pendingTarget = null;
    return result;
  }

  @override
  Future<bool> requestPermission() async {
    if (!_supportsNotifications) return false;
    await initialize();
    return await _android?.requestNotificationsPermission() ?? false;
  }

  @override
  Future<bool> canScheduleExactReminders() async {
    if (!_supportsNotifications) return false;
    await initialize();
    try {
      return await _android?.canScheduleExactNotifications() ?? false;
    } catch (error) {
      debugPrint('Could not check exact alarm permission: $error');
      return false;
    }
  }

  @override
  Future<bool> requestExactReminderPermission() async {
    if (!_supportsNotifications) return false;
    await initialize();
    try {
      if (await canScheduleExactReminders()) return true;
      return await _android?.requestExactAlarmsPermission() ?? false;
    } catch (error) {
      debugPrint('Could not request exact alarm permission: $error');
      return false;
    }
  }

  @override
  Future<void> synchronize(ReminderKind kind, Iterable<ReminderSpec> specs) {
    if (!_supportsNotifications) return Future.value();
    final snapshot = specs.toList(growable: false);
    // Serialize per kind: an older synchronization must not cancel or
    // overwrite reminders scheduled by a newer one.
    final previous = _queues[kind] ?? Future<void>.value();
    final next = previous
        .catchError((Object _) {})
        .then((_) => _synchronizeNow(kind, snapshot));
    _queues[kind] = next;
    return next;
  }

  Future<void> _synchronizeNow(
    ReminderKind kind,
    List<ReminderSpec> specs,
  ) async {
    await initialize();
    final pending = await _plugin.pendingNotificationRequests();
    for (final request in pending) {
      final legacy = kind == ReminderKind.subscription &&
          isLegacySubscriptionNotificationId(request.id);
      if (legacy || kind.ownsId(request.id)) {
        await _plugin.cancel(request.id);
      }
    }
    final planned = _planner.plan(kind, specs, DateTime.now());
    if (planned.isEmpty) return;
    var exact = await canScheduleExactReminders();
    for (final reminder in planned) {
      exact = await _schedule(kind, reminder, exact: exact);
    }
  }

  /// Schedules one reminder; returns whether exact mode is still usable.
  Future<bool> _schedule(
    ReminderKind kind,
    PlannedReminder reminder, {
    required bool exact,
  }) async {
    final fireAt = tz.TZDateTime(
      tz.local,
      reminder.fireAt.year,
      reminder.fireAt.month,
      reminder.fireAt.day,
      reminder.fireAt.hour,
      reminder.fireAt.minute,
    );
    final details = NotificationDetails(
      android: AndroidNotificationDetails(
        kind.channelId,
        kind.channelName,
        channelDescription: kind.channelDescription,
        importance: Importance.high,
        priority: Priority.high,
      ),
    );
    Future<void> schedule(AndroidScheduleMode mode) => _plugin.zonedSchedule(
          reminder.id,
          reminder.title,
          reminder.body,
          fireAt,
          details,
          androidScheduleMode: mode,
          payload: reminder.payload,
        );
    if (exact) {
      try {
        await schedule(AndroidScheduleMode.exactAllowWhileIdle);
        return true;
      } on PlatformException catch (error) {
        // The permission can be revoked at any time; fall back to inexact.
        debugPrint('Exact reminder unavailable, using inexact: $error');
      }
    }
    await schedule(AndroidScheduleMode.inexactAllowWhileIdle);
    return false;
  }

  @override
  Future<void> cancel(ReminderKind kind, int entityId) async {
    if (!_supportsNotifications) return;
    await initialize();
    for (var slot = 0; slot < ReminderKind.slotsPerEntity; slot++) {
      await _plugin.cancel(kind.notificationId(entityId, slot));
    }
  }
}
