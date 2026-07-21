import 'package:flutter_test/flutter_test.dart';

import 'package:medlink_connect/main.dart';

void main() {
  testWidgets('App renders MedLink Connect shell', (WidgetTester tester) async {
    await tester.pumpWidget(const MedLinkConnectApp());

    // Verify the app bar title is displayed.
    expect(find.text('MedLink Connect'), findsOneWidget);

    // Verify the Connect button is present.
    expect(find.text('Connect'), findsOneWidget);
  });
}
