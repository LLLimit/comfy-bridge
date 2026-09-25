import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/agent_controller.dart';
import '../../core/models/task_model.dart';
import '../../shared/empty_state.dart';
import 'media_preview_dialog.dart';

class GalleryPage extends ConsumerStatefulWidget {
  const GalleryPage({super.key, required this.onSelectionChanged});

  final void Function(bool active, int count) onSelectionChanged;

  @override
  ConsumerState<GalleryPage> createState() => GalleryPageState();
}

class GalleryPageState extends ConsumerState<GalleryPage> {
  bool _selecting = false;
  final Set<String> _selected = {};
  final Set<String> _dismissed = {};

  void enterSelectionMode() {
    if (_selecting) return;
    setState(() => _selecting = true);
    widget.onSelectionChanged(true, 0);
  }

  void _toggle(String id) {
    setState(() {
      if (!_selected.add(id)) _selected.remove(id);
    });
    widget.onSelectionChanged(true, _selected.length);
  }

  void _finishSelection() {
    setState(() {
      _selecting = false;
      _selected.clear();
    });
    widget.onSelectionChanged(false, 0);
  }

  Future<bool> _confirmDelete(int count) async {
    return await showDialog<bool>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            title: const Text('确认删除作品？'),
            content: Text('将永久删除选中的 $count 个作品，此操作无法撤销。'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext, false),
                child: const Text('取消'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(dialogContext, true),
                style: FilledButton.styleFrom(backgroundColor: Colors.red),
                child: const Text('删除'),
              ),
            ],
          ),
        ) ??
        false;
  }

  Future<void> deleteSelected() async {
    if (_selected.isEmpty) {
      _finishSelection();
      return;
    }
    if (!await _confirmDelete(_selected.length)) return;
    final outputs = [
      for (final task in ref.read(agentControllerProvider).tasks)
        for (final output in task.outputs)
          if (_selected.contains(output.id)) output,
    ];
    try {
      await ref.read(agentControllerProvider.notifier).deleteOutputs(outputs);
      if (mounted) _finishSelection();
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('删除作品失败：$error')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(agentControllerProvider);
    final entries = <({TaskModel task, TaskOutputModel output})>[
      for (final task in state.tasks.where((item) => item.isCompleted))
        for (final output in task.outputs) (task: task, output: output),
    ].where((entry) => !_dismissed.contains(entry.output.id)).toList();
    if (entries.isEmpty) {
      return const EmptyState(
        icon: Icons.collections_outlined,
        title: '作品库还是空的',
        message: '生成完成的图片和视频会自动出现在这里。',
      );
    }
    final controller = ref.read(agentControllerProvider.notifier);
    return GridView.builder(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 120),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        mainAxisSpacing: 12,
        crossAxisSpacing: 12,
        childAspectRatio: 0.82,
      ),
      itemCount: entries.length,
      itemBuilder: (context, index) {
        final entry = entries[index];
        final uri = controller.mediaUri(entry.output);
        return Dismissible(
          key: ValueKey(entry.output.id),
          direction: _selecting
              ? DismissDirection.none
              : DismissDirection.endToStart,
          background: Container(
            alignment: Alignment.centerRight,
            padding: const EdgeInsets.only(right: 22),
            decoration: BoxDecoration(
              color: Colors.red,
              borderRadius: BorderRadius.circular(24),
            ),
            child: const Icon(Icons.delete_outline, color: Colors.white),
          ),
          confirmDismiss: (_) => _confirmDelete(1),
          onDismissed: (_) => _deleteAfterSwipe(entry.output),
          child: Card(
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: () {
                if (_selecting) {
                  _toggle(entry.output.id);
                  return;
                }
                showDialog<void>(
                  context: context,
                  builder: (_) => MediaPreviewDialog(
                    output: entry.output,
                    uri: uri,
                    headers: controller.mediaHeaders,
                    onSave: () => controller.saveOutputToPhone(entry.output),
                    onDelete: () => controller.deleteOutput(entry.output),
                  ),
                );
              },
              child: Stack(
                fit: StackFit.expand,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Expanded(
                        child: entry.output.mediaType == 'image'
                            ? Image.network(
                                uri.toString(),
                                headers: controller.mediaHeaders,
                                fit: BoxFit.cover,
                                errorBuilder: (_, _, _) => const Center(
                                  child: Icon(
                                    Icons.broken_image_outlined,
                                    size: 40,
                                  ),
                                ),
                              )
                            : const ColoredBox(
                                color: Color(0xFF232331),
                                child: Center(
                                  child: Icon(Icons.play_circle, size: 54),
                                ),
                              ),
                      ),
                      Padding(
                        padding: const EdgeInsets.all(12),
                        child: Text(
                          entry.task.workflowName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                      ),
                    ],
                  ),
                  if (_selecting)
                    Positioned(
                      left: 8,
                      top: 8,
                      child: Material(
                        color: Theme.of(context).colorScheme.surface,
                        shape: const CircleBorder(),
                        child: Checkbox(
                          value: _selected.contains(entry.output.id),
                          onChanged: (_) => _toggle(entry.output.id),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Future<void> _deleteAfterSwipe(TaskOutputModel output) async {
    setState(() => _dismissed.add(output.id));
    try {
      await ref.read(agentControllerProvider.notifier).deleteOutput(output);
    } catch (error) {
      if (!mounted) return;
      setState(() => _dismissed.remove(output.id));
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('删除作品失败：$error')));
    }
  }
}
