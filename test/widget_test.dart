import 'package:flutter_test/flutter_test.dart';

import 'package:chat_app/main.dart';

void main() {
  testWidgets('Hermes Chat App smoke test', (WidgetTester tester) async {
    await tester.pumpWidget(const HermesChatApp());
    expect(find.text('Hermes Chat'), findsOneWidget);
    expect(find.text('History'), findsOneWidget);
    expect(find.text('Settings'), findsOneWidget);
  });
}
