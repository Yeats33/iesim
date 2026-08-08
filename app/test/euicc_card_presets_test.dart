import 'package:flutter_test/flutter_test.dart';
import 'package:iesim/data/euicc_card_presets.dart';

void main() {
  test('可拆卸 eUICC 预设包含 9eSIM 与 eSTK.me 的 9 折推广入口', () {
    expect(builtinEuiccCardPresets, hasLength(2));

    final nineEsim = euiccCardPresetById('9esim-removable');
    expect(nineEsim?.brand, '9eSIM');
    expect(nineEsim?.affiliateOffer.promoCode, 'yeats2');
    expect(
      nineEsim?.affiliateOffer.url,
      'https://www.9esim.com/?coupon=yeats2',
    );
    expect(nineEsim?.affiliateOffer.note, contains('9 折'));

    final estk = euiccCardPresetById('estk-removable');
    expect(estk?.brand, 'eSTK.me');
    expect(estk?.affiliateOffer.promoCode, 'UPTPR0RO9W');
    expect(estk?.affiliateOffer.url, 'https://store.estk.me?ref=UPTPR0RO9W');
    expect(estk?.affiliateOffer.note, contains('9 折'));

    expect(euiccCardPresetById(null), isNull);
    expect(euiccCardPresetById('unknown'), isNull);
  });
}
