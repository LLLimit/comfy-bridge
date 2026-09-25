import 'package:flutter/material.dart';

import '../../core/models/task_model.dart';

class TaskCard extends StatelessWidget {
  const TaskCard({
    super.key,
    required this.task,
    required this.onTap,
    this.selecting = false,
    this.selected = false,
    this.onSelected,
  });

  final TaskModel task;
  final VoidCallback onTap;
  final bool selecting;
  final bool selected;
  final ValueChanged<bool?>? onSelected;

  @override
  Widget build(BuildContext context) {
    final percent = task.progress.percent;
    final status = _statusPresentation(task.status);
    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(24),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Row(
            children: [
              if (selecting) ...[
                Checkbox(value: selected, onChanged: onSelected),
                const SizedBox(width: 8),
              ],
              Container(
                width: 58,
                height: 58,
                decoration: BoxDecoration(
                  color: status.color.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(18),
                ),
                child: Icon(
                  task.category == 'video'
                      ? Icons.movie_creation_outlined
                      : Icons.image_outlined,
                  color: status.color,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      task.workflowName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleMedium
                          ?.copyWith(fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 5),
                    Text(
                      task.progress.stage,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: Theme.of(context).colorScheme.outline,
                      ),
                    ),
                    if (task.isActive) ...[
                      const SizedBox(height: 10),
                      LinearProgressIndicator(
                        value: percent == null ? null : percent / 100,
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    status.label,
                    style: TextStyle(
                      color: status.color,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  if (percent != null && task.isActive) ...[
                    const SizedBox(height: 6),
                    Text('${percent.round()}%'),
                  ],
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  static ({String label, Color color}) _statusPresentation(String status) {
    return switch (status) {
      'completed' => (label: '已完成', color: Colors.greenAccent),
      'failed' => (label: '失败', color: Colors.redAccent),
      'cancelled' => (label: '已取消', color: Colors.orangeAccent),
      'queued' => (label: '排队中', color: Colors.amberAccent),
      _ => (label: '生成中', color: Colors.lightBlueAccent),
    };
  }
}
