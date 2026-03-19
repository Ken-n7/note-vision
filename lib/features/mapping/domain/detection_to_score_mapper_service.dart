import 'dart:math' as math;
import 'package:note_vision/features/detection/domain/detection_result.dart';
import 'mapping_confidence_summary.dart';
import 'mapping_result.dart';
import 'score_mapper_service.dart';
import 'internal/measure_grouper.dart';
import 'internal/score_builder.dart';
import 'internal/semantic_inferrer.dart';
import 'internal/staff_assigner.dart';
import 'internal/stem_associator.dart';

class DetectionToScoreMapperService extends ScoreMapperService {
  final StaffAssigner _staffAssigner;
  final MeasureGrouper _measureGrouper;
  final StemAssociator _stemAssociator;
  final SemanticInferrer _semanticInferrer;
  final ScoreBuilder _scoreBuilder;

  const DetectionToScoreMapperService({
    StaffAssigner staffAssigner = const StaffAssigner(),
    MeasureGrouper measureGrouper = const MeasureGrouper(),
    StemAssociator stemAssociator = const StemAssociator(),
    SemanticInferrer semanticInferrer = const SemanticInferrer(),
    ScoreBuilder scoreBuilder = const ScoreBuilder(),
  })  : _staffAssigner = staffAssigner,
        _measureGrouper = measureGrouper,
        _stemAssociator = stemAssociator,
        _semanticInferrer = semanticInferrer,
        _scoreBuilder = scoreBuilder;

  @override
  MappingResult map(DetectionResult detection) {
    final warnings = <String>[];
    final errors = <String>[];

    if (detection.staffs.isEmpty) {
      warnings.add('No staff detected; returning an empty mapped score.');
      return MappingResult(
        score: _scoreBuilder.buildEmpty(),
        warnings: warnings,
        errors: errors,
        confidenceSummary: _buildConfidenceSummary(
          detection: detection,
          mappedSymbolCount: 0,
        ),
      );
    }

    if (detection.staffs.length > 1) {
      warnings.add(
        'Multiple staffs detected, but Sprint 4 supports only a single staff. Using the best-matching staff assignments only.',
      );
    }

    final assignments = _staffAssigner.assign(detection, warnings: warnings);
    final measures = _measureGrouper.group(
      detection: detection,
      assignments: assignments,
      warnings: warnings,
    );
    final stemLinks = _stemAssociator.associate(measures, warnings: warnings);
    final semanticMeasures = _semanticInferrer.infer(
      measures: measures,
      stemLinks: stemLinks,
      warnings: warnings,
    );
    final score = _scoreBuilder.build(semanticMeasures);

    final mappedCount = semanticMeasures.fold<int>(
      0,
      (sum, m) => sum + m.symbols.length,
    );

    if (mappedCount == 0) {
      warnings.add('No supported symbols were reconstructable.');
    }

    return MappingResult(
      score: score,
      warnings: warnings,
      errors: errors,
      confidenceSummary: _buildConfidenceSummary(
        detection: detection,
        mappedSymbolCount: mappedCount,
      ),
    );
  }

  MappingConfidenceSummary _buildConfidenceSummary({
    required DetectionResult detection,
    required int mappedSymbolCount,
  }) {
    final confidences = detection.symbols
        .map((s) => s.confidence)
        .whereType<double>()
        .toList();

    final avg = confidences.isEmpty
        ? null
        : confidences.reduce((a, b) => a + b) / confidences.length;

    return MappingConfidenceSummary(
      inputSymbolCount: detection.symbols.length,
      mappedSymbolCount: mappedSymbolCount,
      droppedSymbolCount:
          math.max(0, detection.symbols.length - mappedSymbolCount),
      averageDetectionConfidence: avg,
    );
  }
}