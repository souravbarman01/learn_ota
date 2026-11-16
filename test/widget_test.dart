import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:learn_ota/main.dart';

void main() {
  testWidgets('Home shows Hello Patch 1 & 2 buttons and OTA icon', (
    tester,
  ) async {
    await tester.pumpWidget(const MyApp());

    expect(find.widgetWithText(FilledButton, 'Hello Patch 1'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, 'Hello Patch 2'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, 'Hello Patch 3'), findsOneWidget);
    expect(find.byIcon(Icons.system_update), findsOneWidget);

    await tester.tap(find.widgetWithText(FilledButton, 'Hello Patch 2'));
    await tester.pump();
    expect(find.text('Hello Patch 2'), findsNWidgets(2)); // button + snackbar
  });
}
