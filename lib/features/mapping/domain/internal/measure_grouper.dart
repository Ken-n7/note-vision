import 'package:note_vision/features/detection/domain/detected_staff.dart';
import 'package:note_vision/features/detection/domain/detection_result.dart';
import 'mapping_types.dart';

class MeasureGrouper {
  const MeasureGrouper();

  List<MeasureSymbols> group({
    required DetectedStaff staff,
    required DetectionResult detection,
    required List<StaffOwnedSymbol> assignments,
    required List<String> warnings,
  }) {
    if (assignments.isEmpty) return const [];

    final staffSymbols = assignments
        .where((e) => e.staff.id == staff.id)
        .toList()
      ..sort((a, b) => a.symbolCenterX.compareTo(b.symbolCenterX));

    final barlines = detection.barlines
        .where((b) => b.staffId == null || b.staffId == staff.id)
        .toList()
      ..sort((a, b) => a.x.compareTo(b.x));

    if (barlines.isEmpty) {
      warnings.add('No barlines detected; reconstructing a single measure.');
    }

    final measures = <MeasureSymbols>[];
    var measureNumber = 1;
    var currentSymbols = <StaffOwnedSymbol>[];
    var barlineIndex = 0;

    for (final symbol in staffSymbols) {
      while (barlineIndex < barlines.length &&
          symbol.symbolCenterX > barlines[barlineIndex].x) {
        measures.add(MeasureSymbols(
          number: measureNumber,
          staff: staff,
          symbols: List.unmodifiable(currentSymbols),
        ));
        currentSymbols = [];
        measureNumber++;
        barlineIndex++;
      }
      currentSymbols.add(symbol);
    }

    measures.add(MeasureSymbols(
      number: measureNumber,
      staff: staff,
      symbols: List.unmodifiable(currentSymbols),
    ));

    while (barlineIndex < barlines.length - 1) {
      measureNumber++;
      measures.add(MeasureSymbols(
        number: measureNumber,
        staff: staff,
        symbols: const [],
      ));
      barlineIndex++;
    }

    return measures;
  }
}
