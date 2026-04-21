import 'package:note_vision/features/detection/domain/detection_result.dart';

import 'mapping_result.dart';

abstract class ScoreMapperService {
  const ScoreMapperService();

  MappingResult map(DetectionResult detection);
}