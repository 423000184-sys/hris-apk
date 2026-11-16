// lib/services/face_embedder_native.dart
import 'dart:math' as math;
import 'dart:typed_data';
import 'package:tflite_flutter/tflite_flutter.dart';

class FaceEmbedder {
  FaceEmbedder._();
  static final instance = FaceEmbedder._();

  static const String modelAsset = 'assets/models/mobilefacenet.tflite';
  Interpreter? _interp;
  int _dim = 0;

  Future<void> init() async {
    if (_interp != null) return;
    final opts = InterpreterOptions()..threads = 2;
    _interp = await Interpreter.fromAsset(modelAsset, options: opts);
    _dim = _interp!.getOutputTensor(0).shape.last;
  }

  Float32List? embed(Float32List aligned) {
    final it = _interp;
    if (it == null) return null;
    final input = aligned.reshape([1, 112, 112, 3]);
    final output = List.filled(_dim, 0.0).reshape([1, _dim]);
    it.run(input, output);
    final v = Float32List.fromList((output[0] as List).cast<double>());
    double n = 0;
    for (final x in v) {
      n += x * x;
    }
    n = math.sqrt(n);
    if (n == 0 || n.isNaN) return null;
    for (int i = 0; i < v.length; i++) {
      v[i] /= n;
    }
    return v;
  }
}