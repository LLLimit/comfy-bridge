import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/agent_controller.dart';
import '../../core/errors/app_exception.dart';
import '../../core/models/agent_settings.dart';
import 'diagnostics_page.dart';

class SettingsPage extends ConsumerStatefulWidget {
  const SettingsPage({super.key});

  @override
  ConsumerState<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends ConsumerState<SettingsPage> {
  final _formKey = GlobalKey<FormState>();
  final _urlController = TextEditingController();
  final _tokenController = TextEditingController();
  bool _hydrated = false;
  bool _saving = false;
  bool _obscureToken = true;

  @override
  void dispose() {
    _urlController.dispose();
    _tokenController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(agentControllerProvider);
    if (!_hydrated && !state.initializing) {
      _hydrated = true;
      _urlController.text = state.settings.baseUrl;
      _tokenController.text = state.settings.token;
    }
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 120),
      children: [
        Text(
          '连接设置',
          style: Theme.of(context).textTheme.headlineSmall
              ?.copyWith(fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 8),
        Text(
          '支持局域网 IP、公网 IP 或域名。这里填写 Windows Agent 地址，不要填写 ComfyUI 的 8188 地址。',
          style: TextStyle(color: Theme.of(context).colorScheme.outline),
        ),
        const SizedBox(height: 20),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  TextFormField(
                    controller: _urlController,
                    keyboardType: TextInputType.url,
                    autocorrect: false,
                    decoration: const InputDecoration(
                      labelText: 'Windows Agent 地址',
                      hintText: 'http://192.168.1.20:8787 或 http://你的域名:18188',
                      prefixIcon: Icon(Icons.computer),
                    ),
                    onChanged: (_) => setState(() {}),
                    validator: (value) => value == null || value.trim().isEmpty
                        ? '请输入 Agent 地址'
                        : null,
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _tokenController,
                    obscureText: _obscureToken,
                    autocorrect: false,
                    enableSuggestions: false,
                    decoration: InputDecoration(
                      labelText: '设备 Token',
                      prefixIcon: const Icon(Icons.key_outlined),
                      suffixIcon: IconButton(
                        onPressed: () =>
                            setState(() => _obscureToken = !_obscureToken),
                        icon: Icon(
                          _obscureToken
                              ? Icons.visibility
                              : Icons.visibility_off,
                        ),
                      ),
                    ),
                    validator: (value) => value == null || value.trim().isEmpty
                        ? '请输入设备 Token'
                        : null,
                    onChanged: (_) => setState(() {}),
                  ),
                  const SizedBox(height: 20),
                  FilledButton.icon(
                    onPressed: _saving ? null : _saveAndTest,
                    icon: _saving
                        ? const SizedBox.square(
                            dimension: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : Icon(
                            _isConnected(state)
                                ? Icons.check_circle_outline
                                : Icons.link,
                          ),
                    label: Text(
                      _saving
                          ? '正在连接…'
                          : _isConnected(state)
                          ? '已连接'
                          : '连接',
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(height: 20),
        Text('连接状态', style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 12),
        _StatusCard(state: state),
        const SizedBox(height: 12),
        OutlinedButton.icon(
          onPressed: () => Navigator.of(context).push(
            MaterialPageRoute<void>(builder: (_) => const DiagnosticsPage()),
          ),
          icon: const Icon(Icons.article_outlined),
          label: const Text('查看连接错误与软件日志'),
        ),
        const SizedBox(height: 16),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.security_outlined),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'FRP TCP 模式请填写 http://域名:远程端口；公网长期使用建议在服务器增加 HTTPS/WSS 反向代理，避免 Token 明文传输。',
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _saveAndTest() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    try {
      await ref
          .read(agentControllerProvider.notifier)
          .saveSettings(
            AgentSettings(
              baseUrl: _urlController.text,
              token: _tokenController.text,
            ),
          );
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('连接成功，工作流已同步。')));
    } on AppException catch (_) {
      // HomeShell displays a connection dialog with a diagnostics link.
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  bool _isConnected(AgentState state) {
    String normalize(String value) =>
        value.trim().replaceFirst(RegExp(r'/+$'), '');
    return state.status?.agentOnline == true &&
        normalize(_urlController.text) == normalize(state.settings.baseUrl) &&
        _tokenController.text.trim() == state.settings.token;
  }
}

class _StatusCard extends StatelessWidget {
  const _StatusCard({required this.state});

  final AgentState state;

  @override
  Widget build(BuildContext context) {
    final status = state.status;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          children: [
            _StatusRow(
              label: '电脑 Agent',
              value: status?.agentOnline == true
                  ? '在线 · v${status!.agentVersion}'
                  : '离线',
              online: status?.agentOnline == true,
            ),
            const Divider(height: 26),
            _StatusRow(
              label: 'ComfyUI',
              value: status?.comfyOnline == true ? '已连接' : '未连接',
              online: status?.comfyOnline == true,
            ),
            const Divider(height: 26),
            _StatusRow(
              label: '实时通道',
              value: state.liveConnected ? '已连接' : '等待连接',
              online: state.liveConnected,
            ),
            const Divider(height: 26),
            _StatusRow(
              label: 'GPU',
              value: status?.gpuName ?? '等待 ComfyUI 上报',
              online: status?.gpuName != null,
            ),
            const Divider(height: 26),
            _StatusRow(
              label: '运行任务',
              value: '${status?.activeTasks ?? 0} 个',
              online: true,
            ),
          ],
        ),
      ),
    );
  }
}

class _StatusRow extends StatelessWidget {
  const _StatusRow({
    required this.label,
    required this.value,
    required this.online,
  });

  final String label;
  final String value;
  final bool online;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(
          Icons.circle,
          size: 10,
          color: online ? Colors.greenAccent : Colors.grey,
        ),
        const SizedBox(width: 10),
        SizedBox(width: 92, child: Text(label)),
        Expanded(
          child: Text(
            value,
            textAlign: TextAlign.end,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }
}
