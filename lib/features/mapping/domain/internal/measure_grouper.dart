import 'package:note_vision/features/detection/domain/detected_staff.dart';
import 'package:note_vision/features/detection/domain/detection_result.dart';
import 'mapping_types.dart';
import 'symbol_classifier.dart';

class MeasureGrouper {
  const MeasureGrouper();

  List<MeasureSymbols> group({
    required DetectedStaff staff,
    required DetectionResult detection,
    required List<StaffOwnedSymbol> assignments,
    required List<String> warnings,
  }) {
    if (assignments.isEmpty) return const [];

    final staffSymbols =
        assignments.where((e) => e.staff.id == staff.id).toList()
          ..sort((a, b) => a.symbolCenterX.compareTo(b.symbolCenterX));

    final barlines =
        detection.barlines
            .where((b) => b.staffId == null || b.staffId == staff.id)
            .toList()
          ..sort((a, b) => a.x.compareTo(b.x));

    if (barlines.isEmpty) {
      warnings.add(
        'No barlines detected; falling back to beat-count measure splitting.',
      );
      return _splitByBeats(staff: staff, staffSymbols: staffSymbols);
    }

    final measures = <MeasureSymbols>[];
    var measureNumber = 1;
    var currentSymbols = <StaffOwnedSymbol>[];
    var barlineIndex = 0;

    for (final symbol in staffSymbols) {
      while (barlineIndex < barlines.length &&
          symbol.symbolCenterX > barlines[barlineIndex].x) {
        measures.add(
          MeasureSymbols(
            number: measureNumber,
            staff: staff,
            symbols: List.unmodifiable(currentSymbols),
          ),
        );
        currentSymbols = [];
        measureNumber++;
        barlineIndex++;
      }
      currentSymbols.add(symbol);
    }

    measures.add(
      MeasureSymbols(
        number: measureNumber,
        staff: staff,
        symbols: List.unmodifiable(currentSymbols),
      ),
    );

    while (barlineIndex < barlines.length - 1) {
      measureNumber++;
      measures.add(
        MeasureSymbols(number: measureNumber, staff: staff, symbols: const []),
      );
      barlineIndex++;
    }

    return measures;
  }

  List<MeasureSymbols> _splitByBeats({
    required DetectedStaff staff,
    required List<StaffOwnedSymbol> staffSymbols,
  }) {
    if (staffSymbols.isEmpty) {
      return [MeasureSymbols(number: 1, staff: staff, symbols: const [])];
    }

    final beatsPerMeasure = _inferBeatsPerMeasure(staffSymbols);
    final measures = <MeasureSymbols>[];
    var measureNumber = 1;
    var currentSymbols = <StaffOwnedSymbol>[];
    var beatCount = 0;

    for (final symbol in staffSymbols) {
      final isMusical =
          SymbolClassifier.isNotehead(symbol.symbol.type) ||
          SymbolClassifier.isSupportedRest(symbol.symbol.type);

      if (isMusical && beatCount > 0 && beatCount % beatsPerMeasure == 0) {
        measures.add(
          MeasureSymbols(
            number: measureNumber,
            staff: staff,
            symbols: List.unmodifiable(currentSymbols),
          ),
        );
        currentSymbols = [];
        measureNumber++;
      }

      currentSymbols.add(symbol);
      if (isMusical) beatCount++;
    }

    measures.add(
      MeasureSymbols(
        number: measureNumber,
        staff: staff,
        symbols: List.unmodifiable(currentSymbols),
      ),
    );

    return measures;
  }

  int _inferBeatsPerMeasure(List<StaffOwnedSymbol> symbols) {
    for (final s in symbols) {
      if (s.symbol.type == 'timeSigCommon') return 4;
      if (s.symbol.type == 'timeSigCutCommon') return 2;
    }
    final digits =
        symbols
            .where((s) => SymbolClassifier.timeSigDigit(s.symbol.type) != null)
            .toList()
          ..sort((a, b) => a.symbolCenterX.compareTo(b.symbolCenterX));
    if (digits.isNotEmpty) {
      final val = int.tryParse(
        SymbolClassifier.timeSigDigit(digits.first.symbol.type)!,
      );
      if (val != null && val > 0) return val;
    }
    return 4;
  }
}
