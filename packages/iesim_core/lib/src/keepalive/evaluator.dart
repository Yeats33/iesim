import '../model/keep_alive.dart';
import '../time/calendar.dart';
import '../time/clock.dart';
import 'status.dart';

/// 保号状态判定。
///
/// 截止日在订阅的基准时区下按日历日计算，
/// 使剩余天数不因用户跨时区而跳变。
class KeepAliveEvaluator {
  final Clock _clock;

  /// 剩余天数不超过此值时判为 DueSoon。
  final int dueSoonThresholdDays;

  const KeepAliveEvaluator({
    required Clock clock,
    this.dueSoonThresholdDays = 7,
  }) : _clock = clock;

  /// [timeZoneId] 为订阅的 IANA 基准时区标识。
  KeepAliveStatus evaluate(KeepAlive keepAlive, String timeZoneId) {
    if (!keepAlive.required) {
      return const NotRequired();
    }

    final lastActivity = keepAlive.lastActivityAt;
    final cycleDays = keepAlive.cycleDays;
    if (lastActivity == null || cycleDays == null) {
      return const Unknown();
    }

    final calendar = ZonedCalendar(timeZoneId);
    final deadline = calendar.addDays(lastActivity, cycleDays);
    final daysLeft = calendar.daysBetween(_clock.nowUtc(), deadline);
    final inferred = keepAlive.confidence == DataConfidence.inferred;

    if (daysLeft < 0) {
      return Overdue(daysOver: -daysLeft, inferred: inferred);
    }
    if (daysLeft <= dueSoonThresholdDays) {
      return DueSoon(daysLeft: daysLeft, inferred: inferred);
    }
    return Safe(daysLeft: daysLeft, inferred: inferred);
  }
}
