import 'dart:typed_data';

class PreprocessedResult {
  final Uint8List bytes;
  final int width;
  final int height;

  // Letterbox metadata — needed later to remap detection bounding boxes
  final double scale;
  final int padX;
  final int padY;

  const PreprocessedResult({
    required this.bytes,
    required this.width,
    required this.height,
    required this.scale,
    required this.padX,
    required this.padY,
  });
}
