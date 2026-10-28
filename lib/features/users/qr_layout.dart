import 'dart:math' as math;

import 'package:qr_flutter/qr_flutter.dart';

/// Edge length of a QR code on screen plus the device pixels per module.
class QrGeometry {
  const QrGeometry({required this.size, required this.pixelsPerModule});

  /// Logical pixels per side.
  final double size;

  /// Device pixels per module; always a whole number so edges stay crisp.
  final int pixelsPerModule;
}

/// Medium correction for links, low for long payloads (fewer, larger modules).
int qrLevelFor(int bytes) =>
    bytes > 1000 ? QrErrorCorrectLevel.L : QrErrorCorrectLevel.M;

/// Encodes [payload], or null when it does not fit a version 40 code. The
/// validator alone misses that: only the encoder throws, during build.
QrCode? encodeQr(String payload) {
  final code = QrCode.fromData(
    data: payload,
    errorCorrectLevel: qrLevelFor(payload.length),
  );
  try {
    QrImage(code);
  } on InputTooLongException {
    return null;
  }
  return code;
}

/// Sizes a [modules]-wide code within [maxWidth], snapped so each module
/// covers whole device pixels (fractional modules anti-alias into grey).
QrGeometry qrGeometry({
  required int modules,
  required double maxWidth,
  required double dpr,
  double targetModule = 3,
  double minSize = 216,
}) {
  assert(modules > 0 && dpr > 0);
  final cap = math.max(maxWidth, 1.0);
  final wanted = math.min(cap, math.max(minSize, modules * targetModule));
  final px = math.max(1, (wanted * dpr) ~/ modules);
  return QrGeometry(size: modules * px / dpr, pixelsPerModule: px);
}
