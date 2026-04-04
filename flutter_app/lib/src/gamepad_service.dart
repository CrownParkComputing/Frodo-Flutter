/// Listens to the Android gamepad EventChannel and translates button /
/// axis events into C64 joystick CIA-mask overrides via [FrodoBridge].
///
/// CIA mask convention (active-low):
///   bit 0 = Up   (clear → up pressed)
///   bit 1 = Down
///   bit 2 = Left
///   bit 3 = Right
///   bit 4 = Fire
library;

import 'dart:async';

import 'package:flutter/services.dart';

import 'frodo_bindings.dart';

// ---------------------------------------------------------------------------
// Android keycodes used for joystick mapping
// ---------------------------------------------------------------------------
const int _kcDpadUp = 19;
const int _kcDpadDown = 20;
const int _kcDpadLeft = 21;
const int _kcDpadRight = 22;
const int _kcButtonA = 96;
const int _kcButtonB = 97;
const int _kcButtonC = 98;
const int _kcButtonX = 99;
const int _kcButtonY = 100;
const int _kcButtonZ = 101;
const int _kcButtonL1 = 102;
const int _kcButtonR1 = 103;
const int _kcButtonL2 = 104;
const int _kcButtonR2 = 105;
const int _kcButtonThumbL = 106;
const int _kcButtonThumbR = 107;
const int _kcButtonStart = 108;
const int _kcButtonSelect = 109;
const int _kcButtonMode = 110;
const int _kcButton1 = 188;
const int _kcButton2 = 189;
const int _kcButton3 = 190;
const int _kcButton4 = 191;

const double _axisDeadzone = 0.35;

// CIA bit constants (bits that get cleared when pressed)
const int _bitUp = 0x01;
const int _bitDown = 0x02;
const int _bitLeft = 0x04;
const int _bitRight = 0x08;
const int _bitFire = 0x10;

// ---------------------------------------------------------------------------
// Gamepad descriptor (returned by listGamepads)
// ---------------------------------------------------------------------------
class GamepadDevice {
  const GamepadDevice({required this.id, required this.name, this.port = 0});

  final int id;
  final String name;

  /// 0 = unassigned, 1 = port 1, 2 = port 2
  final int port;

  GamepadDevice copyWith({int? port}) =>
      GamepadDevice(id: id, name: name, port: port ?? this.port);

  @override
  String toString() => 'GamepadDevice($id, "$name", port=$port)';
}

// ---------------------------------------------------------------------------
// Service singleton
// ---------------------------------------------------------------------------
class GamepadService {
  GamepadService._() {
    _start();
  }

  static GamepadService? _instance;
  static GamepadService get instance => _instance ??= GamepadService._();

  static const _eventChannel = EventChannel('gamepad_events');
  static const _methodChannel = MethodChannel('gamepad_input');

  StreamSubscription<dynamic>? _sub;

  /// Currently known devices (id → descriptor).
  final Map<int, GamepadDevice> _devices = {};

  /// Per-device current CIA mask (active-low accumulator).
  /// Separate from port assignment so we can merge if multiple devices on same port.
  final Map<int, int> _deviceMask = {};

  /// Per-device mask of direction bits currently held via KEY events (digital).
  /// These take priority over analog motion events and won't be cleared by them.
  final Map<int, int> _digitalDirMask = {};

  /// Notified whenever the device list changes.
  final _devicesController = StreamController<List<GamepadDevice>>.broadcast();
  Stream<List<GamepadDevice>> get devicesStream => _devicesController.stream;
  List<GamepadDevice> get devices => List.unmodifiable(_devices.values);

  // ---- setup ---------------------------------------------------------------

  void _start() {
    _sub = _eventChannel.receiveBroadcastStream().listen(
      _onEvent,
      onError: (_) {},
    );
  }

  void dispose() {
    _sub?.cancel();
    _devicesController.close();
  }

  // ---- external API --------------------------------------------------------

  Future<void> refreshDevices() async {
    try {
      final raw = await _methodChannel.invokeListMethod<Map>('listGamepads');
      if (raw == null) return;

      // Preserve existing port assignments
      final updated = <int, GamepadDevice>{};
      for (final m in raw) {
        final id = (m['id'] as num).toInt();
        final name = m['name'] as String? ?? 'Unknown';
        final existing = _devices[id];
        updated[id] = GamepadDevice(
          id: id,
          name: name,
          port: existing?.port ?? 0,
        );
      }

      // First connected controller defaults to joystick port 2 (typical C64 gameplay).
      if (updated.isNotEmpty && !updated.values.any((d) => d.port != 0)) {
        final firstId = updated.keys.first;
        final first = updated[firstId]!;
        updated[firstId] = first.copyWith(port: 2);
      }

      _devices
        ..clear()
        ..addAll(updated);
      _flush();
      _notifyDevices();
    } catch (_) {}
  }

  /// Assign [deviceId] to C64 joystick [port] (1 or 2, 0 = unassign).
  void assignPort(int deviceId, int port) {
    final d = _devices[deviceId];
    if (d == null) return;
    // Remove any other device that was on this port
    if (port != 0) {
      for (final id in _devices.keys) {
        if (id != deviceId && _devices[id]!.port == port) {
          _devices[id] = _devices[id]!.copyWith(port: 0);
        }
      }
    }
    _devices[deviceId] = d.copyWith(port: port);
    _flush();
    _notifyDevices();
  }

  // ---- event processing ----------------------------------------------------

  void _onEvent(dynamic raw) {
    if (raw is! Map) return;
    final type = raw['type'] as String?;
    final deviceId = (raw['deviceId'] as num?)?.toInt() ?? -1;

    // Register new device on first event if not yet known
    if (deviceId >= 0 && !_devices.containsKey(deviceId)) {
      final anyAssigned = _devices.values.any((d) => d.port != 0);
      _devices[deviceId] = GamepadDevice(
        id: deviceId,
        name: 'Controller $deviceId',
        port: anyAssigned ? 0 : 2,
      );
      _flush();
      _notifyDevices();
      // Try to fetch a proper name asynchronously
      refreshDevices();
    }

    switch (type) {
      case 'key_down':
        final kc = (raw['keyCode'] as num?)?.toInt() ?? -1;
        _applyKey(deviceId, kc, true);

      case 'key_up':
        final kc = (raw['keyCode'] as num?)?.toInt() ?? -1;
        _applyKey(deviceId, kc, false);

      case 'motion':
        final axisX = (raw['axisX'] as num?)?.toDouble() ?? 0.0;
        final axisY = (raw['axisY'] as num?)?.toDouble() ?? 0.0;
        final hatX = (raw['hatX'] as num?)?.toDouble() ?? 0.0;
        final hatY = (raw['hatY'] as num?)?.toDouble() ?? 0.0;
        // Only log non-zero motion to reduce spam
        if (axisX.abs() > 0.1 ||
            axisY.abs() > 0.1 ||
            hatX.abs() > 0.1 ||
            hatY.abs() > 0.1) {
          print('[Gamepad] motion ax=$axisX ay=$axisY hx=$hatX hy=$hatY');
        }
        _applyMotion(deviceId, axisX, axisY, hatX, hatY);
    }
  }

  void _applyKey(int deviceId, int keyCode, bool down) {
    int current = _deviceMask[deviceId] ?? 0xff;
    int digital = _digitalDirMask[deviceId] ?? 0;
    final bit = _keyCodeToBit(keyCode);

    print(
      '[Gamepad] key deviceId=$deviceId keyCode=$keyCode down=$down bit=0x${bit.toRadixString(16)}',
    );

    if (bit == 0) return;

    // Track digital direction presses (not fire button)
    final isDirection = (bit & (_bitUp | _bitDown | _bitLeft | _bitRight)) != 0;

    if (down) {
      current &= ~bit & 0xff;
      if (isDirection) digital |= bit;
    } else {
      current |= bit;
      if (isDirection) digital &= ~bit & 0xff;
    }
    _deviceMask[deviceId] = current;
    _digitalDirMask[deviceId] = digital;
    print(
      '[Gamepad] after: mask=0x${current.toRadixString(16)} digital=0x${digital.toRadixString(16)}',
    );
    _flush();
  }

  void _applyMotion(int deviceId, double ax, double ay, double hx, double hy) {
    int current = _deviceMask[deviceId] ?? 0xff;
    final digital = _digitalDirMask[deviceId] ?? 0;

    // Only clear direction bits NOT held digitally, then recompute from analog
    if ((digital & _bitUp) == 0) current |= _bitUp;
    if ((digital & _bitDown) == 0) current |= _bitDown;
    if ((digital & _bitLeft) == 0) current |= _bitLeft;
    if ((digital & _bitRight) == 0) current |= _bitRight;

    // Left analog stick (only affects non-digital directions)
    if (ax < -_axisDeadzone && (digital & _bitLeft) == 0) {
      current &= ~_bitLeft & 0xff;
    }
    if (ax > _axisDeadzone && (digital & _bitRight) == 0) {
      current &= ~_bitRight & 0xff;
    }
    if (ay < -_axisDeadzone && (digital & _bitUp) == 0) {
      current &= ~_bitUp & 0xff;
    }
    if (ay > _axisDeadzone && (digital & _bitDown) == 0) {
      current &= ~_bitDown & 0xff;
    }

    // D-pad hat (only affects non-digital directions)
    if (hx < -0.5 && (digital & _bitLeft) == 0) current &= ~_bitLeft & 0xff;
    if (hx > 0.5 && (digital & _bitRight) == 0) current &= ~_bitRight & 0xff;
    if (hy < -0.5 && (digital & _bitUp) == 0) current &= ~_bitUp & 0xff;
    if (hy > 0.5 && (digital & _bitDown) == 0) current &= ~_bitDown & 0xff;

    _deviceMask[deviceId] = current;
    _flush();
  }

  int _keyCodeToBit(int kc) {
    switch (kc) {
      case _kcDpadUp:
        return _bitUp;
      case _kcDpadDown:
        return _bitDown;
      case _kcDpadLeft:
        return _bitLeft;
      case _kcDpadRight:
        return _bitRight;
      // Fire buttons - excluding START/SELECT/MODE which pause games
      case _kcButtonA:
      case _kcButtonB:
      case _kcButtonC:
      case _kcButtonX:
      case _kcButtonY:
      case _kcButtonZ:
      case _kcButtonL1:
      case _kcButtonR1:
      case _kcButtonL2:
      case _kcButtonR2:
      case _kcButtonThumbL:
      case _kcButtonThumbR:
      case _kcButton1:
      case _kcButton2:
      case _kcButton3:
      case _kcButton4:
        return _bitFire;
      default:
        return 0;
    }
  }

  /// Merge device masks by port and push to the emulator FFI.
  void _flush() {
    final bridge = FrodoBridge.instance;
    if (!bridge.isReady) return;

    int assignedCount = 0;
    for (final d in _devices.values) {
      if (d.port != 0) assignedCount += 1;
    }

    int mergedP1 = 0xff;
    int mergedP2 = 0xff;

    for (final entry in _devices.entries) {
      final mask = _deviceMask[entry.key] ?? 0xff;
      if (entry.value.port == 1) {
        mergedP1 &= mask;
      } else if (entry.value.port == 2) {
        mergedP2 &= mask;
      }
    }

    // Compatibility fallback: with exactly one controller on Port 1, mirror
    // DIRECTIONS ONLY to Port 2 (where most single-player games expect input).
    //
    // IMPORTANT: We do NOT mirror to Port 1 because:
    // - Port 1 joystick shares CIA#1 port B with the keyboard matrix
    // - Any bit pulled low on Port 1 activates the corresponding keyboard column:
    //   - Bit 0 (Up)    = Column 0: DEL, 3, 5, 7, 9, +, £, 1
    //   - Bit 1 (Down)  = Column 1: RETURN, W, R, Y, I, P, *, ←
    //   - Bit 2 (Left)  = Column 2: CRSR-R, A, D, G, J, L, ;, CTRL
    //   - Bit 3 (Right) = Column 3: F7, 4, 6, 8, 0, -, HOME, 2
    //   - Bit 4 (Fire)  = Column 4: F1, Z, C, B, M, ., RSHIFT, SPACE
    // - This causes games to see phantom keypresses (SPACE=pause, F keys, etc.)
    //
    // Port 2 does NOT have this problem - it only affects the joystick, not keyboard.
    if (assignedCount == 1 && mergedP1 != 0xff && mergedP2 == 0xff) {
      // Controller on Port 1: mirror directions only to Port 2
      mergedP2 = (mergedP2 & 0xf0) | (mergedP1 & 0x0f);
    }
    // If controller is on Port 2, no mirroring needed - Port 2 is the standard gaming port

    if (mergedP1 != 0xff || mergedP2 != 0xff) {
      print(
        '[Gamepad] flush: P1=0x${mergedP1.toRadixString(16)} P2=0x${mergedP2.toRadixString(16)}',
      );
    }
    bridge.joystickSetOverride(0, mergedP1);
    bridge.joystickSetOverride(1, mergedP2);
  }

  void _notifyDevices() {
    _devicesController.add(devices);
  }
}
