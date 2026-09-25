import 'package:comfy_bridge_mobile/core/models/workflow_definition.dart';
import 'package:comfy_bridge_mobile/features/generate/dynamic_workflow_form.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('renders fields from the workflow manifest', (tester) async {
    const workflow = WorkflowDefinition(
      id: 'test',
      revision: 1,
      name: '测试工作流',
      description: '',
      category: 'image',
      submitLabel: '开始测试',
      outputTypes: ['image'],
      inputs: [
        WorkflowInput(
          key: 'prompt',
          label: '提示词',
          valueType: 'string',
          widget: 'textarea',
          required: true,
          advanced: false,
          options: [],
          constraints: {},
        ),
        WorkflowInput(
          key: 'style',
          label: '风格',
          valueType: 'string',
          widget: 'chips',
          required: true,
          advanced: false,
          defaultValue: 'photo',
          options: [WorkflowOption(value: 'photo', label: '摄影')],
          constraints: {},
        ),
      ],
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: DynamicWorkflowForm(
              workflow: workflow,
              submitting: false,
              onSubmit: (_, _) async {},
            ),
          ),
        ),
      ),
    );

    expect(find.text('提示词'), findsWidgets);
    expect(find.text('摄影'), findsOneWidget);
    expect(find.text('开始测试'), findsOneWidget);
  });
}
