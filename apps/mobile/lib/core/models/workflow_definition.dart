class WorkflowOption {
  const WorkflowOption({required this.value, required this.label});

  final Object value;
  final String label;

  factory WorkflowOption.fromJson(Map<String, dynamic> json) {
    return WorkflowOption(
      value: json['value']!,
      label: json['label'] as String,
    );
  }
}

class WorkflowInput {
  const WorkflowInput({
    required this.key,
    required this.label,
    required this.valueType,
    required this.widget,
    required this.required,
    required this.advanced,
    required this.options,
    required this.constraints,
    this.description,
    this.defaultValue,
  });

  final String key;
  final String label;
  final String? description;
  final String valueType;
  final String widget;
  final bool required;
  final bool advanced;
  final Object? defaultValue;
  final List<WorkflowOption> options;
  final Map<String, dynamic> constraints;

  factory WorkflowInput.fromJson(Map<String, dynamic> json) {
    return WorkflowInput(
      key: json['key'] as String,
      label: json['label'] as String,
      description: json['description'] as String?,
      valueType: json['valueType'] as String,
      widget: json['widget'] as String,
      required: json['required'] as bool? ?? false,
      advanced: json['advanced'] as bool? ?? false,
      defaultValue: json['default'],
      options: (json['options'] as List<dynamic>? ?? const [])
          .map((item) => WorkflowOption.fromJson(item as Map<String, dynamic>))
          .toList(growable: false),
      constraints: Map<String, dynamic>.from(
        json['constraints'] as Map<String, dynamic>? ?? const {},
      ),
    );
  }
}

class WorkflowDefinition {
  const WorkflowDefinition({
    required this.id,
    required this.revision,
    required this.name,
    required this.description,
    required this.category,
    required this.submitLabel,
    required this.inputs,
    required this.outputTypes,
  });

  final String id;
  final int revision;
  final String name;
  final String description;
  final String category;
  final String submitLabel;
  final List<WorkflowInput> inputs;
  final List<String> outputTypes;

  factory WorkflowDefinition.fromJson(Map<String, dynamic> json) {
    final presentation = Map<String, dynamic>.from(
      json['presentation'] as Map<String, dynamic>? ?? const {},
    );
    return WorkflowDefinition(
      id: json['id'] as String,
      revision: json['revision'] as int,
      name: json['name'] as String,
      description: json['description'] as String? ?? '',
      category: json['category'] as String,
      submitLabel: presentation['submitLabel'] as String? ?? '开始生成',
      inputs: (json['inputs'] as List<dynamic>? ?? const [])
          .map((item) => WorkflowInput.fromJson(item as Map<String, dynamic>))
          .toList(growable: false),
      outputTypes: (json['outputTypes'] as List<dynamic>? ?? const [])
          .cast<String>(),
    );
  }
}
