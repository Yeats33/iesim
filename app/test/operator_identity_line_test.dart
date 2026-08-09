import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart' hide KeepAlive;
import 'package:flutter_test/flutter_test.dart';
import 'package:iesim/services/operator_identity_service.dart';
import 'package:iesim/widgets/operator_identity_line.dart';
import 'package:iesim_core/iesim_core.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _catalog = r'''
mcc = "234"
country = "United Kingdom"
iso = "GB"
[[operators]]
mnc = "10"
operator = "Telefonica Europe"
brand = "O2 (UK)"
icon = "o2"
icon_scope = "234"
''';

final _png = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk'
  '/A8AAQUBAScY42YAAAAASUVORK5CYII=',
);

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('缺少手填名称时显示匹配名称与 Logo', (tester) async {
    final service = OperatorIdentityService(
      transport: const _Transport(),
      iconStore: _MemoryStore(),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: OperatorIdentityLine(
            subscription: _subscription(),
            service: service,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('O2 (UK)'), findsOneWidget);
    expect(find.byType(Image), findsOneWidget);
  });

  testWidgets('用户手填运营商名称始终优先', (tester) async {
    final service = OperatorIdentityService(
      transport: const _Transport(),
      iconStore: _MemoryStore(),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: OperatorIdentityLine(
            subscription: _subscription(operator: '我的 MVNO'),
            service: service,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('我的 MVNO'), findsOneWidget);
    expect(find.text('O2 (UK)'), findsNothing);
  });
}

Subscription _subscription({String? operator}) {
  final now = DateTime.utc(2026, 8, 9);
  return Subscription(
    id: 'profile-1',
    number: const PhoneNumber.unknown(),
    operator: operator,
    plan: Plan(),
    keepAlive: KeepAlive(required: false),
    details: const SubscriptionDetails(mcc: '234', mnc: '10'),
    timeZoneId: 'Europe/London',
    createdAt: now,
    updatedAt: now,
  );
}

class _Transport implements OperatorIdentityTransport {
  const _Transport();

  @override
  Future<OperatorResourceResponse> get(Uri uri, {String? etag}) async {
    return uri.path.endsWith('.toml')
        ? OperatorResourceResponse(
            statusCode: HttpStatus.ok,
            bodyBytes: utf8.encode(_catalog),
          )
        : OperatorResourceResponse(statusCode: HttpStatus.ok, bodyBytes: _png);
  }
}

class _MemoryStore implements OperatorIconStore {
  final _values = <String, Uint8List>{};

  @override
  Future<Uint8List?> read(String key) async => _values[key];

  @override
  Future<void> write(String key, Uint8List bytes) async {
    _values[key] = bytes;
  }
}
