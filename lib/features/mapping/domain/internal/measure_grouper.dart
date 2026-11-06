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

    final staffSymbols =
        assignments
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

    final barlines =
        detection.barlines
            .where((b) => b.staffId == null || b.staffId == staff.id)
            .toList()
          ..sort((a, b) => a.x.compareTo(b.x));
    final boundaryTypes = _boundaryTypes(barlines, repeatDots);

    if (barlines.isEmpty) {
      if (staffSymbols.any(
        (s) =>
            SymbolClassifier.isNotehead(s.symbol.type) ||
            SymbolClassifier.isSupportedRest(s.symbol.type),
      )) {
        warnings.add(
          'No barlines detected on ${staff.id}; row kept together for review.',
        );
        return [
          MeasureSymbols(
            number: 1,
            staff: staff,
            symbols: List.unmodifiable(staffSymbols),
            unresolvedBarlines: true,
          ),
        ];
      }
      return [
        MeasureSymbols(
          number: 1,
          staff: staff,
          symbols: List.unmodifiable(staffSymbols),
        ),
      ];
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
        measures.add(
          MeasureSymbols(
            number: measureNumber,
            staff: staff,
            symbols: List.unmodifiable(currentSymbols),
            leftBarlineType: pendingLeftBarlineType,
            rightBarlineType: boundary?.rightType,
          ),
        );
        currentSymbols = [];
        pendingLeftBarlineType = boundary?.leftType;
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
        leftBarlineType: pendingLeftBarlineType,
      ),
    );

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
      measures.add(
        MeasureSymbols(
          number: measureNumber,
          staff: staff,
          symbols: const [],
          leftBarlineType: boundary?.leftType,
        ),
      );
    }

    return measures;
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
