import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../features/gallery/gallery_page.dart';
import '../features/generate/generate_page.dart';
import '../features/settings/diagnostics_page.dart';
import '../features/settings/settings_page.dart';
import '../features/tasks/tasks_page.dart';
import 'agent_controller.dart';
import 'theme_controller.dart';

class HomeShell extends ConsumerStatefulWidget {
  const HomeShell({super.key});

  @override
  ConsumerState<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends ConsumerState<HomeShell>
    with WidgetsBindingObserver {
  int _index = 0;
  bool _connectionDialogOpen = false;
  bool _tasksSelecting = false;
  int _tasksSelected = 0;
  bool _gallerySelecting = false;
  int _gallerySelected = 0;
  final _tasksKey = GlobalKey<TasksPageState>();
  final _galleryKey = GlobalKey<GalleryPageState>();
  late final List<Widget> _pages;

  static const _titles = ['生成', '任务', '作品', '设置'];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _pages = [
      const GeneratePage(),
      TasksPage(
        key: _tasksKey,
        onSelectionChanged: (active, count) {
          if (!mounted) return;
          setState(() {
            _tasksSelecting = active;
            _tasksSelected = count;
          });
        },
      ),
      GalleryPage(
        key: _galleryKey,
        onSelectionChanged: (active, count) {
          if (!mounted) return;
          setState(() {
            _gallerySelecting = active;
            _gallerySelected = count;
          });
        },
      ),
      const SettingsPage(),
    ];
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      ref.read(agentControllerProvider.notifier).refresh();
    }
  }

  Future<void> _showConnectionDialog(String detail) async {
    if (_connectionDialogOpen || !mounted) return;
    _connectionDialogOpen = true;
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        icon: const Icon(Icons.cloud_off_outlined),
        title: const Text('与 ComfyUI 未建立连接'),
        content: Text(detail),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('关闭'),
          ),
          FilledButton.icon(
            onPressed: () {
              Navigator.of(dialogContext).pop();
              Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => const DiagnosticsPage(),
                ),
              );
            },
            icon: const Icon(Icons.article_outlined),
            label: const Text('查看错误/日志'),
          ),
        ],
      ),
    );
    if (mounted) _connectionDialogOpen = false;
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(agentControllerProvider, (previous, next) {
      if (next.errorMessage != null &&
          next.errorMessage != previous?.errorMessage) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _showConnectionDialog(next.errorMessage!);
        });
      }
    });
    return Scaffold(
      appBar: AppBar(
        title: Text(
          _index == 1 && _tasksSelecting
              ? '已选择 $_tasksSelected 项'
              : _index == 2 && _gallerySelecting
              ? '已选择 $_gallerySelected 项'
              : _titles[_index],
        ),
        actions: [
          if (_index == 1)
            IconButton(
              tooltip: _tasksSelecting ? '删除所选任务' : '多选任务',
              onPressed: _tasksSelecting
                  ? _tasksKey.currentState?.deleteSelected
                  : _tasksKey.currentState?.enterSelectionMode,
              color: _tasksSelecting ? Colors.redAccent : null,
              icon: Icon(
                _tasksSelecting
                    ? Icons.delete_outline
                    : Icons.format_list_bulleted,
              ),
            ),
          if (_index == 2)
            IconButton(
              tooltip: _gallerySelecting ? '删除所选作品' : '多选作品',
              onPressed: _gallerySelecting
                  ? _galleryKey.currentState?.deleteSelected
                  : _galleryKey.currentState?.enterSelectionMode,
              color: _gallerySelecting ? Colors.redAccent : null,
              icon: Icon(
                _gallerySelecting
                    ? Icons.delete_outline
                    : Icons.format_list_bulleted,
              ),
            ),
          if (_index == 3)
            Consumer(
              builder: (context, ref, _) {
                final themeMode = ref.watch(themeControllerProvider);
                final isLight = themeMode == ThemeMode.light;
                return IconButton(
                  tooltip: isLight ? '切换到深色主题' : '切换到白色主题',
                  onPressed: () => ref
                      .read(themeControllerProvider.notifier)
                      .setMode(isLight ? ThemeMode.dark : ThemeMode.light),
                  icon: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 180),
                    transitionBuilder: (child, animation) =>
                        RotationTransition(turns: animation, child: child),
                    child: Icon(
                      isLight
                          ? Icons.light_mode_rounded
                          : Icons.dark_mode_rounded,
                      key: ValueKey(isLight),
                      size: 22,
                    ),
                  ),
                );
              },
            ),
          Consumer(
            builder: (context, ref, _) {
              final state = ref.watch(agentControllerProvider);
              return Padding(
                padding: const EdgeInsets.only(right: 14),
                child: Tooltip(
                  message: state.status?.agentOnline == true
                      ? 'Agent 在线'
                      : 'Agent 离线',
                  child: Icon(
                    Icons.circle,
                    size: 11,
                    color: state.status?.agentOnline == true
                        ? Colors.greenAccent
                        : Colors.grey,
                  ),
                ),
              );
            },
          ),
        ],
      ),
      body: IndexedStack(index: _index, children: _pages),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (index) => setState(() => _index = index),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.auto_awesome_outlined),
            label: '生成',
          ),
          NavigationDestination(
            icon: Icon(Icons.pending_actions_outlined),
            label: '任务',
          ),
          NavigationDestination(
            icon: Icon(Icons.collections_outlined),
            label: '作品',
          ),
          NavigationDestination(
            icon: Icon(Icons.settings_outlined),
            label: '设置',
          ),
        ],
      ),
    );
  }
}
