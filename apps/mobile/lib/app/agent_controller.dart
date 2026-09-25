import 'dart:async';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:saver_gallery/saver_gallery.dart';
import 'package:uuid/uuid.dart';

import '../core/errors/app_exception.dart';
import '../core/models/agent_settings.dart';
import '../core/models/agent_status.dart';
import '../core/models/task_model.dart';
import '../core/models/workflow_definition.dart';
import '../core/network/agent_api_client.dart';
import '../core/network/agent_event_channel.dart';
import '../core/storage/settings_repository.dart';

const _unset = Object();

class AgentState {
  const AgentState({
    this.settings = const AgentSettings(),
    this.workflows = const [],
    this.tasks = const [],
    this.logs = const [],
    this.status,
    this.initializing = true,
    this.refreshing = false,
    this.submitting = false,
    this.liveConnected = false,
    this.errorMessage,
  });

  final AgentSettings settings;
  final List<WorkflowDefinition> workflows;
  final List<TaskModel> tasks;
  final List<String> logs;
  final AgentStatusModel? status;
  final bool initializing;
  final bool refreshing;
  final bool submitting;
  final bool liveConnected;
  final String? errorMessage;

  bool get isConfigured => settings.isConfigured;

  AgentState copyWith({
    AgentSettings? settings,
    List<WorkflowDefinition>? workflows,
    List<TaskModel>? tasks,
    List<String>? logs,
    Object? status = _unset,
    bool? initializing,
    bool? refreshing,
    bool? submitting,
    bool? liveConnected,
    Object? errorMessage = _unset,
  }) {
    return AgentState(
      settings: settings ?? this.settings,
      workflows: workflows ?? this.workflows,
      tasks: tasks ?? this.tasks,
      logs: logs ?? this.logs,
      status: identical(status, _unset)
          ? this.status
          : status as AgentStatusModel?,
      initializing: initializing ?? this.initializing,
      refreshing: refreshing ?? this.refreshing,
      submitting: submitting ?? this.submitting,
      liveConnected: liveConnected ?? this.liveConnected,
      errorMessage: identical(errorMessage, _unset)
          ? this.errorMessage
          : errorMessage as String?,
    );
  }
}

final agentControllerProvider = NotifierProvider<AgentController, AgentState>(
  AgentController.new,
);

class AgentController extends Notifier<AgentState> {
  late final SettingsRepository _settingsRepository;
  AgentApiClient? _client;
  AgentEventChannel? _eventChannel;
  StreamSubscription<Map<String, dynamic>>? _eventSubscription;
  Timer? _reconnectTimer;
  int _lastSequence = -1;

  @override
  AgentState build() {
    _settingsRepository = SettingsRepository();
    ref.onDispose(() {
      _reconnectTimer?.cancel();
      _eventSubscription?.cancel();
      _eventChannel?.close();
    });
    Future<void>.microtask(_initialize);
    return const AgentState();
  }

  Future<void> _initialize() async {
    _log('应用已启动。');
    try {
      final settings = await _settingsRepository.load();
      state = state.copyWith(settings: settings, initializing: false);
      _log(settings.isConfigured ? '已读取 Agent 连接设置。' : '尚未配置 Agent。');
      if (settings.isConfigured) {
        await _configureClient(settings);
        await refresh();
      }
    } catch (error) {
      final message = '读取本地设置失败：$error';
      _log(message);
      state = state.copyWith(initializing: false, errorMessage: message);
    }
  }

  Future<void> saveSettings(AgentSettings settings) async {
    final uri = Uri.tryParse(settings.baseUrl.trim());
    if (uri == null ||
        !{'http', 'https'}.contains(uri.scheme) ||
        uri.host.isEmpty) {
      throw const AppException(
        '请输入完整的 Agent 地址，可使用局域网 IP、公网 IP 或域名，例如 http://192.168.1.20:8787 或 https://agent.example.com。',
      );
    }
    if (settings.token.trim().isEmpty) {
      throw const AppException('请输入 Agent 显示的设备 Token。');
    }
    final normalized = AgentSettings(
      baseUrl: settings.baseUrl.trim().replaceFirst(RegExp(r'/+$'), ''),
      token: settings.token.trim(),
    );
    await _settingsRepository.save(normalized);
    state = state.copyWith(
      settings: normalized,
      workflows: const [],
      tasks: const [],
      status: null,
      errorMessage: null,
    );
    _log('已保存 Agent 地址：${normalized.baseUrl}');
    await _configureClient(normalized);
    await refresh(throwOnFailure: true);
  }

  Future<void> _configureClient(AgentSettings settings) async {
    _reconnectTimer?.cancel();
    await _eventSubscription?.cancel();
    await _eventChannel?.close();
    _lastSequence = -1;
    _client = AgentApiClient(settings);
    _eventChannel = AgentEventChannel(settings);
    _connectEvents();
  }

  Future<void> refresh({bool throwOnFailure = false}) async {
    final client = _client;
    if (client == null) return;
    _log('正在连接 ${state.settings.baseUrl}');
    state = state.copyWith(refreshing: true, errorMessage: null);
    try {
      final status = await client.getStatus();
      state = state.copyWith(status: status);
      final workflows = await client.getWorkflows();
      final tasks = await client.getTasks();
      state = state.copyWith(
        status: status,
        workflows: workflows,
        tasks: tasks,
        refreshing: false,
      );
      _log(
        '连接成功：${workflows.length} 个工作流，'
        'ComfyUI ${status.comfyOnline ? '在线' : '离线'}。',
      );
    } on AppException catch (error) {
      _log('连接失败 [${error.code}]：${error.message}');
      state = state.copyWith(refreshing: false, errorMessage: error.message);
      if (throwOnFailure) rethrow;
    }
  }

  Future<TaskModel> submitTask({
    required WorkflowDefinition workflow,
    required Map<String, dynamic> values,
    required Map<String, XFile> assets,
  }) async {
    final client = _client;
    if (client == null) {
      throw const AppException('请先在设置中连接 Windows Agent。');
    }
    state = state.copyWith(submitting: true, errorMessage: null);
    try {
      final resolvedValues = Map<String, dynamic>.from(values);
      for (final entry in assets.entries) {
        resolvedValues[entry.key] = await client.uploadAsset(
          path: entry.value.path,
          fileName: entry.value.name,
        );
      }
      final task = await client.createTask(
        workflow: workflow,
        clientRequestId: const Uuid().v4(),
        inputs: resolvedValues,
      );
      _mergeTask(task);
      state = state.copyWith(submitting: false);
      return task;
    } on AppException catch (error) {
      _log('任务提交失败 [${error.code}]：${error.message}');
      state = state.copyWith(submitting: false, errorMessage: error.message);
      rethrow;
    }
  }

  Uri mediaUri(TaskOutputModel output) {
    final client = _client;
    if (client == null) return Uri();
    return client.absoluteMediaUri(output.url);
  }

  Map<String, String> get mediaHeaders => _client?.mediaHeaders ?? const {};

  Future<void> saveOutputToPhone(TaskOutputModel output) async {
    final client = _client;
    if (client == null) {
      throw const AppException('请先连接 Windows Agent。');
    }
    final extension = _safeExtension(output.fileName, output.mediaType);
    final fileName =
        'ComfyBridge_${DateTime.now().millisecondsSinceEpoch}$extension';
    if (output.mediaType == 'image') {
      final bytes = await client.downloadMedia(output);
      if (bytes.isEmpty) {
        throw const AppException('作品文件为空，无法保存。');
      }
      final result = await SaverGallery.saveImage(
        bytes,
        fileName: fileName,
        albumPath: 'Comfy Bridge',
        skipIfExists: false,
      );
      if (!result.isSuccess) {
        throw AppException(result.errorMessage ?? '保存图片失败。');
      }
    } else {
      final directory = await getTemporaryDirectory();
      final path = '${directory.path}${Platform.pathSeparator}$fileName';
      final file = File(path);
      try {
        await client.downloadMediaToFile(output, path);
        if (!await file.exists() || await file.length() == 0) {
          throw const AppException('作品文件为空，无法保存。');
        }
        final result = await SaverGallery.saveFile(
          filePath: path,
          fileName: fileName,
          albumPath: 'Comfy Bridge',
          skipIfExists: false,
        );
        if (!result.isSuccess) {
          throw AppException(result.errorMessage ?? '保存视频失败。');
        }
      } finally {
        await file.delete().catchError((_) => file);
      }
    }
    _log('作品已保存到手机相册：$fileName');
  }

  Future<void> deleteOutput(TaskOutputModel output) async {
    final client = _client;
    if (client == null) {
      throw const AppException('请先连接 Windows Agent。');
    }
    await client.deleteMedia(output.id);
    final tasks = await client.getTasks();
    state = state.copyWith(tasks: tasks);
    _log('已删除作品：${output.fileName}');
  }

  Future<void> deleteOutputs(Iterable<TaskOutputModel> outputs) async {
    for (final output in outputs) {
      await deleteOutput(output);
    }
  }

  Future<void> deleteTasks(Iterable<String> taskIds) async {
    final client = _client;
    if (client == null) {
      throw const AppException('请先连接 Windows Agent。');
    }
    final ids = taskIds.toSet();
    state = state.copyWith(
      tasks: state.tasks.where((task) => !ids.contains(task.id)).toList(),
    );
    try {
      for (final id in ids) {
        await client.deleteTask(id);
      }
    } catch (_) {
      await refresh();
      rethrow;
    }
    _log('已删除 ${ids.length} 个任务。');
  }

  Future<List<String>> fetchAgentLogs() async {
    final client = _client;
    if (client == null) return const [];
    try {
      return await client.getLogs();
    } on AppException catch (error) {
      _log('读取 Agent 日志失败 [${error.code}]：${error.message}');
      return const [];
    }
  }

  void clearError() {
    state = state.copyWith(errorMessage: null);
  }

  void _connectEvents() {
    final channel = _eventChannel;
    if (channel == null) return;
    _eventSubscription = channel.connect().listen(
      _handleEvent,
      onError: (Object error, StackTrace stackTrace) {
        _log('实时通道错误：$error');
        _scheduleReconnect();
      },
      onDone: () {
        _log('实时通道已断开，3 秒后重连。');
        _scheduleReconnect();
      },
    );
  }

  void _scheduleReconnect() {
    if (!ref.mounted || !state.isConfigured) return;
    state = state.copyWith(liveConnected: false);
    _reconnectTimer?.cancel();
    _reconnectTimer = Timer(const Duration(seconds: 3), () {
      if (!ref.mounted) return;
      _eventChannel?.close();
      _eventChannel = AgentEventChannel(state.settings);
      _connectEvents();
    });
  }

  void _handleEvent(Map<String, dynamic> event) {
    final sequence = event['sequence'] as int? ?? 0;
    if (sequence > 0 && sequence <= _lastSequence) return;
    if (sequence > 0) _lastSequence = sequence;
    final type = event['type'] as String?;
    final payload = event['payload'];
    if (type == 'task.deleted' && payload is Map<String, dynamic>) {
      final taskId = payload['id'] as String?;
      if (taskId != null) {
        state = state.copyWith(
          liveConnected: true,
          tasks: state.tasks.where((task) => task.id != taskId).toList(),
        );
      }
      return;
    }
    if (type == 'agent.snapshot' && payload is Map<String, dynamic>) {
      final items = payload['tasks'] as List<dynamic>? ?? const [];
      state = state.copyWith(
        liveConnected: true,
        tasks: items
            .map((item) => TaskModel.fromJson(item as Map<String, dynamic>))
            .toList(growable: false),
      );
      return;
    }
    if (type?.startsWith('task.') == true && payload is Map<String, dynamic>) {
      _mergeTask(TaskModel.fromJson(payload));
      state = state.copyWith(liveConnected: true);
    }
  }

  void _log(String message) {
    if (!ref.mounted) return;
    final entry = '${DateTime.now().toIso8601String()}  $message';
    final logs = [...state.logs, entry];
    if (logs.length > 200) {
      logs.removeRange(0, logs.length - 200);
    }
    state = state.copyWith(logs: List.unmodifiable(logs));
  }

  void _mergeTask(TaskModel task) {
    final tasks = [...state.tasks];
    final index = tasks.indexWhere((item) => item.id == task.id);
    if (index == -1) {
      tasks.add(task);
    } else {
      tasks[index] = task;
    }
    tasks.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    state = state.copyWith(tasks: tasks);
  }

  static String _safeExtension(String fileName, String mediaType) {
    final match = RegExp(r'\.[A-Za-z0-9]{2,5}$').firstMatch(fileName);
    if (match != null) return match.group(0)!.toLowerCase();
    return mediaType == 'image' ? '.png' : '.mp4';
  }
}
