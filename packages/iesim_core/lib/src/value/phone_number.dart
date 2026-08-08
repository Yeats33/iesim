/// 电话号码值对象。
///
/// 规范化存储：去除空格、连字符与括号，仅保留数字、国际前缀 + 以及
/// # 与 *（USSD 拨号场景）。规范化结果为空或含非法字符时抛 ArgumentError。
class PhoneNumber {
  final String _normalized;

  /// [number] 为任意常见书写形式（如 +86 138-0000-0000），构造时自动规范化。
  PhoneNumber(String number) : _normalized = _normalize(number);

  /// eSIM Profile 尚未分配或不提供号码时使用。普通文本构造仍拒绝空值。
  const PhoneNumber.unknown() : _normalized = '';

  /// 规范化后的号码（保留 + 前缀）。
  String get value => _normalized;

  bool get isUnknown => _normalized.isEmpty;

  static String _normalize(String input) {
    final cleaned = input
        .trim()
        .replaceAll(' ', '')
        .replaceAll('-', '')
        .replaceAll('(', '')
        .replaceAll(')', '');
    if (cleaned.isEmpty) {
      throw ArgumentError.value(input, 'number', '号码不能为空');
    }
    if (!RegExp(r'^\+?[0-9#*]+$').hasMatch(cleaned)) {
      throw ArgumentError.value(input, 'number', '仅允许数字、国际前缀 + 及 #/*（USSD）');
    }
    return cleaned;
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is PhoneNumber && other._normalized == _normalized;

  @override
  int get hashCode => _normalized.hashCode;

  @override
  String toString() => 'PhoneNumber($value)';
}
