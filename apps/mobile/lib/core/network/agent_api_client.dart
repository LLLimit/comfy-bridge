import 'dart:typed_data';

import 'package:dio/dio.dart';

import '../errors/app_exception.dart';
import '../models/agent_settings.dart';
import '../models/agent_status.dart';
import '../models/task_model.dart';
import '../models/workflow_definition.dart';

class AgentApiClient {
  AgentApiClient(AgentSettings settings)
    : _settings = settings,
      _dio = Dio(
        BaseOptions(
          baseUrl: settings.baseUrl,
          connectTimeout: const Duration(seconds: 5),
          receiveTimeout: const Duration(seconds: 20),
          headers: {'Authorization': 'Bearer ${settings.token}'},
        ),
      );

  final AgentSettings _settings;
  final Dio _dio;

  Future<AgentStatusModel> getStatus() async {
    return _guard(() async {
      final response = await _dio.get<Map<String, dynamic>>('/api/v1/status');
      return AgentStatusModel.fromJson(response.data!);
    });
  }

  Future<List<WorkflowDefinition>> getWorkflows() async {
    return _guard(() async {
      final response = await _dio.get<Map<String, dynamic>>(
        '/api/v1/workflows',
      );
      final items = response.data?['items'] as List<dynamic>? ?? const [];
      return items
          .map(
            (item) => WorkflowDefinition.fromJson(item as Map<String, dynamic>),
          )
          .where((item) => item.id != 'demo_image')
          .toList(growable: false);
    });
  }

  Future<List<TaskModel>> getTasks() async {
    return _guard(() async {
      final response = await _dio.get<Map<String, dynamic>>('/api/v1/tasks');
      final items = response.data?['items'] as List<dynamic>? ?? const [];
      return items
          .map((item) => TaskModel.fromJson(item as Map<String, dynamic>))
          .toList(growable: false);
    });
  }

  Future<List<String>> getLogs() async {
    return _guard(() async {
      final response = await _dio.get<Map<String, dynamic>>(
        '/api/v1/logs',
        queryParameters: {'limit': 200},
      );
      final items = response.data?['items'] as List<dynamic>? ?? const [];
      return items.map((item) => item.toString()).toList(growable: false);
    });
  }

  Future<String> uploadAsset({
    required String path,
    required String fileName,
  }) async {
    return _guard(() async {
      final mediaType = _mediaType(fileName);
      final form = FormData.fromMap({
        'file': await MultipartFile.fromFile(
          path,
          filename: fileName,
          contentType: DioMediaType.parse(mediaType),
        ),
      });
      final response = await _dio.post<Map<String, dynamic>>(
        '/api/v1/assets',
        data: form,
      );
      return response.data!['id'] as String;
    });
  }

  Future<TaskModel> createTask({
    required WorkflowDefinition workflow,
    required String clientRequestId,
    required Map<String, dynamic> inputs,
  }) async {
    return _guard(() async {
      final response = await _dio.post<Map<String, dynamic>>(
        '/api/v1/tasks',
        data: {
          'clientRequestId': clientRequestId,
          'workflowId': workflow.id,
          'workflowRevision': workflow.revision,
          'inputs': inputs,
        },
      );
      return TaskModel.fromJson(response.data!);
    });
  }

  Future<Uint8List> downloadMedia(TaskOutputModel output) async {
    return _guard(() async {
      final response = await _dio.get<List<int>>(
        output.url,
        options: Options(
          responseType: ResponseType.bytes,
          receiveTimeout: const Duration(minutes: 30),
        ),
      );
      return Uint8List.fromList(response.data ?? const []);
    });
  }

  Future<void> downloadMediaToFile(
    TaskOutputModel output,
    String destinationPath,
  ) async {
    await _guard(() async {
      await _dio.download(
        output.url,
        destinationPath,
        deleteOnError: true,
        options: Options(receiveTimeout: const Duration(minutes: 30)),
      );
    });
  }

  Future<void> deleteMedia(String mediaId) async {
    await _guard(() async {
      await _dio.delete<void>('/api/v1/media/$mediaId');
    });
  }

  Future<void> deleteTask(String taskId) async {
    await _guard(() async {
      await _dio.delete<void>('/api/v1/tasks/$taskId');
    });
  }

  Uri absoluteMediaUri(String relativeUrl) {
    return Uri.parse(_settings.baseUrl).resolve(relativeUrl);
  }

  Map<String, String> get mediaHeaders => {
    'Authorization': 'Bearer ${_settings.token}',
  };

  Future<T> _guard<T>(Future<T> Function() request) async {
    try {
      return await request();
    } on DioException catch (error) {
      throw AppException.fromDio(error);
    }
  }

  static String _mediaType(String fileName) {
    final lower = fileName.toLowerCase();
    if (lower.endsWith('.png')) return 'image/png';
    if (lower.endsWith('.webp')) return 'image/webp';
    if (lower.endsWith('.jpg') || lower.endsWith('.jpeg')) return 'image/jpeg';
    if (lower.endsWith('.mp3')) return 'audio/mpeg';
    if (lower.endsWith('.wav')) return 'audio/wav';
    if (lower.endsWith('.m4a') || lower.endsWith('.mp4')) return 'audio/mp4';
    if (lower.endsWith('.flac')) return 'audio/flac';
    if (lower.endsWith('.ogg')) return 'audio/ogg';
    return 'image/jpeg';
  }
}
