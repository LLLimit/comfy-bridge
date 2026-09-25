import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app_theme.dart';
import 'home_shell.dart';
import 'theme_controller.dart';

class ComfyBridgeApp extends ConsumerWidget {
  const ComfyBridgeApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final themeMode = ref.watch(themeControllerProvider);
    return MaterialApp(
      title: 'Comfy Bridge',
      debugShowCheckedModeBanner: false,
      darkTheme: AppTheme.dark(),
      themeMode: themeMode,
      theme: AppTheme.light(),
      home: const HomeShell(),
    );
  }
}
