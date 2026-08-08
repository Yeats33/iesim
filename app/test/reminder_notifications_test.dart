import 'package:flutter_test/flutter_test.dart';
import 'package:iesim/services/reminder_notifications.dart';

void main() {
  test('相同提醒键始终得到相同的正数通知 ID', () {
    const key = 'sub-a:keepAlive:offset-7';
    expect(stableNotificationId(key), stableNotificationId(key));
    expect(stableNotificationId(key), greaterThanOrEqualTo(0));
    expect(
      stableNotificationId(key),
      isNot(stableNotificationId('sub-a:planExpiry:offset-7')),
    );
  });
}
