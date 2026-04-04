import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:html/parser.dart' as html_parser;

import 'tosec_storage.dart';
import 'tosec_storage_settings_page.dart';

const _archiveGamesBaseUrl =
    'https://archive.org/download/tosec-full-2022-07-10/Commodore/C64/Games/';

const List<String> _categoryOrder = [
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

const List<String> _formatOrder = ['D64', 'T64', 'TAP', 'Z64', 'PRG'];

class TosecGameEntry {
  const TosecGameEntry({
    required this.title,
    required this.category,
    required this.format,
    required this.detailUrl,
  });

  final String title;
  final String category;
  final String format;
  final String detailUrl;
}

class TosecDownloadBrowser extends StatefulWidget {
  const TosecDownloadBrowser({
    super.key,
    required this.onListLocalGames,
    required this.onDownloadGame,
    required this.onOpenLocalGame,
  });

  final Future<List<TosecLocalGame>> Function(String category, String format)
  onListLocalGames;
  final Future<List<TosecLocalGame>> Function(TosecGameEntry game)
  onDownloadGame;
  final Future<void> Function(String path) onOpenLocalGame;

  @override
  State<TosecDownloadBrowser> createState() => _TosecDownloadBrowserState();
}

class _TosecDownloadBrowserState extends State<TosecDownloadBrowser> {
  final http.Client _client = http.Client();

  String _selectedCategory = 'Arcade';
  String _selectedFormat = 'D64';
  bool _loadingRemote = false;
  bool _loadingLocal = false;
  bool _syncingGame = false;
  String? _remoteError;
  String? _localError;
  List<TosecGameEntry> _gameEntries = const [];
  List<TosecLocalGame> _localGames = const [];

  @override
  void initState() {
    super.initState();
    _refreshSelection();
  }

  @override
  void dispose() {
    _client.close();
    super.dispose();
  }

  Future<void> _refreshSelection() async {
    await _loadLocalGames();
    await _loadEntries();
  }

  Future<void> _loadLocalGames() async {
    setState(() {
      _loadingLocal = true;
      _localError = null;
    });

    try {
      final games = await widget.onListLocalGames(
        _selectedCategory,
        _selectedFormat,
      );
      if (!mounted) {
        return;
      }
      setState(() {
        _localGames = games;
        _loadingLocal = false;
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _localGames = const [];
        _loadingLocal = false;
        _localError = error.toString();
      });
    }
  }

  Future<void> _loadEntries() async {
    setState(() {
      _loadingRemote = true;
      _remoteError = null;
    });

    final baseUri = Uri.parse(_archiveGamesBaseUrl);

    try {
      final categoryPath = Uri.encodeComponent(_selectedCategory);
      final formatDir = Uri.encodeComponent('[$_selectedFormat]');
      final formatUri = baseUri.resolve('$categoryPath/$formatDir/');

      final response = await _client.get(
        formatUri,
        headers: const {
          'User-Agent': 'Mozilla/5.0 (compatible; FrodoTosecBrowser/1.0)',
        },
      );
      if (response.statusCode != 200) {
        throw Exception(
          'Failed to load category/format directory: HTTP ${response.statusCode}',
        );
      }

      final document = html_parser.parse(response.body);
      final entries = <TosecGameEntry>[];

      // Find all .7z and .zip archive files in the directory
      for (final anchor in document.querySelectorAll('a[href]')) {
        final href = anchor.attributes['href'];
        if (href == null || href.isEmpty) {
          continue;
        }
        final title = anchor.text.trim();
        final lowerTitle = title.toLowerCase();

        // Only accept .7z and .zip files
        bool isZip = lowerTitle.endsWith('.zip');
        bool is7z = lowerTitle.endsWith('.7z');

        if (!isZip && !is7z) {
          continue;
        }

        final archiveUri = formatUri.resolve(href);
        final downloadUrl = archiveUri.toString();

        // Create a single game entry for this archive
        entries.add(
          TosecGameEntry(
            title: title,
            category: _selectedCategory,
            format: _selectedFormat,
            detailUrl: downloadUrl,
          ),
        );
      }

      if (entries.isEmpty) {
        // No archives found for this category/format
        if (!mounted) {
          return;
        }
        setState(() {
          _gameEntries = const [];
          _loadingRemote = false;
          _remoteError = null;
        });
        return;
      }

      entries.sort((a, b) => a.title.compareTo(b.title));

      if (!mounted) {
        return;
      }
      setState(() {
        _gameEntries = entries;
        _loadingRemote = false;
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _gameEntries = const [];
        _loadingRemote = false;
        _remoteError = error.toString();
      });
    }
  }

  Future<void> _downloadGame(TosecGameEntry entry) async {
    setState(() {
      _syncingGame = true;
      _localError = null;
    });

    try {
      final games = await widget.onDownloadGame(entry);
      if (!mounted) {
        return;
      }
      setState(() {
        _localGames = games;
        _syncingGame = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Downloaded. Local games: ${games.length}')),
      );
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _syncingGame = false;
        _localError = error.toString();
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Game download failed: $error'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<void> _openLocalGame(TosecLocalGame game) async {
    try {
      await widget.onOpenLocalGame(game.path);
      if (!mounted) {
        return;
      }
      Navigator.of(context).pop();
    } catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to load game: $error'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<void> _showDownloadedGamesSheet() async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder:
          (ctx) => SafeArea(
            child: SizedBox(
              height: MediaQuery.of(ctx).size.height * 0.75,
              child: Column(
                children: [
                  const ListTile(
                    title: Text('Downloaded Games'),
                    subtitle: Text('Tap a game to load it.'),
                  ),
                  const Divider(height: 1),
                  Expanded(
                    child:
                        _loadingLocal
                            ? const Center(child: CircularProgressIndicator())
                            : _localError != null
                            ? Padding(
                              padding: const EdgeInsets.all(16),
                              child: Text(
                                _localError!,
                                style: const TextStyle(color: Colors.redAccent),
                              ),
                            )
                            : _localGames.isEmpty
                            ? const Padding(
                              padding: EdgeInsets.all(16),
                              child: Text(
                                'No downloaded games for this category and format.',
                              ),
                            )
                            : ListView.builder(
                              itemCount: _localGames.length,
                              itemBuilder: (context, index) {
                                final game = _localGames[index];
                                return ListTile(
                                  leading: const Icon(Icons.videogame_asset),
                                  title: Text(game.name),
                                  subtitle: Text(game.relativePath),
                                  onTap: () => _openLocalGame(game),
                                );
                              },
                            ),
                  ),
                ],
              ),
            ),
          ),
    );
  }

  Future<void> _openStorageSettings() async {
    final changed = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => const TosecStorageSettingsPage()),
    );

    if (changed == true) {
      await _loadLocalGames();
    }
  }

  @override
  Widget build(BuildContext context) {
    final remoteEntries = _gameEntries;

    return Scaffold(
      appBar: AppBar(
        title: const Text('TOSEC Browser'),
        actions: [
          Badge(
            label: Text('${_localGames.length}'),
            isLabelVisible: _localGames.isNotEmpty,
            child: IconButton(
              tooltip: 'Downloaded games',
              onPressed: _showDownloadedGamesSheet,
              icon: const Icon(Icons.download_done),
            ),
          ),
          IconButton(
            tooltip: 'Refresh',
            onPressed: _loadingRemote ? null : _refreshSelection,
            icon: const Icon(Icons.refresh),
          ),
          IconButton(
            tooltip: 'Storage settings',
            onPressed: _openStorageSettings,
            icon: const Icon(Icons.folder_copy_outlined),
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 6),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Expanded(
                  flex: 3,
                  child: DropdownButtonFormField<String>(
                    initialValue: _selectedCategory,
                    isDense: true,
                    decoration: const InputDecoration(
                      labelText: 'Category',
                      isDense: true,
                      border: OutlineInputBorder(),
                      contentPadding: EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 10,
                      ),
                    ),
                    items:
                        _categoryOrder
                            .map(
                              (c) => DropdownMenuItem<String>(
                                value: c,
                                child: Text(c, overflow: TextOverflow.ellipsis),
                              ),
                            )
                            .toList(),
                    onChanged: (value) {
                      if (value == null) return;
                      setState(() => _selectedCategory = value);
                      _refreshSelection();
                    },
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  flex: 2,
                  child: DropdownButtonFormField<String>(
                    initialValue: _selectedFormat,
                    isDense: true,
                    decoration: const InputDecoration(
                      labelText: 'Format',
                      isDense: true,
                      border: OutlineInputBorder(),
                      contentPadding: EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 10,
                      ),
                    ),
                    items:
                        _formatOrder
                            .map(
                              (f) => DropdownMenuItem<String>(
                                value: f,
                                child: Text(f),
                              ),
                            )
                            .toList(),
                    onChanged: (value) {
                      if (value == null) return;
                      setState(() => _selectedFormat = value);
                      _refreshSelection();
                    },
                  ),
                ),
              ],
            ),
          ),
          if (_syncingGame)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 8),
              child: LinearProgressIndicator(),
            ),
          Expanded(
            child: ListView(
              children: [
                ListTile(
                  leading: const Icon(Icons.archive, color: Colors.amberAccent),
                  title: Text('Remote games: ${_gameEntries.length}'),
                  subtitle: const Text(
                    'Download individual games from the selected category/format.',
                  ),
                ),
                if (_loadingRemote)
                  const Padding(
                    padding: EdgeInsets.all(24),
                    child: Center(child: CircularProgressIndicator()),
                  )
                else if (_remoteError != null)
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: Text(
                      _remoteError!,
                      style: const TextStyle(color: Colors.redAccent),
                    ),
                  )
                else if (remoteEntries.isEmpty)
                  const Padding(
                    padding: EdgeInsets.all(16),
                    child: Text(
                      'No remote games found for this selection.',
                      style: TextStyle(color: Colors.white60),
                    ),
                  )
                else
                  ...remoteEntries.map(
                    (entry) => ListTile(
                      leading: const Icon(
                        Icons.inventory_2,
                        color: Colors.amberAccent,
                      ),
                      title: Text(entry.title),
                      subtitle: Text('${entry.category}  •  ${entry.format}'),
                      trailing: FilledButton(
                        onPressed:
                            _syncingGame ? null : () => _downloadGame(entry),
                        child: const Text('Download'),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
