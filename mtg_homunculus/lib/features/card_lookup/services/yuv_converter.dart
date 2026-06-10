import 'dart:typed_data';

import 'package:camera/camera.dart';

/// Converts raw camera frames to formats expected by OpenCV and ML Kit.
///
/// Android camera delivers YUV_420_888 frames (three separate planes).
/// Both OpenCV (via `cv.COLOR_YUV2BGR_NV21`) and ML Kit expect the planes
/// interleaved in NV21 layout: all Y bytes first, then interleaved VU pairs.
class YuvConverter {
  YuvConverter._();

  /// Convert a [CameraImage] in YUV_420_888 format to a flat NV21 byte buffer.
  ///
  /// Output layout:
  /// ```
  /// [ Y0 Y1 … Yw×h | V0 U0 V1 U1 … V(w/2×h/2) U(w/2×h/2) ]
  /// ```
  ///
  /// Handles non-contiguous planes (stride > width) and semi-planar UV
  /// layouts (bytesPerPixel == 2) correctly.
  static Uint8List yuv420ToNv21(CameraImage frame) {
    final int w = frame.width;
    final int h = frame.height;

    final yPlane = frame.planes[0];
    final uPlane = frame.planes[1];
    final vPlane = frame.planes[2];

    final int yStride  = yPlane.bytesPerRow;
    final int uvStride = uPlane.bytesPerRow;
    final int uvStep   = uPlane.bytesPerPixel ?? 1;

    final out = Uint8List(w * h + 2 * (w ~/ 2) * (h ~/ 2));
    int idx = 0;

    // Copy Y plane — strip row padding if stride > width.
    for (int row = 0; row < h; row++) {
      final rowStart = row * yStride;
      for (int col = 0; col < w; col++) {
        out[idx++] = yPlane.bytes[rowStart + col];
      }
    }

    // Interleave V then U (NV21 order) from the chroma planes.
    for (int row = 0; row < h ~/ 2; row++) {
      for (int col = 0; col < w ~/ 2; col++) {
        final int offset = row * uvStride + col * uvStep;
        out[idx++] = vPlane.bytes[offset];
        out[idx++] = uPlane.bytes[offset];
      }
    }

    return out;
  }
}
