import 'dart:async';

import 'package:flutter/material.dart';

import 'emulator_display.dart';
import 'frodo_bindings.dart';
import 'gamepad_service.dart';
import 'pages/gamepad_page.dart';

/// Main toolbar with display, file, and machine controls.
class EmulatorToolbar extends StatelessWidget {
  const EmulatorToolbar({
    super.key,
    required this.onLoadFile,
    required this.onToggleKeyboard,
    required this.keyboardVisible,
    required this.aspectMode,
    required this.onAspectModeChanged,
    required this.crtMode,
    required this.onToggleCrt,
  });

  final VoidCallback onLoadFile;
  final VoidCallback onToggleKeyboard;
  final bool keyboardVisible;
  final DisplayAspectMode aspectMode;
  final ValueChanged<DisplayAspectMode> onAspectModeChanged;
  final bool crtMode;
  final VoidCallback onToggleCrt;

  @override
  Widget build(BuildContext context) {
    final bridge = FrodoBridge.instance;
    // Ensure the singleton is alive so it starts listening to events.
    GamepadService.instance;

    return Container(
      margin: const EdgeInsets.all(12),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: const Color(0xCC111111),
        border: Border.all(color: Colors.white24),
        borderRadius: BorderRadius.circular(14),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            // ---- Display aspect ratio ----
            SegmentedButton<DisplayAspectMode>(
              segments:
                  DisplayAspectMode.values
                      .map(
                        (mode) => ButtonSegment<DisplayAspectMode>(
                          value: mode,
                          label: Text(mode.label),
                        ),
                      )
                      .toList(),
              selected: {aspectMode},
              showSelectedIcon: false,
              onSelectionChanged: (selection) {
                onAspectModeChanged(selection.first);
              },
            ),
            const _Separator(),

            // ---- File operations ----
            IconButton(
              icon: const Icon(Icons.folder_open, color: Colors.white70),
              tooltip: 'Load File',
              onPressed: onLoadFile,
            ),
            const _Separator(),

            // ---- Keyboard toggle (standalone) ----
            IconButton(
              icon: Icon(
                Icons.keyboard,
                color: keyboardVisible ? Colors.cyanAccent : Colors.white70,
              ),
              tooltip:
                  keyboardVisible
                      ? 'Hide Virtual Keyboard'
                      : 'Show Virtual Keyboard',
              onPressed: onToggleKeyboard,
            ),
            const _Separator(),

            // ---- CRT mode toggle ----
            IconButton(
              icon: Icon(
                Icons.tv,
                color: crtMode ? Colors.cyanAccent : Colors.white70,
              ),
              tooltip: crtMode ? 'CRT Mode: On' : 'CRT Mode: Off',
              onPressed: onToggleCrt,
            ),
            const _Separator(),

            // ---- Machine controls ----
            IconButton(
              icon: const Icon(Icons.restart_alt, color: Colors.white70),
              tooltip: 'Reset (soft)',
              onPressed: () => bridge.reset(clearMemory: false),
            ),
            IconButton(
              icon: const Icon(Icons.power_settings_new, color: Colors.orange),
              tooltip: 'Reset (hard)',
              onPressed: () => bridge.reset(clearMemory: true),
            ),
            IconButton(
              icon: const Icon(Icons.sports_esports, color: Colors.white70),
              tooltip: 'Controls (Swap Joy/Drive, Restore)',
              onPressed: () {
                showModalBottomSheet<void>(
                  context: context,
                  builder:
                      (sheetContext) => SafeArea(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const ListTile(
                              title: Text('Control Actions'),
                              subtitle: Text('Joystick, drives, and restore'),
                            ),
                            ListTile(
                              leading: const Icon(Icons.swap_vert),
                              title: const Text('Swap Joystick Ports'),
                              onTap: () {
                                bridge.toggleJoystickSwap();
                                Navigator.of(sheetContext).pop();
                              },
                            ),
                            ListTile(
                              leading: const Icon(Icons.swap_horiz),
                              title: const Text('Swap Drives 8 & 9'),
                              onTap: () {
                                bridge.swapDrives();
                                Navigator.of(sheetContext).pop();
                              },
                            ),
                            ListTile(
                              leading: const Icon(Icons.flash_on),
                              title: const Text('Restore (NMI)'),
                              onTap: () {
                                bridge.nmi();
                                Navigator.of(sheetContext).pop();
                              },
                            ),
                            ListTile(
                              leading: const Icon(Icons.gamepad_outlined),
                              title: const Text('Configure Gamepads…'),
                              onTap: () {
                                Navigator.of(sheetContext).pop();
                                showModalBottomSheet<void>(
                                  context: context,
                                  isScrollControlled: true,
                                  backgroundColor: const Color(0xFF1A1A2E),
                                  shape: const RoundedRectangleBorder(
                                    borderRadius: BorderRadius.vertical(
                                      top: Radius.circular(16),
                                    ),
                                  ),
                                  builder: (_) => const GamepadPage(),
                                );
                              },
                            ),
                          ],
                        ),
                      ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

/// Tape deck controls bar with cassette tape operation buttons.
class TapeDeckBar extends StatefulWidget {
  const TapeDeckBar({super.key, required this.onHide});

  /// Called when the tape has been inactive for 2 seconds, requesting the
  /// parent to hide this widget.
  final VoidCallback onHide;

  @override
  State<TapeDeckBar> createState() => _TapeDeckBarState();
}

class _TapeDeckBarState extends State<TapeDeckBar> {
  final FrodoBridge _bridge = FrodoBridge.instance;
  bool _blinkOn = false;
  bool _active = false;
  Timer? _blinkTimer;
  Timer? _inactivityTimer;

  @override
  void initState() {
    super.initState();
    _blinkTimer = Timer.periodic(const Duration(milliseconds: 180), (_) {
      _updateActivityLight();
    });
  }

  void _updateActivityLight() {
    final active = _bridge.tapeDriveState != 0;
    if (!mounted) {
      return;
    }
    if (!active && (_active || _blinkOn)) {
      setState(() {
        _active = false;
        _blinkOn = false;
      });
      // Start the 2-second inactivity timer to auto-hide
      _inactivityTimer?.cancel();
      _inactivityTimer = Timer(const Duration(seconds: 2), () {
        if (mounted) {
          widget.onHide();
        }
      });
      return;
    }

    if (active) {
      // Tape became active again — cancel any pending hide
      _inactivityTimer?.cancel();
      _inactivityTimer = null;
      setState(() {
        _active = true;
        _blinkOn = !_blinkOn;
      });
    }
  }

  @override
  void dispose() {
    _blinkTimer?.cancel();
    _inactivityTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bridge = _bridge;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 12),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: const Color(0xCC1a1a1a),
        border: Border.all(color: Colors.white12),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          AnimatedContainer(
            duration: const Duration(milliseconds: 120),
            width: 12,
            height: 12,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color:
                  _active
                      ? (_blinkOn
                          ? Colors.greenAccent
                          : const Color(0xFF0C4A2E))
                      : const Color(0xFF062615),
              boxShadow:
                  _active && _blinkOn
                      ? const [
                        BoxShadow(
                          color: Color(0x9900FF7F),
                          blurRadius: 8,
                          spreadRadius: 1,
                        ),
                      ]
                      : null,
            ),
          ),
          const SizedBox(width: 8),
          const Text(
            'Tape Deck',
            style: TextStyle(
              color: Colors.white54,
              fontSize: 12,
              fontWeight: FontWeight.bold,
            ),
          ),
          const _Separator(),
          IconButton(
            icon: const Icon(Icons.fast_rewind, color: Colors.white70),
            tooltip: 'Rewind (go to start)',
            onPressed: bridge.tapeRewind,
          ),
          IconButton(
            icon: const Icon(Icons.play_arrow, color: Colors.green),
            tooltip: 'Play',
            onPressed: bridge.tapePlay,
          ),
          IconButton(
            icon: const Icon(Icons.stop, color: Colors.red),
            tooltip: 'Stop',
            onPressed: bridge.tapeStop,
          ),
          IconButton(
            icon: const Icon(Icons.fiber_manual_record, color: Colors.red),
            tooltip: 'Record',
            onPressed: bridge.tapeRecord,
          ),
          IconButton(
            icon: const Icon(Icons.fast_forward, color: Colors.white70),
            tooltip: 'Forward (go to end)',
            onPressed: bridge.tapeForward,
          ),
          IconButton(
            icon: const Icon(Icons.eject, color: Colors.white70),
            tooltip: 'Eject Tape',
            onPressed: bridge.tapeEject,
          ),
        ],
      ),
    );
  }
}

class _Separator extends StatelessWidget {
  const _Separator();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 1,
      height: 24,
      margin: const EdgeInsets.symmetric(horizontal: 4),
      color: Colors.white24,
    );
  }
}
