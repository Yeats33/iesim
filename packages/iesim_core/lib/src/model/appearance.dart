/// 卡片外观与展示信息。
///
/// 全部为非业务字段，与 SimHub JSON 的对应字段一一映射（spec §5.1），
/// 便于互操作往返。不做内容校验，保持宽松。
class Appearance {
  /// 国旗 emoji。
  final String? flag;

  /// 卡片主题色，如 #0a84ff。
  final String? cardColorHex;

  /// 卡片背景资源名。
  final String? cardBackgroundAssetName;

  /// 运营商官网。
  final String? websiteURL;

  /// 自定义提示语。
  final String? customPrompt;

  const Appearance({
    this.flag,
    this.cardColorHex,
    this.cardBackgroundAssetName,
    this.websiteURL,
    this.customPrompt,
  });

  Appearance copyWith({
    String? flag,
    String? cardColorHex,
    String? cardBackgroundAssetName,
    String? websiteURL,
    String? customPrompt,
  }) =>
      Appearance(
        flag: flag ?? this.flag,
        cardColorHex: cardColorHex ?? this.cardColorHex,
        cardBackgroundAssetName:
            cardBackgroundAssetName ?? this.cardBackgroundAssetName,
        websiteURL: websiteURL ?? this.websiteURL,
        customPrompt: customPrompt ?? this.customPrompt,
      );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Appearance &&
          other.flag == flag &&
          other.cardColorHex == cardColorHex &&
          other.cardBackgroundAssetName == cardBackgroundAssetName &&
          other.websiteURL == websiteURL &&
          other.customPrompt == customPrompt;

  @override
  int get hashCode =>
      Object.hash(flag, cardColorHex, cardBackgroundAssetName, websiteURL, customPrompt);
}
