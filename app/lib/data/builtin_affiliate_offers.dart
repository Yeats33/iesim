import 'package:iesim_core/iesim_core.dart';

/// ieSIM 默认展示的推广/推荐项目。
///
/// 优惠码和推荐参数由产品维护；页面会始终显示推广披露，不会静默跳转。
const nineEsimAffiliateOffer = AffiliateOffer(
  id: 'builtin-9esim',
  brand: '9eSIM',
  category: AffiliateOfferCategory.physicalEsimCard,
  url: 'https://www.9esim.com/?coupon=yeats2',
  promoCode: 'yeats2',
  note: '可写入 eSIM Profile 的实体 eUICC 卡；通过此推广链接购买享 9 折。',
  isBuiltIn: true,
);

const estkAffiliateOffer = AffiliateOffer(
  id: 'builtin-estk',
  brand: 'eSTK.me',
  category: AffiliateOfferCategory.physicalEsimCard,
  url: 'https://store.estk.me?ref=UPTPR0RO9W',
  promoCode: 'UPTPR0RO9W',
  note: '实体 eUICC / eSIM 卡；通过此推广链接购买享 9 折。',
  isBuiltIn: true,
);

const builtinAffiliateOffers = <AffiliateOffer>[
  nineEsimAffiliateOffer,
  estkAffiliateOffer,
  AffiliateOffer(
    id: 'builtin-esim-gg',
    brand: 'eSIM.gg',
    category: AffiliateOfferCategory.esimService,
    url: 'https://esim.gg/',
    promoCode: '1esim',
    note: '全球 eSIM 与号码服务。',
    isBuiltIn: true,
  ),
  AffiliateOffer(
    id: 'builtin-redteago',
    brand: 'RedteaGO 红茶移动',
    category: AffiliateOfferCategory.esimService,
    url: 'https://redteago.com/',
    promoCode: 'FRAN0530',
    note: '旅行 eSIM 数据套餐。',
    isBuiltIn: true,
  ),
  AffiliateOffer(
    id: 'builtin-ctexcel-uk',
    brand: 'CTExcel UK',
    category: AffiliateOfferCategory.mobileOperator,
    url:
        'https://www.ctexcel.com/uk/buyCard/buyCardPackage/1?recommendCode=RNAFZW',
    promoCode: 'RNAFZW',
    note: '英国实体 SIM / 手机号码推荐。',
    isBuiltIn: true,
  ),
];
