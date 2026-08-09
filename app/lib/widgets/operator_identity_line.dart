import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:iesim_core/iesim_core.dart';

import '../services/operator_identity_service.dart';

/// Displays the user's carrier label and augments it with a locally cached,
/// evidence-matched operator logo. A user-entered carrier name always wins.
class OperatorIdentityLine extends StatefulWidget {
  const OperatorIdentityLine({
    super.key,
    required this.subscription,
    this.service,
    this.textStyle,
    this.iconSize = 30,
    this.fallbackText = '未填写运营商',
    this.iconBackgroundColor,
  });

  final Subscription subscription;
  final OperatorIdentityService? service;
  final TextStyle? textStyle;
  final double iconSize;
  final String fallbackText;
  final Color? iconBackgroundColor;

  @override
  State<OperatorIdentityLine> createState() => _OperatorIdentityLineState();
}

class _OperatorIdentityLineState extends State<OperatorIdentityLine> {
  late Future<OperatorIdentity?> _identity;

  @override
  void initState() {
    super.initState();
    _identity = _resolve();
  }

  @override
  void didUpdateWidget(covariant OperatorIdentityLine oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_identityKey(oldWidget.subscription) !=
            _identityKey(widget.subscription) ||
        oldWidget.service != widget.service) {
      _identity = _resolve();
    }
  }

  Future<OperatorIdentity?> _resolve() {
    final subscription = widget.subscription;
    return (widget.service ?? OperatorIdentityService.instance).resolve(
      mcc: subscription.details.mcc,
      mnc: subscription.details.mnc,
      gid1: subscription.details.gid1,
      gid2: subscription.details.gid2,
      profileName: subscription.details.profileName ?? subscription.plan.name,
      serviceProviderName: subscription.operator,
    );
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<OperatorIdentity?>(
      future: _identity,
      builder: (context, snapshot) {
        final identity = snapshot.data;
        final manualName = widget.subscription.operator?.trim();
        final displayName = manualName?.isNotEmpty == true
            ? manualName!
            : identity?.displayName ?? widget.fallbackText;
        final logo = identity?.iconBytes;
        return Row(
          children: [
            if (logo != null)
              _Logo(
                bytes: logo,
                size: widget.iconSize,
                backgroundColor: widget.iconBackgroundColor,
              )
            else if (widget.subscription.appearance.flag case final flag?)
              SizedBox(
                width: widget.iconSize,
                height: widget.iconSize,
                child: Center(
                  child: Text(
                    flag,
                    style: TextStyle(fontSize: widget.iconSize * .68),
                  ),
                ),
              )
            else
              Icon(
                Icons.cell_tower_rounded,
                size: widget.iconSize * .72,
                color:
                    widget.textStyle?.color?.withValues(alpha: .72) ??
                    Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            const SizedBox(width: 9),
            Flexible(
              child: Text(
                displayName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: widget.textStyle,
              ),
            ),
          ],
        );
      },
    );
  }
}

class _Logo extends StatelessWidget {
  const _Logo({
    required this.bytes,
    required this.size,
    required this.backgroundColor,
  });

  final Uint8List bytes;
  final double size;
  final Color? backgroundColor;

  @override
  Widget build(BuildContext context) {
    final resolvedBackground =
        backgroundColor ?? Theme.of(context).colorScheme.surfaceContainerHigh;
    return Container(
      width: size,
      height: size,
      padding: EdgeInsets.all(size * .12),
      decoration: BoxDecoration(
        color: resolvedBackground,
        borderRadius: BorderRadius.circular(size * .28),
      ),
      child: Image.memory(
        bytes,
        fit: BoxFit.contain,
        gaplessPlayback: true,
        cacheWidth: (size * 3).round(),
        errorBuilder: (_, _, _) => const Icon(Icons.cell_tower_rounded),
      ),
    );
  }
}

String _identityKey(Subscription subscription) => [
  subscription.operator,
  subscription.details.mcc,
  subscription.details.mnc,
  subscription.details.gid1,
  subscription.details.gid2,
  subscription.details.profileName,
  subscription.plan.name,
].join('\u0000');
