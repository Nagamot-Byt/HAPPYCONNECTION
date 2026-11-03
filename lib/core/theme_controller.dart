import 'package:flutter/material.dart';
import 'package:medlink_connect/core/settings_storage.dart';

class ThemeController extends ChangeNotifier {
  ThemeController(this._settings) : _mode = _settings.themeMode;

  final SettingsStorage _settings;
  ThemeMode _mode;

  ThemeMode get mode => _mode;

  void setMode(ThemeMode mode) {
    if (_mode == mode) return;
    _mode = mode;
    _settings.themeMode = mode;
    notifyListeners();
  }
}
