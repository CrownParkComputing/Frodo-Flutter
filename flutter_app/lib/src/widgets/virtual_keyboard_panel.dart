import 'package:flutter/material.dart';

import '../frodo_bindings.dart';

class VirtualKeyboardPanel extends StatelessWidget {
  const VirtualKeyboardPanel({
    super.key,
    required this.onClose,
    required this.bridge,
  });

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
            if (i != keys.length - 1) const SizedBox(width: 3),
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
      height: 26,
      child: ElevatedButton(
        style: ElevatedButton.styleFrom(
          minimumSize: Size(width, 26),
          padding: const EdgeInsets.symmetric(horizontal: 2),
          textStyle: const TextStyle(fontSize: 8, fontWeight: FontWeight.w600),
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          visualDensity: const VisualDensity(horizontal: -3, vertical: -3),
        ),
        onPressed: onPressed,
        child: Text(label),
      ),
    );
  }
}
