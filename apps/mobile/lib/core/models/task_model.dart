class TaskProgressModel {
  const TaskProgressModel({
    required this.stage,
    this.value,
    this.maximum,
    this.percent,
    this.indeterminate = false,
  });

  final String stage;
  final int? value;
  final int? maximum;
  final double? percent;
  final bool indeterminate;

  factory TaskProgressModel.fromJson(Map<String, dynamic> json) {
    return TaskProgressModel(
      stage: json['stage'] as String? ?? '等待中',
      value: json['value'] as int?,
      maximum: json['maximum'] as int?,
      percent: (json['percent'] as num?)?.toDouble(),
      indeterminate: json['indeterminate'] as bool? ?? false,
    );
  }
}

class TaskOutputModel {
  const TaskOutputModel({
    required this.id,
    required this.key,
    required this.mediaType,
    required this.mimeType,
    required this.fileName,
    required this.url,
    this.thumbnailUrl,
  });

  final String id;
  final String key;
  final String mediaType;
  final String mimeType;
  final String fileName;
  final String url;
  final String? thumbnailUrl;

  factory TaskOutputModel.fromJson(Map<String, dynamic> json) {
    return TaskOutputModel(
      id: json['id'] as String,
      key: json['key'] as String,
      mediaType: json['mediaType'] as String,
      mimeType: json['mimeType'] as String,
      fileName: json['fileName'] as String,
      url: json['url'] as String,
      thumbnailUrl: json['thumbnailUrl'] as String?,
    );
  }
}

class TaskErrorModel {
  const TaskErrorModel({required this.code, required this.message});

  final String code;
  final String message;

  factory TaskErrorModel.fromJson(Map<String, dynamic> json) {
    return TaskErrorModel(
      code: json['code'] as String? ?? 'UNKNOWN',
      message: json['message'] as String? ?? '任务失败',
    );
  }
}

class TaskModel {
  const TaskModel({
    required this.id,
    required this.workflowId,
    required this.workflowRevision,
    required this.workflowName,
    required this.category,
    required this.status,
    required this.progress,
    required this.createdAt,
    required this.updatedAt,
    required this.inputs,
    required this.outputs,
    this.promptId,
    this.completedAt,
    this.error,
  });

  final String id;
  final String workflowId;
  final int workflowRevision;
  final String workflowName;
  final String category;
  final String? promptId;
  final String status;
  final TaskProgressModel progress;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? completedAt;
  final Map<String, dynamic> inputs;
  final List<TaskOutputModel> outputs;
  final TaskErrorModel? error;

  bool get isActive => const {
    'pending',
    'uploading',
    'queued',
    'running',
    'processing',
  }.contains(status);

  bool get isCompleted => status == 'completed';

  factory TaskModel.fromJson(Map<String, dynamic> json) {
    return TaskModel(
      id: json['id'] as String,
      workflowId: json['workflowId'] as String,
      workflowRevision: json['workflowRevision'] as int,
      workflowName: json['workflowName'] as String,
      category: json['category'] as String,
      promptId: json['promptId'] as String?,
      status: json['status'] as String,
      progress: TaskProgressModel.fromJson(
        json['progress'] as Map<String, dynamic>,
      ),
      createdAt: DateTime.parse(json['createdAt'] as String),
      updatedAt: DateTime.parse(json['updatedAt'] as String),
      completedAt: json['completedAt'] == null
          ? null
          : DateTime.parse(json['completedAt'] as String),
      inputs: Map<String, dynamic>.from(
        json['inputs'] as Map<String, dynamic>? ?? const {},
      ),
      outputs: (json['outputs'] as List<dynamic>? ?? const [])
          .map((item) => TaskOutputModel.fromJson(item as Map<String, dynamic>))
          .toList(growable: false),
      error: json['error'] == null
          ? null
          : TaskErrorModel.fromJson(json['error'] as Map<String, dynamic>),
    );
  }
}
