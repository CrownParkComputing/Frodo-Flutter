import 'dart:async';
import 'dart:developer' as developer;
import 'dart:io';

import 'package:archive/archive_io.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

import 'app_settings.dart';

class TosecLocalGame {
  const TosecLocalGame({
    required this.name,
    required this.path,
    required this.relativePath,
    required this.category,
    required this.format,
  });

  final String name;
  final String path;
  final String relativePath;
  final String category;
  final String format;
}

class TosecArchiveContents {
  const TosecArchiveContents({
    required this.archivePath,
    required this.entries,
  });

  final String archivePath;
  final List<String> entries;
}

class TosecStorage {
  TosecStorage({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;

  static const supportedExtensions = <String>{
    '.d64',
    '.t64',
    '.tap',
    '.z64',
    '.prg',
  };

  static const _userAgent =
      'Mozilla/5.0 (compatible; FrodoTosecDownloader/1.0; +https://data.spludlow.co.uk)';

  Future<List<TosecLocalGame>> listGames(String category, String format) async {
    final dir = await _gamesDir(category, format);
    if (!await dir.exists()) {
      return const [];
    }

    final results = <TosecLocalGame>[];
    await for (final entity in dir.list(recursive: true, followLinks: false)) {
      if (entity is! File) {
        continue;
      }
      final lowerPath = entity.path.toLowerCase();
      if (!supportedExtensions.any(lowerPath.endsWith)) {
        continue;
      }
      final relativePath = entity.path.substring(dir.path.length + 1);
      final name = relativePath.split(Platform.pathSeparator).last;
      results.add(
        TosecLocalGame(
          name: name,
          path: entity.path,
          relativePath: relativePath,
          category: category,
          format: format,
        ),
      );
    }

    results.sort((a, b) => a.relativePath.compareTo(b.relativePath));
    return results;
  }

  Future<List<TosecLocalGame>> downloadAndExtractPack({
    required String category,
    required String format,
    required String url,
  }) async {
    final downloadsDir = await _downloadsDir();
    final gamesDir = await _gamesDir(category, format);
    final zipName = Uri.parse(url).pathSegments.last;
    final zipFile = File('${downloadsDir.path}/$zipName');

    await downloadsDir.create(recursive: true);
    await gamesDir.create(recursive: true);
    await _downloadToFile(url, zipFile);
    await _clearDirectory(gamesDir);
    await _extractZip(zipFile, gamesDir);

    return listGames(category, format);
  }

  Future<List<TosecLocalGame>> downloadSingleGame({
    required String category,
    required String format,
    required String detailUrl,
    required String gameTitle,
  }) async {
    final gamesDir = await _gamesDir(category, format);
    await gamesDir.create(recursive: true);

    final decodedPath = Uri.decodeFull(Uri.parse(detailUrl).path);
    final archiveFileName = decodedPath.split('/').last;

    final downloadsDir = await _downloadsDir();
    await downloadsDir.create(recursive: true);
    final archiveFile = File('${downloadsDir.path}/$archiveFileName');

    developer.log(
      'Downloading archive: $archiveFileName',
      name: 'TosecStorage',
    );
    await _downloadToFile(detailUrl, archiveFile);

    developer.log(
      'Downloaded archive, file size: ${await archiveFile.length()} bytes',
      name: 'TosecStorage',
    );

    await _extractArchive(archiveFile, gamesDir);
    developer.log('Archive extraction complete', name: 'TosecStorage');

    return listGames(category, format);
  }

  Future<TosecArchiveContents> prepareArchiveSelection({
    required String detailUrl,
    void Function(String status)? onStatus,
    void Function(int receivedBytes, int? totalBytes)? onProgress,
  }) async {
    final decodedPath = Uri.decodeFull(Uri.parse(detailUrl).path);
    final archiveFileName = decodedPath.split('/').last;

    final downloadsDir = await _downloadsDir();
    await downloadsDir.create(recursive: true);
    final archiveFile = File('${downloadsDir.path}/$archiveFileName');

    onStatus?.call('Checking archive...');

    if (await archiveFile.exists() && await archiveFile.length() > 0) {
      onStatus?.call('Using cached archive...');
      developer.log(
        'Reusing cached archive for selection: $archiveFileName',
        name: 'TosecStorage',
      );
      try {
        onStatus?.call('Listing archive contents...');
        final cachedEntries = await _listArchiveEntries(archiveFile);
        cachedEntries.sort();
        return TosecArchiveContents(
          archivePath: archiveFile.path,
          entries: cachedEntries,
        );
      } catch (error) {
        developer.log(
          'Cached archive listing failed; redownloading $archiveFileName ($error)',
          name: 'TosecStorage',
        );
      }
    }

    onStatus?.call('Downloading archive...');
    developer.log(
      'Downloading archive for selection: $archiveFileName',
      name: 'TosecStorage',
    );
    await _downloadToFile(detailUrl, archiveFile, onProgress: onProgress);

    onStatus?.call('Listing archive contents...');
    final entries = await _listArchiveEntries(archiveFile);
    entries.sort();

    return TosecArchiveContents(
      archivePath: archiveFile.path,
      entries: entries,
    );
  }

  Future<int?> fetchRemoteArchiveSize(String url) async {
    try {
      final request = http.Request('HEAD', Uri.parse(url));
      request.headers['User-Agent'] = _userAgent;
      final response = await _client
          .send(request)
          .timeout(const Duration(seconds: 20));
      await response.stream.drain<void>();
      final contentLength = response.headers['content-length'];
      if (contentLength == null) {
        return null;
      }
      return int.tryParse(contentLength);
    } catch (_) {
      return null;
    }
  }

  Future<List<TosecLocalGame>> extractSelectedFromArchive({
    required String category,
    required String format,
    required String archivePath,
    required List<String> selectedEntries,
    void Function(int extracted, int total, String status)? onProgress,
  }) async {
    if (selectedEntries.isEmpty) {
      return listGames(category, format);
    }

    final gamesDir = await _gamesDir(category, format);
    await gamesDir.create(recursive: true);

    final archiveFile = File(archivePath);
    if (!await archiveFile.exists()) {
      throw Exception('Downloaded archive is missing: $archivePath');
    }

    onProgress?.call(0, selectedEntries.length, 'Preparing extraction...');

    await _extractArchiveSelected(
      archiveFile,
      gamesDir,
      selectedEntries.toSet(),
      onProgress: onProgress,
    );

    // Keep storage tidy after successful extraction.
    if (await archiveFile.exists()) {
      await archiveFile.delete();
    }

    return listGames(category, format);
  }

  Future<TosecArchiveContents> prepareLocalArchiveSelection({
    required String archivePath,
  }) async {
    final archiveFile = File(archivePath);
    if (!await archiveFile.exists()) {
      throw Exception('Archive file not found: $archivePath');
    }

    final entries = await _listArchiveEntries(archiveFile);
    entries.sort();
    return TosecArchiveContents(archivePath: archivePath, entries: entries);
  }

  Future<List<String>> extractSelectedFromLocalArchive({
    required String archivePath,
    required List<String> selectedEntries,
  }) async {
    if (selectedEntries.isEmpty) {
      return const [];
    }

    final archiveFile = File(archivePath);
    if (!await archiveFile.exists()) {
      throw Exception('Archive file not found: $archivePath');
    }

    final importRoot = await _rootDir();

    // Wipe previous play-temp so old files don't accumulate.
    final playTmp = Directory('${importRoot.path}/play_tmp');
    if (await playTmp.exists()) {
      await playTmp.delete(recursive: true);
    }
    await playTmp.create(recursive: true);

    final stamp = DateTime.now().millisecondsSinceEpoch;
    final archiveStem = archiveFile.uri.pathSegments.last.split('.').first;
    final destination = Directory(
      '${importRoot.path}/local_imports_tmp/${archiveStem}_$stamp',
    );
    await destination.create(recursive: true);

    try {
      await _extractArchiveSelected(
        archiveFile,
        destination,
        selectedEntries.toSet(),
      );

      final extractedPaths = <String>[];
      for (final entry in selectedEntries) {
        final sourceFile = await _resolveExtractedFile(destination, entry);
        if (sourceFile == null) {
          continue;
        }

        final baseName = entry.replaceAll('\\', '/').split('/').last;
        final targetPath = '${playTmp.path}/$baseName';
        await sourceFile.copy(targetPath);
        extractedPaths.add(targetPath);
      }

      return extractedPaths;
    } finally {
      if (await destination.exists()) {
        await destination.delete(recursive: true);
      }
    }
  }

  void dispose() {
    _client.close();
  }

  Future<void> _downloadToFile(
    String url,
    File destination, {
    void Function(int receivedBytes, int? totalBytes)? onProgress,
  }) async {
    final request = http.Request('GET', Uri.parse(url));
    request.headers['User-Agent'] = _userAgent;
    developer.log('TOSEC download: url=$url', name: 'TosecStorage');

    final response = await _client
        .send(request)
        .timeout(const Duration(seconds: 30));
    final contentType = response.headers['content-type'] ?? '';
    developer.log(
      'TOSEC response: status=${response.statusCode}  content-type=$contentType',
      name: 'TosecStorage',
    );

    if (response.statusCode != 200) {
      String bodySnippet = '';
      if (contentType.contains('text/html') ||
          contentType.contains('text/plain')) {
        bodySnippet = await response.stream.bytesToString();
        if (bodySnippet.length > 1200) {
          bodySnippet = bodySnippet.substring(0, 1200);
        }
      } else {
        await response.stream.drain<void>();
      }
      throw _DownloadHttpException(
        url: url,
        statusCode: response.statusCode,
        bodySnippet: bodySnippet,
      );
    }

    if (contentType.contains('text/html')) {
      await response.stream.drain<void>();
      throw Exception(
        'The download URL returned an HTML page instead of a game file (HTTP 200).',
      );
    }

    final sink = destination.openWrite();
    final totalBytes = int.tryParse(response.headers['content-length'] ?? '');
    var receivedBytes = 0;
    var lastLoggedPercent = -1;
    try {
      await for (final chunk in response.stream.timeout(
        const Duration(seconds: 30),
      )) {
        sink.add(chunk);
        receivedBytes += chunk.length;
        onProgress?.call(receivedBytes, totalBytes);

        if (totalBytes != null && totalBytes > 0) {
          final percent = (receivedBytes * 100) ~/ totalBytes;
          if (percent >= lastLoggedPercent + 10) {
            lastLoggedPercent = percent;
            developer.log(
              'TOSEC download progress: $percent% ($receivedBytes/$totalBytes bytes)',
              name: 'TosecStorage',
            );
          }
        }
      }
    } finally {
      await sink.close();
    }

    final fileSize = await destination.length();
    if (fileSize == 0) {
      throw Exception(
        'Archive returned an empty file payload for this game. Try a different entry.',
      );
    }
  }

  Future<void> _extractArchive(File archiveFile, Directory destination) async {
    final fileName = archiveFile.path.toLowerCase();
    if (fileName.endsWith('.7z')) {
      await _extract7z(archiveFile, destination);
    } else if (fileName.endsWith('.zip')) {
      await _extractZip(archiveFile, destination);
    } else {
      throw Exception('Unknown archive format: ${archiveFile.path}');
    }
  }

  Future<List<String>> _listArchiveEntries(File archiveFile) async {
    final fileName = archiveFile.path.toLowerCase();
    if (fileName.endsWith('.7z')) {
      return _list7zEntries(archiveFile);
    }

    if (fileName.endsWith('.zip')) {
      final input = InputFileStream(archiveFile.path);
      try {
        final archive = ZipDecoder().decodeBuffer(input, verify: false);
        final entries = <String>[];
        for (final entry in archive) {
          if (!entry.isFile) {
            continue;
          }
          final normalizedName = entry.name.replaceAll('\\', '/');
          if (normalizedName.contains('..')) {
            continue;
          }
          final lowerName = normalizedName.toLowerCase();
          if (!supportedExtensions.any(lowerName.endsWith)) {
            continue;
          }
          entries.add(normalizedName);
        }
        return entries;
      } finally {
        input.close();
      }
    }

    throw Exception('Unknown archive format: ${archiveFile.path}');
  }

  Future<void> _extractArchiveSelected(
    File archiveFile,
    Directory destination,
    Set<String> selectedEntries, {
    void Function(int extracted, int total, String status)? onProgress,
  }) async {
    final fileName = archiveFile.path.toLowerCase();
    if (fileName.endsWith('.7z')) {
      await _extract7zSelected(
        archiveFile,
        destination,
        selectedEntries,
        onProgress: onProgress,
      );
      return;
    }
    if (fileName.endsWith('.zip')) {
      await _extractZipSelected(
        archiveFile,
        destination,
        selectedEntries,
        onProgress: onProgress,
      );
      return;
    }

    throw Exception('Unknown archive format: ${archiveFile.path}');
  }

  Future<List<String>> _list7zEntries(File sevenZFile) async {
    const channel = MethodChannel('archive_extract');
    try {
      final result = await channel
          .invokeMethod<List<dynamic>>('list7zEntries', {
            'archivePath': sevenZFile.path,
          })
          .timeout(const Duration(minutes: 2));

      if (result == null) {
        return const [];
      }

      return result
          .whereType<String>()
          .map((e) => e.replaceAll('\\', '/'))
          .toList();
    } on TimeoutException {
      throw Exception('Listing 7z contents timed out after 2 minutes.');
    } on PlatformException catch (e) {
      throw Exception('Failed to list 7z contents: ${e.message}');
    }
  }

  Future<void> _extract7z(File sevenZFile, Directory destination) async {
    developer.log(
      'Attempting to extract 7z archive: ${sevenZFile.path}',
      name: 'TosecStorage',
    );

    const channel = MethodChannel('archive_extract');
    try {
      final result = await channel
          .invokeMethod<bool>('extract7z', {
            'archivePath': sevenZFile.path,
            'destinationPath': destination.path,
          })
          .timeout(const Duration(minutes: 2));
      if (result != true) {
        throw Exception('7z extraction returned false');
      }
      developer.log('Successfully extracted 7z archive', name: 'TosecStorage');
    } on TimeoutException {
      throw Exception(
        '7z extraction timed out after 2 minutes. The archive may be too large or unsupported.',
      );
    } on PlatformException catch (e) {
      throw Exception('Failed to extract 7z archive: ${e.message}');
    }
  }

  Future<void> _extract7zSelected(
    File sevenZFile,
    Directory destination,
    Set<String> selectedEntries, {
    void Function(int extracted, int total, String status)? onProgress,
  }) async {
    const channel = MethodChannel('archive_extract');
    final selectedList = selectedEntries.toList(growable: false);
    final total = selectedList.length;
    onProgress?.call(0, total, 'Extracting 7z files...');

    try {
      final result = await channel
          .invokeMethod<bool>('extract7zSelected', {
            'archivePath': sevenZFile.path,
            'destinationPath': destination.path,
            'selectedEntries': selectedList,
          })
          .timeout(const Duration(minutes: 4));

      if (result != true) {
        throw Exception('7z selective extraction returned false');
      }

      onProgress?.call(total, total, 'Extracting 7z files...');
    } on TimeoutException {
      throw Exception('Selective 7z extraction timed out after 4 minutes.');
    } on PlatformException catch (e) {
      throw Exception('Failed to extract selected 7z files: ${e.message}');
    }
  }

  Future<void> _extractZip(File zipFile, Directory destination) async {
    final input = InputFileStream(zipFile.path);
    try {
      final archive = ZipDecoder().decodeBuffer(input, verify: false);
      for (final entry in archive) {
        if (!entry.isFile) {
          continue;
        }

        final normalizedName = entry.name.replaceAll('\\', '/');
        if (normalizedName.contains('..')) {
          continue;
        }

        final lowerName = normalizedName.toLowerCase();
        if (!supportedExtensions.any(lowerName.endsWith)) {
          continue;
        }

        final baseName = normalizedName.split('/').last;
        if (baseName.isEmpty) {
          continue;
        }
        final outputFile = File('${destination.path}/$baseName');
        await outputFile.parent.create(recursive: true);
        final output = OutputFileStream(outputFile.path);
        try {
          entry.writeContent(output);
        } finally {
          output.close();
        }
      }
    } finally {
      input.close();
    }
  }

  Future<void> _extractZipSelected(
    File zipFile,
    Directory destination,
    Set<String> selectedEntries, {
    void Function(int extracted, int total, String status)? onProgress,
  }) async {
    if (selectedEntries.isEmpty) {
      return;
    }

    final total = selectedEntries.length;
    var extracted = 0;
    onProgress?.call(0, total, 'Extracting zip files...');

    final input = InputFileStream(zipFile.path);
    try {
      final archive = ZipDecoder().decodeBuffer(input, verify: false);
      for (final entry in archive) {
        if (!entry.isFile) {
          continue;
        }

        final normalizedName = entry.name.replaceAll('\\', '/');
        if (normalizedName.contains('..') ||
            !selectedEntries.contains(normalizedName)) {
          continue;
        }

        final lowerName = normalizedName.toLowerCase();
        if (!supportedExtensions.any(lowerName.endsWith)) {
          continue;
        }

        final baseName = normalizedName.split('/').last;
        if (baseName.isEmpty) {
          continue;
        }
        final outputFile = File('${destination.path}/$baseName');
        await outputFile.parent.create(recursive: true);
        final output = OutputFileStream(outputFile.path);
        try {
          entry.writeContent(output);
        } finally {
          output.close();
        }

        extracted += 1;
        onProgress?.call(extracted, total, 'Extracting zip files...');
      }
    } finally {
      input.close();
    }
  }

  Future<Directory> _rootDir() async {
    final base = await getApplicationSupportDirectory();
    return Directory('${base.path}/tosec_cache');
  }

  Future<Directory> _downloadsDir() async {
    final configuredBasePath =
        await AppSettings.instance.getTosecGamesBasePath();
    if (configuredBasePath != null && configuredBasePath.isNotEmpty) {
      return Directory('$configuredBasePath/downloads');
    }

    final root = await _rootDir();
    return Directory('${root.path}/downloads');
  }

  Future<Directory> _gamesDir(String category, String format) async {
    final configuredBasePath =
        await AppSettings.instance.getTosecGamesBasePath();
    if (configuredBasePath != null && configuredBasePath.isNotEmpty) {
      return Directory('$configuredBasePath/$format');
    }

    final root = await _rootDir();
    return Directory('${root.path}/games/$category/$format');
  }

  /// Returns the root directory for all local game files.
  /// This includes both TOSEC downloads and local imports.
  Future<Directory> getGamesRootDirectory() async {
    final configuredBasePath =
        await AppSettings.instance.getTosecGamesBasePath();
    if (configuredBasePath != null && configuredBasePath.isNotEmpty) {
      return Directory(configuredBasePath);
    }

    final root = await _rootDir();
    return Directory('${root.path}/games');
  }

  Future<Directory> _localImportsDir() async {
    final root = await _rootDir();
    return Directory('${root.path}/local_imports');
  }

  Future<Directory> _localTargetDirForEntry(String entry) async {
    final normalized = entry.replaceAll('\\', '/').toLowerCase();
    final format =
        supportedExtensions
            .firstWhere(
              (ext) => normalized.endsWith(ext),
              orElse: () => '.misc',
            )
            .replaceFirst('.', '')
            .toUpperCase();

    final configuredBasePath =
        await AppSettings.instance.getTosecGamesBasePath();
    if (configuredBasePath != null && configuredBasePath.isNotEmpty) {
      return Directory('$configuredBasePath/$format');
    }

    final importRoot = await _localImportsDir();
    return Directory('${importRoot.path}/$format');
  }

  Future<File?> _resolveExtractedFile(Directory tempDir, String entry) async {
    final normalized = entry.replaceAll('\\', '/');
    final direct = File('${tempDir.path}/$normalized');
    if (await direct.exists() && await direct.length() > 0) {
      return direct;
    }

    final baseName = normalized.split('/').last;
    if (baseName.isEmpty) {
      return null;
    }

    final flat = File('${tempDir.path}/$baseName');
    if (await flat.exists() && await flat.length() > 0) {
      return flat;
    }

    await for (final entity in tempDir.list(
      recursive: true,
      followLinks: false,
    )) {
      if (entity is! File) {
        continue;
      }

      final candidateBase = entity.path.replaceAll('\\', '/').split('/').last;
      if (candidateBase.toLowerCase() != baseName.toLowerCase()) {
        continue;
      }

      if (await entity.length() > 0) {
        return entity;
      }
    }

    return null;
  }

  Future<String> _dedupeOutputPath(Directory dir, String fileName) async {
    final dot = fileName.lastIndexOf('.');
    final stem = dot > 0 ? fileName.substring(0, dot) : fileName;
    final ext = dot > 0 ? fileName.substring(dot) : '';

    var index = 0;
    while (true) {
      final suffix = index == 0 ? '' : ' ($index)';
      final candidate = '${dir.path}/$stem$suffix$ext';
      final exists = await File(candidate).exists();
      if (!exists) {
        return candidate;
      }
      index += 1;
    }
  }

  Future<void> _clearDirectory(Directory dir) async {
    if (!await dir.exists()) {
      return;
    }
    await for (final entity in dir.list(recursive: false, followLinks: false)) {
      await entity.delete(recursive: true);
    }
  }
}

class _DownloadHttpException implements Exception {
  _DownloadHttpException({
    required this.url,
    required this.statusCode,
    required this.bodySnippet,
  });

  final String url;
  final int statusCode;
  final String bodySnippet;

  @override
  String toString() {
    return 'Download failed ($statusCode) for $url';
  }
}
