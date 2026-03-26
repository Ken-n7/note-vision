import 'package:note_vision/features/preprocessing/domain/preprocessed_result.dart';
import 'package:note_vision/features/structure/domain/score_structure.dart';

import 'stave_crop.dart';

abstract class StaveAwareCropper {
  Future<List<StaveCrop>> crop(PreprocessedResult preprocessed, ScoreStructure structure);
}
