import 'package:note_vision/core/models/barline_type.dart';
import 'package:note_vision/features/detection/domain/detected_barline.dart';
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

    final staffSymbols = assignments
        .where(
          (e) =>
              e.staff.id == staff.id &&
              !SymbolClassifier.isRepeatDot(e.symbol.type),
        )
        .toList()
      ..sort((a, b) => a.symbolCenterX.compareTo(b.symbolCenterX));
    final repeatDots = assignments
        .where(
          (e) =>
              e.staff.id == staff.id &&
              SymbolClassifier.isRepeatDot(e.symbol.type),
        )
        .toList();

    final barlines = detection.barlines
        .where((b) => b.staffId == null || b.staffId == staff.id)
        .toList()
      ..sort((a, b) => a.x.compareTo(b.x));
    final boundaryTypes = _boundaryTypes(barlines, repeatDots);

    if (barlines.isEmpty) {
      warnings.add(
        'No barlines detected; falling back to beat-count measure splitting.',
      );
      return _splitByBeats(
        staff: staff,
        staffSymbols: staffSymbols,
      );
    }

    final measures = <MeasureSymbols>[];
    var measureNumber = 1;
    var currentSymbols = <StaffOwnedSymbol>[];
    var barlineIndex = 0;
    BarlineType? pendingLeftBarlineType;

    for (final symbol in staffSymbols) {
      while (barlineIndex < barlines.length &&
          symbol.symbolCenterX > barlines[barlineIndex].x) {
        final boundary = boundaryTypes[barlines[barlineIndex].x];
        measures.add(MeasureSymbols(
          number: measureNumber,
          staff: staff,
          symbols: List.unmodifiable(currentSymbols),
          leftBarlineType: pendingLeftBarlineType,
          rightBarlineType: boundary?.rightType,
        ));
        currentSymbols = [];
        pendingLeftBarlineType = boundary?.leftType;
        measureNumber++;
        barlineIndex++;
      }
      currentSymbols.add(symbol);
    }

    measures.add(MeasureSymbols(
      number: measureNumber,
      staff: staff,
      symbols: List.unmodifiable(currentSymbols),
      leftBarlineType: pendingLeftBarlineType,
    ));

    while (barlineIndex < barlines.length) {
      final boundary = boundaryTypes[barlines[barlineIndex].x];
      measures[measures.length - 1] = MeasureSymbols(
        number: measures.last.number,
        staff: measures.last.staff,
        symbols: measures.last.symbols,
        leftBarlineType: measures.last.leftBarlineType,
        rightBarlineType: boundary?.rightType,
      );
      barlineIndex++;
      if (barlineIndex >= barlines.length) break;
      measureNumber++;
      measures.add(MeasureSymbols(
        number: measureNumber,
        staff: staff,
        symbols: const [],
        leftBarlineType: boundary?.leftType,
      ));
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
    var beatCount = 0.0;

    for (final symbol in staffSymbols) {
      final isMusical = SymbolClassifier.isNotehead(symbol.symbol.type) ||
          SymbolClassifier.isSupportedRest(symbol.symbol.type);
      final beats = isMusical ? _beatsFor(symbol) : 0.0;

      if (isMusical &&
          beatCount > 0 &&
          beatCount + beats > beatsPerMeasure + 1e-6) {
        measures.add(MeasureSymbols(
          number: measureNumber,
          staff: staff,
          symbols: List.unmodifiable(currentSymbols),
        ));
        currentSymbols = [];
        measureNumber++;
        beatCount = 0;
      }

      currentSymbols.add(symbol);
      beatCount += beats;
    }

    measures.add(MeasureSymbols(
      number: measureNumber,
      staff: staff,
      symbols: List.unmodifiable(currentSymbols),
    ));

    return measures;
  }

  /// Beats a musical symbol occupies. Noteheads only know their value when
  /// the detector supplies `metadata['noteType']`; otherwise (stem not yet
  /// associated) they count as one beat.
  double _beatsFor(StaffOwnedSymbol entry) {
    final noteType = switch (entry.symbol.type) {
      'restWhole' => 'whole',
      'restHalf' => 'half',
      'restQuarter' => 'quarter',
      'rest8th' => 'eighth',
      'rest16th' => 'sixteenth',
      _ => entry.symbol.metadata?['noteType'] as String?,
    };
    return noteType == null ? 1 : SymbolClassifier.beatValueFor(noteType);
  }

  int _inferBeatsPerMeasure(List<StaffOwnedSymbol> symbols) {
    for (final s in symbols) {
      if (s.symbol.type == 'timeSigCommon') return 4;
      if (s.symbol.type == 'timeSigCutCommon') return 2;
    }
    final digits = symbols
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

  Map<double, _BoundaryType> _boundaryTypes(
    List<DetectedBarline> barlines,
    List<StaffOwnedSymbol> repeatDots,
  ) {
    final result = <double, _BoundaryType>{};
    for (final barline in barlines) {
      var hasLeftDots = false;
      var hasRightDots = false;
      for (final dot in repeatDots) {
        final delta = dot.symbolCenterX - barline.x;
        if (delta.abs() > 18) continue;
        if (delta < 0) {
          hasLeftDots = true;
        } else if (delta > 0) {
          hasRightDots = true;
        }
      }
      result[barline.x] = _BoundaryType(
        leftType: hasRightDots ? BarlineType.repeatStart : null,
        rightType: hasLeftDots ? BarlineType.repeatEnd : null,
      );
    }
    return result;
  }
}

class _BoundaryType {
  const _BoundaryType({this.leftType, this.rightType});

  final BarlineType? leftType;
  final BarlineType? rightType;
}
