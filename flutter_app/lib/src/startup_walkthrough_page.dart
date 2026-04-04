import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import 'app_settings.dart';

class StartupWalkthroughPage extends StatefulWidget {
  const StartupWalkthroughPage({super.key});

  @override
  State<StartupWalkthroughPage> createState() => _StartupWalkthroughPageState();
}

class _StartupWalkthroughPageState extends State<StartupWalkthroughPage> {
  final PageController _pageController = PageController();

  int _pageIndex = 0;
  bool _loading = true;
  bool _saving = false;
  String? _basePath;

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    final basePath = await AppSettings.instance.getTosecGamesBasePath();
    if (!mounted) {
      return;
    }
    setState(() {
      _basePath = basePath;
      _loading = false;
    });
  }

  Future<void> _pickParentFolder() async {
    final path = await FilePicker.platform.getDirectoryPath(
      dialogTitle: 'Choose parent folder for TOSEC games',
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

  Future<void> _completeWalkthrough() async {
    setState(() => _saving = true);
    try {
      await AppSettings.instance.setTosecGamesBasePath(_basePath);
      await AppSettings.instance.setStartupWalkthroughSeen(true);
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

  Future<void> _skipForNow() async {
    await AppSettings.instance.setStartupWalkthroughSeen(true);
    if (!mounted) {
      return;
    }
    Navigator.of(context).pop(false);
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Quick Setup'),
        actions: [
          TextButton(
            onPressed: _saving ? null : _skipForNow,
            child: const Text('Skip'),
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: PageView(
              controller: _pageController,
              onPageChanged: (index) {
                setState(() => _pageIndex = index);
              },
              children: [
                _buildWelcomePage(),
                _buildFolderPage(),
                _buildControlsPage(),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed:
                        _pageIndex == 0
                            ? null
                            : () {
                              _pageController.previousPage(
                                duration: const Duration(milliseconds: 220),
                                curve: Curves.easeOut,
                              );
                            },
                    child: const Text('Back'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child:
                      _pageIndex < 2
                          ? FilledButton(
                            onPressed: () {
                              _pageController.nextPage(
                                duration: const Duration(milliseconds: 220),
                                curve: Curves.easeOut,
                              );
                            },
                            child: const Text('Next'),
                          )
                          : FilledButton(
                            onPressed: _saving ? null : _completeWalkthrough,
                            child:
                                _saving
                                    ? const SizedBox(
                                      width: 20,
                                      height: 20,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                      ),
                                    )
                                    : const Text('Finish Setup'),
                          ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildWelcomePage() {
    return ListView(
      padding: const EdgeInsets.all(20),
      children: const [
        Icon(Icons.computer, size: 64, color: Colors.lightBlueAccent),
        SizedBox(height: 16),
        Text(
          'Welcome to Frodo C64',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
        ),
        SizedBox(height: 16),
        Text(
          'This quick setup will configure your game storage and explain how to load and control games.',
          textAlign: TextAlign.center,
          style: TextStyle(color: Colors.white70),
        ),
        SizedBox(height: 20),
        Card(
          child: ListTile(
            leading: Icon(Icons.public),
            title: Text('TOSEC Download'),
            subtitle: Text('Top-right globe button opens the TOSEC browser.'),
          ),
        ),
        Card(
          child: ListTile(
            leading: Icon(Icons.folder_open),
            title: Text('Load Local File'),
            subtitle: Text(
              'Toolbar folder icon loads a local game file directly.',
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildFolderPage() {
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        const Icon(Icons.folder_copy, size: 64, color: Colors.amberAccent),
        const SizedBox(height: 16),
        const Text(
          'Game Storage Folder',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 16),
        Card(
          child: ListTile(
            leading: const Icon(Icons.drive_folder_upload),
            title: const Text('Parent folder'),
            subtitle: Text(
              _basePath ?? 'Default app storage (internal)',
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ),
        const SizedBox(height: 8),
        FilledButton.icon(
          onPressed: _pickParentFolder,
          icon: const Icon(Icons.folder_open),
          label: const Text('Choose parent folder'),
        ),
        const SizedBox(height: 12),
        Text(
          'Final layout:\n${_basePath ?? '<default app storage>'}/<Format>/\n${_basePath ?? '<default app storage>'}/downloads/',
          style: const TextStyle(color: Colors.white70),
        ),
      ],
    );
  }

  Widget _buildControlsPage() {
    return ListView(
      padding: const EdgeInsets.all(20),
      children: const [
        Icon(Icons.sports_esports, size: 64, color: Colors.greenAccent),
        SizedBox(height: 16),
        Text(
          'Controls and Loading',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
        ),
        SizedBox(height: 16),
        Card(
          child: ListTile(
            leading: Icon(Icons.touch_app),
            title: Text('Show/Hide Controls'),
            subtitle: Text(
              'Tap screen to show toolbar. It auto-hides after 5 seconds.',
            ),
          ),
        ),
        Card(
          child: ListTile(
            leading: Icon(Icons.folder_open),
            title: Text('Load Local Game'),
            subtitle: Text(
              'Use folder icon to pick .d64/.t64/.tap/.z64/.prg and autostart.',
            ),
          ),
        ),
        Card(
          child: ListTile(
            leading: Icon(Icons.public),
            title: Text('Download from TOSEC'),
            subtitle: Text(
              'Use globe button, pick category/format, then extract selected games.',
            ),
          ),
        ),
        Card(
          child: ListTile(
            leading: Icon(Icons.save),
            title: Text('Where Downloads Go'),
            subtitle: Text(
              'Extracted files are saved in parent format folders (D64/T64/TAP/Z64/PRG), and archives in parent/downloads.',
            ),
          ),
        ),
      ],
    );
  }
}
