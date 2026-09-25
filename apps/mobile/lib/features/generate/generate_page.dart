import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../../app/agent_controller.dart';
import '../../core/errors/app_exception.dart';
import '../../core/models/workflow_definition.dart';
import '../settings/diagnostics_page.dart';
import 'dynamic_workflow_form.dart';

class GeneratePage extends ConsumerStatefulWidget {
  const GeneratePage({super.key});

  @override
  ConsumerState<GeneratePage> createState() => _GeneratePageState();
}

class _GeneratePageState extends ConsumerState<GeneratePage> {
  String _category = 'image';
  String? _selectedWorkflowId;

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(agentControllerProvider);
    if (state.initializing) {
      return const Center(child: CircularProgressIndicator());
    }

    final categories = state.workflows.map((item) => item.category).toSet();
    if (!categories.contains(_category) && categories.isNotEmpty) {
      _category = categories.first;
    }
    final workflows = state.workflows
        .where((item) => item.category == _category)
        .toList(growable: false);
    final selected = _selectWorkflow(workflows);

    return RefreshIndicator(
      onRefresh: () => ref.read(agentControllerProvider.notifier).refresh(),
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 120),
        children: [
          _hero(context, state),
          const SizedBox(height: 24),
          if (!state.isConfigured)
            _setupPrompt(context)
          else if (categories.isEmpty)
            _ConnectionUnavailable(
              state: state,
              onRetry: () =>
                  ref.read(agentControllerProvider.notifier).refresh(),
              onDiagnostics: _openDiagnostics,
            )
          else ...[
            SegmentedButton<String>(
              segments: [
                if (categories.contains('image'))
                  const ButtonSegment(
                    value: 'image',
                    label: Text('图片'),
                    icon: Icon(Icons.image_outlined),
                  ),
                if (categories.contains('video'))
                  const ButtonSegment(
                    value: 'video',
                    label: Text('视频'),
                    icon: Icon(Icons.movie_outlined),
                  ),
              ],
              selected: {_category},
              onSelectionChanged: (value) => setState(() {
                _category = value.first;
                _selectedWorkflowId = null;
              }),
            ),
            const SizedBox(height: 20),
            if (workflows.isEmpty)
              const _EmptyWorkflow()
            else ...[
              Text('生成模式', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 10),
              SizedBox(
                height: 52,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: workflows.length,
                  separatorBuilder: (_, _) => const SizedBox(width: 10),
                  itemBuilder: (context, index) {
                    final workflow = workflows[index];
                    return ChoiceChip(
                      label: Text(workflow.name),
                      selected: workflow.id == selected?.id,
                      onSelected: (_) => setState(() {
                        _selectedWorkflowId = workflow.id;
                      }),
                    );
                  },
                ),
              ),
            ],
            if (selected != null) ...[
              const SizedBox(height: 18),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        selected.name,
                        style: Theme.of(context).textTheme.headlineSmall
                            ?.copyWith(fontWeight: FontWeight.bold),
                      ),
                      if (selected.description.isNotEmpty) ...[
                        const SizedBox(height: 6),
                        Text(
                          selected.description,
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.outline,
                          ),
                        ),
                      ],
                      const SizedBox(height: 24),
                      DynamicWorkflowForm(
                        key: ValueKey('${selected.id}:${selected.revision}'),
                        workflow: selected,
                        submitting: state.submitting,
                        onSubmit: (values, assets) =>
                            _submit(selected, values, assets),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ],
        ],
      ),
    );
  }

  WorkflowDefinition? _selectWorkflow(List<WorkflowDefinition> workflows) {
    if (workflows.isEmpty) return null;
    return workflows
            .where((item) => item.id == _selectedWorkflowId)
            .firstOrNull ??
        workflows.first;
  }

  Future<void> _submit(
    WorkflowDefinition workflow,
    Map<String, dynamic> values,
    Map<String, XFile> assets,
  ) async {
    try {
      final task = await ref
          .read(agentControllerProvider.notifier)
          .submitTask(workflow: workflow, values: values, assets: assets);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${task.workflowName} 已提交，可在任务页查看进度。')),
      );
    } on AppException catch (_) {
      // HomeShell presents the connection/error dialog with a diagnostics link.
    }
  }

  void _openDiagnostics() {
    Navigator.of(context)
        .push(MaterialPageRoute<void>(builder: (_) => const DiagnosticsPage()));
  }

  Widget _hero(BuildContext context, AgentState state) {
    final isLightTheme = Theme.of(context).brightness == Brightness.light;
    final agentOnline = state.status?.agentOnline == true;
    final comfyOnline = state.status?.comfyOnline == true;
    final connected = agentOnline && comfyOnline;
    final subtitle = !agentOnline
        ? '等待 Windows Agent'
        : !comfyOnline
        ? 'Agent 已连接，ComfyUI 未连接'
        : state.liveConnected
        ? '实时通道已连接'
        : 'ComfyUI 已连接，实时通道正在恢复';
    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(28),
        color: isLightTheme ? Colors.black : null,
        gradient: isLightTheme
            ? null
            : const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [Color(0xFF33255F), Color(0xFF172F45)],
              ),
      ),
      child: Row(
        children: [
          Container(
            width: 54,
            height: 54,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(18),
            ),
            child: const Icon(
              Icons.auto_awesome,
              size: 30,
              color: Colors.white,
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Comfy Bridge',
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  subtitle,
                  style: TextStyle(color: Colors.white.withValues(alpha: 0.78)),
                ),
              ],
            ),
          ),
          Icon(
            Icons.circle,
            size: 12,
            color: connected ? Colors.greenAccent : Colors.orangeAccent,
          ),
        ],
      ),
    );
  }

  Widget _setupPrompt(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            Icon(
              Icons.desktop_windows_outlined,
              size: 56,
              color: Theme.of(context).colorScheme.primary,
            ),
            const SizedBox(height: 16),
            Text(
              '先连接 Windows Agent',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 8),
            const Text(
              '打开“设置”，填写电脑局域网地址和设备 Token。',
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

class _ConnectionUnavailable extends StatelessWidget {
  const _ConnectionUnavailable({
    required this.state,
    required this.onRetry,
    required this.onDiagnostics,
  });

  final AgentState state;
  final VoidCallback onRetry;
  final VoidCallback onDiagnostics;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            Icon(
              Icons.cloud_off_outlined,
              size: 52,
              color: Theme.of(context).colorScheme.outline,
            ),
            const SizedBox(height: 16),
            Text(
              state.refreshing ? '正在重新连接…' : '暂时无法读取生成工作流',
              style: Theme.of(context).textTheme.titleLarge,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              state.errorMessage ?? '请确认电脑端 Agent 与 ComfyUI 均已启动。',
              textAlign: TextAlign.center,
              style: TextStyle(color: Theme.of(context).colorScheme.outline),
            ),
            const SizedBox(height: 20),
            Wrap(
              spacing: 12,
              runSpacing: 10,
              alignment: WrapAlignment.center,
              children: [
                FilledButton.icon(
                  onPressed: state.refreshing ? null : onRetry,
                  icon: state.refreshing
                      ? const SizedBox.square(
                          dimension: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.refresh),
                  label: const Text('重新连接'),
                ),
                OutlinedButton.icon(
                  onPressed: onDiagnostics,
                  icon: const Icon(Icons.article_outlined),
                  label: const Text('错误/日志'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _EmptyWorkflow extends StatelessWidget {
  const _EmptyWorkflow();

  @override
  Widget build(BuildContext context) {
    return const Card(
      child: Padding(
        padding: EdgeInsets.all(24),
        child: Text('Agent 暂未提供这一类工作流。'),
      ),
    );
  }
}
