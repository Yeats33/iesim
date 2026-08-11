import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:iesim/data/app_controller.dart';
import 'package:iesim/services/diagnostic_report_service.dart';
import 'package:iesim_core/iesim_core.dart';

void main() {
  test('诊断报告只导出聚合状态，不泄露 Profile 标识与凭据', () async {
    final controller = AppController.inMemory();
    addTearDown(controller.dispose);
    await controller.initialize(defaultTimeZoneId: 'UTC');
    final now = DateTime.utc(2026, 8, 9, 12);
    const secrets = [
      '+37257633333',
      '8901000000000000000',
      'SECRET-MATCHING-ID',
      'private.operator.example',
    ];
    expect(
      await controller.saveSubscription(
        Subscription(
          id: 'private-profile-id',
          number: PhoneNumber(secrets[0]),
          operator: secrets[3],
          iccid: secrets[1],
          activation: LpaActivation(
            smdpAddress: 'rsp.private.example',
            matchingId: secrets[2],
          ),
          plan: Plan(),
          keepAlive: KeepAlive.notRequired(),
          timeZoneId: 'UTC',
          createdAt: now,
          updatedAt: now,
        ),
      ),
      isNull,
    );

    final source = utf8.decode(
      DiagnosticReportService.build(controller, generatedAtUtc: now),
    );
    final report = jsonDecode(source) as Map<String, dynamic>;
    final records = report['records'] as Map<String, dynamic>;
    final privacy = report['privacy'] as Map<String, dynamic>;

    expect(report['formatVersion'], DiagnosticReportService.formatVersion);
    expect(records['profiles'], 1);
    expect((records['profileStages'] as Map<String, dynamic>)['active'], 1);
    expect(privacy['containsIdentifiers'], isFalse);
    expect(privacy['containsCredentials'], isFalse);
    for (final secret in [
      ...secrets,
      'private-profile-id',
      'rsp.private.example',
    ]) {
      expect(source, isNot(contains(secret)));
    }
  });

  test('诊断报告拒绝非 UTC 生成时间', () async {
    final controller = AppController.inMemory();
    addTearDown(controller.dispose);
    await controller.initialize(defaultTimeZoneId: 'UTC');

    expect(
      () => DiagnosticReportService.build(
        controller,
        generatedAtUtc: DateTime(2026, 8, 9),
      ),
      throwsArgumentError,
    );
  });
}
