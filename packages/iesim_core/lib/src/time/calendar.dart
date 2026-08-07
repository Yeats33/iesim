import 'package:timezone/data/latest.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

bool _initialized = false;

/// 加载 IANA 时区数据库。使用 ZonedCalendar 前必须调用一次。
/// 重复调用安全。
void initializeIesimTimeZones() {
  if (_initialized) return;
  tzdata.initializeTimeZones();
  _initialized = true;
}

/// 在指定基准时区下进行日历日运算。
///
/// 剩余天数的语义是「翻过多少页日历」，而非「相差多少小时除以 24」。
/// 夏令时切换日只有 23 或 25 小时，按时长相除会得出错误结果。
class ZonedCalendar {
  final tz.Location _location;

  /// [timeZoneId] 为 IANA 标识，如 Asia/Shanghai。
  /// 标识无效时抛出 ArgumentError。
  ZonedCalendar(String timeZoneId) : _location = _resolve(timeZoneId);

  static tz.Location _resolve(String timeZoneId) {
    try {
      return tz.getLocation(timeZoneId);
    } catch (_) {
      throw ArgumentError.value(
        timeZoneId,
        'timeZoneId',
        '未知的 IANA 时区标识（是否忘记调用 initializeIesimTimeZones）',
      );
    }
  }

  /// 两个 UTC 时刻在基准时区下相隔的日历天数。
  /// [toUtc] 早于 [fromUtc] 时返回负数。
  int daysBetween(DateTime fromUtc, DateTime toUtc) {
    final from = _calendarDay(fromUtc);
    final to = _calendarDay(toUtc);
    return to.difference(from).inDays;
  }

  /// 在基准时区下推进 [days] 个日历日，返回对应的 UTC 时刻。
  DateTime addDays(DateTime utc, int days) {
    final zoned = tz.TZDateTime.from(utc, _location);
    final shifted = tz.TZDateTime(
      _location,
      zoned.year,
      zoned.month,
      zoned.day + days,
      zoned.hour,
      zoned.minute,
      zoned.second,
    );
    return shifted.toUtc();
  }

  /// 取该时刻在基准时区下所属的日历日，归一化为 UTC 零点。
  /// 归一化后两日期相减不受时区偏移与夏令时影响。
  DateTime _calendarDay(DateTime utc) {
    final zoned = tz.TZDateTime.from(utc, _location);
    return DateTime.utc(zoned.year, zoned.month, zoned.day);
  }
}
