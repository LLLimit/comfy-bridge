import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/models/task_model.dart';

class TaskDetailSheet extends StatelessWidget {
  const TaskDetailSheet({super.key, required this.task});

  final TaskModel task;

  @override
  Widget build(BuildContext context) {
    final prompt = task.inputs['prompt']?.toString();
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.72,
      maxChildSize: 0.94,
      builder: (context, controller) => ListView(
        controller: controller,
        padding: const EdgeInsets.fromLTRB(24, 14, 24, 40),
        children: [
          Center(
            child: Container(
              width: 42,
              height: 4,
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.outlineVariant,
                borderRadius: BorderRadius.circular(4),
              ),
            ),
          ),
          const SizedBox(height: 24),
          Text(
            task.workflowName,
            style: Theme.of(context).textTheme.headlineSmall
                ?.copyWith(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          Text(task.progress.stage),
          const SizedBox(height: 16),
          LinearProgressIndicator(
            value: task.progress.percent == null
                ? null
                : task.progress.percent! / 100,
          ),
          if (task.error != null) ...[
            const SizedBox(height: 20),
            Card(
              color: Theme.of(context).colorScheme.errorContainer,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(Icons.error_outline),
                    const SizedBox(width: 12),
                    Expanded(child: Text(task.error!.message)),
                  ],
                ),
              ),
            ),
          ],
          if (prompt != null && prompt.isNotEmpty) ...[
            const SizedBox(height: 24),
            Row(
              children: [
                Text('Prompt', style: Theme.of(context).textTheme.titleMedium),
                const Spacer(),
                IconButton(
                  tooltip: '复制 Prompt',
                  onPressed: () async {
                    await Clipboard.setData(ClipboardData(text: prompt));
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Prompt 已复制')),
                      );
                    }
                  },
                  icon: const Icon(Icons.copy_outlined),
                ),
              ],
            ),
            SelectableText(prompt),
          ],
          const SizedBox(height: 24),
          Text('任务信息', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 10),
          _InfoRow(label: '状态', value: task.status),
          _InfoRow(label: '创建时间', value: task.createdAt.toLocal().toString()),
          if (task.promptId != null)
            _InfoRow(label: 'Prompt ID', value: task.promptId!),
          _InfoRow(label: '输出数量', value: '${task.outputs.length}'),
        ],
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 7),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 90,
            child: Text(
              label,
              style: TextStyle(color: Theme.of(context).colorScheme.outline),
            ),
          ),
          Expanded(child: SelectableText(value)),
        ],
      ),
    );
  }
}
