import 'dart:async';
import 'dart:ui' show DartPluginRegistrant;

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
/// payload `"<key>:<entityId>"`. To add a kind:
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
    this.actions = const [],
  });

  final String key;
  final int block;
  final String channelId;
  final String channelName;
  final String channelDescription;

  /// Notification buttons; a kind with actions carries the due date in its
  /// payload so a stale notification never acts on a later occurrence.
  final List<ReminderAction> actions;

  bool get hasActions => actions.isNotEmpty;

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
    actions: [ReminderAction.snooze, ReminderAction.done],
  );

  static const promo = ReminderKind._(
    key: 'promo',
    block: 3,
    channelId: 'promo_expiry',
    channelName: 'Промокоды и баллы',
    channelDescription: 'Напоминания об истечении промокодов и сгорании баллов',
  );

  static const values = [subscription, payment, promo];

  /// Ids per kind block; blocks 1..6 fit below the legacy range.
  static const blockSize = 100000000;

  /// Notification slots per entity (one per distinct reminder day).
  static const slotsPerEntity = 32;
  static const entitiesPerBlock = blockSize ~/ slotsPerEntity;

  /// The last slot holds a snoozed («Напомнить позже») copy; reminder days
  /// (at most 20 per entity) use the slots before it.
  static const snoozeSlot = slotsPerEntity - 1;

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

/// How long «Напомнить позже» postpones a payment reminder. One hour keeps
/// the obligation on the same day without a settings screen; change it here.
const reminderSnoozeDelay = Duration(hours: 1);

/// A notification button. Snooze runs without opening the app (Android
/// background isolate, no network needed); done opens the app, which marks
/// the occurrence paid through the same API call as the in-app button.
enum ReminderAction {
  snooze('reminder_snooze', 'Напомнить позже', showsUserInterface: false),
  done('reminder_done', 'Сделано', showsUserInterface: true);

  const ReminderAction(this.id, this.label, {required this.showsUserInterface});

  final String id;
  final String label;
  final bool showsUserInterface;

  static ReminderAction? byId(String? id) {
    for (final action in values) {
      if (action.id == id) return action;
    }
    return null;
  }
}

/// What a tapped notification (or one of its buttons) points at.
@immutable
class ReminderTarget {
  const ReminderTarget(this.kind, this.entityId, {this.dueDate, this.action});

  final ReminderKind kind;
  final int entityId;

  /// Civil due date the notification was about; null in older payloads.
  final DateTime? dueDate;

  /// Pressed button; null for a tap on the notification body.
  final ReminderAction? action;

  /// `"<kind>:<id>"`, plus `"@YYYY-MM-DD"` when the due date is known.
  String get payload {
    final due = dueDate;
    if (due == null) return '${kind.key}:$entityId';
    return '${kind.key}:$entityId@${due.year.toString().padLeft(4, '0')}-'
        '${due.month.toString().padLeft(2, '0')}-'
        '${due.day.toString().padLeft(2, '0')}';
  }

  ReminderTarget withAction(ReminderAction? action) =>
      ReminderTarget(kind, entityId, dueDate: dueDate, action: action);

  /// Parses `"<kind>:<id>[@<date>]"`; a bare integer is a legacy subscription
  /// payload.
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
    var rest = payload.substring(separator + 1);
    DateTime? dueDate;
    final at = rest.indexOf('@');
    if (at >= 0) {
      final match = RegExp(r'^(\d{4})-(\d{2})-(\d{2})$')
          .firstMatch(rest.substring(at + 1));
      if (match == null) return null;
      dueDate = DateTime(
          int.parse(match[1]!), int.parse(match[2]!), int.parse(match[3]!));
      rest = rest.substring(0, at);
    }
    final id = int.tryParse(rest);
    if (kind == null || id == null) return null;
    return ReminderTarget(kind, id, dueDate: dueDate);
  }

  @override
  bool operator ==(Object other) =>
      other is ReminderTarget &&
      other.kind == kind &&
      other.entityId == entityId &&
      other.dueDate == dueDate &&
      other.action == action;

  @override
  int get hashCode => Object.hash(kind.key, entityId, dueDate, action);

  @override
  String toString() =>
      'ReminderTarget($payload${action == null ? '' : ' ${action!.id}'})';
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
          slot < days.length && slot < ReminderKind.snoozeSlot;
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
          target: reminderTargetFor(kind, spec),
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

/// The tap target of [spec]'s reminders; kinds with buttons pin the due date.
ReminderTarget reminderTargetFor(ReminderKind kind, ReminderSpec spec) =>
    ReminderTarget(
      kind,
      spec.entityId,
      dueDate: kind.hasActions
          ? DateTime(spec.dueDate.year, spec.dueDate.month, spec.dueDate.day)
          : null,
    );

/// Ids of pending snoozed reminders that a synchronization must keep: the
/// entity is still reminded about the same due date. A paid, archived or
/// rescheduled payment drops its snooze.
Set<int> snoozedRemindersToKeep(
  ReminderKind kind,
  Iterable<ReminderSpec> specs,
  Iterable<({int id, String? payload})> pending,
) {
  if (!kind.hasActions) return const {};
  final expected = {
    for (final spec in specs)
      kind.notificationId(spec.entityId, ReminderKind.snoozeSlot):
          reminderTargetFor(kind, spec).payload,
  };
  return {
    for (final request in pending)
      if (expected[request.id] != null &&
          expected[request.id] == request.payload)
        request.id,
  };
}

/// A postponed copy of a shown reminder.
class SnoozedReminder {
  const SnoozedReminder({
    required this.id,
    required this.target,
    required this.fireAt,
    required this.title,
    required this.body,
  });

  final int id;
  final ReminderTarget target;

  /// Absolute moment (UTC) at which the copy fires.
  final DateTime fireAt;
  final String title;
  final String body;
}

/// Pure snooze math: the copy goes to the kind's snooze slot [delay] after
/// [now] and repeats the shown text ([title]/[body] may be unknown).
SnoozedReminder? planSnooze({
  required String? payload,
  required DateTime now,
  String? title,
  String? body,
  Duration delay = reminderSnoozeDelay,
}) {
  final target = ReminderTarget.parse(payload);
  if (target == null || !target.kind.hasActions) return null;
  return SnoozedReminder(
    id: target.kind.notificationId(target.entityId, ReminderKind.snoozeSlot),
    target:
        ReminderTarget(target.kind, target.entityId, dueDate: target.dueDate),
    fireAt: now.toUtc().add(delay),
    title: title == null || title.isEmpty ? 'Напоминание о платеже' : title,
    body: body ?? '',
  );
}

/// Android details for a kind's reminders, buttons included.
NotificationDetails reminderNotificationDetails(ReminderKind kind) =>
    NotificationDetails(
      android: AndroidNotificationDetails(
        kind.channelId,
        kind.channelName,
        channelDescription: kind.channelDescription,
        importance: Importance.high,
        priority: Priority.high,
        actions: [
          for (final action in kind.actions)
            AndroidNotificationAction(
              action.id,
              action.label,
              showsUserInterface: action.showsUserInterface,
              // Snooze reads the shown text first and cancels it itself.
              cancelNotification: action != ReminderAction.snooze,
            ),
        ],
      ),
    );

const _androidInitialization = InitializationSettings(
  android: AndroidInitializationSettings('@mipmap/ic_launcher'),
);

/// Re-posts the reminder behind [response] [reminderSnoozeDelay] later.
/// Runs in the notification background isolate (or the main isolate when the
/// platform delivers the action there); needs no session or network.
Future<void> snoozeReminder(
  FlutterLocalNotificationsPlugin plugin,
  NotificationResponse response, {
  DateTime? now,
}) async {
  String? title;
  String? body;
  final android = plugin.resolvePlatformSpecificImplementation<
      AndroidFlutterLocalNotificationsPlugin>();
  try {
    final shown = await android?.getActiveNotifications() ?? const [];
    final match = shown.where((item) => item.id == response.id).firstOrNull;
    title = match?.title;
    body = match?.body;
  } catch (error) {
    debugPrint('Could not read the shown reminder: $error');
  }
  final snooze = planSnooze(
    payload: response.payload,
    now: now ?? DateTime.now(),
    title: title,
    body: body,
  );
  if (response.id != null) await plugin.cancel(response.id!);
  if (snooze == null) return;
  tz_data.initializeTimeZones();
  final fireAt = tz.TZDateTime.from(snooze.fireAt, tz.UTC);
  final details = reminderNotificationDetails(snooze.target.kind);
  Future<void> schedule(AndroidScheduleMode mode) => plugin.zonedSchedule(
        snooze.id,
        snooze.title,
        snooze.body,
        fireAt,
        details,
        androidScheduleMode: mode,
        payload: snooze.target.payload,
      );
  try {
    final exact = await android?.canScheduleExactNotifications() ?? false;
    if (exact) {
      await schedule(AndroidScheduleMode.exactAllowWhileIdle);
      return;
    }
  } on PlatformException catch (error) {
    debugPrint('Exact snooze unavailable, using inexact: $error');
  }
  await schedule(AndroidScheduleMode.inexactAllowWhileIdle);
}

/// Entry point for buttons pressed while the app UI is not shown (Android
/// starts a separate isolate for it).
@pragma('vm:entry-point')
Future<void> onReminderNotificationBackgroundResponse(
  NotificationResponse response,
) async {
  if (ReminderAction.byId(response.actionId) != ReminderAction.snooze) return;
  DartPluginRegistrant.ensureInitialized();
  final plugin = FlutterLocalNotificationsPlugin();
  await plugin.initialize(
    _androidInitialization,
    onDidReceiveBackgroundNotificationResponse:
        onReminderNotificationBackgroundResponse,
  );
  await snoozeReminder(plugin, response);
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

    await _plugin.initialize(
      _androidInitialization,
      onDidReceiveNotificationResponse: _recordResponse,
      onDidReceiveBackgroundNotificationResponse:
          onReminderNotificationBackgroundResponse,
    );
    final launchDetails = await _plugin.getNotificationAppLaunchDetails();
    if (launchDetails?.didNotificationLaunchApp ?? false) {
      final response = launchDetails?.notificationResponse;
      if (response != null) _recordResponse(response);
    }
    _initialized = true;
  }

  void _recordResponse(NotificationResponse response) {
    final action = ReminderAction.byId(response.actionId);
    if (action == ReminderAction.snooze) {
      // Delivered to the main isolate on some Android versions; same work.
      unawaited(snoozeReminder(_plugin, response).catchError((Object error) {
        debugPrint('Could not snooze reminder: $error');
      }));
      return;
    }
    final target = ReminderTarget.parse(response.payload)?.withAction(action);
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
    final keep = snoozedRemindersToKeep(kind, specs, [
      for (final request in pending) (id: request.id, payload: request.payload),
    ]);
    for (final request in pending) {
      if (keep.contains(request.id)) continue;
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
    final details = reminderNotificationDetails(kind);
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
