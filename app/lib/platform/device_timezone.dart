import 'package:flutter/services.dart';

class DeviceTimeZone {
  static const _channel = MethodChannel('im.ies.iesim/device');

  static Future<String> get identifier async {
    final value = await _channel.invokeMethod<String>('timeZoneId');
    return value == null || value.isEmpty ? 'UTC' : value;
  }
}
