import 'package:dio/dio.dart';

class AppException implements Exception {
  const AppException(
    this.message, {
    this.code = 'UNKNOWN',
    this.retryable = false,
  });

  final String code;
  final String message;
  final bool retryable;

  factory AppException.fromDio(DioException error) {
    final data = error.response?.data;
    if (data is Map<String, dynamic>) {
      final rawError = data['error'];
      if (rawError is Map<String, dynamic>) {
        return AppException(
          rawError['message'] as String? ?? '请求失败，请稍后重试。',
          code: rawError['code'] as String? ?? 'AGENT_ERROR',
          retryable: rawError['retryable'] as bool? ?? false,
        );
      }
    }
    if (error.type == DioExceptionType.connectionTimeout ||
        error.type == DioExceptionType.connectionError ||
        error.type == DioExceptionType.receiveTimeout) {
      return const AppException(
        '无法连接到 Windows Agent，请检查地址、网络和防火墙。',
        code: 'AGENT_OFFLINE',
        retryable: true,
      );
    }
    return const AppException('请求失败，请稍后重试。', code: 'NETWORK_ERROR');
  }

  @override
  String toString() => message;
}
