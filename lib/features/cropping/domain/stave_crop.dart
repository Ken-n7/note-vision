import 'dart:typed_data';

class StaveCrop {
  final Uint8List imageBytes;
  final int staveIndex;
  final String? instrumentGroup;
  final double offsetX;
  final double offsetY;
  final double scale;
  final bool isBracePair;

  const StaveCrop({
    required this.imageBytes,
    required this.staveIndex,
    this.instrumentGroup,
    required this.offsetX,
    required this.offsetY,
    required this.scale,
    this.isBracePair = false,
  });
}
