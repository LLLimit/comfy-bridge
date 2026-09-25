import 'dart:convert';

import 'package:web_socket_channel/web_socket_channel.dart';

import '../models/agent_settings.dart';

class AgentEventChannel {
  AgentEventChannel(this._settings);

  final AgentSettings _settings;
  WebSocketChannel? _channel;

  Stream<Map<String, dynamic>> connect() async* {
    final base = Uri.parse(_settings.baseUrl);
    final uri = base.replace(
      scheme: base.scheme == 'https' ? 'wss' : 'ws',
      path: '${base.path}/api/v1/events'.replaceAll('//', '/'),
      queryParameters: {'token': _settings.token},
    );
    final channel = WebSocketChannel.connect(uri);
    _channel = channel;
    await channel.ready;
    await for (final message in channel.stream) {
      final decoded = jsonDecode(message as String);
      if (decoded is Map<String, dynamic>) {
        yield decoded;
      }
    }
  }

  Future<void> close() async {
    await _channel?.sink.close();
    _channel = null;
  }
}
