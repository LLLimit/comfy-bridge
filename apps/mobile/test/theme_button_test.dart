import 'package:comfy_bridge_mobile/app/agent_controller.dart';
import 'package:comfy_bridge_mobile/app/home_shell.dart';
import 'package:comfy_bridge_mobile/core/models/agent_settings.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _OfflineAgentController extends AgentController {
  @override
  AgentState build() => const AgentState(
    settings: AgentSettings(baseUrl: '', token: ''),
    initializing: false,
  );

  @override
  Future<void> refresh({bool throwOnFailure = false}) async {}
}

void main() {
  testWidgets('settings app bar toggles sun and moon without a settings card', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          agentControllerProvider.overrideWith(_OfflineAgentController.new),
        ],
        child: const MaterialApp(home: HomeShell()),
      ),
    );
    await tester.pump();

    await tester.tap(find.text('设置'));
    await tester.pumpAndSettle();

    expect(find.byIcon(Icons.dark_mode_rounded), findsOneWidget);
    expect(find.text('白色简约主题'), findsNothing);

    await tester.tap(find.byIcon(Icons.dark_mode_rounded));
    await tester.pumpAndSettle();

    expect(find.byIcon(Icons.light_mode_rounded), findsOneWidget);
  });
}
