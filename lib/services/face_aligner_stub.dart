import 'dart:typed_data';
import 'package:camera/camera.dart';

class RgbImage {
  final int w, h;
  final Uint8List px;
  const RgbImage(this.w, this.h, this.px);
}

class FaceAligner {
  static const int size = 112;

  static RgbImage? cameraToRgb(CameraImage img, {int down = 2}) => null;
  static RgbImage rotate(RgbImage s, int deg) => s;
  static Float32List? align(RgbImage src, double ax, double ay, double bx, double by) => null;
}