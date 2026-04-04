/// Gamepad detection, port assignment, and live button indicator sheet.
library;

import 'dart:async';

import 'package:flutter/material.dart';

import '../gamepad_service.dart';

class GamepadPage extends StatefulWidget {
  const GamepadPage({super.key});

  @override
  State<GamepadPage> createState() => _GamepadPageState();
}

class _GamepadPageState extends State<GamepadPage> {
  final _service = GamepadService.instance;
  StreamSubscription<List<GamepadDevice>>? _sub;
  List<GamepadDevice> _devices = [];

  @override
  void initState() {
    super.initState();
    _devices = List.of(_service.devices);
    _sub = _service.devicesStream.listen((d) {
      if (mounted) setState(() => _devices = List.of(d));
    });
    _service.refreshDevices();
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Header
            Row(
              children: [
                const Icon(Icons.sports_esports, color: Colors.cyanAccent),
                const SizedBox(width: 10),
                const Expanded(
                  child: Text(
                    'Gamepads',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.refresh, color: Colors.white54),
                  tooltip: 'Refresh',
                  onPressed: () => _service.refreshDevices(),
                ),
              ],
            ),
            const Divider(color: Colors.white24),

            if (_devices.isEmpty) ...[
              const SizedBox(height: 16),
              const Center(
                child: Text(
                  'No gamepads detected.\nConnect a controller and tap Refresh.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.white54),
                ),
              ),
              const SizedBox(height: 16),
            ] else ...[
              const SizedBox(height: 4),
              ..._devices.map((d) => _DeviceTile(device: d, service: _service)),
            ],

            const Divider(color: Colors.white12),
            const _MappingLegend(),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Single device row with port selector
// ---------------------------------------------------------------------------
class _DeviceTile extends StatelessWidget {
  const _DeviceTile({required this.device, required this.service});

  final GamepadDevice device;
  final GamepadService service;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0x22FFFFFF),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.white12),
      ),
      child: Row(
        children: [
          const Icon(Icons.gamepad, color: Colors.white70, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              device.name,
              style: const TextStyle(color: Colors.white, fontSize: 14),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: 8),
          _PortSelector(device: device, service: service),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Port assignment toggle: Off / Port 1 / Port 2
// ---------------------------------------------------------------------------
class _PortSelector extends StatelessWidget {
  const _PortSelector({required this.device, required this.service});

  final GamepadDevice device;
  final GamepadService service;

  @override
  Widget build(BuildContext context) {
    return SegmentedButton<int>(
      segments: const [
        ButtonSegment(
          value: 0,
          label: Text('Off', style: TextStyle(fontSize: 11)),
        ),
        ButtonSegment(
          value: 1,
          label: Text('P1', style: TextStyle(fontSize: 11)),
        ),
        ButtonSegment(
          value: 2,
          label: Text('P2', style: TextStyle(fontSize: 11)),
        ),
      ],
      selected: {device.port},
      showSelectedIcon: false,
      style: ButtonStyle(
        visualDensity: VisualDensity.compact,
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),
      onSelectionChanged: (set) => service.assignPort(device.id, set.first),
    );
  }
}

// ---------------------------------------------------------------------------
// Button mapping legend
// ---------------------------------------------------------------------------
class _MappingLegend extends StatelessWidget {
  const _MappingLegend();

  @override
  Widget build(BuildContext context) {
    const rowStyle = TextStyle(color: Colors.white60, fontSize: 12);
    const labelStyle = TextStyle(
      color: Colors.white38,
      fontSize: 11,
      fontWeight: FontWeight.bold,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Default button mapping', style: labelStyle),
        const SizedBox(height: 6),
        Wrap(
          spacing: 16,
          runSpacing: 4,
          children: const [
            _LegendChip(icon: Icons.arrow_upward, label: 'D-pad / Left stick'),
            _LegendChip(
              icon: Icons.circle_outlined,
              label: 'A / B / X / Y / L1 / R1 = Fire',
            ),
          ],
        ),
        const SizedBox(height: 4),
        const Text(
          'Assign this controller to Port 1 or Port 2 above.',
          style: rowStyle,
        ),
      ],
    );
  }
}

class _LegendChip extends StatelessWidget {
  const _LegendChip({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 14, color: Colors.white54),
        const SizedBox(width: 4),
        Text(
          label,
          style: const TextStyle(color: Colors.white60, fontSize: 12),
        ),
      ],
    );
  }
}
