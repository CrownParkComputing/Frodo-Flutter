import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'src/emulator_display.dart';
import 'src/emulator_toolbar.dart';
import 'src/frodo_bindings.dart';
import 'src/app_settings.dart';
import 'src/pages/local_file_browser_page.dart';
import 'src/startup_walkthrough_page.dart';
import 'src/tosec_download_browser.dart';
import 'src/tosec_storage.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setPreferredOrientations([
    DeviceOrientation.landscapeLeft,
    DeviceOrientation.landscapeRight,
  ]);
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
  runApp(const FrodoApp());
}

class FrodoApp extends StatelessWidget {
  const FrodoApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Frodo C64',
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark(useMaterial3: true).copyWith(
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.indigo,
          brightness: Brightness.dark,
        ),
      ),
      home: const EmulatorPage(),
    );
  }
}

class EmulatorPage extends StatefulWidget {
  const EmulatorPage({super.key});

  @override
  State<EmulatorPage> createState() => _EmulatorPageState();
}

class _EmulatorPageState extends State<EmulatorPage>
    with WidgetsBindingObserver {
  final TosecStorage _tosecStorage = TosecStorage();
  FrodoBridge? _bridge;
  bool _startupWalkthroughChecked = false;
  Future<void> _extractionQueue = Future.value();
  var _queuedExtractions = 0;
  var _activeExtractions = 0;
  bool _initialized = false;
  bool _initializing = false;
  String? _initError;
  DisplayAspectMode _aspectMode = DisplayAspectMode.standard4x3;
  bool _toolbarVisible = true;
  bool _keyboardVisible = false;
  bool _crtMode = false;
  bool _tapVisible = false;
  Timer? _hideToolbarTimer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _bridge = FrodoBridge.instance;
    _startHideToolbarTimer();
  }

  Future<void> _showStartupWalkthroughIfNeeded({bool force = false}) async {
    if (!force) {
      return;
    }

    if (!mounted) {
      return;
    }

    if (!force && _startupWalkthroughChecked) {
      return;
    }

    final hasSeen = await AppSettings.instance.hasSeenStartupWalkthrough();
    final configuredBasePath =
        await AppSettings.instance.getTosecGamesBasePath();
    final hasConfiguredPath =
        configuredBasePath != null && configuredBasePath.trim().isNotEmpty;
    if (!mounted) {
      return;
    }

    _startupWalkthroughChecked = true;
    if (!force && (hasSeen || hasConfiguredPath)) {
      if (hasConfiguredPath && !hasSeen) {
        await AppSettings.instance.setStartupWalkthroughSeen(true);
      }
      return;
    }

    await Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => const StartupWalkthroughPage()));
  }

  Future<void> _initEmulator() async {
    if (_initializing || _initialized) return;
    setState(() {
      _initializing = true;
      _initError = null;
    });

    try {
      final rc = _bridge!.init();
      setState(() {
        _initialized = rc >= 0;
        _initError = rc < 0 ? 'Emulator init failed (code $rc)' : null;
        _initializing = false;
      });
    } catch (e) {
      setState(() {
        _initError = e.toString();
        _initializing = false;
      });
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _hideToolbarTimer?.cancel();
    _tosecStorage.dispose();
    _bridge?.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (_bridge == null || !_initialized) return;
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive) {
      _bridge!.pauseAudio();
    } else if (state == AppLifecycleState.resumed) {
      _bridge!.resumeAudio();
    }
  }

  void _startHideToolbarTimer() {
    if (_keyboardVisible) {
      _hideToolbarTimer?.cancel();
      return;
    }
    _hideToolbarTimer?.cancel();
    _hideToolbarTimer = Timer(const Duration(seconds: 5), () {
      if (mounted) {
        setState(() => _toolbarVisible = false);
      }
    });
  }

  void _showToolbar() {
    if (!_toolbarVisible) {
      setState(() => _toolbarVisible = true);
    }
    _startHideToolbarTimer();
  }

  void _toggleVirtualKeyboard() {
    setState(() {
      _keyboardVisible = !_keyboardVisible;
      _toolbarVisible = true;
    });
    _startHideToolbarTimer();
  }

  Future<void> _handleLoadFile() async {
    if (_bridge == null || !mounted) return;

    final source = await showModalBottomSheet<String>(
      context: context,
      builder:
          (ctx) => SafeArea(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const ListTile(
                  title: Text('Game Selector'),
                  subtitle: Text('Choose source for loading a game'),
                ),
                ListTile(
                  leading: const Icon(Icons.games),
                  title: const Text('My Games'),
                  subtitle: const Text('Browse, rename, delete local games'),
                  onTap: () => Navigator.of(ctx).pop('browse'),
                ),
                ListTile(
                  leading: const Icon(Icons.public),
                  title: const Text('TOSEC Browser'),
                  subtitle: const Text('Download/select from TOSEC archives'),
                  onTap: () => Navigator.of(ctx).pop('tosec'),
                ),
              ],
            ),
          ),
    );

    if (!mounted || source == null) {
      return;
    }

    if (source == 'tosec') {
      _handleTosecDownload();
      return;
    }

    if (source == 'browse') {
      _handleBrowseLocalGames();
      return;
    }
  }

  Future<void> _handleBrowseLocalGames() async {
    final gamesDir = await _tosecStorage.getGamesRootDirectory();
    if (!mounted) return;

    Navigator.of(context).push(
      MaterialPageRoute(
        builder:
            (_) => LocalFileBrowserPage(
              gamesDirectory: gamesDir,
              onOpenGame: (path) {
                final lower = path.toLowerCase();
                if (lower.endsWith('.zip') || lower.endsWith('.7z')) {
                  _loadFromLocalArchive(path);
                } else {
                  _loadLocalGame(path);
                }
              },
            ),
      ),
    );
  }

  Future<void> _loadFromLocalArchive(String archivePath) async {
    if (!mounted) {
      return;
    }

    final archiveName = archivePath.split(Platform.pathSeparator).last;

    final progressDialog = showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder:
          (_) => const AlertDialog(
            title: Text('Reading archive...'),
            content: SizedBox(
              height: 72,
              child: Center(child: CircularProgressIndicator()),
            ),
          ),
    );

    TosecArchiveContents contents;
    try {
      contents = await _tosecStorage.prepareLocalArchiveSelection(
        archivePath: archivePath,
      );
    } finally {
      if (mounted) {
        Navigator.of(context, rootNavigator: true).pop();
      }
      await progressDialog;
    }

    if (contents.entries.isEmpty) {
      throw Exception('No supported C64 files found inside $archiveName');
    }

    List<String> selectedEntries;
    if (contents.entries.length == 1) {
      selectedEntries = [contents.entries.first];
    } else {
      selectedEntries =
          await Navigator.of(context).push<List<String>>(
            MaterialPageRoute(
              builder:
                  (context) => ArchiveSelectionPage(
                    archiveTitle: archiveName,
                    entries: contents.entries,
                  ),
            ),
          ) ??
          const [];
    }

    if (selectedEntries.isEmpty) {
      return;
    }

    final extractingDialog = showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder:
          (_) => AlertDialog(
            title: const Text('Extracting game files...'),
            content: Text('${selectedEntries.length} file(s) selected'),
          ),
    );

    List<String> extractedPaths;
    try {
      extractedPaths = await _tosecStorage.extractSelectedFromLocalArchive(
        archivePath: archivePath,
        selectedEntries: selectedEntries,
      );
    } finally {
      if (mounted) {
        Navigator.of(context, rootNavigator: true).pop();
      }
      await extractingDialog;
    }

    if (extractedPaths.isEmpty) {
      throw Exception('Failed to extract selected files from $archiveName');
    }

    String fileToLoad = extractedPaths.first;
    if (extractedPaths.length > 1 && mounted) {
      final chosen = await showModalBottomSheet<String>(
        context: context,
        builder:
            (ctx) => SafeArea(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const ListTile(title: Text('Select extracted game to load')),
                  for (final path in extractedPaths)
                    ListTile(
                      title: Text(path.split(Platform.pathSeparator).last),
                      onTap: () => Navigator.of(ctx).pop(path),
                    ),
                ],
              ),
            ),
      );
      if (chosen == null) {
        return;
      }
      fileToLoad = chosen;
    }

    await _loadLocalGame(fileToLoad);
  }

  void _handleTosecDownload() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder:
            (_) => TosecDownloadBrowser(
              onListLocalGames: _listTosecGames,
              onDownloadGame: _downloadSingleGame,
              onOpenLocalGame: _loadLocalGame,
            ),
      ),
    );
  }

  Future<List<TosecLocalGame>> _listTosecGames(String category, String format) {
    return _tosecStorage.listGames(category, format);
  }

  Future<List<TosecLocalGame>> _downloadSingleGame(TosecGameEntry game) async {
    final progress = ValueNotifier<_ArchiveProgress>(
      const _ArchiveProgress(status: 'Preparing...', receivedBytes: 0),
    );

    var progressDialogOpen = false;
    if (mounted) {
      progressDialogOpen = true;
      showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder:
            (ctx) => ValueListenableBuilder<_ArchiveProgress>(
              valueListenable: progress,
              builder: (context, value, _) {
                final totalBytes = value.totalBytes;
                final hasTotal = totalBytes != null && totalBytes > 0;
                final progressValue =
                    hasTotal ? value.receivedBytes / totalBytes : null;
                final percentText =
                    hasTotal
                        ? '${(progressValue! * 100).toStringAsFixed(1)}%'
                        : null;

                return AlertDialog(
                  title: const Text('Archive download / scan'),
                  content: SizedBox(
                    width: 360,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('${game.category}  •  ${game.format}'),
                        const SizedBox(height: 12),
                        Text(value.status),
                        const SizedBox(height: 12),
                        LinearProgressIndicator(value: progressValue),
                        const SizedBox(height: 8),
                        Text(
                          hasTotal
                              ? '${_formatBytes(value.receivedBytes)} / ${_formatBytes(totalBytes)} ($percentText)'
                              : '${_formatBytes(value.receivedBytes)} downloaded',
                          style: const TextStyle(color: Colors.white70),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
      );
    }

    try {
      final archiveContents = await _tosecStorage.prepareArchiveSelection(
        detailUrl: game.detailUrl,
        onStatus: (status) {
          progress.value = progress.value.copyWith(status: status);
        },
        onProgress: (receivedBytes, totalBytes) {
          progress.value = progress.value.copyWith(
            status: 'Downloading archive...',
            receivedBytes: receivedBytes,
            totalBytes: totalBytes,
          );
        },
      );
      if (progressDialogOpen && mounted) {
        Navigator.pop(context);
        progressDialogOpen = false;
      }

      if (archiveContents.entries.isEmpty) {
        throw Exception('Archive has no supported game files to load.');
      }

      if (!mounted) return [];
      final selectedEntries =
          await Navigator.of(context).push<List<String>>(
            MaterialPageRoute(
              builder:
                  (context) => ArchiveSelectionPage(
                    archiveTitle: game.title,
                    entries: archiveContents.entries,
                  ),
            ),
          ) ??
          [];

      if (selectedEntries.isEmpty) {
        return _tosecStorage.listGames(game.category, game.format);
      }

      _queueExtractionJob(
        game: game,
        archivePath: archiveContents.archivePath,
        selectedEntries: selectedEntries,
      );

      return _tosecStorage.listGames(game.category, game.format);
    } catch (error) {
      if (progressDialogOpen && mounted) {
        Navigator.pop(context);
        progressDialogOpen = false;
      }
      rethrow;
    } finally {
      progress.dispose();
    }
  }

  void _queueExtractionJob({
    required TosecGameEntry game,
    required String archivePath,
    required List<String> selectedEntries,
  }) {
    _queuedExtractions += 1;
    final queueDepth = _queuedExtractions + _activeExtractions;
    if (mounted) {
      final queuedText = queueDepth > 1 ? 'Queued (#$queueDepth)' : 'Queued';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '$queuedText extraction for ${game.format}: ${selectedEntries.length} file(s)',
          ),
          duration: const Duration(seconds: 2),
        ),
      );
    }

    _extractionQueue = _extractionQueue
        .then((_) async {
          _queuedExtractions -= 1;
          _activeExtractions += 1;

          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                  'Extracting ${selectedEntries.length} ${game.format} file(s)...',
                ),
                duration: const Duration(seconds: 2),
              ),
            );
          }

          await _tosecStorage.extractSelectedFromArchive(
            category: game.category,
            format: game.format,
            archivePath: archivePath,
            selectedEntries: selectedEntries,
          );

          if (mounted) {
            final updatedGames = await _tosecStorage.listGames(
              game.category,
              game.format,
            );
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                  'Extraction complete. ${updatedGames.length} local ${game.format} game(s).',
                ),
                duration: const Duration(seconds: 3),
              ),
            );
          }
        })
        .catchError((error) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('Background extraction failed: $error'),
                backgroundColor: Colors.red,
                duration: const Duration(seconds: 4),
              ),
            );
          }
        })
        .whenComplete(() {
          _activeExtractions = (_activeExtractions - 1).clamp(0, 1 << 20);
        });
  }

  String _formatBytes(int bytes) {
    const units = ['B', 'KB', 'MB', 'GB'];
    var value = bytes.toDouble();
    var unitIndex = 0;
    while (value >= 1024 && unitIndex < units.length - 1) {
      value /= 1024;
      unitIndex += 1;
    }
    final precision = value >= 100 ? 0 : (value >= 10 ? 1 : 2);
    return '${value.toStringAsFixed(precision)} ${units[unitIndex]}';
  }

  Future<void> _loadLocalGame(String path) async {
    if (_bridge == null) return;

    if (!_initialized || !_bridge!.isReady) {
      await _initEmulator();
      if (!_initialized || !_bridge!.isReady) {
        throw Exception('Emulator is not ready');
      }
    }

    final lower = path.toLowerCase();

    // Mount media first, then run format-specific auto-load sequence.
    _bridge!.loadFile(path);
    await Future<void>.delayed(const Duration(milliseconds: 80));

    if (lower.endsWith('.tap') ||
        lower.endsWith('.d64') ||
        lower.endsWith('.g64') ||
        lower.endsWith('.t64')) {
      // Set AutoStart flag and let the pending-frames countdown fire
      // AutoStartOp() once BASIC is ready.  AutoStartOp handles each
      // media type: disk → LOAD"*",8,1  tape → LOAD"" + PLAY
      // archive/t64 → LOAD"",8.
      _bridge!.autostartMountedMedia();
    } else {
      _bridge!.autostartMountedMedia();
      _bridge!.startCurrentMedia();
    }

    // Show the tape deck bar only when a .tap file is loaded
    setState(() {
      _tapVisible = lower.endsWith('.tap');
    });

    if (mounted) {
      final fileName = path.split(Platform.pathSeparator).last;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Loaded: $fileName')));
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_initialized) {
      return Scaffold(
        backgroundColor: Colors.black,
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (_initError != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 16),
                  child: Text(
                    _initError!,
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Colors.red, fontSize: 14),
                  ),
                ),
              ElevatedButton.icon(
                onPressed: _initializing ? null : _initEmulator,
                icon: const Icon(Icons.play_arrow),
                label: Text(_initializing ? 'Starting...' : 'Start Emulator'),
              ),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: () => _showStartupWalkthroughIfNeeded(force: true),
                icon: const Icon(Icons.help_outline),
                label: const Text('Quick Setup Walkthrough'),
              ),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: Colors.black,
      body: GestureDetector(
        onTap: _showToolbar,
        child: Stack(
          children: [
            Positioned.fill(
              child: EmulatorDisplay(
                aspectMode: _aspectMode,
                crtMode: _crtMode,
              ),
            ),
            if (_toolbarVisible)
              SafeArea(
                child: Align(
                  alignment: Alignment.topCenter,
                  child: EmulatorToolbar(
                    onLoadFile: _handleLoadFile,
                    onToggleKeyboard: _toggleVirtualKeyboard,
                    keyboardVisible: _keyboardVisible,
                    aspectMode: _aspectMode,
                    onAspectModeChanged: (mode) {
                      setState(() => _aspectMode = mode);
                      _startHideToolbarTimer();
                    },
                    crtMode: _crtMode,
                    onToggleCrt: () {
                      setState(() => _crtMode = !_crtMode);
                      _startHideToolbarTimer();
                    },
                  ),
                ),
              ),
            if (_toolbarVisible && !_keyboardVisible && _tapVisible)
              SafeArea(
                child: Align(
                  alignment: Alignment.bottomCenter,
                  child: Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: TapeDeckBar(
                      onHide: () {
                        if (mounted) {
                          setState(() => _tapVisible = false);
                        }
                      },
                    ),
                  ),
                ),
              ),
            if (_keyboardVisible)
              SafeArea(
                child: Align(
                  alignment: Alignment.bottomCenter,
                  child: Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: _VirtualKeyboardPanel(
                      onClose: _toggleVirtualKeyboard,
                      bridge: _bridge!,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _VirtualKeyboardPanel extends StatelessWidget {
  const _VirtualKeyboardPanel({required this.onClose, required this.bridge});

  final VoidCallback onClose;
  final FrodoBridge bridge;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 12),
      padding: const EdgeInsets.fromLTRB(8, 6, 8, 8),
      decoration: BoxDecoration(
        color: const Color(0xD9151515),
        border: Border.all(color: Colors.white24),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Text(
                'Virtual Keyboard',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
              ),
              const Spacer(),
              IconButton(
                visualDensity: VisualDensity.compact,
                icon: const Icon(Icons.close),
                tooltip: 'Close Keyboard',
                onPressed: onClose,
              ),
            ],
          ),
          const SizedBox(height: 2),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  children: [
                    _buildRow(const [
                      _VirtualKeySpec('<-', keyName: 'BACKSPACE', width: 32),
                      _VirtualKeySpec('1', keyName: '1'),
                      _VirtualKeySpec('2', keyName: '2'),
                      _VirtualKeySpec('3', keyName: '3'),
                      _VirtualKeySpec('4', keyName: '4'),
                      _VirtualKeySpec('5', keyName: '5'),
                      _VirtualKeySpec('6', keyName: '6'),
                      _VirtualKeySpec('7', keyName: '7'),
                      _VirtualKeySpec('8', keyName: '8'),
                      _VirtualKeySpec('9', keyName: '9'),
                      _VirtualKeySpec('0', keyName: '0'),
                      _VirtualKeySpec('+', keyName: 'PLUS'),
                      _VirtualKeySpec('-', keyName: 'MINUS'),
                      _VirtualKeySpec('CLR/HOME', keyName: 'HOME', width: 56),
                      _VirtualKeySpec('INST/DEL', keyName: 'DELETE', width: 56),
                    ]),
                    const SizedBox(height: 4),
                    _buildRow(const [
                      _VirtualKeySpec('CTRL', keyName: 'LCTRL', width: 44),
                      _VirtualKeySpec('Q', keyName: 'Q'),
                      _VirtualKeySpec('W', keyName: 'W'),
                      _VirtualKeySpec('E', keyName: 'E'),
                      _VirtualKeySpec('R', keyName: 'R'),
                      _VirtualKeySpec('T', keyName: 'T'),
                      _VirtualKeySpec('Y', keyName: 'Y'),
                      _VirtualKeySpec('U', keyName: 'U'),
                      _VirtualKeySpec('I', keyName: 'I'),
                      _VirtualKeySpec('O', keyName: 'O'),
                      _VirtualKeySpec('P', keyName: 'P'),
                      _VirtualKeySpec('@', keyName: 'LEFTBRACKET'),
                      _VirtualKeySpec('*', keyName: 'RIGHTBRACKET'),
                      _VirtualKeySpec('^', keyName: 'BACKSLASH'),
                      _VirtualKeySpec(
                        'RESTORE',
                        width: 66,
                        action: _VirtualKeyAction.nmi,
                      ),
                    ]),
                    const SizedBox(height: 4),
                    _buildRow(const [
                      _VirtualKeySpec('RUN/STOP', keyName: 'ESCAPE', width: 56),
                      _VirtualKeySpec(
                        'SHIFT LOCK',
                        keyName: 'LSHIFT',
                        width: 64,
                      ),
                      _VirtualKeySpec('A', keyName: 'A'),
                      _VirtualKeySpec('S', keyName: 'S'),
                      _VirtualKeySpec('D', keyName: 'D'),
                      _VirtualKeySpec('F', keyName: 'F'),
                      _VirtualKeySpec('G', keyName: 'G'),
                      _VirtualKeySpec('H', keyName: 'H'),
                      _VirtualKeySpec('J', keyName: 'J'),
                      _VirtualKeySpec('K', keyName: 'K'),
                      _VirtualKeySpec('L', keyName: 'L'),
                      _VirtualKeySpec(':', keyName: 'SEMICOLON'),
                      _VirtualKeySpec(';', keyName: 'APOSTROPHE'),
                      _VirtualKeySpec('=', keyName: 'EQUALS'),
                      _VirtualKeySpec('RETURN', keyName: 'RETURN', width: 70),
                    ]),
                    const SizedBox(height: 4),
                    _buildRow(const [
                      _VirtualKeySpec('C=', keyName: 'LALT', width: 40),
                      _VirtualKeySpec('SHIFT', keyName: 'LSHIFT', width: 52),
                      _VirtualKeySpec('Z', keyName: 'Z'),
                      _VirtualKeySpec('X', keyName: 'X'),
                      _VirtualKeySpec('C', keyName: 'C'),
                      _VirtualKeySpec('V', keyName: 'V'),
                      _VirtualKeySpec('B', keyName: 'B'),
                      _VirtualKeySpec('N', keyName: 'N'),
                      _VirtualKeySpec('M', keyName: 'M'),
                      _VirtualKeySpec(',', keyName: 'COMMA'),
                      _VirtualKeySpec('.', keyName: 'PERIOD'),
                      _VirtualKeySpec('/', keyName: 'SLASH'),
                      _VirtualKeySpec('SHIFT', keyName: 'RSHIFT', width: 52),
                      _VirtualKeySpec('CRSR V', keyName: 'DOWN', width: 52),
                      _VirtualKeySpec('CRSR >', keyName: 'RIGHT', width: 52),
                    ]),
                    const SizedBox(height: 4),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Padding(
                        padding: const EdgeInsets.only(left: 130),
                        child: _VirtualKeyButton(
                          label: 'SPACE',
                          width: 214,
                          onPressed: () => _tapKey(bridge, 'SPACE'),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 6),
              Column(
                children: [
                  for (final f in const ['F1', 'F3', 'F5', 'F7'])
                    Padding(
                      padding: const EdgeInsets.only(bottom: 6),
                      child: _VirtualKeyButton(
                        label: f,
                        width: 44,
                        onPressed: () => _tapKey(bridge, f),
                      ),
                    ),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildRow(List<_VirtualKeySpec> keys) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var i = 0; i < keys.length; i++) ...[
            _VirtualKeyButton(
              label: keys[i].label,
              width: keys[i].width,
              onPressed: () {
                if (keys[i].action == _VirtualKeyAction.nmi) {
                  bridge.nmi();
                  return;
                }
                if (keys[i].keyName == null) {
                  return;
                }
                _tapKey(bridge, keys[i].keyName!);
              },
            ),
            if (i != keys.length - 1) const SizedBox(width: 4),
          ],
        ],
      ),
    );
  }

  void _tapKey(FrodoBridge bridge, String key) {
    bridge.keyDown(key);
    Future<void>.delayed(const Duration(milliseconds: 80), () {
      bridge.keyUp(key);
    });
  }
}

enum _VirtualKeyAction { keyTap, nmi }

class _VirtualKeySpec {
  const _VirtualKeySpec(
    this.label, {
    this.keyName,
    this.width = 32,
    this.action = _VirtualKeyAction.keyTap,
  });

  final String label;
  final String? keyName;
  final double width;
  final _VirtualKeyAction action;
}

class _VirtualKeyButton extends StatelessWidget {
  const _VirtualKeyButton({
    required this.label,
    required this.onPressed,
    this.width = 32,
  });

  final String label;
  final VoidCallback onPressed;
  final double width;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width,
      height: 36,
      child: ElevatedButton(
        style: ElevatedButton.styleFrom(
          minimumSize: Size(width, 36),
          padding: const EdgeInsets.symmetric(horizontal: 2),
          textStyle: const TextStyle(fontSize: 10, fontWeight: FontWeight.w600),
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          visualDensity: const VisualDensity(horizontal: -3, vertical: -2),
        ),
        onPressed: onPressed,
        child: Text(label),
      ),
    );
  }
}

class _ArchiveProgress {
  const _ArchiveProgress({
    required this.status,
    required this.receivedBytes,
    this.totalBytes,
  });

  final String status;
  final int receivedBytes;
  final int? totalBytes;

  _ArchiveProgress copyWith({
    String? status,
    int? receivedBytes,
    int? totalBytes,
  }) {
    return _ArchiveProgress(
      status: status ?? this.status,
      receivedBytes: receivedBytes ?? this.receivedBytes,
      totalBytes: totalBytes ?? this.totalBytes,
    );
  }
}

class ArchiveSelectionPage extends StatefulWidget {
  const ArchiveSelectionPage({
    required this.archiveTitle,
    required this.entries,
    super.key,
  });

  final String archiveTitle;
  final List<String> entries;

  @override
  State<ArchiveSelectionPage> createState() => _ArchiveSelectionPageState();
}

class _ArchiveSelectionPageState extends State<ArchiveSelectionPage> {
  late Set<String> _selected;
  final searchController = TextEditingController();
  String _query = '';
  String _extensionFilter = 'All';
  bool _selectedOnly = false;
  String _alphaFilter = 'All';
  late List<String> _sortedEntries;

  @override
  void initState() {
    super.initState();
    _selected = <String>{};
    _initializeSortedEntries();
  }

  void _initializeSortedEntries() {
    _sortedEntries = List<String>.from(widget.entries);
    _sortedEntries.sort((a, b) {
      final nameA = a.split('/').last.toLowerCase();
      final nameB = b.split('/').last.toLowerCase();
      return nameA.compareTo(nameB);
    });
  }

  List<String> _computeFilteredEntries() {
    final normalizedQuery = _query.trim().toLowerCase();
    return _sortedEntries
        .where((entry) {
          final lower = entry.toLowerCase();
          if (_extensionFilter != 'All' &&
              !lower.endsWith('.${_extensionFilter.toLowerCase()}')) {
            return false;
          }
          if (_selectedOnly && !_selected.contains(entry)) {
            return false;
          }
          final fileName = entry.split('/').last;
          if (_alphaFilter != 'All') {
            final first = fileName.isEmpty ? '#' : fileName[0].toUpperCase();
            final alpha = RegExp(r'[A-Z]').hasMatch(first) ? first : '#';
            if (alpha != _alphaFilter) {
              return false;
            }
          }
          if (normalizedQuery.isEmpty) {
            return true;
          }
          final lowerName = fileName.toLowerCase();
          return lowerName.contains(normalizedQuery) ||
              lower.contains(normalizedQuery);
        })
        .toList(growable: false);
  }

  Set<String> _getExtensionOptions() {
    final extensionOptions = <String>{'All'};
    for (final entry in widget.entries) {
      final lower = entry.toLowerCase();
      for (final ext in const ['.d64', '.t64', '.tap', '.z64', '.prg']) {
        if (lower.endsWith(ext)) {
          extensionOptions.add(ext.substring(1).toUpperCase());
          break;
        }
      }
    }
    return extensionOptions;
  }

  List<String> _getAlphaOptions() {
    final set = <String>{'All'};
    for (final entry in _sortedEntries) {
      final fileName = entry.split('/').last;
      final first = fileName.isEmpty ? '#' : fileName[0].toUpperCase();
      set.add(RegExp(r'[A-Z]').hasMatch(first) ? first : '#');
    }

    final letters = set.where((e) => e != 'All').toList()..sort();
    return ['All', ...letters];
  }

  @override
  void dispose() {
    searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final filteredEntries = _computeFilteredEntries();
    final extensionOptions = _getExtensionOptions();
    final alphaOptions = _getAlphaOptions();

    return Scaffold(
      appBar: AppBar(
        title: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Select games to extract',
              style: TextStyle(fontSize: 16),
            ),
            Text(
              widget.archiveTitle,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 12, color: Colors.white70),
            ),
          ],
        ),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.pop(context),
        ),
        actions: [
          TextButton(
            onPressed: () {
              setState(_selected.clear);
            },
            child: const Text('Untick all'),
          ),
          TextButton(
            onPressed:
                filteredEntries.isEmpty
                    ? null
                    : () {
                      setState(() {
                        _selected.addAll(filteredEntries);
                      });
                    },
            child: const Text('Tick shown'),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 12),
            child: Center(
              child: Chip(
                label: Text(
                  '${_selected.length}/${widget.entries.length}',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
              ),
            ),
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(10, 8, 10, 6),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: searchController,
                        onChanged: (value) {
                          setState(() {
                            _query = value;
                          });
                        },
                        decoration: InputDecoration(
                          isDense: true,
                          prefixIcon: const Icon(Icons.search, size: 18),
                          hintText: 'Search...',
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                          suffixIcon:
                              _query.isEmpty
                                  ? null
                                  : IconButton(
                                    onPressed: () {
                                      setState(() {
                                        searchController.clear();
                                        _query = '';
                                      });
                                    },
                                    icon: const Icon(Icons.clear, size: 18),
                                  ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    SizedBox(
                      width: 92,
                      child: DropdownButton<String>(
                        isExpanded: true,
                        value: _extensionFilter,
                        items:
                            extensionOptions
                                .toList()
                                .map(
                                  (option) => DropdownMenuItem<String>(
                                    value: option,
                                    child: Text(option),
                                  ),
                                )
                                .toList(),
                        onChanged: (value) {
                          if (value == null) {
                            return;
                          }
                          setState(() {
                            _extensionFilter = value;
                          });
                        },
                      ),
                    ),
                    const SizedBox(width: 8),
                    FilterChip(
                      selected: _selectedOnly,
                      label: const Text('Selected'),
                      onSelected: (value) {
                        setState(() {
                          _selectedOnly = value;
                        });
                      },
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      for (final alpha in alphaOptions)
                        Padding(
                          padding: const EdgeInsets.only(right: 4),
                          child: ChoiceChip(
                            label: Text(alpha),
                            selected: _alphaFilter == alpha,
                            onSelected: (_) {
                              setState(() {
                                _alphaFilter = alpha;
                              });
                            },
                            visualDensity: VisualDensity.compact,
                          ),
                        ),
                      const SizedBox(width: 6),
                      Text(
                        '${filteredEntries.length} shown',
                        style: const TextStyle(
                          fontSize: 12,
                          color: Colors.white70,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1, thickness: 1),
          Expanded(
            child:
                filteredEntries.isEmpty
                    ? Center(
                      child: Text(
                        _query.isEmpty && !_selectedOnly
                            ? 'No games found'
                            : 'No matches for current filters',
                        style: const TextStyle(color: Colors.white70),
                      ),
                    )
                    : ListView.builder(
                      itemCount: filteredEntries.length,
                      itemBuilder: (context, index) {
                        final entry = filteredEntries[index];
                        final fileName = entry.split('/').last;
                        final isChecked = _selected.contains(entry);
                        return ListTile(
                          dense: true,
                          visualDensity: const VisualDensity(
                            vertical: -3,
                            horizontal: -2,
                          ),
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 8,
                          ),
                          leading: Checkbox(
                            value: isChecked,
                            onChanged: (checked) {
                              setState(() {
                                if (checked == true) {
                                  _selected.add(entry);
                                } else {
                                  _selected.remove(entry);
                                }
                              });
                            },
                            visualDensity: VisualDensity.compact,
                            materialTapTargetSize:
                                MaterialTapTargetSize.shrinkWrap,
                          ),
                          title: Text(
                            fileName,
                            overflow: TextOverflow.ellipsis,
                          ),
                          subtitle:
                              fileName == entry
                                  ? null
                                  : Text(
                                    entry,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(fontSize: 10),
                                  ),
                          onTap: () {
                            setState(() {
                              if (isChecked) {
                                _selected.remove(entry);
                              } else {
                                _selected.add(entry);
                              }
                            });
                          },
                        );
                      },
                    ),
          ),
        ],
      ),
      bottomNavigationBar: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: () => Navigator.pop(context),
                icon: const Icon(Icons.close),
                label: const Text('Cancel'),
              ),
            ),
            const SizedBox(width: 8),
            OutlinedButton(
              onPressed:
                  filteredEntries.isEmpty
                      ? null
                      : () {
                        setState(() {
                          _selected.removeAll(filteredEntries);
                        });
                      },
              child: const Text('Clear shown'),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: FilledButton.icon(
                onPressed:
                    _selected.isEmpty
                        ? null
                        : () => Navigator.pop(context, _selected.toList()),
                icon: const Icon(Icons.check_circle),
                label: const Text('Extract selected'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
