import 'package:flutter/services.dart';

class ArchiveAuthService {
  ArchiveAuthService._();

  static final ArchiveAuthService instance = ArchiveAuthService._();

  static const MethodChannel _channel = MethodChannel('archive_auth');

  Future<String?> getArchiveCookies() async {
    final cookies = await _channel.invokeMethod<String>('getArchiveCookies');
    if (cookies == null) {
      return null;
    }
    final trimmed = cookies.trim();
    return trimmed.isEmpty ? null : trimmed;
  }

  Future<bool> hasArchiveSession() async {
    final cookies = await getArchiveCookies();
    if (cookies == null) {
      return false;
    }
    final lower = cookies.toLowerCase();
    return lower.contains('logged') ||
        lower.contains('archive') ||
        lower.isNotEmpty;
  }

  Future<void> clearArchiveCookies() async {
    await _channel.invokeMethod('clearArchiveCookies');
  }
}
