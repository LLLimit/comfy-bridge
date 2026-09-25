import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

final themeControllerProvider = NotifierProvider<ThemeController, ThemeMode>(
  ThemeController.new,
);

class ThemeController extends Notifier<ThemeMode> {
  static const _key = 'app_theme_mode';

  @override
  ThemeMode build() {
    Future<void>.microtask(_load);
    return ThemeMode.dark;
  }

  Future<void> _load() async {
    final preferences = await SharedPreferences.getInstance();
    if (!ref.mounted) return;
    state = preferences.getString(_key) == 'light'
        ? ThemeMode.light
        : ThemeMode.dark;
  }

  Future<void> setMode(ThemeMode mode) async {
    if (mode != ThemeMode.light && mode != ThemeMode.dark) return;
    state = mode;
    final preferences = await SharedPreferences.getInstance();
    await preferences.setString(
      _key,
      mode == ThemeMode.light ? 'light' : 'dark',
    );
  }
}
