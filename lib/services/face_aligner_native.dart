// lib/services/face_aligner_native.dart
import 'dart:math' as math;
import 'dart:typed_data';
import 'package:camera/camera.dart';

class RgbImage {
  final int w, h;
  final Uint8List px; // RGB, 3 bytes per pixel
  const RgbImage(this.w, this.h, this.px);
}

class FaceAligner {
  static const int size = 112;
  static const double _lx = 38.2946, _ly = 51.6963;
  static const double _rx = 73.5318, _ry = 51.5014;

  static RgbImage? cameraToRgb(CameraImage img, {int down = 2}) {
    try {
      final w = img.width, h = img.height;
      final ow = w ~/ down, oh = h ~/ down;
      final out = Uint8List(ow * oh * 3);
      final planes = img.planes;
      int o = 0;

      for (int oy = 0; oy < oh; oy++) {
        final y = oy * down;
        for (int ox = 0; ox < ow; ox++) {
          final x = ox * down;
          int yy, u, v;
          if (planes.length == 1) {
            final p = planes[0];
            final stride = p.bytesPerRow;
            yy = p.bytes[y * stride + x];
            final i = stride * h + (y >> 1) * stride + (x >> 1) * 2;
            v = p.bytes[i];
            u = p.bytes[i + 1];
          } else if (planes.length >= 3) {
            yy = planes[0].bytes[y * planes[0].bytesPerRow + x];
            final uvRow = planes[1].bytesPerRow;
            final uvPix = planes[1].bytesPerPixel ?? 1;
            final i = (y >> 1) * uvRow + (x >> 1) * uvPix;
            u = planes[1].bytes[i];
            v = planes[2].bytes[i];
          } else {
            return null;
          }
          final r = yy + 1.402 * (v - 128);
          final g = yy - 0.344136 * (u - 128) - 0.714136 * (v - 128);
          final b = yy + 1.772 * (u - 128);
          out[o++] = r.clamp(0, 255).toInt();
          out[o++] = g.clamp(0, 255).toInt();
          out[o++] = b.clamp(0, 255).toInt();
        }
      }
      return RgbImage(ow, oh, out);
    } catch (_) {
      return null;
    }
  }

  static RgbImage rotate(RgbImage s, int deg) {
    if (deg == 0) return s;
    final w = s.w, h = s.h;
    final swap = deg == 90 || deg == 270;
    final nw = swap ? h : w, nh = swap ? w : h;
    final d = Uint8List(nw * nh * 3);
    for (int y = 0; y < h; y++) {
      for (int x = 0; x < w; x++) {
        int dx, dy;
        switch (deg) {
          case 90:
            dx = h - 1 - y;
            dy = x;
            break;
          case 180:
            dx = w - 1 - x;
            dy = h - 1 - y;
            break;
          default: // 270
            dx = y;
            dy = w - 1 - x;
        }
        final si = (y * w + x) * 3, di = (dy * nw + dx) * 3;
        d[di] = s.px[si];
        d[di + 1] = s.px[si + 1];
        d[di + 2] = s.px[si + 2];
      }
    }
    return RgbImage(nw, nh, d);
  }

  static Float32List? align(RgbImage src, double ax, double ay, double bx, double by) {
    if (ax > bx) {
      final tx = ax, ty = ay;
      ax = bx;
      ay = by;
      bx = tx;
      by = ty;
    }
    final dx = bx - ax, dy = by - ay;
    final dist = math.sqrt(dx * dx + dy * dy);
    if (dist < 12) return null;

    final tdx = _rx - _lx, tdy = _ry - _ly;
    final scale = math.sqrt(tdx * tdx + tdy * tdy) / dist;
    final theta = math.atan2(tdy, tdx) - math.atan2(dy, dx);
    final cosT = math.cos(-theta), sinT = math.sin(-theta);
    final mx = (ax + bx) / 2, my = (ay + by) / 2;
    final tmx = (_lx + _rx) / 2, tmy = (_ly + _ry) / 2;

    final out = Float32List(size * size * 3);
    int o = 0;
    for (int v = 0; v < size; v++) {
      for (int u = 0; u < size; u++) {
        final px = (u - tmx) / scale, py = (v - tmy) / scale;
        final sx = cosT * px - sinT * py + mx;
        final sy = sinT * px + cosT * py + my;
        _bilinear(src, sx, sy, out, o);
        o += 3;
      }
    }
    return out;
  }

  static void _bilinear(RgbImage s, double x, double y, Float32List out, int o) {
    if (x < 0 || y < 0 || x >= s.w - 1 || y >= s.h - 1) {
      out[o] = out[o + 1] = out[o + 2] = (0 - 127.5) / 128;
      return;
    }
    final x0 = x.floor(), y0 = y.floor();
    final fx = x - x0, fy = y - y0;
    for (int c = 0; c < 3; c++) {
      final p00 = s.px[(y0 * s.w + x0) * 3 + c];
      final p10 = s.px[(y0 * s.w + x0 + 1) * 3 + c];
      final p01 = s.px[((y0 + 1) * s.w + x0) * 3 + c];
      final p11 = s.px[((y0 + 1) * s.w + x0 + 1) * 3 + c];
      final v = p00 * (1 - fx) * (1 - fy) +
          p10 * fx * (1 - fy) +
          p01 * (1 - fx) * fy +
          p11 * fx * fy;
      out[o + c] = (v - 127.5) / 128;
    }
  }
}