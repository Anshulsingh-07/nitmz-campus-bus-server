import 'package:flutter_test/flutter_test.dart';
import 'package:campus_bus_tracker/main.dart';

void main() {
  testWidgets('App smoke test', (WidgetTester tester) async {
    await tester.pumpWidget(const CampusBusTrackerApp());
    expect(find.byType(CampusBusTrackerApp), findsOneWidget);
  });
}
