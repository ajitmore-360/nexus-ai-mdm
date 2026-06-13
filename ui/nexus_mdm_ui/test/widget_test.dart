import 'package:flutter_test/flutter_test.dart';

import 'package:nexus_mdm_ui/main.dart';

void main() {
  testWidgets('App renders without crashing', (WidgetTester tester) async {
    await tester.pumpWidget(const NexusMdmApp());
    expect(find.byType(NexusMdmApp), findsOneWidget);
  });
}
