import '../value/money.dart';
import 'affiliate_offer.dart';

const _unsetSubscriptionDetail = Object();

/// Optional operational metadata used by richer SimHub v5 backups.
///
/// These fields do not participate in keep-alive calculations, but retaining
/// them prevents a full backup round-trip from discarding useful account and
/// carrier-app context.
class SubscriptionDetails {
  const SubscriptionDetails({
    this.profileName,
    this.profileClassCode,
    this.declaredProfileSizeBytes,
    this.installedProfileSizeBytes,
    this.gid1,
    this.gid2,
    this.countryCode,
    this.countryName,
    this.mcc,
    this.mnc,
    this.apn,
    this.secondaryPhoneNumber,
    this.secondaryPhoneNumberEnabled = false,
    this.activationDate,
    this.currentBalance,
    this.affiliateOffers = const [],
    this.autoTopUpEnabled = false,
    this.topUpCycleUnit,
    this.renewalIntervalValue,
    this.renewalUnit,
    this.transactionNotes,
    this.carrierAppName,
    this.carrierAppStoreUrl,
    this.carrierAppIconUrl,
    this.keepAliveModeRaw,
    this.orderIndex = 0,
    this.isDormant = false,
    this.isPinned = false,
  });

  /// 用户用于在首页识别 Profile 的名称；不等同于运营商品牌。
  final String? profileName;

  /// eSIM Profile class 的外部整数代码；保留原值，不猜测厂商语义。
  final int? profileClassCode;

  /// Profile 元数据声明的大小（字节）。
  final int? declaredProfileSizeBytes;

  /// eUICC 报告的实际占用空间（字节）。
  final int? installedProfileSizeBytes;

  /// 运营商分组标识。
  final String? gid1;
  final String? gid2;

  final String? countryCode;
  final String? countryName;
  final String? mcc;
  final String? mnc;
  final String? apn;
  final String? secondaryPhoneNumber;
  final bool secondaryPhoneNumberEnabled;
  final DateTime? activationDate;
  final Money? currentBalance;
  final List<AffiliateOffer> affiliateOffers;
  final bool autoTopUpEnabled;
  final String? topUpCycleUnit;
  final int? renewalIntervalValue;
  final String? renewalUnit;
  final String? transactionNotes;
  final String? carrierAppName;
  final String? carrierAppStoreUrl;
  final String? carrierAppIconUrl;
  final String? keepAliveModeRaw;
  final int orderIndex;
  final bool isDormant;
  final bool isPinned;

  SubscriptionDetails copyWith({
    Object? profileName = _unsetSubscriptionDetail,
    int? profileClassCode,
    int? declaredProfileSizeBytes,
    int? installedProfileSizeBytes,
    String? gid1,
    String? gid2,
    String? countryCode,
    String? countryName,
    String? mcc,
    String? mnc,
    String? apn,
    String? secondaryPhoneNumber,
    bool? secondaryPhoneNumberEnabled,
    DateTime? activationDate,
    Money? currentBalance,
    List<AffiliateOffer>? affiliateOffers,
    bool? autoTopUpEnabled,
    String? topUpCycleUnit,
    int? renewalIntervalValue,
    String? renewalUnit,
    String? transactionNotes,
    String? carrierAppName,
    String? carrierAppStoreUrl,
    String? carrierAppIconUrl,
    String? keepAliveModeRaw,
    int? orderIndex,
    bool? isDormant,
    bool? isPinned,
  }) => SubscriptionDetails(
    profileName: identical(profileName, _unsetSubscriptionDetail)
        ? this.profileName
        : profileName as String?,
    profileClassCode: profileClassCode ?? this.profileClassCode,
    declaredProfileSizeBytes:
        declaredProfileSizeBytes ?? this.declaredProfileSizeBytes,
    installedProfileSizeBytes:
        installedProfileSizeBytes ?? this.installedProfileSizeBytes,
    gid1: gid1 ?? this.gid1,
    gid2: gid2 ?? this.gid2,
    countryCode: countryCode ?? this.countryCode,
    countryName: countryName ?? this.countryName,
    mcc: mcc ?? this.mcc,
    mnc: mnc ?? this.mnc,
    apn: apn ?? this.apn,
    secondaryPhoneNumber: secondaryPhoneNumber ?? this.secondaryPhoneNumber,
    secondaryPhoneNumberEnabled:
        secondaryPhoneNumberEnabled ?? this.secondaryPhoneNumberEnabled,
    activationDate: activationDate ?? this.activationDate,
    currentBalance: currentBalance ?? this.currentBalance,
    affiliateOffers: affiliateOffers ?? this.affiliateOffers,
    autoTopUpEnabled: autoTopUpEnabled ?? this.autoTopUpEnabled,
    topUpCycleUnit: topUpCycleUnit ?? this.topUpCycleUnit,
    renewalIntervalValue: renewalIntervalValue ?? this.renewalIntervalValue,
    renewalUnit: renewalUnit ?? this.renewalUnit,
    transactionNotes: transactionNotes ?? this.transactionNotes,
    carrierAppName: carrierAppName ?? this.carrierAppName,
    carrierAppStoreUrl: carrierAppStoreUrl ?? this.carrierAppStoreUrl,
    carrierAppIconUrl: carrierAppIconUrl ?? this.carrierAppIconUrl,
    keepAliveModeRaw: keepAliveModeRaw ?? this.keepAliveModeRaw,
    orderIndex: orderIndex ?? this.orderIndex,
    isDormant: isDormant ?? this.isDormant,
    isPinned: isPinned ?? this.isPinned,
  );

  @override
  bool operator ==(Object other) =>
      other is SubscriptionDetails &&
      other.profileName == profileName &&
      other.profileClassCode == profileClassCode &&
      other.declaredProfileSizeBytes == declaredProfileSizeBytes &&
      other.installedProfileSizeBytes == installedProfileSizeBytes &&
      other.gid1 == gid1 &&
      other.gid2 == gid2 &&
      other.countryCode == countryCode &&
      other.countryName == countryName &&
      other.mcc == mcc &&
      other.mnc == mnc &&
      other.apn == apn &&
      other.secondaryPhoneNumber == secondaryPhoneNumber &&
      other.secondaryPhoneNumberEnabled == secondaryPhoneNumberEnabled &&
      other.activationDate == activationDate &&
      other.currentBalance == currentBalance &&
      _listEquals(other.affiliateOffers, affiliateOffers) &&
      other.autoTopUpEnabled == autoTopUpEnabled &&
      other.topUpCycleUnit == topUpCycleUnit &&
      other.renewalIntervalValue == renewalIntervalValue &&
      other.renewalUnit == renewalUnit &&
      other.transactionNotes == transactionNotes &&
      other.carrierAppName == carrierAppName &&
      other.carrierAppStoreUrl == carrierAppStoreUrl &&
      other.carrierAppIconUrl == carrierAppIconUrl &&
      other.keepAliveModeRaw == keepAliveModeRaw &&
      other.orderIndex == orderIndex &&
      other.isDormant == isDormant &&
      other.isPinned == isPinned;

  @override
  int get hashCode => Object.hashAll([
    profileName,
    profileClassCode,
    declaredProfileSizeBytes,
    installedProfileSizeBytes,
    gid1,
    gid2,
    countryCode,
    countryName,
    mcc,
    mnc,
    apn,
    secondaryPhoneNumber,
    secondaryPhoneNumberEnabled,
    activationDate,
    currentBalance,
    Object.hashAll(affiliateOffers),
    autoTopUpEnabled,
    topUpCycleUnit,
    renewalIntervalValue,
    renewalUnit,
    transactionNotes,
    carrierAppName,
    carrierAppStoreUrl,
    carrierAppIconUrl,
    keepAliveModeRaw,
    orderIndex,
    isDormant,
    isPinned,
  ]);

  static bool _listEquals(List<AffiliateOffer> a, List<AffiliateOffer> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}
