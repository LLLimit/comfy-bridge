class AgentSettings {
  const AgentSettings({this.baseUrl = '', this.token = ''});

  final String baseUrl;
  final String token;

  bool get isConfigured => baseUrl.trim().isNotEmpty && token.trim().isNotEmpty;

  AgentSettings copyWith({String? baseUrl, String? token}) {
    return AgentSettings(
      baseUrl: baseUrl ?? this.baseUrl,
      token: token ?? this.token,
    );
  }
}
