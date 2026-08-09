import 'package:iesim_core/iesim_core.dart';
import 'package:test/test.dart';

void main() {
  PhoneAppBinding sample() => PhoneAppBinding(
    id: 'binding-1',
    phoneNumber: '+37257633333',
    appName: 'WhatsApp Messenger',
    presetId: 'whatsapp',
    developerName: 'WhatsApp LLC',
    accountLabel: '主账号',
    status: PhoneAppBindingStatus.active,
    purposes: const [
      PhoneAppBindingPurpose.messaging,
      PhoneAppBindingPurpose.verification,
    ],
    verificationChannels: const [
      PhoneVerificationChannel.sms,
      PhoneVerificationChannel.voiceCall,
    ],
    verifiedAt: DateTime.utc(2026, 8, 9),
    appStoreId: '310633997',
    appStoreBundleId: 'net.whatsapp.WhatsApp',
    appStoreUrl: 'https://apps.apple.com/app/whatsapp-messenger/id310633997',
    googlePlayPackage: 'com.whatsapp',
    googlePlayUrl: 'https://play.google.com/store/apps/details?id=com.whatsapp',
    iconUrl: 'https://example.com/whatsapp.png',
    websiteUrl: 'https://www.whatsapp.com/',
    storeMetadataUpdatedAt: DateTime.utc(2026, 8, 9),
    createdAt: DateTime.utc(2026, 8, 9),
    updatedAt: DateTime.utc(2026, 8, 9),
  );

  test('号码绑定 JSON 完整往返', () {
    final binding = sample();
    expect(PhoneAppBinding.fromJson(binding.toJson()), binding);
  });

  test('copyWith 可清除验证时间并保留其余商店字段', () {
    final changed = sample().copyWith(
      status: PhoneAppBindingStatus.pending,
      verifiedAt: null,
      updatedAt: DateTime.utc(2026, 8, 10),
    );
    expect(changed.verifiedAt, isNull);
    expect(changed.status, PhoneAppBindingStatus.pending);
    expect(changed.googlePlayPackage, 'com.whatsapp');
  });

  test('拒绝非 HTTPS 商店地址和重复用途', () {
    expect(
      () => sample().copyWith(appStoreUrl: 'http://example.com/app'),
      throwsFormatException,
    );
    expect(
      () => sample().copyWith(
        purposes: const [
          PhoneAppBindingPurpose.messaging,
          PhoneAppBindingPurpose.messaging,
        ],
      ),
      throwsFormatException,
    );
  });
}
