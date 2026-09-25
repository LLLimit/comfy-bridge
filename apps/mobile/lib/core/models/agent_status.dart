class AgentStatusModel {
  const AgentStatusModel({
    required this.agentOnline,
    required this.agentVersion,
    required this.comfyOnline,
    required this.comfyUrl,
    required this.activeTasks,
    this.gpuName,
  });

  final bool agentOnline;
  final String agentVersion;
  final bool comfyOnline;
  final String comfyUrl;
  final int activeTasks;
  final String? gpuName;

  factory AgentStatusModel.fromJson(Map<String, dynamic> json) {
    final agent = Map<String, dynamic>.from(json['agent'] as Map);
    final comfy = Map<String, dynamic>.from(json['comfyUi'] as Map);
    final rawGpu = json['gpu'];
    final gpu = rawGpu is Map ? Map<String, dynamic>.from(rawGpu) : null;
    return AgentStatusModel(
      agentOnline: agent['online'] as bool? ?? false,
      agentVersion: agent['version'] as String? ?? '未知',
      comfyOnline: comfy['online'] as bool? ?? false,
      comfyUrl: comfy['url'] as String? ?? '',
      activeTasks: json['activeTasks'] as int? ?? 0,
      gpuName: gpu?['name'] as String? ?? gpu?['device_name'] as String?,
    );
  }
}
