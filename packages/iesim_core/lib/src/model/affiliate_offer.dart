/// AFF 推荐的业务分类。
enum AffiliateOfferCategory {
  /// 可写入 Profile 的实体 eUICC / eSIM 卡。
  physicalEsimCard,

  /// 旅行或全球 eSIM 服务。
  esimService,

  /// 提供实体 SIM / 移动号码的运营商。
  mobileOperator,

  /// 用户自定义的其他推荐。
  other,
}

/// Profile 关联的推广或推荐入口。
///
/// 链接只保存资料，不会在 core 层自动访问网络。UI 必须向用户披露这是
/// 推广/推荐链接，并在打开前保留完整目标地址供用户查看。
class AffiliateOffer {
  const AffiliateOffer({
    required this.id,
    required this.brand,
    required this.category,
    required this.url,
    this.promoCode,
    this.note,
    this.isBuiltIn = false,
  });

  final String id;
  final String brand;
  final AffiliateOfferCategory category;
  final String url;
  final String? promoCode;
  final String? note;
  final bool isBuiltIn;

  AffiliateOffer copyWith({
    String? id,
    String? brand,
    AffiliateOfferCategory? category,
    String? url,
    String? promoCode,
    String? note,
    bool? isBuiltIn,
  }) => AffiliateOffer(
    id: id ?? this.id,
    brand: brand ?? this.brand,
    category: category ?? this.category,
    url: url ?? this.url,
    promoCode: promoCode ?? this.promoCode,
    note: note ?? this.note,
    isBuiltIn: isBuiltIn ?? this.isBuiltIn,
  );

  Map<String, Object?> toJson() => {
    'id': id,
    'brand': brand,
    'category': category.name,
    'url': url,
    'promoCode': promoCode,
    'note': note,
    'isBuiltIn': isBuiltIn,
  };

  factory AffiliateOffer.fromJson(Map<String, dynamic> value) => AffiliateOffer(
    id: value['id'] as String,
    brand: value['brand'] as String,
    category: AffiliateOfferCategory.values.byName(value['category'] as String),
    url: value['url'] as String,
    promoCode: value['promoCode'] as String?,
    note: value['note'] as String?,
    isBuiltIn: value['isBuiltIn'] as bool? ?? false,
  );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AffiliateOffer &&
          other.id == id &&
          other.brand == brand &&
          other.category == category &&
          other.url == url &&
          other.promoCode == promoCode &&
          other.note == note &&
          other.isBuiltIn == isBuiltIn;

  @override
  int get hashCode =>
      Object.hash(id, brand, category, url, promoCode, note, isBuiltIn);
}
