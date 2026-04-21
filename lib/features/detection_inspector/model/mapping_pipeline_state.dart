// lib/features/dev/detection_inspector/model/mapping_pipeline_state.dart

import 'package:note_vision/features/detection/domain/detection_result.dart';
import 'package:note_vision/features/mapping/domain/internal/mapping_types.dart';
import 'package:note_vision/features/mapping/domain/mapping_result.dart';

/// Captures the full intermediate state of the mapping pipeline
/// so each stage can be inspected independently.
class MappingPipelineState {
  /// Stage 1 – raw detection input
  final DetectionResult detection;

  /// Stage 2 – every symbol assigned to a staff
  final List<StaffOwnedSymbol> assignments;

  /// Stage 3 – symbols grouped into measures
  final List<MeasureSymbols> measures;

  /// Stage 4 – stem/flag links keyed by notehead symbol id
  final Map<String, StemLink> stemLinks;

  /// Stage 5 – final mapping result (score + warnings + errors)
  final MappingResult result;

  const MappingPipelineState({
    required this.detection,
    required this.assignments,
    required this.measures,
    required this.stemLinks,
    required this.result,
  });
}
