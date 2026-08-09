import '../model/keep_alive.dart';
import '../model/subscription.dart';
import '../time/calendar.dart';
import '../value/phone_number.dart';
import 'nekoko_tag_codec.dart';

/// 将 Nekoko 结构化标签映射为 ieSIM 原生字段后的结果。
class NekokoTagExtractionResult {
  NekokoTagExtractionResult({
    required this.subscription,
    required List<String> appliedFields,
    required List<String> ignoredDateNotes,
  }) : appliedFields = List.unmodifiable(appliedFields),
       ignoredDateNotes = List.unmodifiable(ignoredDateNotes);

  final Subscription subscription;
  final List<String> appliedFields;

  /// 未能安全判断语义的日期备注。ieSIM 保留原始 Tag，但不会猜测写入字段。
  final List<String> ignoredDateNotes;
}

/// 把已知的 Nekoko Tag 语义显式写入 ieSIM 自己的数据模型。
abstract final class NekokoTagExtractor {
  static NekokoTagExtractionResult apply(
    Subscription source,
    Iterable<NekokoTag> sourceTags, {
    required DateTime updatedAtUtc,
  }) {
    if (!updatedAtUtc.isUtc) {
      throw ArgumentError.value(updatedAtUtc, 'updatedAtUtc', '必须为 UTC');
    }
    final calendar = ZonedCalendar(source.timeZoneId);
    final nativeTags = <String>{...source.tags};
    var plan = source.plan;
    var keepAlive = source.keepAlive;
    var lifecycle = source.lifecycle;
    var number = source.number;
    final applied = <String>[];
    final ignored = <String>[];
    var addedTextTags = 0;

    for (final tag in sourceTags) {
      switch (tag) {
        case NekokoTextTag(value: final value):
          final extractedNumber = _phoneNumber(value);
          if (extractedNumber != null) {
            if (number.isUnknown) {
              number = extractedNumber;
              _addOnce(applied, '手机号');
            }
          } else if (nativeTags.add(value)) {
            addedTextTags++;
          }
        case NekokoDateTag(date: final date, note: final note):
          final meaning = _dateMeaning(note);
          final localDate = calendar.utcFromParts(
            year: date.year,
            month: date.month,
            day: date.day,
          );
          switch (meaning) {
            case _DateMeaning.planExpiry:
              plan = plan.copyWith(expiryDate: localDate);
              _addOnce(applied, '套餐到期日');
            case _DateMeaning.keepAliveAction:
              keepAlive = keepAlive.copyWith(
                required: true,
                lastActivityAt: localDate,
                confidence: DataConfidence.confirmed,
              );
              _addOnce(applied, '最近保号动作');
            case _DateMeaning.keepAliveDeadline:
              final cycleDays = keepAlive.cycleDays;
              if (cycleDays == null) {
                ignored.add(note ?? '未备注日期');
              } else {
                keepAlive = keepAlive.copyWith(
                  required: true,
                  lastActivityAt: calendar.addDays(localDate, -cycleDays),
                  confidence: DataConfidence.confirmed,
                );
                _addOnce(applied, '保号截止日');
              }
            case _DateMeaning.activationDeadline:
              lifecycle = lifecycle.copyWith(activationDeadline: localDate);
              _addOnce(applied, '激活期限');
            case _DateMeaning.serviceExpiry:
              lifecycle = lifecycle.copyWith(serviceExpiresAt: localDate);
              _addOnce(applied, 'Profile 服务到期日');
            case null:
              ignored.add(note ?? '未备注日期');
          }
      }
    }

    if (addedTextTags > 0) {
      applied.insert(0, '订阅标签 $addedTextTags 个');
    }
    return NekokoTagExtractionResult(
      subscription: source.copyWith(
        plan: plan,
        keepAlive: keepAlive,
        lifecycle: lifecycle,
        number: number,
        tags: nativeTags.toList(growable: false),
        updatedAt: updatedAtUtc,
      ),
      appliedFields: applied,
      ignoredDateNotes: ignored,
    );
  }

  static _DateMeaning? _dateMeaning(String? note) {
    final value = note?.trim().toLowerCase();
    if (value == null || value.isEmpty) return _DateMeaning.planExpiry;
    final expires = _containsAny(value, const [
      '到期',
      '截止',
      '期限',
      'expire',
      'deadline',
    ]);
    if (_containsAny(value, const ['保号', 'keep alive'])) {
      return expires
          ? _DateMeaning.keepAliveDeadline
          : _DateMeaning.keepAliveAction;
    }
    if (_containsAny(value, const [
      '续费',
      '充值',
      '最近动作',
      '保号动作',
      'renewal',
      'top up',
      'topup',
    ])) {
      return _DateMeaning.keepAliveAction;
    }
    if (_containsAny(value, const ['激活', 'activation', 'activate']) &&
        expires) {
      return _DateMeaning.activationDeadline;
    }
    if (_containsAny(value, const ['套餐', '流量', 'plan', 'package']) && expires) {
      return _DateMeaning.planExpiry;
    }
    if (_containsAny(value, const [
          'profile',
          '服务',
          '卡有效期',
          'sim validity',
          'service',
        ]) &&
        expires) {
      return _DateMeaning.serviceExpiry;
    }
    if (expires &&
        _containsAny(value, const ['到期', '截止', 'expire', 'expiry'])) {
      return _DateMeaning.planExpiry;
    }
    return null;
  }

  static bool _containsAny(String source, List<String> candidates) =>
      candidates.any(source.contains);

  static PhoneNumber? _phoneNumber(String value) {
    final candidate = RegExp(
      r'\+\d(?:[\d\s_()\-]*\d)?',
    ).firstMatch(value)?.group(0);
    if (candidate == null) return null;
    final digits = candidate.replaceAll(RegExp(r'\D'), '');
    if (digits.length < 7) return null;
    try {
      return PhoneNumber(candidate.replaceAll('_', ' '));
    } on ArgumentError {
      return null;
    }
  }

  static void _addOnce(List<String> values, String value) {
    if (!values.contains(value)) values.add(value);
  }
}

enum _DateMeaning {
  planExpiry,
  keepAliveAction,
  keepAliveDeadline,
  activationDeadline,
  serviceExpiry,
}
