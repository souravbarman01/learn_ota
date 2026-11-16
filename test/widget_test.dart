import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:learn_ota/main.dart';

void main() {
  testWidgets('Home shows Hello Patch 1 button and OTA icon', (tester) async {
    await tester.pumpWidget(const MyApp());

    expect(find.widgetWithText(FilledButton, 'Hello Patch 1'), findsOneWidget);
    expect(find.byIcon(Icons.system_update), findsOneWidget);

    await tester.tap(find.byType(FilledButton));
    await tester.pump();
    expect(find.text('Hello Patch 1'), findsNWidgets(2)); // button + snackbar
  });
}
