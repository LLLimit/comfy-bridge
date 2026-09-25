import 'package:comfy_bridge_mobile/app/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('theme can render the application title', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark(),
        home: const Scaffold(body: Center(child: Text('Comfy Bridge'))),
      ),
    );

    expect(find.text('Comfy Bridge'), findsOneWidget);
  });
}
