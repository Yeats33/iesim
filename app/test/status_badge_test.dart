import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iesim/widgets/status_badge.dart';
import 'package:iesim_core/iesim_core.dart';

void main() {
  testWidgets('推测的临期状态显示问号提示', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: StatusBadge(status: DueSoon(daysLeft: 3, inferred: true)),
        ),
      ),
    );

    expect(find.text('3 天后截止'), findsOneWidget);
    expect(find.byIcon(Icons.help_outline_rounded), findsOneWidget);
  });

  testWidgets('未知状态不会显示为安全', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: StatusBadge(status: Unknown())),
      ),
    );

    expect(find.text('状态未知'), findsOneWidget);
    expect(find.textContaining('安全'), findsNothing);
  });
}
