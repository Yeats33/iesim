import 'package:flutter_test/flutter_test.dart';
import 'package:iesim_core/iesim_core.dart';
import 'package:iesim/data/builtin_affiliate_offers.dart';

void main() {
  test('内置 AFF 推荐包含产品指定的五项与优惠码', () {
    expect(builtinAffiliateOffers, hasLength(5));
    expect({
      for (final offer in builtinAffiliateOffers) offer.brand: offer.promoCode,
    }, containsPair('9eSIM', 'yeats2'));
    expect({
      for (final offer in builtinAffiliateOffers) offer.brand: offer.promoCode,
    }, containsPair('eSTK.me', 'UPTPR0RO9W'));
    expect({
      for (final offer in builtinAffiliateOffers) offer.brand: offer.promoCode,
    }, containsPair('eSIM.gg', '1esim'));
    expect({
      for (final offer in builtinAffiliateOffers) offer.brand: offer.promoCode,
    }, containsPair('RedteaGO 红茶移动', 'FRAN0530'));
    expect({
      for (final offer in builtinAffiliateOffers) offer.brand: offer.promoCode,
    }, containsPair('CTExcel UK', 'RNAFZW'));
    expect(
      builtinAffiliateOffers.every(
        (offer) =>
            offer.isBuiltIn &&
            offer.url.startsWith('https://') &&
            offer.category != AffiliateOfferCategory.other,
      ),
      isTrue,
    );
    expect(
      builtinAffiliateOffers
          .where((offer) => offer.brand == '9eSIM' || offer.brand == 'eSTK.me')
          .every((offer) => offer.note?.contains('9 折') ?? false),
      isTrue,
    );
  });
}
