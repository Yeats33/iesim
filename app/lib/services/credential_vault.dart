import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:iesim_core/iesim_core.dart';

/// 一条由安全存储保护的 LPA 凭据记录。
///
/// [activation] 为空表示删除墓碑，避免另一台设备的旧凭据在同步时复活。
class ActivationCredentialRecord {
  const ActivationCredentialRecord({
    required this.subscriptionId,
    required this.updatedAtUtc,
    required this.activation,
  });

  final String subscriptionId;
  final DateTime updatedAtUtc;
  final LpaActivation? activation;

  Map<String, Object?> toJson() => {
    'subscriptionId': subscriptionId,
    'updatedAt': updatedAtUtc.toIso8601String(),
    'activation': switch (activation) {
      final value? => {
        'smdpAddress': value.smdpAddress,
        'matchingId': value.matchingId,
        'extra': value.extra,
        'confirmationCode': value.confirmationCode,
      },
      null => null,
    },
  };

  factory ActivationCredentialRecord.fromJson(Map<String, dynamic> value) {
    final subscriptionId = value['subscriptionId'];
    final updatedAt = DateTime.tryParse(value['updatedAt'] as String? ?? '');
    final activation = value['activation'];
    if (subscriptionId is! String || subscriptionId.isEmpty) {
      throw const FormatException('凭据记录缺少 subscriptionId');
    }
    if (updatedAt == null || !updatedAt.isUtc) {
      throw const FormatException('凭据记录 updatedAt 必须为 UTC');
    }
    if (activation != null && activation is! Map<String, dynamic>) {
      throw const FormatException('凭据记录 activation 必须是对象或 null');
    }
    return ActivationCredentialRecord(
      subscriptionId: subscriptionId,
      updatedAtUtc: updatedAt,
      activation: activation == null
          ? null
          : LpaActivation(
              smdpAddress: _requiredString(activation, 'smdpAddress'),
              matchingId: _requiredString(activation, 'matchingId'),
              extra: _optionalString(activation, 'extra'),
              confirmationCode: _optionalString(activation, 'confirmationCode'),
            ),
    );
  }
}

abstract interface class ActivationCredentialVault {
  Future<ActivationCredentialRecord?> read(String subscriptionId);

  Future<List<ActivationCredentialRecord>> readAll();

  Future<void> write(ActivationCredentialRecord record);

  Future<void> purge(String subscriptionId);

  Future<void> retain(Set<String> subscriptionIds);

  Future<void> clear();
}

/// Android 上由 flutter_secure_storage / Keystore 保护的凭据保险库。
class SecureActivationCredentialVault implements ActivationCredentialVault {
  const SecureActivationCredentialVault([
    this._storage = const FlutterSecureStorage(),
  ]);

  static const _prefix = 'activation_vault.v1.';
  final FlutterSecureStorage _storage;

  @override
  Future<ActivationCredentialRecord?> read(String subscriptionId) async {
    final source = await _storage.read(key: '$_prefix$subscriptionId');
    if (source == null) return null;
    return _decode(source);
  }

  @override
  Future<List<ActivationCredentialRecord>> readAll() async {
    final values = await _storage.readAll();
    final records = <ActivationCredentialRecord>[];
    for (final entry in values.entries) {
      if (!entry.key.startsWith(_prefix)) continue;
      records.add(_decode(entry.value));
    }
    return records;
  }

  @override
  Future<void> write(ActivationCredentialRecord record) => _storage.write(
    key: '$_prefix${record.subscriptionId}',
    value: jsonEncode(record.toJson()),
  );

  @override
  Future<void> purge(String subscriptionId) =>
      _storage.delete(key: '$_prefix$subscriptionId');

  @override
  Future<void> retain(Set<String> subscriptionIds) async {
    final values = await _storage.readAll();
    for (final key in values.keys) {
      if (!key.startsWith(_prefix)) continue;
      final id = key.substring(_prefix.length);
      if (!subscriptionIds.contains(id)) await _storage.delete(key: key);
    }
  }

  @override
  Future<void> clear() async {
    final values = await _storage.readAll();
    for (final key in values.keys) {
      if (key.startsWith(_prefix)) await _storage.delete(key: key);
    }
  }

  static ActivationCredentialRecord _decode(String source) {
    final value = jsonDecode(source);
    if (value is! Map<String, dynamic>) {
      throw const FormatException('本机凭据记录格式无效');
    }
    return ActivationCredentialRecord.fromJson(value);
  }
}

/// 测试与无平台环境使用的内存保险库。
class MemoryActivationCredentialVault implements ActivationCredentialVault {
  final Map<String, ActivationCredentialRecord> _records = {};

  @override
  Future<ActivationCredentialRecord?> read(String subscriptionId) async =>
      _records[subscriptionId];

  @override
  Future<List<ActivationCredentialRecord>> readAll() async =>
      List.unmodifiable(_records.values);

  @override
  Future<void> write(ActivationCredentialRecord record) async {
    _records[record.subscriptionId] = record;
  }

  @override
  Future<void> purge(String subscriptionId) async {
    _records.remove(subscriptionId);
  }

  @override
  Future<void> retain(Set<String> subscriptionIds) async {
    _records.removeWhere((id, _) => !subscriptionIds.contains(id));
  }

  @override
  Future<void> clear() async => _records.clear();
}

String _requiredString(Map<String, dynamic> value, String field) {
  final item = value[field];
  if (item is String) return item;
  throw FormatException('$field 必须是字符串');
}

String? _optionalString(Map<String, dynamic> value, String field) {
  final item = value[field];
  if (item == null) return null;
  if (item is String) return item;
  throw FormatException('$field 必须是字符串或 null');
}
