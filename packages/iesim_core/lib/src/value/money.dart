/// 跨币种运算错误。金额禁止隐式换算。
class CurrencyMismatchError extends Error {
  final String left;
  final String right;

  CurrencyMismatchError(this.left, this.right);

  @override
  String toString() => '币种不匹配：$left 与 $right 不可直接运算';
}

/// 金额值对象。
///
/// 以最小货币单位的整数存储（如人民币的分、日元的円），
/// 避免浮点误差。此做法沿用自 SimJ 的 cyclePaymentMinorUnits。
class Money {
  /// 最小货币单位数量。允许为负，用于表示退款或调整。
  final int minorUnits;

  /// ISO 4217 币种代码，如 CNY、USD、JPY。
  final String currencyCode;

  const Money({required this.minorUnits, required this.currencyCode});

  factory Money.zero(String currencyCode) =>
      Money(minorUnits: 0, currencyCode: currencyCode);

  Money operator +(Money other) {
    _assertSameCurrency(other);
    return Money(
      minorUnits: minorUnits + other.minorUnits,
      currencyCode: currencyCode,
    );
  }

  Money operator -(Money other) {
    _assertSameCurrency(other);
    return Money(
      minorUnits: minorUnits - other.minorUnits,
      currencyCode: currencyCode,
    );
  }

  void _assertSameCurrency(Money other) {
    if (currencyCode != other.currencyCode) {
      throw CurrencyMismatchError(currencyCode, other.currencyCode);
    }
  }

  Money copyWith({int? minorUnits, String? currencyCode}) => Money(
        minorUnits: minorUnits ?? this.minorUnits,
        currencyCode: currencyCode ?? this.currencyCode,
      );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Money &&
          other.minorUnits == minorUnits &&
          other.currencyCode == currencyCode;

  @override
  int get hashCode => Object.hash(minorUnits, currencyCode);

  @override
  String toString() => 'Money($minorUnits $currencyCode)';
}
