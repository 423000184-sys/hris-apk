import 'dart:typed_data';

class FaceEmbedder {
  FaceEmbedder._();
  static final instance = FaceEmbedder._();

  static const String modelAsset = 'assets/models/mobilefacenet.tflite';

  Future<void> init() async {}

  Float32List? embed(Float32List aligned) => null;
}