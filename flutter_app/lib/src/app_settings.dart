import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

class AppSettings {
  AppSettings._();

  static final AppSettings instance = AppSettings._();

  static const _tosecGamesBasePathKey = 'tosec.games.base.path';
  static const _tosecGamesSubfolderKey = 'tosec.games.subfolder';
  static const _startupWalkthroughSeenKey = 'startup.walkthrough.seen';
  static const _lastBrowsedPathKey = 'browser.last.path';
  static const _settingsFileName = 'app_settings.json';
  static const _androidMediaSettingsPath =
      '/storage/emulated/0/Android/media/org.simplec64.frodo_app/app_settings.json';

  Future<File> _settingsFile() async {
    final base = await getApplicationSupportDirectory();
    return File('${base.path}/$_settingsFileName');
  }

  Future<File> _mirrorSettingsFile() async {
    return File(_androidMediaSettingsPath);
  }

  Future<Map<String, dynamic>> _readJsonFile(File file) async {
    if (!await file.exists()) {
      return <String, dynamic>{};
    }

    final text = await file.readAsString();
    if (text.trim().isEmpty) {
      return <String, dynamic>{};
    }

    try {
      final data = jsonDecode(text);
      if (data is Map) {
        return data.map((key, value) => MapEntry(key.toString(), value));
      }
    } catch (_) {
      // Ignore invalid JSON and reset settings.
    }
    return <String, dynamic>{};
  }

  Future<Map<String, dynamic>> _readSettings() async {
    final file = await _settingsFile();
    final localSettings = await _readJsonFile(file);
    if (localSettings.isNotEmpty) {
      return localSettings;
    }

    // Fall back to external mirrored settings so path survives app reinstall.
    try {
      final mirrorFile = await _mirrorSettingsFile();
      final mirrorSettings = await _readJsonFile(mirrorFile);
      if (mirrorSettings.isNotEmpty) {
        await _writeSettings(mirrorSettings);
      }
      return mirrorSettings;
    } catch (_) {
      // If mirror read fails, continue with empty settings.
    }

    return <String, dynamic>{};
  }

  Future<void> _writeSettings(Map<String, dynamic> settings) async {
    final file = await _settingsFile();
    await file.parent.create(recursive: true);
    await file.writeAsString(jsonEncode(settings));

    // Best-effort mirror into external Android/media path for reinstall persistence.
    try {
      final mirrorFile = await _mirrorSettingsFile();
      await mirrorFile.parent.create(recursive: true);
      await mirrorFile.writeAsString(jsonEncode(settings));
    } catch (_) {
      // Ignore mirror write failures; local settings remain primary.
    }
  }

  Future<String?> getTosecGamesBasePath() async {
    final settings = await _readSettings();
    final raw = settings[_tosecGamesBasePathKey];
    if (raw is! String) {
      return null;
    }
    final value = raw.trim();
    if (value.isEmpty) {
      return null;
    }
    return value;
  }

  Future<void> setTosecGamesBasePath(String? path) async {
    final settings = await _readSettings();
    final normalized = path?.trim();
    if (normalized == null || normalized.isEmpty) {
      settings.remove(_tosecGamesBasePathKey);
      await _writeSettings(settings);
      return;
    }
    settings[_tosecGamesBasePathKey] = normalized;
    await _writeSettings(settings);
  }

  Future<String?> getLastBrowsedPath() async {
    final settings = await _readSettings();
    final raw = settings[_lastBrowsedPathKey];
    if (raw is! String || raw.trim().isEmpty) return null;
    return raw.trim();
  }

  Future<void> setLastBrowsedPath(String path) async {
    final settings = await _readSettings();
    settings[_lastBrowsedPathKey] = path.trim();
    await _writeSettings(settings);
  }

  Future<String?> getTosecGamesSubfolder() async {
    final settings = await _readSettings();
    final raw = settings[_tosecGamesSubfolderKey];
    if (raw is! String) {
      return null;
    }
    final value = raw.trim();
    if (value.isEmpty) {
      return null;
    }
    return value;
  }

  Future<void> setTosecGamesSubfolder(String? subfolder) async {
    final settings = await _readSettings();
    final normalized = subfolder?.trim();
    if (normalized == null || normalized.isEmpty) {
      settings.remove(_tosecGamesSubfolderKey);
      await _writeSettings(settings);
      return;
    }
    settings[_tosecGamesSubfolderKey] = normalized;
    await _writeSettings(settings);
  }

  Future<bool> hasSeenStartupWalkthrough() async {
    final settings = await _readSettings();
    final value = settings[_startupWalkthroughSeenKey];
    return value == true;
  }

  Future<void> setStartupWalkthroughSeen(bool seen) async {
    final settings = await _readSettings();
    settings[_startupWalkthroughSeenKey] = seen;
    await _writeSettings(settings);
  }
}
