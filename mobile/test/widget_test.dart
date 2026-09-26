import 'package:flutter_test/flutter_test.dart';

import 'package:solray/main.dart';

void main() {
  testWidgets('fresh install shows the onboarding (server address) screen', (tester) async {
    await tester.pumpWidget(const MyTeamApp());
    await tester.pumpAndSettle();
    expect(find.text('My Team'), findsOneWidget);
    expect(find.text('Poveži se'), findsOneWidget);
  });
}
