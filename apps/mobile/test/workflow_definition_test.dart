import 'package:comfy_bridge_mobile/core/models/workflow_definition.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('parses a server-driven workflow without private mappings', () {
    final workflow = WorkflowDefinition.fromJson({
      'id': 'demo_image',
      'revision': 1,
      'name': '演示图片生成',
      'description': 'demo',
      'category': 'image',
      'presentation': {'submitLabel': '生成图片'},
      'inputs': [
        {
          'key': 'prompt',
          'label': '提示词',
          'valueType': 'string',
          'widget': 'textarea',
          'required': true,
          'advanced': false,
          'default': 'hello',
          'options': <Object>[],
          'constraints': {'maxLength': 4000},
        },
      ],
      'outputTypes': ['image'],
    });

    expect(workflow.id, 'demo_image');
    expect(workflow.inputs.single.widget, 'textarea');
    expect(workflow.inputs.single.defaultValue, 'hello');
  });
}
