/// GSMA consumer eSIM activation code carried by an LPA QR code.
///
/// The canonical representation is `LPA:1$<SM-DP+>$<matching ID>` with an
/// optional SM-DP+ OID and confirmation-required flag. The matching ID and
/// confirmation code are credentials, so [toString] never includes them in
/// full.
class LpaActivation {
  const LpaActivation._({
    required this.smdpAddress,
    required this.matchingId,
    this.extra,
    this.confirmationCode,
  });

  final String smdpAddress;
  final String matchingId;
  final String? extra;
  final String? confirmationCode;

  factory LpaActivation({
    required String smdpAddress,
    required String matchingId,
    String? extra,
    String? confirmationCode,
  }) {
    final host = _normalizeSmdpAddress(smdpAddress);
    final code = matchingId.trim();
    final suffix = _normalizeExtra(extra);
    final confirmation = confirmationCode?.trim();
    final oid = suffix?.split(r'$').first ?? '';
    if (code.isEmpty && oid.isEmpty) {
      throw ArgumentError.value(
        matchingId,
        'matchingId',
        'Matching ID 为空时必须提供 SM-DP+ OID',
      );
    }
    _validateComponent(code, 'matchingId', allowEmpty: true);
    if (confirmation != null && confirmation.isNotEmpty) {
      _validateComponent(confirmation, 'confirmationCode');
    }
    return LpaActivation._(
      smdpAddress: host,
      matchingId: code,
      extra: suffix,
      confirmationCode: confirmation == null || confirmation.isEmpty
          ? null
          : confirmation,
    );
  }

  /// Parses a QR payload, a bare `1$...` activation code, or a URL whose
  /// `carddata` query parameter contains an LPA activation code.
  factory LpaActivation.parse(String source) {
    final payload = _extractPayload(source);
    final parts = payload.split(r'$');
    if (parts.length < 3 || parts[0] != '1') {
      throw const FormatException('不是有效的 LPA:1 激活码');
    }
    if (parts.length > 5) {
      throw const FormatException('LPA 激活码包含无法识别的额外字段');
    }
    return LpaActivation(
      smdpAddress: parts[1],
      matchingId: parts[2],
      extra: parts.length > 3 ? parts.sublist(3).join(r'$') : null,
    );
  }

  static LpaActivation? tryParse(String source) {
    try {
      return LpaActivation.parse(source);
    } on FormatException {
      return null;
    } on ArgumentError {
      return null;
    }
  }

  String get encoded =>
      'LPA:1\$$smdpAddress\$$matchingId${extra == null ? '' : '\$$extra'}';

  String get redactedMatchingId {
    if (matchingId.isEmpty) return '未提供';
    if (matchingId.length <= 4) return '••••';
    return '••••${matchingId.substring(matchingId.length - 4)}';
  }

  /// Optional SM-DP+ object identifier encoded in the activation code.
  String? get smdpOid {
    final value = extra?.split(r'$').first;
    return value == null || value.isEmpty ? null : value;
  }

  /// Whether the activation code says the LPA must request a separate
  /// confirmation code from the user.
  bool get confirmationCodeRequired {
    final parts = extra?.split(r'$');
    return parts != null && parts.length == 2 && parts[1] == '1';
  }

  /// Identifies the same pending profile even if one copy has a separately
  /// supplied confirmation code and the other does not.
  bool hasSameDownloadKey(LpaActivation other) =>
      smdpAddress == other.smdpAddress &&
      matchingId == other.matchingId &&
      extra == other.extra;

  static String _extractPayload(String source) {
    var value = source.trim();
    if (value.isEmpty) throw const FormatException('LPA 激活码不能为空');

    final uri = Uri.tryParse(value);
    final cardData = uri?.queryParameters['carddata'];
    if (cardData != null && cardData.trim().isNotEmpty) value = cardData.trim();

    try {
      value = Uri.decodeFull(value);
    } on FormatException {
      // Keep the original text so the validation below can report one error.
    }
    final match = RegExp(r'LPA:1\$', caseSensitive: false).firstMatch(value);
    if (match != null) value = value.substring(match.end - 2);
    if (value.toUpperCase().startsWith('LPA:')) value = value.substring(4);
    return value;
  }

  static String _normalizeSmdpAddress(String input) {
    var value = input.trim().toLowerCase();
    if (value.startsWith('https://')) {
      final uri = Uri.tryParse(value);
      if (uri == null ||
          uri.host.isEmpty ||
          (uri.path.isNotEmpty && uri.path != '/') ||
          uri.hasQuery ||
          uri.hasFragment ||
          uri.userInfo.isNotEmpty) {
        throw ArgumentError.value(input, 'smdpAddress', 'SM-DP+ 地址无效');
      }
      value = uri.hasPort ? '${uri.host}:${uri.port}' : uri.host;
    }
    value = value.replaceFirst(RegExp(r'\.$'), '');
    if (value.length > 253 ||
        value.contains(RegExp(r'[\s/@?#]')) ||
        !RegExp(r'^[a-z0-9.-]+(?::\d{1,5})?$').hasMatch(value)) {
      throw ArgumentError.value(input, 'smdpAddress', 'SM-DP+ 地址无效');
    }
    final host = value.split(':').first;
    if (!host.contains('.') ||
        host
            .split('.')
            .any(
              (label) =>
                  label.isEmpty ||
                  label.length > 63 ||
                  label.startsWith('-') ||
                  label.endsWith('-'),
            )) {
      throw ArgumentError.value(input, 'smdpAddress', 'SM-DP+ 地址无效');
    }
    return value;
  }

  static String? _normalizeExtra(String? input) {
    if (input == null) return null;
    final value = input.trim();
    if (value.isEmpty) return null;
    final parts = value.split(r'$');
    if (parts.length > 2) {
      throw ArgumentError.value(input, 'extra', 'LPA 扩展字段无效');
    }
    final oid = parts.first;
    if (oid.isNotEmpty && !RegExp(r'^\d+(?:\.\d+)*$').hasMatch(oid)) {
      throw ArgumentError.value(input, 'extra', 'SM-DP+ OID 无效');
    }
    if (parts.length == 2 && parts[1] != '1') {
      throw ArgumentError.value(input, 'extra', '确认码标志无效');
    }
    if (oid.isEmpty && parts.length == 1) {
      throw ArgumentError.value(input, 'extra', 'LPA 扩展字段无效');
    }
    return value;
  }

  static void _validateComponent(
    String value,
    String name, {
    bool allowEmpty = false,
  }) {
    if ((!allowEmpty && value.isEmpty) ||
        value.length > 255 ||
        value.contains(RegExp(r'[\s$]'))) {
      throw ArgumentError.value(value, name, 'LPA 字段无效');
    }
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is LpaActivation &&
          other.smdpAddress == smdpAddress &&
          other.matchingId == matchingId &&
          other.extra == extra &&
          other.confirmationCode == confirmationCode;

  @override
  int get hashCode =>
      Object.hash(smdpAddress, matchingId, extra, confirmationCode);

  @override
  String toString() =>
      'LpaActivation($smdpAddress, $redactedMatchingId${extra == null ? '' : ', extra'})';
}
