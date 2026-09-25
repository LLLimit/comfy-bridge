import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/agent_controller.dart';
import '../../shared/empty_state.dart';
import 'task_card.dart';
import 'task_detail_sheet.dart';

class TasksPage extends ConsumerStatefulWidget {
  const TasksPage({super.key, required this.onSelectionChanged});

  final void Function(bool active, int count) onSelectionChanged;

  @override
  ConsumerState<TasksPage> createState() => TasksPageState();
}

class TasksPageState extends ConsumerState<TasksPage> {
  bool _selecting = false;
  final Set<String> _selected = {};

  void enterSelectionMode() {
    if (_selecting) return;
    setState(() => _selecting = true);
    widget.onSelectionChanged(true, 0);
  }

  Future<void> deleteSelected() async {
    if (_selected.isEmpty) {
      _finishSelection();
      return;
    }
    if (!await _confirmDelete(_selected.length)) return;
    final ids = Set<String>.from(_selected);
    try {
      await ref.read(agentControllerProvider.notifier).deleteTasks(ids);
      if (mounted) _finishSelection();
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('删除任务失败：$error')));
      }
    }
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
            title: const Text('确认删除任务？'),
            content: Text('将删除选中的 $count 个任务及其作品文件，此操作无法撤销。'),
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

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(agentControllerProvider);
    if (!state.isConfigured) {
      return const EmptyState(
        icon: Icons.link_off,
        title: '尚未连接 Agent',
        message: '连接电脑后，生成任务会显示在这里。',
      );
    }
    return RefreshIndicator(
      onRefresh: () => ref.read(agentControllerProvider.notifier).refresh(),
      child: state.tasks.isEmpty
          ? const CustomScrollView(
              slivers: [
                SliverFillRemaining(
                  child: EmptyState(
                    icon: Icons.hourglass_empty,
                    title: '还没有任务',
                    message: '从生成页创建第一个任务。',
                  ),
                ),
              ],
            )
          : ListView.separated(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 120),
              itemCount: state.tasks.length,
              separatorBuilder: (_, _) => const SizedBox(height: 12),
              itemBuilder: (context, index) {
                final task = state.tasks[index];
                return Dismissible(
                  key: ValueKey(task.id),
                  direction: _selecting
                      ? DismissDirection.none
                      : DismissDirection.endToStart,
                  background: Container(
                    alignment: Alignment.centerRight,
                    padding: const EdgeInsets.only(right: 24),
                    decoration: BoxDecoration(
                      color: Colors.red,
                      borderRadius: BorderRadius.circular(24),
                    ),
                    child: const Icon(
                      Icons.delete_outline,
                      color: Colors.white,
                    ),
                  ),
                  confirmDismiss: (_) => _confirmDelete(1),
                  onDismissed: (_) => ref
                      .read(agentControllerProvider.notifier)
                      .deleteTasks([task.id]),
                  child: TaskCard(
                    task: task,
                    selecting: _selecting,
                    selected: _selected.contains(task.id),
                    onSelected: (_) => _toggle(task.id),
                    onTap: () {
                      if (_selecting) {
                        _toggle(task.id);
                        return;
                      }
                      showModalBottomSheet<void>(
                        context: context,
                        isScrollControlled: true,
                        backgroundColor: Theme.of(context).colorScheme.surface,
                        builder: (_) => TaskDetailSheet(task: task),
                      );
                    },
                  ),
                );
              },
            ),
    );
  }
}
