import 'package:flutter_test/flutter_test.dart';
import 'package:wasel/main.dart';

void main() {
  testWidgets('shows backend setup guidance before configuration', (tester) async {
    await tester.pumpWidget(const WaselApp(configured: false));
    expect(find.text('واصل'), findsOneWidget);
    expect(find.textContaining('اربط مشروع Supabase'), findsOneWidget);
  });
}
