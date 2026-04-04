import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import 'app_settings.dart';

class TosecStorageSettingsPage extends StatefulWidget {
  const TosecStorageSettingsPage({super.key});

  @override
  State<TosecStorageSettingsPage> createState() =>
      _TosecStorageSettingsPageState();
}

class _TosecStorageSettingsPageState extends State<TosecStorageSettingsPage> {
  bool _loading = true;
  bool _saving = false;
  String? _basePath;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final path = await AppSettings.instance.getTosecGamesBasePath();
    if (!mounted) {
      return;
    }
    setState(() {
      _basePath = path;
      _loading = false;
    });
  }

  Future<void> _pickFolder() async {
    final path = await FilePicker.platform.getDirectoryPath(
      dialogTitle: 'Choose TOSEC games folder',
    );
    if (path == null || path.trim().isEmpty) {
      return;
    }

    final dir = Directory(path);
    await dir.create(recursive: true);

    if (!mounted) {
      return;
    }
    setState(() {
      _basePath = dir.path;
    });
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      await AppSettings.instance.setTosecGamesBasePath(_basePath);
      await AppSettings.instance.setStartupWalkthroughSeen(
        _basePath != null && _basePath!.trim().isNotEmpty,
      );
      if (!mounted) {
        return;
      }
      Navigator.of(context).pop(true);
    } finally {
      if (mounted) {
        setState(() => _saving = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('TOSEC Storage Settings')),
      body:
          _loading
              ? const Center(child: CircularProgressIndicator())
              : Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Text(
                      'Choose where TOSEC games are extracted and listed. Files are stored in category/format subfolders.',
                      style: TextStyle(color: Colors.white70),
                    ),
                    const SizedBox(height: 16),
                    Card(
                      child: ListTile(
                        leading: const Icon(Icons.folder),
                        title: const Text('Games base folder'),
                        subtitle: Text(
                          _basePath ?? 'Default app storage',
                          maxLines: 3,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        FilledButton.icon(
                          onPressed: _saving ? null : _pickFolder,
                          icon: const Icon(Icons.folder_open),
                          label: const Text('Choose folder'),
                        ),
                        OutlinedButton.icon(
                          onPressed:
                              _saving
                                  ? null
                                  : () => setState(() {
                                    _basePath = null;
                                  }),
                          icon: const Icon(Icons.restore),
                          label: const Text('Use default'),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    const Text(
                      'Saved structure: <parent>/<Format>/ plus <parent>/downloads/',
                      style: TextStyle(color: Colors.white54),
                    ),
                    const Spacer(),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            onPressed:
                                _saving
                                    ? null
                                    : () => Navigator.of(context).pop(false),
                            child: const Text('Cancel'),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: FilledButton(
                            onPressed: _saving ? null : _save,
                            child:
                                _saving
                                    ? const SizedBox(
                                      width: 20,
                                      height: 20,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                      ),
                                    )
                                    : const Text('Save'),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
    );
  }
}
