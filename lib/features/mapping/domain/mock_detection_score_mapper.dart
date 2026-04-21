import 'dart:convert';
import 'dart:io';

import 'package:note_vision/features/detection/domain/detection_result.dart';

import 'mapping_result.dart';
import 'score_mapper_service.dart';

/// Maps supported mock-detection JSON inputs into a score reconstruction.
class MockDetectionScoreMapper {
  final ScoreMapperService _mapper;

  const MockDetectionScoreMapper({
    required ScoreMapperService mapper,
  }) : _mapper = mapper;

  MappingResult mapJson(Map<String, dynamic> json) {
    final detection = DetectionResult.fromJson(json);
    return _mapper.map(detection);
  }

  MappingResult mapJsonString(String jsonString) {
    final decoded = jsonDecode(jsonString);
    if (decoded is! Map) {
      throw const FormatException(
        'Mock detection JSON must decode to an object.',
      );
    }

    return mapJson(Map<String, dynamic>.from(decoded));
  }

  Future<MappingResult> mapFile(String path) async {
    final jsonString = await File(path).readAsString();
    return mapJsonString(jsonString);
  }
}
