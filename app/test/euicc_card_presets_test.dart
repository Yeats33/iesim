import 'package:flutter_test/flutter_test.dart';
import 'package:iesim/data/euicc_card_presets.dart';

void main() {
  test('可拆卸 eUICC 按 9eSIM 与 eSTK.me 的具体型号提供预设', () {
    expect(builtinEuiccCardPresets, hasLength(6));
    expect(builtinEuiccCardPresets.map((preset) => preset.id).toSet(), {
      '9esim-v0',
      '9esim-v0-max',
      '9esim-v3',
      'estk-c-beta',
      'estk-plus',
      'estk-max',
    });

    final v3 = euiccCardPresetById('9esim-v3');
    expect(v3?.displayName, '9eSIM V3');
    expect(v3?.storageLabel, '1.5 MB');
    expect(v3?.profileCapacityLabel, contains('50'));
    expect(v3?.managementLabel, contains('Kigen OS'));
    expect(v3?.affiliateOffer.promoCode, 'yeats2');
    expect(v3?.affiliateOffer.url, 'https://www.9esim.com/?coupon=yeats2');

    final max = euiccCardPresetById('estk-max');
    expect(max?.displayName, 'eSTK.me Max');
    expect(max?.storageLabel, '1600 KiB');
    expect(max?.profileCapacityLabel, contains('60'));
    expect(max?.affiliateOffer.promoCode, 'UPTPR0RO9W');
    expect(max?.affiliateOffer.url, 'https://store.estk.me?ref=UPTPR0RO9W');

    expect(
      builtinEuiccCardPresets.every(
        (preset) => preset.affiliateOffer.note?.contains('9 折') ?? false,
      ),
      isTrue,
    );
    expect(euiccCardPresetById('9esim-removable'), isNull);
    expect(euiccCardPresetById('estk-removable'), isNull);
    expect(euiccCardPresetById(null), isNull);
    expect(euiccCardPresetById('unknown'), isNull);
  });
}
