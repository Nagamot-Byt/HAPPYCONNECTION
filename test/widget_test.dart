import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:medlink_connect/main.dart';
import 'package:medlink_connect/core/injection.dart';
import 'package:medlink_connect/core/theme_controller.dart';
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

  testWidgets('App switches the interface to English',
      (WidgetTester tester) async {
    tester.binding.platformDispatcher.localeTestValue = const Locale('en');
    addTearDown(tester.binding.platformDispatcher.clearLocaleTestValue);

    await tester.pumpWidget(const MedLinkConnectApp());

    expect(find.text('Refresh Networks'), findsOneWidget);
    expect(find.text('Connect Wi-Fi'), findsOneWidget);
    expect(find.text('Advanced Options'), findsOneWidget);
  });

  testWidgets('App switches and persists the dark theme',
      (WidgetTester tester) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('themeMode');
    final themeController = getIt<ThemeController>();
    themeController.setMode(ThemeMode.system);
    addTearDown(() => themeController.setMode(ThemeMode.system));

    await tester.pumpWidget(const MedLinkConnectApp());
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('theme-menu')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('theme-dark')));
    await tester.pumpAndSettle();

    final app = tester.widget<MaterialApp>(find.byType(MaterialApp));
    expect(app.themeMode, ThemeMode.dark);
    expect(prefs.getString('themeMode'), 'dark');
    expect(
      Theme.of(tester.element(find.byType(Scaffold))).brightness,
      Brightness.dark,
    );
  });
}
