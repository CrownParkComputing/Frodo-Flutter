import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import 'frodo_bindings.dart';

enum DisplayAspectMode {
  standard4x3(4 / 3, '4:3'),
  widescreen16x9(16 / 9, '16:9');

  const DisplayAspectMode(this.aspectRatio, this.label);

  final double aspectRatio;
  final String label;
}

/// Widget that renders the C64 framebuffer at ~50 Hz.
class EmulatorDisplay extends StatefulWidget {
  const EmulatorDisplay({super.key, required this.aspectMode});

  final DisplayAspectMode aspectMode;

  @override
  State<EmulatorDisplay> createState() => _EmulatorDisplayState();
}

class _EmulatorDisplayState extends State<EmulatorDisplay> {
  ui.Image? _frame;
  Timer? _timer;
  final _bridge = FrodoBridge.instance;

  @override
  void initState() {
    super.initState();
    // ~50 fps to match PAL VBlank rate
    _timer = Timer.periodic(const Duration(milliseconds: 20), (_) {
      _grabFrame();
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _frame?.dispose();
    super.dispose();
  }

  Future<void> _grabFrame() async {
    if (!_bridge.isReady) return;

    final Uint8List argbBytes = _bridge.captureFrame();
    final Uint32List argb32 = argbBytes.buffer.asUint32List(
      argbBytes.offsetInBytes,
      framePixels,
    );

    // Convert packed ARGB8888 words to RGBA8888 bytes for dart:ui.
    // The native buffer is uint32 ARGB values, so reading per-byte directly
    // can break channels on little-endian devices.
    final rgba = Uint8List(argbBytes.length);
    for (int i = 0; i < argb32.length; i++) {
      final pixel = argb32[i];
      final base = i * 4;
      rgba[base] = (pixel >> 16) & 0xFF; // R
      rgba[base + 1] = (pixel >> 8) & 0xFF; // G
      rgba[base + 2] = pixel & 0xFF; // B
      rgba[base + 3] = (pixel >> 24) & 0xFF; // A
    }

    final completer = Completer<ui.Image>();
    ui.decodeImageFromPixels(
      rgba,
      displayW,
      displayH,
      ui.PixelFormat.rgba8888,
      (image) => completer.complete(image),
    );

    final newFrame = await completer.future;
    if (!mounted) {
      newFrame.dispose();
      return;
    }

    setState(() {
      _frame?.dispose();
      _frame = newFrame;
    });
  }

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: Colors.black,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final viewport = _fitViewport(
            constraints.biggest,
            widget.aspectMode.aspectRatio,
          );

          return Center(
            child: SizedBox(
              width: viewport.width,
              height: viewport.height,
              child:
                  _frame != null
                      ? CustomPaint(
                        painter: _FramePainter(_frame!),
                        size: Size.infinite,
                      )
                      : const ColoredBox(
                        color: Colors.black,
                        child: Center(
                          child: Text(
                            'Initializing...',
                            style: TextStyle(color: Colors.white38),
                          ),
                        ),
                      ),
            ),
          );
        },
      ),
    );
  }

  Size _fitViewport(Size available, double targetAspect) {
    final availableAspect = available.width / available.height;
    if (availableAspect > targetAspect) {
      final height = available.height;
      return Size(height * targetAspect, height);
    }

    final width = available.width;
    return Size(width, width / targetAspect);
  }
}

class _FramePainter extends CustomPainter {
  _FramePainter(this.image);
  final ui.Image image;

  @override
  void paint(Canvas canvas, Size size) {
    final src = Rect.fromLTWH(
      0,
      0,
      image.width.toDouble(),
      image.height.toDouble(),
    );
    final dst = Rect.fromLTWH(0, 0, size.width, size.height);
    canvas.drawImageRect(
      image,
      src,
      dst,
      Paint()..filterQuality = FilterQuality.low,
    );
  }

  @override
  bool shouldRepaint(_FramePainter old) => true;
}
