import 'package:flutter/material.dart';
import 'package:iesim_core/iesim_core.dart';
import 'package:qr_flutter/qr_flutter.dart';

/// Renders the canonical LPA payload stored on a Profile as a scannable QR.
///
/// The payload is intentionally never printed as plain text: it contains the
/// complete matching ID and must be treated like a credential.
class ActivationQrView extends StatelessWidget {
  const ActivationQrView({
    super.key,
    required this.activation,
    this.size = 220,
    this.compact = false,
  });

  final LpaActivation activation;
  final double size;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Center(
          child: Semantics(
            image: true,
            label: 'eSIM 激活二维码',
            child: Container(
              padding: EdgeInsets.all(compact ? 10 : 14),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(compact ? 14 : 18),
                border: Border.all(
                  color: scheme.outlineVariant.withValues(alpha: .7),
                ),
              ),
              child: QrImageView(
                key: ValueKey('activation-qr-${activation.smdpAddress}'),
                data: activation.encoded,
                version: QrVersions.auto,
                size: size,
                padding: EdgeInsets.zero,
                backgroundColor: Colors.white,
                eyeStyle: const QrEyeStyle(
                  eyeShape: QrEyeShape.square,
                  color: Colors.black,
                ),
                dataModuleStyle: const QrDataModuleStyle(
                  dataModuleShape: QrDataModuleShape.square,
                  color: Colors.black,
                ),
                errorCorrectionLevel: QrErrorCorrectLevel.M,
              ),
            ),
          ),
        ),
        SizedBox(height: compact ? 12 : 14),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              Icons.shield_outlined,
              size: 18,
              color: scheme.onSurfaceVariant,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                '二维码包含完整激活凭据，请勿截图公开分享。是否可以重复下载由运营商决定。',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                  height: 1.45,
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}
