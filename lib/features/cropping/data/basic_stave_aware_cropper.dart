import 'package:note_vision/features/cropping/domain/stave_aware_cropper.dart';
import 'package:note_vision/features/cropping/domain/stave_crop.dart';
import 'package:note_vision/features/preprocessing/domain/preprocessed_result.dart';
import 'package:note_vision/features/structure/domain/score_structure.dart';

class BasicStaveAwareCropper implements StaveAwareCropper {
  const BasicStaveAwareCropper();

  @override
  Future<List<StaveCrop>> crop(
    PreprocessedResult preprocessed,
    ScoreStructure structure,
  ) async {
    if (structure.systems.isEmpty) {
      return [
        StaveCrop(
          imageBytes: preprocessed.bytes,
          staveIndex: 0,
          offsetX: 0,
          offsetY: 0,
          scale: preprocessed.scale,
        ),
      ];
    }

    // Current implementation keeps full-image crop while preserving metadata.
    return List<StaveCrop>.generate(structure.systems.length, (index) {
      final system = structure.systems[index];
      return StaveCrop(
        imageBytes: preprocessed.bytes,
        staveIndex: index,
        instrumentGroup: _groupForSystem(structure, system.bounds.top),
        offsetX: system.bounds.left,
        offsetY: system.bounds.top,
        scale: preprocessed.scale,
      );
    });
  }

  String? _groupForSystem(ScoreStructure structure, double y) {
    for (final group in structure.groups) {
      if (y >= group.bounds.top && y <= group.bounds.bottom) {
        return group.type;
      }
    }
    return null;
  }
}
