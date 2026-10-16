/// Business calendar is Europe/Moscow (UTC+03:00), independently of the
/// workstation/device timezone. A calendar selection keeps its civil fields.
class BusinessClock {
  BusinessClock({DateTime Function()? now}) : _now = now ?? DateTime.now;
  final DateTime Function() _now;

  DateTime get today {
    final moscow = _now().toUtc().add(const Duration(hours: 3));
    return DateTime(moscow.year, moscow.month, moscow.day);
  }
}
