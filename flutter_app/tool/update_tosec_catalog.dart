import 'dart:convert';
import 'dart:io';

import 'package:html/parser.dart' as html_parser;
import 'package:http/http.dart' as http;

const _archiveRoot =
    'https://archive.org/download/tosec-main/Commodore/C64/Games/';

const _defaultCategories = <String>[
  'Adventure',
  'Arcade',
  'Board',
  'Boulder Dash',
  'Cards',
  'Gambling',
  'Misc',
  'Racing',
  "Shoot'em Up",
  'Simulation',
  'Sports',
  'Strategy',
];

const _defaultFormats = <String>['D64', 'T64', 'TAP', 'PRG', 'CRT', 'G64'];

void main(List<String> args) async {
  final options = _parseArgs(args);
  final scraper = ArchiveTosecScraper(
    client: http.Client(),
    requestDelay: Duration(milliseconds: options.delayMs),
  );

  try {
    final catalog = await scraper.scrapeCatalog(
      categories:
          options.categories.isEmpty ? _defaultCategories : options.categories,
      formats: options.formats.isEmpty ? _defaultFormats : options.formats,
    );

    final outputFile = File(options.outputPath);
    await outputFile.parent.create(recursive: true);
    await outputFile.writeAsString(
      const JsonEncoder.withIndent('  ').convert(catalog),
    );

    if (options.dartOutputPath != null) {
      final dartFile = File(options.dartOutputPath!);
      await dartFile.parent.create(recursive: true);
      await dartFile.writeAsString(_buildDartCatalog(catalog));
    }

    stdout.writeln('Wrote ${catalog.length} entries to ${outputFile.path}');
    if (options.dartOutputPath != null) {
      stdout.writeln('Wrote Dart catalog to ${options.dartOutputPath}');
    }
  } finally {
    scraper.close();
  }
}

class ArchiveTosecScraper {
  ArchiveTosecScraper({required http.Client client, required this.requestDelay})
    : _client = client;

  final http.Client _client;
  final Duration requestDelay;

  Future<List<Map<String, Object?>>> scrapeCatalog({
    required List<String> categories,
    required List<String> formats,
  }) async {
    final entries = <Map<String, Object?>>[];

    for (final category in categories) {
      final urls = <String, String>{};
      for (final format in formats) {
        final packUrl = await _findPackUrl(category: category, format: format);
        if (packUrl != null) {
          urls[format] = packUrl;
        }
      }

      if (urls.isNotEmpty) {
        entries.add({
          'name': '$category Set',
          'category': category,
          'urls': urls,
        });
      }
    }

    entries.sort((a, b) {
      final left = a['name'] as String? ?? '';
      final right = b['name'] as String? ?? '';
      return left.compareTo(right);
    });
    return entries;
  }

  Future<String?> _findPackUrl({
    required String category,
    required String format,
  }) async {
    final uri = _folderUri(category: category, format: format);
    final response = await _client.get(
      uri,
      headers: const {
        'User-Agent':
            'Mozilla/5.0 (compatible; FrodoTosecScraper/1.0; +https://archive.org)',
      },
    );
    await Future<void>.delayed(requestDelay);

    if (response.statusCode != 200) {
      stderr.writeln(
        'Skipping ${uri.toString()} -> HTTP ${response.statusCode}',
      );
      return null;
    }

    final document = html_parser.parse(response.body);
    for (final anchor in document.querySelectorAll('a[href]')) {
      final href = anchor.attributes['href'];
      if (href == null || href.isEmpty) {
        continue;
      }
      final resolved = uri.resolve(href).toString();
      if (resolved.toLowerCase().endsWith('.zip')) {
        return resolved;
      }
    }

    for (final row in document.querySelectorAll(
      'tr.directory-listing-table__restricted-file',
    )) {
      final cells = row.querySelectorAll('td');
      if (cells.isEmpty) {
        continue;
      }
      final fileName = cells.first.text.trim();
      if (!fileName.toLowerCase().endsWith('.zip')) {
        continue;
      }
      return uri.resolve(Uri.encodeComponent(fileName)).toString();
    }
    return null;
  }

  Uri _folderUri({required String category, required String format}) {
    final categoryPart = Uri.encodeComponent(category);
    final formatPart = Uri.encodeComponent('[$format]');
    return Uri.parse('$_archiveRoot$categoryPart/$formatPart/');
  }

  void close() {
    _client.close();
  }
}

_Options _parseArgs(List<String> args) {
  var outputPath = 'tool/tosec_catalog.json';
  String? dartOutputPath;
  var delayMs = 250;
  final categories = <String>[];
  final formats = <String>[];

  for (var index = 0; index < args.length; index++) {
    final arg = args[index];
    if (arg == '--output' && index + 1 < args.length) {
      outputPath = args[++index];
      continue;
    }
    if (arg == '--dart-output' && index + 1 < args.length) {
      dartOutputPath = args[++index];
      continue;
    }
    if (arg == '--delay-ms' && index + 1 < args.length) {
      delayMs = int.tryParse(args[++index]) ?? delayMs;
      continue;
    }
    if (arg.startsWith('--category=')) {
      categories.add(arg.substring('--category='.length));
      continue;
    }
    if (arg.startsWith('--format=')) {
      formats.add(arg.substring('--format='.length).toUpperCase());
      continue;
    }
  }

  return _Options(
    outputPath: outputPath,
    dartOutputPath: dartOutputPath,
    delayMs: delayMs,
    categories: categories,
    formats: formats,
  );
}

class _Options {
  const _Options({
    required this.outputPath,
    required this.dartOutputPath,
    required this.delayMs,
    required this.categories,
    required this.formats,
  });

  final String outputPath;
  final String? dartOutputPath;
  final int delayMs;
  final List<String> categories;
  final List<String> formats;
}

String _buildDartCatalog(List<Map<String, Object?>> catalog) {
  final buffer = StringBuffer()..writeln('const generatedTosecCatalog = [');

  for (final entry in catalog) {
    final name = _escapeDart(entry['name'] as String? ?? '');
    final category = _escapeDart(entry['category'] as String? ?? '');
    final urls = Map<String, Object?>.from(entry['urls'] as Map);
    final sortedFormats =
        urls.keys.map((key) => key.toString()).toList()..sort();

    buffer.writeln('  {');
    buffer.writeln("    'name': '$name',");
    buffer.writeln("    'category': '$category',");
    buffer.writeln("    'urls': {");
    for (final format in sortedFormats) {
      final escapedFormat = _escapeDart(format);
      final escapedUrl = _escapeDart(urls[format] as String? ?? '');
      buffer.writeln("      '$escapedFormat': '$escapedUrl',");
    }
    buffer.writeln('    },');
    buffer.writeln('  },');
  }

  buffer.writeln('];');
  return buffer.toString();
}

String _escapeDart(String input) {
  return input.replaceAll(r'\', r'\\').replaceAll("'", r"\'");
}
