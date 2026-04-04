import 'dart:io';

import 'package:archive/archive_io.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

/// A local game file with metadata for display and operations.
class LocalGameFile {
  const LocalGameFile({
    required this.name,
    required this.path,
    required this.size,
    required this.modified,
  });

  final String name;
  final String path;
  final int size;
  final DateTime modified;

  String get extension => p.extension(name).toLowerCase();

  String get sizeFormatted {
    if (size < 1024) return '$size B';
    if (size < 1024 * 1024) return '${(size / 1024).toStringAsFixed(1)} KB';
    return '${(size / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
}

class LocalFileBrowserPage extends StatefulWidget {
  const LocalFileBrowserPage({
    required this.gamesDirectory,
    required this.onOpenGame,
    super.key,
  });

  /// Root directory containing game files.
  final Directory gamesDirectory;

  /// Callback when user selects a game to load.
  final void Function(String path) onOpenGame;

  @override
  State<LocalFileBrowserPage> createState() => _LocalFileBrowserPageState();
}

class _LocalFileBrowserPageState extends State<LocalFileBrowserPage> {
  static const _supportedExtensions = {
    '.d64',
    '.t64',
    '.tap',
    '.z64',
    '.prg',
    '.zip',
  };

  late Directory _rootDir;
  late Directory _currentDir;
  List<Directory> _subDirs = [];
  List<LocalGameFile> _files = [];
  bool _loading = true;
  String? _error;
  final _searchController = TextEditingController();
  String _query = '';
  String _extensionFilter = 'All';
  String _sortBy = 'name'; // 'name', 'date', 'size'
  bool _sortAscending = true;

  @override
  void initState() {
    super.initState();
    _rootDir = widget.gamesDirectory;
    _currentDir = widget.gamesDirectory;
    _loadFiles();
  }

  Future<void> _pickFolder() async {
    final path = await FilePicker.platform.getDirectoryPath(
      dialogTitle: 'Choose games folder',
    );
    if (path == null || !mounted) return;
    setState(() {
      _rootDir = Directory(path);
      _currentDir = Directory(path);
      _extensionFilter = 'All';
      _query = '';
      _searchController.clear();
    });
    _loadFiles();
  }

  void _navigateInto(Directory dir) {
    setState(() {
      _currentDir = dir;
      _extensionFilter = 'All';
      _query = '';
      _searchController.clear();
    });
    _loadFiles();
  }

  void _navigateUp() {
    final parent = _currentDir.parent;
    setState(() {
      _currentDir = parent;
      _extensionFilter = 'All';
      _query = '';
      _searchController.clear();
    });
    _loadFiles();
  }

  bool get _canGoUp => _currentDir.path != _rootDir.path;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadFiles() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final files = <LocalGameFile>[];
      final subDirs = <Directory>[];

      if (await _currentDir.exists()) {
        // Non-recursive: show subfolders + game files in current dir only.
        // When a search query is active, do a deep recursive scan instead.
        final isSearching = _query.trim().isNotEmpty;
        await for (final entity in _currentDir.list(
          recursive: isSearching,
          followLinks: false,
        )) {
          if (!isSearching && entity is Directory) {
            subDirs.add(entity);
            continue;
          }
          if (entity is! File) continue;

          final ext = p.extension(entity.path).toLowerCase();
          if (!_supportedExtensions.contains(ext)) continue;

          final stat = await entity.stat();
          files.add(
            LocalGameFile(
              name: p.basename(entity.path),
              path: entity.path,
              size: stat.size,
              modified: stat.modified,
            ),
          );
        }
        subDirs.sort(
          (a, b) => p
              .basename(a.path)
              .toLowerCase()
              .compareTo(p.basename(b.path).toLowerCase()),
        );
      }

      setState(() {
        _subDirs = subDirs;
        _files = files;
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  List<LocalGameFile> _getFilteredFiles() {
    var filtered =
        _files.where((f) {
          // Extension filter
          if (_extensionFilter != 'All') {
            if (f.extension != '.${_extensionFilter.toLowerCase()}') {
              return false;
            }
          }
          // Search query
          if (_query.isNotEmpty) {
            if (!f.name.toLowerCase().contains(_query.toLowerCase())) {
              return false;
            }
          }
          return true;
        }).toList();

    // Sort
    filtered.sort((a, b) {
      int cmp;
      switch (_sortBy) {
        case 'date':
          cmp = a.modified.compareTo(b.modified);
        case 'size':
          cmp = a.size.compareTo(b.size);
        default:
          cmp = a.name.toLowerCase().compareTo(b.name.toLowerCase());
      }
      return _sortAscending ? cmp : -cmp;
    });

    return filtered;
  }

  Set<String> _getExtensionOptions() {
    final options = <String>{'All'};
    for (final f in _files) {
      final ext = f.extension.replaceFirst('.', '').toUpperCase();
      if (ext.isNotEmpty) options.add(ext);
    }
    return options;
  }

  Future<void> _deleteFile(LocalGameFile file) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder:
          (ctx) => AlertDialog(
            title: const Text('Delete File'),
            content: Text('Delete "${file.name}"?\n\nThis cannot be undone.'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Cancel'),
              ),
              TextButton(
                onPressed: () => Navigator.pop(ctx, true),
                style: TextButton.styleFrom(foregroundColor: Colors.red),
                child: const Text('Delete'),
              ),
            ],
          ),
    );

    if (confirm != true || !mounted) return;

    try {
      await File(file.path).delete();
      _loadFiles();
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Deleted ${file.name}')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Failed to delete: $e')));
      }
    }
  }

  Future<void> _renameFile(LocalGameFile file) async {
    final controller = TextEditingController(
      text: p.basenameWithoutExtension(file.name),
    );

    final newName = await showDialog<String>(
      context: context,
      builder:
          (ctx) => AlertDialog(
            title: const Text('Rename File'),
            content: TextField(
              controller: controller,
              autofocus: true,
              decoration: InputDecoration(
                labelText: 'New name',
                suffixText: file.extension,
              ),
              onSubmitted: (value) => Navigator.pop(ctx, value),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Cancel'),
              ),
              TextButton(
                onPressed: () => Navigator.pop(ctx, controller.text),
                child: const Text('Rename'),
              ),
            ],
          ),
    );

    controller.dispose();

    if (newName == null || newName.trim().isEmpty || !mounted) return;

    final sanitized = newName.trim().replaceAll(RegExp(r'[<>:"/\\|?*]'), '_');
    final newPath = p.join(p.dirname(file.path), '$sanitized${file.extension}');

    if (newPath == file.path) return;

    try {
      await File(file.path).rename(newPath);
      _loadFiles();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Renamed to $sanitized${file.extension}')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Failed to rename: $e')));
      }
    }
  }

  Future<void> _zipFile(LocalGameFile file) async {
    final zipName = '${p.basenameWithoutExtension(file.name)}.zip';
    // Organise by file type: place zip in <root>/D64/, <root>/T64/, etc.
    final format = file.extension.replaceFirst('.', '').toUpperCase();
    final targetDir = Directory(p.join(_rootDir.path, format));
    await targetDir.create(recursive: true);
    final zipPath = p.join(targetDir.path, zipName);

    // Check if zip already exists
    if (await File(zipPath).exists()) {
      final overwrite = await showDialog<bool>(
        context: context,
        builder:
            (ctx) => AlertDialog(
              title: const Text('File Exists'),
              content: Text('$zipName already exists. Overwrite?'),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx, false),
                  child: const Text('Cancel'),
                ),
                TextButton(
                  onPressed: () => Navigator.pop(ctx, true),
                  child: const Text('Overwrite'),
                ),
              ],
            ),
      );
      if (overwrite != true || !mounted) return;
    }

    try {
      // Show progress
      showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder:
            (_) => const AlertDialog(
              title: Text('Creating ZIP...'),
              content: SizedBox(
                height: 60,
                child: Center(child: CircularProgressIndicator()),
              ),
            ),
      );

      final archive = Archive();
      final fileBytes = await File(file.path).readAsBytes();
      archive.addFile(ArchiveFile(file.name, fileBytes.length, fileBytes));

      // Write directly to disk via OutputFileStream (reliable path).
      final output = OutputFileStream(zipPath);
      ZipEncoder().encode(archive, output: output);
      output.close();

      // Verify zip was created and is not empty before removing original.
      final createdZip = File(zipPath);
      final zipSize = await createdZip.length();
      if (!await createdZip.exists() || zipSize <= 22) {
        // 22 bytes = empty zip (end-of-central-directory only).
        if (await createdZip.exists()) await createdZip.delete();
        throw Exception('ZIP creation produced an empty file');
      }

      await File(file.path).delete();

      if (mounted) {
        Navigator.of(context, rootNavigator: true).pop(); // Close progress
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Created $zipName → $format/')));
        // Navigate into the target subfolder so the new zip is visible.
        _navigateInto(targetDir);
      }
    } catch (e) {
      if (mounted) {
        Navigator.of(context, rootNavigator: true).pop(); // Close progress
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Failed to create ZIP: $e')));
      }
    }
  }

  void _showFileOptions(LocalGameFile file) {
    showModalBottomSheet(
      context: context,
      builder:
          (ctx) => SafeArea(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ListTile(
                  leading: const Icon(Icons.play_arrow),
                  title: const Text('Load Game'),
                  onTap: () {
                    Navigator.pop(ctx);
                    Navigator.pop(context); // Close browser
                    widget.onOpenGame(file.path);
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.edit),
                  title: const Text('Rename'),
                  onTap: () {
                    Navigator.pop(ctx);
                    _renameFile(file);
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.archive),
                  title: const Text('Create ZIP'),
                  onTap: () {
                    Navigator.pop(ctx);
                    _zipFile(file);
                  },
                ),
                const Divider(),
                ListTile(
                  leading: const Icon(Icons.delete, color: Colors.red),
                  title: const Text(
                    'Delete',
                    style: TextStyle(color: Colors.red),
                  ),
                  onTap: () {
                    Navigator.pop(ctx);
                    _deleteFile(file);
                  },
                ),
              ],
            ),
          ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final filtered = _getFilteredFiles();
    final extensionOptions = _getExtensionOptions();

    return Scaffold(
      appBar: AppBar(
        leading:
            _canGoUp
                ? IconButton(
                  icon: const Icon(Icons.arrow_upward),
                  tooltip: 'Up to parent folder',
                  onPressed: _navigateUp,
                )
                : null,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Local Games', style: TextStyle(fontSize: 18)),
            Text(
              _currentDir.path,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 11, color: Colors.white60),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.folder_open),
            tooltip: 'Change folder',
            onPressed: _pickFolder,
          ),
          PopupMenuButton<String>(
            icon: const Icon(Icons.sort),
            tooltip: 'Sort',
            onSelected: (value) {
              setState(() {
                if (_sortBy == value) {
                  _sortAscending = !_sortAscending;
                } else {
                  _sortBy = value;
                  _sortAscending = true;
                }
              });
            },
            itemBuilder:
                (_) => [
                  CheckedPopupMenuItem(
                    value: 'name',
                    checked: _sortBy == 'name',
                    child: const Text('Name'),
                  ),
                  CheckedPopupMenuItem(
                    value: 'date',
                    checked: _sortBy == 'date',
                    child: const Text('Date'),
                  ),
                  CheckedPopupMenuItem(
                    value: 'size',
                    checked: _sortBy == 'size',
                    child: const Text('Size'),
                  ),
                ],
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh',
            onPressed: _loadFiles,
          ),
        ],
      ),
      body: Column(
        children: [
          // Search and filter bar
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _searchController,
                    decoration: InputDecoration(
                      isDense: true,
                      hintText: 'Search...',
                      prefixIcon: const Icon(Icons.search, size: 20),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 8,
                      ),
                      suffixIcon:
                          _query.isNotEmpty
                              ? IconButton(
                                icon: const Icon(Icons.clear, size: 18),
                                onPressed: () {
                                  _searchController.clear();
                                  setState(() => _query = '');
                                  _loadFiles();
                                },
                              )
                              : null,
                    ),
                    onChanged: (v) {
                      setState(() => _query = v);
                      _loadFiles();
                    },
                  ),
                ),
                const SizedBox(width: 4),
                SizedBox(
                  width: 70,
                  child: DropdownButton<String>(
                    isExpanded: true,
                    value: _extensionFilter,
                    items:
                        extensionOptions
                            .map(
                              (e) => DropdownMenuItem(
                                value: e,
                                child: Text(
                                  e,
                                  style: const TextStyle(fontSize: 13),
                                ),
                              ),
                            )
                            .toList(),
                    onChanged: (v) {
                      if (v != null) setState(() => _extensionFilter = v);
                    },
                  ),
                ),
              ],
            ),
          ),
          // File list
          Expanded(
            child:
                _loading
                    ? const Center(child: CircularProgressIndicator())
                    : _error != null
                    ? Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(
                            Icons.error_outline,
                            size: 48,
                            color: Colors.red,
                          ),
                          const SizedBox(height: 8),
                          Text('Error: $_error'),
                          const SizedBox(height: 16),
                          ElevatedButton(
                            onPressed: _loadFiles,
                            child: const Text('Retry'),
                          ),
                        ],
                      ),
                    )
                    : (_subDirs.isEmpty && filtered.isEmpty)
                    ? Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(
                            Icons.folder_open,
                            size: 64,
                            color: Colors.grey,
                          ),
                          const SizedBox(height: 16),
                          Text(
                            _query.isNotEmpty
                                ? 'No matches for "$_query"'
                                : 'No game files found',
                            style: const TextStyle(color: Colors.grey),
                          ),
                        ],
                      ),
                    )
                    : ListView.builder(
                      itemCount: _subDirs.length + filtered.length,
                      itemBuilder: (context, index) {
                        // Subfolders first
                        if (index < _subDirs.length) {
                          final dir = _subDirs[index];
                          final name = p.basename(dir.path);
                          return ListTile(
                            leading: const CircleAvatar(
                              backgroundColor: Color(0x33FFB300),
                              child: Icon(
                                Icons.folder,
                                color: Colors.amber,
                                size: 20,
                              ),
                            ),
                            title: Text(
                              name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            trailing: const Icon(Icons.chevron_right),
                            onTap: () => _navigateInto(dir),
                          );
                        }
                        // Game files
                        final file = filtered[index - _subDirs.length];
                        return ListTile(
                          leading: _iconForExtension(file.extension),
                          title: Text(
                            file.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          subtitle: Text(
                            '${file.sizeFormatted} • ${_formatDate(file.modified)}',
                            style: const TextStyle(fontSize: 12),
                          ),
                          trailing: IconButton(
                            icon: const Icon(Icons.more_vert),
                            onPressed: () => _showFileOptions(file),
                          ),
                          onTap: () {
                            Navigator.pop(context);
                            widget.onOpenGame(file.path);
                          },
                          onLongPress: () => _showFileOptions(file),
                        );
                      },
                    ),
          ),
        ],
      ),
    );
  }

  Widget _iconForExtension(String ext) {
    IconData icon;
    Color color;
    switch (ext) {
      case '.d64':
        icon = Icons.album;
        color = Colors.blue;
      case '.t64':
        icon = Icons.storage;
        color = Colors.green;
      case '.tap':
        icon = Icons.radio; // tape player icon substitute
        color = Colors.orange;
      case '.prg':
        icon = Icons.code;
        color = Colors.purple;
      default:
        icon = Icons.insert_drive_file;
        color = Colors.grey;
    }
    return CircleAvatar(
      backgroundColor: color.withOpacity(0.2),
      child: Icon(icon, color: color, size: 20),
    );
  }

  String _formatDate(DateTime dt) {
    return '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')}';
  }
}
