/// Dart FFI bindings to the Rust/C++ Frodo emulator bridge.
///
/// The native library is loaded once and all functions are resolved eagerly.
/// Call [FrodoBridge.instance] to obtain the singleton.
library;

import 'dart:ffi';
import 'dart:io' show Platform;
import 'dart:typed_data';
import 'package:ffi/ffi.dart';

/// Display dimensions (must match C header / Rust constants).
const int displayW = 384;
const int displayH = 272;
const int framePixels = displayW * displayH;

// ---------------------------------------------------------------------------
// Typedefs for every exported symbol
// ---------------------------------------------------------------------------
typedef _InitC = Int32 Function();
typedef _InitDart = int Function();

typedef _VoidVoidC = Void Function();
typedef _VoidVoidDart = void Function();

typedef _IsReadyC = Int32 Function();
typedef _IsReadyDart = int Function();

typedef _ResetC = Void Function(Int32 clearMemory);
typedef _ResetDart = void Function(int clearMemory);

typedef _LoadFileC = Void Function(Pointer<Utf8> path);
typedef _LoadFileDart = void Function(Pointer<Utf8> path);

typedef _MountDiskC = Int32 Function(Int32 driveNumber, Pointer<Utf8> path);
typedef _MountDiskDart = int Function(int driveNumber, Pointer<Utf8> path);

typedef _SwapDrivesC = Int32 Function();
typedef _SwapDrivesDart = int Function();

typedef _MountTapeC = Void Function(Pointer<Utf8> path);
typedef _MountTapeDart = void Function(Pointer<Utf8> path);

typedef _TapePositionC = Int32 Function();
typedef _TapePositionDart = int Function();

typedef _TapeSetSpeedC = Void Function(Int32 multiplier);
typedef _TapeSetSpeedDart = void Function(int multiplier);

typedef _InsertCartridgeC = Void Function(Pointer<Utf8> path);
typedef _InsertCartridgeDart = void Function(Pointer<Utf8> path);

typedef _KeyC = Void Function(Pointer<Utf8> name);
typedef _KeyDart = void Function(Pointer<Utf8> name);

typedef _KeyComboC =
    Void Function(Pointer<Utf8> modName, Pointer<Utf8> keyName);
typedef _KeyComboDart =
    void Function(Pointer<Utf8> modName, Pointer<Utf8> keyName);

typedef _SetJoystickPortsC = Void Function(Int32 port1, Int32 port2);
typedef _SetJoystickPortsDart = void Function(int port1, int port2);

typedef _JoystickSetOverrideC = Void Function(Int32 port, Int32 bits);
typedef _JoystickSetOverrideDart = void Function(int port, int bits);

typedef _CaptureFrameC = Void Function(Pointer<Uint32> outArgb);
typedef _CaptureFrameDart = void Function(Pointer<Uint32> outArgb);

typedef _DisplayDimC = Uint32 Function();
typedef _DisplayDimDart = int Function();

// ---------------------------------------------------------------------------
// Bridge singleton
// ---------------------------------------------------------------------------

class FrodoBridge {
  FrodoBridge._() {
    _lib = _openLibrary();
    _bindAll();
  }

  static FrodoBridge? _instance;
  static FrodoBridge get instance => _instance ??= FrodoBridge._();

  late final DynamicLibrary _lib;

  // ---- resolved function pointers ----
  late final _InitDart _init;
  late final _VoidVoidDart _shutdown;
  late final _IsReadyDart _isReady;
  late final _ResetDart _reset;
  late final _VoidVoidDart _resetAndAutostart;
  late final _VoidVoidDart _nmi;
  late final _LoadFileDart _loadFile;
  late final _MountDiskDart _mountDisk;
  late final _SwapDrivesDart _swapDrives;
  late final _VoidVoidDart _queueDiskAutoload;
  late final _MountTapeDart _mountTape;
  late final _VoidVoidDart _tapePlay;
  late final _VoidVoidDart _tapeStop;
  late final _VoidVoidDart _tapeRecord;
  late final _VoidVoidDart _tapeRewind;
  late final _VoidVoidDart _tapeForward;
  late final _VoidVoidDart _tapeEject;
  late final _TapePositionDart _tapePosition;
  late final _TapePositionDart _tapeButtonState;
  late final _TapePositionDart _tapeDriveState;
  late final _TapeSetSpeedDart _tapeSetSpeed;
  late final _InsertCartridgeDart _insertCartridge;
  late final _KeyDart _keyDown;
  late final _KeyDart _keyUp;
  late final _KeyComboDart _keyCombo;
  late final _SetJoystickPortsDart _setJoystickPorts;
  late final _VoidVoidDart _toggleJoystickSwap;
  late final _JoystickSetOverrideDart _joystickSetOverride;
  late final _CaptureFrameDart _captureFrame;
  late final _VoidVoidDart _pauseAudio;
  late final _VoidVoidDart _resumeAudio;
  late final _VoidVoidDart _autostartMountedMedia;
  late final _VoidVoidDart _startCurrentMedia;
  late final _VoidVoidDart _queueTapeAutoload;
  late final _DisplayDimDart _displayWidth;
  late final _DisplayDimDart _displayHeight;

  // ---- frame buffer (reused across calls) ----
  Pointer<Uint32>? _frameBuf;

  // ---- public API ----

  int init() => _init();
  void shutdown() => _shutdown();
  bool get isReady => _isReady() != 0;

  void reset({bool clearMemory = true}) => _reset(clearMemory ? 1 : 0);
  void resetAndAutostart() => _resetAndAutostart();
  void nmi() => _nmi();

  void loadFile(String path) {
    final p = path.toNativeUtf8();
    try {
      _loadFile(p);
    } finally {
      calloc.free(p);
    }
  }

  bool mountDisk(int driveNumber, String path) {
    final p = path.toNativeUtf8();
    try {
      return _mountDisk(driveNumber, p) != 0;
    } finally {
      calloc.free(p);
    }
  }

  bool swapDrives() => _swapDrives() != 0;
  void queueDiskAutoload() => _queueDiskAutoload();

  void mountTape(String path) {
    final p = path.toNativeUtf8();
    try {
      _mountTape(p);
    } finally {
      calloc.free(p);
    }
  }

  void tapePlay() => _tapePlay();
  void tapeStop() => _tapeStop();
  void tapeRecord() => _tapeRecord();
  void tapeRewind() => _tapeRewind();
  void tapeForward() => _tapeForward();
  void tapeEject() => _tapeEject();
  int get tapePosition => _tapePosition();
  int get tapeButtonState => _tapeButtonState();
  int get tapeDriveState => _tapeDriveState();
  void setTapeSpeed(int multiplier) => _tapeSetSpeed(multiplier);

  void insertCartridge(String path) {
    final p = path.toNativeUtf8();
    try {
      _insertCartridge(p);
    } finally {
      calloc.free(p);
    }
  }

  void keyDown(String name) {
    final p = name.toNativeUtf8();
    try {
      _keyDown(p);
    } finally {
      calloc.free(p);
    }
  }

  void keyUp(String name) {
    final p = name.toNativeUtf8();
    try {
      _keyUp(p);
    } finally {
      calloc.free(p);
    }
  }

  void keyCombo(String modName, String keyName) {
    final m = modName.toNativeUtf8();
    final k = keyName.toNativeUtf8();
    try {
      _keyCombo(m, k);
    } finally {
      calloc.free(m);
      calloc.free(k);
    }
  }

  void setJoystickPorts(int port1, int port2) =>
      _setJoystickPorts(port1, port2);
  void toggleJoystickSwap() => _toggleJoystickSwap();

  /// Set software joystick state for a port (Android, no SDL device).
  /// [bits] is the CIA mask: 0xff = nothing pressed.
  /// Clear a bit to activate: bit0=Up, bit1=Down, bit2=Left, bit3=Right, bit4=Fire.
  void joystickSetOverride(int port, int bits) =>
      _joystickSetOverride(port, bits);

  /// Captures the current frame as ARGB8888 pixel data.
  Uint8List captureFrame() {
    _frameBuf ??= calloc<Uint32>(framePixels);
    _captureFrame(_frameBuf!);
    // View the native memory as bytes (4 bytes per pixel)
    return _frameBuf!.cast<Uint8>().asTypedList(framePixels * 4);
  }

  void pauseAudio() => _pauseAudio();
  void resumeAudio() => _resumeAudio();
  void autostartMountedMedia() => _autostartMountedMedia();
  void startCurrentMedia() => _startCurrentMedia();
  void queueTapeAutoload() => _queueTapeAutoload();

  int get nativeDisplayWidth => _displayWidth();
  int get nativeDisplayHeight => _displayHeight();

  /// Free the frame buffer when no longer needed.
  void dispose() {
    if (_frameBuf != null) {
      calloc.free(_frameBuf!);
      _frameBuf = null;
    }
  }

  // ---- private helpers ----

  static DynamicLibrary _openLibrary() {
    if (Platform.isAndroid) {
      // Try direct open first; if the platform loader rejects the name,
      // fall back to process() after MainActivity preloads the lib.
      try {
        return DynamicLibrary.open('libfrodo_bridge.so');
      } catch (_) {
        return DynamicLibrary.process();
      }
    } else if (Platform.isIOS) {
      return DynamicLibrary.process(); // statically linked
    } else if (Platform.isLinux) {
      return DynamicLibrary.open('libfrodo_bridge.so');
    } else if (Platform.isMacOS) {
      return DynamicLibrary.open('libfrodo_bridge.dylib');
    } else if (Platform.isWindows) {
      return DynamicLibrary.open('frodo_bridge.dll');
    }
    throw UnsupportedError('Unsupported platform');
  }

  void _bindAll() {
    _init = _lib.lookupFunction<_InitC, _InitDart>('bridge_init');
    _shutdown = _lib.lookupFunction<_VoidVoidC, _VoidVoidDart>(
      'bridge_shutdown',
    );
    _isReady = _lib.lookupFunction<_IsReadyC, _IsReadyDart>('bridge_is_ready');
    _reset = _lib.lookupFunction<_ResetC, _ResetDart>('bridge_reset');
    _resetAndAutostart = _lib.lookupFunction<_VoidVoidC, _VoidVoidDart>(
      'bridge_reset_and_autostart',
    );
    _nmi = _lib.lookupFunction<_VoidVoidC, _VoidVoidDart>('bridge_nmi');
    _loadFile = _lib.lookupFunction<_LoadFileC, _LoadFileDart>(
      'bridge_load_file',
    );
    _mountDisk = _lib.lookupFunction<_MountDiskC, _MountDiskDart>(
      'bridge_mount_disk',
    );
    _swapDrives = _lib.lookupFunction<_SwapDrivesC, _SwapDrivesDart>(
      'bridge_swap_drives',
    );
    _queueDiskAutoload = _lib.lookupFunction<_VoidVoidC, _VoidVoidDart>(
      'bridge_queue_disk_autoload',
    );
    _mountTape = _lib.lookupFunction<_MountTapeC, _MountTapeDart>(
      'bridge_mount_tape',
    );
    _tapePlay = _lib.lookupFunction<_VoidVoidC, _VoidVoidDart>(
      'bridge_tape_play',
    );
    _tapeStop = _lib.lookupFunction<_VoidVoidC, _VoidVoidDart>(
      'bridge_tape_stop',
    );
    _tapeRecord = _lib.lookupFunction<_VoidVoidC, _VoidVoidDart>(
      'bridge_tape_record',
    );
    _tapeRewind = _lib.lookupFunction<_VoidVoidC, _VoidVoidDart>(
      'bridge_tape_rewind',
    );
    _tapeForward = _lib.lookupFunction<_VoidVoidC, _VoidVoidDart>(
      'bridge_tape_forward',
    );
    _tapeEject = _lib.lookupFunction<_VoidVoidC, _VoidVoidDart>(
      'bridge_tape_eject',
    );
    _tapePosition = _lib.lookupFunction<_TapePositionC, _TapePositionDart>(
      'bridge_tape_position',
    );
    _tapeButtonState = _lib.lookupFunction<_TapePositionC, _TapePositionDart>(
      'bridge_tape_button_state',
    );
    _tapeDriveState = _lib.lookupFunction<_TapePositionC, _TapePositionDart>(
      'bridge_tape_drive_state',
    );
    _tapeSetSpeed = _lib.lookupFunction<_TapeSetSpeedC, _TapeSetSpeedDart>(
      'bridge_tape_set_speed',
    );
    _insertCartridge = _lib
        .lookupFunction<_InsertCartridgeC, _InsertCartridgeDart>(
          'bridge_insert_cartridge',
        );
    _keyDown = _lib.lookupFunction<_KeyC, _KeyDart>('bridge_key_down');
    _keyUp = _lib.lookupFunction<_KeyC, _KeyDart>('bridge_key_up');
    _keyCombo = _lib.lookupFunction<_KeyComboC, _KeyComboDart>(
      'bridge_key_combo',
    );
    _setJoystickPorts = _lib
        .lookupFunction<_SetJoystickPortsC, _SetJoystickPortsDart>(
          'bridge_set_joystick_ports',
        );
    _toggleJoystickSwap = _lib.lookupFunction<_VoidVoidC, _VoidVoidDart>(
      'bridge_toggle_joystick_swap',
    );
    _joystickSetOverride = _lib
        .lookupFunction<_JoystickSetOverrideC, _JoystickSetOverrideDart>(
          'bridge_joystick_set_override',
        );
    _captureFrame = _lib.lookupFunction<_CaptureFrameC, _CaptureFrameDart>(
      'bridge_capture_frame',
    );
    _pauseAudio = _lib.lookupFunction<_VoidVoidC, _VoidVoidDart>(
      'bridge_pause_audio',
    );
    _resumeAudio = _lib.lookupFunction<_VoidVoidC, _VoidVoidDart>(
      'bridge_resume_audio',
    );
    _autostartMountedMedia = _lib.lookupFunction<_VoidVoidC, _VoidVoidDart>(
      'bridge_autostart_mounted_media',
    );
    _startCurrentMedia = _lib.lookupFunction<_VoidVoidC, _VoidVoidDart>(
      'bridge_start_current_media',
    );
    _queueTapeAutoload = _lib.lookupFunction<_VoidVoidC, _VoidVoidDart>(
      'bridge_queue_tape_autoload',
    );
    _displayWidth = _lib.lookupFunction<_DisplayDimC, _DisplayDimDart>(
      'bridge_display_width',
    );
    _displayHeight = _lib.lookupFunction<_DisplayDimC, _DisplayDimDart>(
      'bridge_display_height',
    );
  }
}
