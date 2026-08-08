import 'package:iesim_core/iesim_core.dart';
import 'package:intl/intl.dart';

String formatPhone(String value) {
  if (value.length < 8 || value.contains('#') || value.contains('*')) {
    return value;
  }
  final prefix = value.startsWith('+') ? '+' : '';
  final digits = value.replaceFirst('+', '');
  final groups = <String>[];
  var cursor = digits.length;
  while (cursor > 0) {
    final start = (cursor - 4).clamp(0, cursor);
    groups.insert(0, digits.substring(start, cursor));
    cursor = start;
  }
  return '$prefix${groups.join(' ')}';
}

String displayPhone(PhoneNumber number) =>
    number.isUnknown ? '未分配号码' : formatPhone(number.value);

String? profileDisplayName(Subscription subscription) {
  final value = subscription.details.profileName?.trim();
  return value == null || value.isEmpty ? null : value;
}

String displayProfileIdentity(Subscription subscription) {
  final name = profileDisplayName(subscription);
  if (name != null) return name;
  final iccid = subscription.iccid?.trim();
  if (subscription.number.isUnknown && iccid != null && iccid.isNotEmpty) {
    final ending = iccid.length <= 8
        ? iccid
        : iccid.substring(iccid.length - 8);
    return 'Profile · $ending';
  }
  return displayPhone(subscription.number);
}

String formatZonedDate(DateTime utc, String timeZoneId) {
  final moment = ZonedCalendar(timeZoneId).momentAt(utc);
  return '${moment.year.toString().padLeft(4, '0')}-'
      '${moment.month.toString().padLeft(2, '0')}-'
      '${moment.day.toString().padLeft(2, '0')}';
}

String formatZonedDateTime(DateTime utc, String timeZoneId) {
  final moment = ZonedCalendar(timeZoneId).momentAt(utc);
  return '${formatZonedDate(utc, timeZoneId)} '
      '${moment.hour.toString().padLeft(2, '0')}:'
      '${moment.minute.toString().padLeft(2, '0')} '
      '(${formatUtcOffset(moment.utcOffset)})';
}

String formatUtcOffset(Duration offset) {
  final minutes = offset.inMinutes;
  final sign = minutes < 0 ? '-' : '+';
  final absolute = minutes.abs();
  final hours = absolute ~/ 60;
  final remainder = absolute % 60;
  if (remainder == 0) return 'UTC$sign$hours';
  return 'UTC$sign$hours:${remainder.toString().padLeft(2, '0')}';
}

String formatMoney(Money money) {
  final amount = money.minorUnits / 100;
  return NumberFormat.currency(
    locale: 'zh_CN',
    name: money.currencyCode,
    symbol: '${money.currencyCode} ',
  ).format(amount);
}

String formatByteSize(int bytes) {
  if (bytes < 1024) return '$bytes B';
  final kib = bytes / 1024;
  if (kib < 1024) {
    return '${kib.toStringAsFixed(kib >= 10 ? 0 : 1)} KiB';
  }
  final mib = kib / 1024;
  return '${mib.toStringAsFixed(mib >= 10 ? 0 : 1)} MiB';
}

String activityName(ActivityType type) => switch (type) {
  ActivityType.topUp => '充值',
  ActivityType.call => '通话',
  ActivityType.sms => '短信',
  ActivityType.renewal => '续费',
  ActivityType.mobileData => '使用流量',
  ActivityType.planPurchase => '购买套餐',
  ActivityType.balanceChange => '余额变动',
  ActivityType.other => '其他动作',
};
