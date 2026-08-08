import 'package:iesim_core/iesim_core.dart';
import 'package:test/test.dart';

void main() {
  test('AffiliateOffer JSON 完整往返', () {
    const offer = AffiliateOffer(
      id: 'builtin-9esim',
      brand: '9eSIM',
      category: AffiliateOfferCategory.physicalEsimCard,
      url: 'https://www.9esim.com/?coupon=yeats2',
      promoCode: 'yeats2',
      note: '实体 eUICC',
      isBuiltIn: true,
    );

    expect(AffiliateOffer.fromJson(offer.toJson()), offer);
  });
}
