import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/agent_controller.dart';

class DiagnosticsPage extends ConsumerStatefulWidget {
  const DiagnosticsPage({super.key});

  @override
  ConsumerState<DiagnosticsPage> createState() => _DiagnosticsPageState();
}

class _DiagnosticsPageState extends ConsumerState<DiagnosticsPage> {
  List<String> _agentLogs = const [];
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    Future<void>.microtask(_loadAgentLogs);
  }

  Future<void> _loadAgentLogs() async {
    setState(() => _loading = true);
    final logs = await ref
        .read(agentControllerProvider.notifier)
        .fetchAgentLogs();
    if (!mounted) return;
    setState(() {
      _agentLogs = logs;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(agentControllerProvider);
    final status = state.status;
    return Scaffold(
      appBar: AppBar(
        title: const Text('连接诊断与日志'),
        actions: [
          IconButton(
            tooltip: '刷新',
            onPressed: _loading
                ? null
                : () async {
                    await ref.read(agentControllerProvider.notifier).refresh();
                    await _loadAgentLogs();
                  },
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 40),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(18),
              child: Column(
                children: [
                  _StatusLine(label: 'Agent 地址', value: state.settings.baseUrl),
                  const Divider(height: 26),
                  _StatusLine(
                    label: '电脑 Agent',
                    value: status?.agentOnline == true ? '在线' : '离线',
                    online: status?.agentOnline == true,
                  ),
                  const Divider(height: 26),
                  _StatusLine(
                    label: 'ComfyUI',
                    value: status?.comfyOnline == true ? '已连接' : '未连接',
                    online: status?.comfyOnline == true,
                  ),
                  const Divider(height: 26),
                  _StatusLine(
                    label: '实时通道',
                    value: state.liveConnected ? '已连接' : '未连接',
                    online: state.liveConnected,
                  ),
                ],
              ),
            ),
          ),
          if (state.errorMessage != null) ...[
            const SizedBox(height: 16),
            Card(
              color: Theme.of(context).colorScheme.errorContainer,
              child: Padding(
                padding: const EdgeInsets.all(18),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '最近错误',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        color: Theme.of(context).colorScheme.onErrorContainer,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),
                    SelectableText(
                      state.errorMessage!,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.onErrorContainer,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
          const SizedBox(height: 22),
          _LogSection(
            title: '手机 App 日志',
            emptyText: '暂无 App 日志。',
            logs: state.logs,
          ),
          const SizedBox(height: 18),
          _LogSection(
            title: '电脑 Agent 日志',
            emptyText: _loading ? '正在读取 Agent 日志…' : 'Agent 离线或暂时没有日志。',
            logs: _agentLogs,
          ),
        ],
      ),
    );
  }
}

class _StatusLine extends StatelessWidget {
  const _StatusLine({required this.label, required this.value, this.online});

  final String label;
  final String value;
  final bool? online;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (online != null) ...[
          Padding(
            padding: const EdgeInsets.only(top: 5),
            child: Icon(
              Icons.circle,
              size: 10,
              color: online! ? Colors.greenAccent : Colors.grey,
            ),
          ),
          const SizedBox(width: 10),
        ],
        SizedBox(width: 88, child: Text(label)),
        Expanded(
          child: Text(value.isEmpty ? '未配置' : value, textAlign: TextAlign.end),
        ),
      ],
    );
  }
}

class _LogSection extends StatelessWidget {
  const _LogSection({
    required this.title,
    required this.emptyText,
    required this.logs,
  });

  final String title;
  final String emptyText;
  final List<String> logs;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 10),
        Container(
          width: double.infinity,
          constraints: const BoxConstraints(minHeight: 120),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: const Color(0xFF111117),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: const Color(0xFF30303D)),
          ),
          child: SelectableText(
            logs.isEmpty ? emptyText : logs.reversed.join('\n\n'),
            style: const TextStyle(
              fontFamily: 'monospace',
              fontSize: 12,
              height: 1.45,
            ),
          ),
        ),
      ],
    );
  }
}
