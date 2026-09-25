import 'package:comfy_bridge_mobile/app/agent_controller.dart';
import 'package:comfy_bridge_mobile/core/models/agent_settings.dart';
import 'package:comfy_bridge_mobile/features/generate/generate_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class _OfflineAgentController extends AgentController {
  @override
  AgentState build() => const AgentState(
    settings: AgentSettings(
      baseUrl: 'http://192.168.1.20:8787',
      token: 'test-token',
    ),
    initializing: false,
    errorMessage: '无法连接到 Windows Agent，请检查地址、网络和防火墙。',
  );

  @override
  Future<void> refresh({bool throwOnFailure = false}) async {}
}

void main() {
  testWidgets(
    'offline generation page keeps normal UI without empty segments',
    (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            agentControllerProvider.overrideWith(_OfflineAgentController.new),
          ],
          child: const MaterialApp(home: Scaffold(body: GeneratePage())),
        ),
      );

      await tester.pump();

      expect(tester.takeException(), isNull);
      expect(find.text('Comfy Bridge'), findsOneWidget);
      final title = tester.widget<Text>(find.text('Comfy Bridge'));
      expect(title.style?.color, Colors.white);
      expect(
        find.byWidgetPredicate(
          (widget) =>
              widget is Container &&
              widget.decoration is BoxDecoration &&
              (widget.decoration! as BoxDecoration).color == Colors.black,
        ),
        findsOneWidget,
      );
      expect(find.text('暂时无法读取生成工作流'), findsOneWidget);
      expect(find.text('重新连接'), findsOneWidget);
      expect(find.text('错误/日志'), findsOneWidget);
      expect(find.byType(SegmentedButton<String>), findsNothing);
    },
  );
}
