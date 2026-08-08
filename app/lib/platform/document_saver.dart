import 'package:flutter/services.dart';

abstract final class DocumentSaver {
  static const _channel = MethodChannel('im.ies.iesim/documents');

  /// 打开 Android 系统“创建文档”界面并写入 JSON；用户取消时返回 false。
  static Future<bool> saveJson({
    required String fileName,
    required Uint8List bytes,
  }) async =>
      await _channel.invokeMethod<bool>('saveJson', {
        'fileName': fileName,
        'bytes': bytes,
      }) ??
      false;
}
