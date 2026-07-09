import 'package:flutter_test/flutter_test.dart';

import 'package:azile_mdm_ui/main.dart';

void main() {
  testWidgets('App renders without crashing', (WidgetTester tester) async {
    await tester.pumpWidget(const AzileMdmApp());
    expect(find.byType(AzileMdmApp), findsOneWidget);
  });
}
