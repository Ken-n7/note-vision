import 'package:note_vision/features/preprocessing/domain/preprocessed_result.dart';
import 'score_structure.dart';

abstract class StructureDetector {
  Future<ScoreStructure> detect(PreprocessedResult input);
}
