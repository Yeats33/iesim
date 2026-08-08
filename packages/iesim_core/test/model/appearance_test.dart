import 'package:test/test.dart';
import 'package:iesim_core/src/model/appearance.dart';

void main() {
  group('Appearance', () {
    test('默认构造为全空', () {
      const a = Appearance();
      expect(a.flag, isNull);
      expect(a.cardColorHex, isNull);
      expect(a.cardBackgroundAssetName, isNull);
      expect(a.websiteURL, isNull);
      expect(a.customPrompt, isNull);
    });

    test('copyWith 仅覆盖指定字段', () {
      const a = Appearance(flag: '🇨🇳');
      expect(a.copyWith(cardColorHex: '#0a84ff').flag, equals('🇨🇳'));
      expect(
        a.copyWith(cardColorHex: '#0a84ff').cardColorHex,
        equals('#0a84ff'),
      );
    });

    test('相同字段视为相等', () {
      expect(
        const Appearance(flag: '🇨🇳'),
        equals(const Appearance(flag: '🇨🇳')),
      );
      expect(
        const Appearance(flag: '🇨🇳'),
        isNot(equals(const Appearance(flag: '🇯🇵'))),
      );
    });
  });
}
