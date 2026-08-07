/// 时钟抽象。
///
/// 业务逻辑一律通过此接口取当前时刻，不直接调用 DateTime.now()，
/// 否则依赖时间的测试无法构造确定场景。
abstract class Clock {
  const Clock();

  /// 当前时刻，始终为 UTC。
  DateTime nowUtc();
}

/// 生产环境时钟。
class SystemClock extends Clock {
  const SystemClock();

  @override
  DateTime nowUtc() => DateTime.now().toUtc();
}

/// 测试用固定时钟。
class FixedClock extends Clock {
  final DateTime _instant;

  /// [instant] 必须为 UTC，否则抛出 ArgumentError。
  FixedClock(DateTime instant) : _instant = instant {
    if (!instant.isUtc) {
      throw ArgumentError.value(instant, 'instant', '必须为 UTC 时刻');
    }
  }

  @override
  DateTime nowUtc() => _instant;
}
