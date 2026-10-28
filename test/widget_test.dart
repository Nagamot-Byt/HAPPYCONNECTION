import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:medlink_connect/main.dart';
import 'package:medlink_connect/core/injection.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await configureDependencies();
  });

  testWidgets('App renders MedLink Connect shell', (WidgetTester tester) async {
    await tester.pumpWidget(const MedLinkConnectApp());

    // Verify the app bar title is displayed.
    expect(find.text('MedLink Connect'), findsOneWidget);

    // Ensure the app renders without crashing.
    expect(find.byType(MaterialApp), findsOneWidget);
  });
}
