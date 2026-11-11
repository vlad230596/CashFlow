import 'package:cashflow/services/reminder_notification_service.dart';

/// Records reminder synchronization per kind without touching the platform.
class FakeReminders implements ReminderNotificationService {
  final synchronized = <ReminderKind, List<List<ReminderSpec>>>{};
  final canceled = <ReminderTarget>[];
  var permissionRequests = 0;
  var exactAllowed = false;
  var exactRequests = 0;

  List<ReminderSpec> lastSpecs(ReminderKind kind) =>
      synchronized[kind]?.last ?? const [];

  @override
  bool get supportsReminders => true;

  @override
  Stream<ReminderTarget> get notificationTaps => const Stream.empty();

  @override
  Future<void> initialize() async {}

  @override
  Future<bool> requestPermission() async {
    permissionRequests++;
    return true;
  }

  @override
  Future<bool> canScheduleExactReminders() async => exactAllowed;

  @override
  Future<bool> requestExactReminderPermission() async {
    exactRequests++;
    exactAllowed = true;
    return true;
  }

  @override
  Future<void> synchronize(
    ReminderKind kind,
    Iterable<ReminderSpec> specs,
  ) async {
    synchronized.putIfAbsent(kind, () => []).add(specs.toList());
  }

  @override
  Future<void> cancel(ReminderKind kind, int entityId) async {
    canceled.add(ReminderTarget(kind, entityId));
  }

  @override
  ReminderTarget? consumePendingTarget() => null;
}
