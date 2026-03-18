import 'dart:math' as math;

import 'package:note_vision/core/models/clef.dart';
import 'package:note_vision/core/models/measure.dart';
import 'package:note_vision/core/models/note.dart';
import 'package:note_vision/core/models/part.dart';
import 'package:note_vision/core/models/rest.dart';
import 'package:note_vision/core/models/score.dart';
import 'package:note_vision/core/models/score_symbol.dart';
// import 'package:note_vision/features/detection/domain/detected_barline.dart';
import 'package:note_vision/features/detection/domain/detected_staff.dart';
import 'package:note_vision/features/detection/domain/detected_symbol.dart';
import 'package:note_vision/features/detection/domain/detection_result.dart';

import 'mapping_confidence_summary.dart';
import 'mapping_result.dart';
import 'score_mapper_service.dart';

class DetectionToScoreMapperService extends ScoreMapperService {
  const DetectionToScoreMapperService();

  @override
  MappingResult map(DetectionResult detection) {
    final warnings = <String>[];
    final errors = <String>[];

    if (detection.staffs.isEmpty) {
      warnings.add('No staff detected; returning an empty mapped score.');
      return MappingResult(
        score: _buildEmptyScore(),
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

    final assignments = assignSymbolsToStaffs(detection, warnings: warnings);
    final measures = groupSymbolsIntoMeasures(
      detection: detection,
      assignments: assignments,
      warnings: warnings,
    );
    final stemLinks = associateStemsWithNoteheads(measures, warnings: warnings);
    final semanticMeasures = inferNoteRestSemantics(
      measures: measures,
      stemLinks: stemLinks,
      warnings: warnings,
    );
    final score = buildScore(semanticMeasures);

    final mappedSymbolCount = semanticMeasures.fold<int>(
      0,
      (sum, measure) => sum + measure.symbols.length,
    );

    if (mappedSymbolCount == 0) {
      warnings.add('No supported symbols were reconstructable from the detection result.');
    }

    return MappingResult(
      score: score,
      warnings: warnings,
      errors: errors,
      confidenceSummary: _buildConfidenceSummary(
        detection: detection,
        mappedSymbolCount: mappedSymbolCount,
      ),
    );
  }

  List<_StaffOwnedSymbol> assignSymbolsToStaffs(
    DetectionResult detection, {
    required List<String> warnings,
  }) {
    final staffs = detection.staffs;
    if (staffs.isEmpty) return const [];

    return detection.symbols.map((symbol) {
      final bestStaff = _findBestStaff(symbol, staffs);
      return _StaffOwnedSymbol(symbol: symbol, staff: bestStaff);
    }).toList(growable: false);
  }

  List<_MeasureSymbols> groupSymbolsIntoMeasures({
    required DetectionResult detection,
    required List<_StaffOwnedSymbol> assignments,
    required List<String> warnings,
  }) {
    if (assignments.isEmpty) return const [];

    final primaryStaff = detection.staffs.first;
    final staffSymbols = assignments
        .where((entry) => entry.staff.id == primaryStaff.id)
        .toList(growable: false)
      ..sort((left, right) => left.symbolCenterX.compareTo(right.symbolCenterX));

    final barlines = detection.barlines
        .where((barline) => barline.staffId == null || barline.staffId == primaryStaff.id)
        .toList(growable: false)
      ..sort((left, right) => left.x.compareTo(right.x));

    if (barlines.isEmpty) {
      warnings.add('No barlines detected; reconstructing a single measure.');
    }

    final measures = <_MeasureSymbols>[];
    var measureNumber = 1;
    var currentSymbols = <_StaffOwnedSymbol>[];
    var barlineIndex = 0;

    for (final symbol in staffSymbols) {
      while (barlineIndex < barlines.length && symbol.symbolCenterX > barlines[barlineIndex].x) {
        measures.add(
          _MeasureSymbols(
            number: measureNumber,
            staff: primaryStaff,
            symbols: List<_StaffOwnedSymbol>.unmodifiable(currentSymbols),
          ),
        );
        currentSymbols = <_StaffOwnedSymbol>[];
        measureNumber += 1;
        barlineIndex += 1;
      }
      currentSymbols.add(symbol);
    }

    measures.add(
      _MeasureSymbols(
        number: measureNumber,
        staff: primaryStaff,
        symbols: List<_StaffOwnedSymbol>.unmodifiable(currentSymbols),
      ),
    );

    while (barlineIndex < barlines.length - 1) {
      measureNumber += 1;
      measures.add(
        _MeasureSymbols(
          number: measureNumber,
          staff: primaryStaff,
          symbols: const [],
        ),
      );
      barlineIndex += 1;
    }

    return measures;
  }

  Map<String, _StemLink> associateStemsWithNoteheads(
    List<_MeasureSymbols> measures, {
    required List<String> warnings,
  }) {
    final result = <String, _StemLink>{};

    for (final measure in measures) {
      final noteheads = measure.symbols.where((entry) => _isNotehead(entry.symbol.type)).toList();
      final stems = measure.symbols.where((entry) => entry.symbol.type == 'stem').toList();
      final flags = measure.symbols.where((entry) => _isSupportedFlag(entry.symbol.type)).toList();
      final usedStemIds = <String>{};
      final usedFlagIds = <String>{};

      for (final notehead in noteheads) {
        final stem = _pickClosestStem(notehead.symbol, stems, usedStemIds);
        if (stem == null) {
          result[notehead.symbol.id] = const _StemLink();
          continue;
        }

        usedStemIds.add(stem.symbol.id);
        final flag = _pickClosestFlag(stem.symbol, flags, usedFlagIds);
        if (flag != null) {
          usedFlagIds.add(flag.symbol.id);
        }

        result[notehead.symbol.id] = _StemLink(stem: stem.symbol, flag: flag?.symbol);
      }

      final unclaimedFlags = flags.where((entry) => !usedFlagIds.contains(entry.symbol.id));
      for (final flag in unclaimedFlags) {
        warnings.add('Unsupported or unclaimed flag ${flag.symbol.id} was ignored during mapping.');
      }
    }

    return result;
  }

  List<_SemanticMeasure> inferNoteRestSemantics({
    required List<_MeasureSymbols> measures,
    required Map<String, _StemLink> stemLinks,
    required List<String> warnings,
  }) {
    return measures.map((measure) {
      final semanticSymbols = <_OrderedScoreSymbol>[];
      Clef? clef;

      for (final entry in measure.symbols) {
        final symbol = entry.symbol;
        final type = symbol.type;

        if (_isSupportedTrebleClef(type)) {
          clef ??= const Clef(sign: 'G', line: 2);
          continue;
        }

        if (_isSupportedRest(type)) {
          semanticSymbols.add(
            _OrderedScoreSymbol(
              x: entry.symbolCenterX,
              symbol: _buildRest(type),
            ),
          );
          continue;
        }

        if (_isNotehead(type)) {
          final link = stemLinks[symbol.id] ?? const _StemLink();
          final note = _buildNote(symbol, entry.staff, link, warnings);
          if (note != null) {
            semanticSymbols.add(
              _OrderedScoreSymbol(
                x: entry.symbolCenterX,
                symbol: note,
              ),
            );
          }
          continue;
        }

        if (type == 'stem' || _isSupportedFlag(type)) {
          continue;
        }

        warnings.add('Unsupported symbol "$type" was ignored during Sprint 4 mapping.');
      }

      if (clef == null && measure.symbols.any((entry) => _isNotehead(entry.symbol.type))) {
        warnings.add(
          'No supported treble clef detected near the staff start; note pitch reconstruction may be ambiguous.',
        );
      }

      semanticSymbols.sort((left, right) => left.x.compareTo(right.x));

      return _SemanticMeasure(
        number: measure.number,
        clef: clef,
        symbols: semanticSymbols.map((entry) => entry.symbol).toList(growable: false),
      );
    }).toList(growable: false);
  }

  Score buildScore(List<_SemanticMeasure> measures) {
    return Score(
      id: 'mapped-score',
      title: '',
      composer: '',
      parts: [
        Part(
          id: 'P1',
          name: 'Detected Part',
          measures: measures.isEmpty
              ? const [Measure(number: 1, symbols: [])]
              : measures
                    .map(
                      (measure) => Measure(
                        number: measure.number,
                        clef: measure.clef,
                        symbols: measure.symbols,
                      ),
                    )
                    .toList(growable: false),
        ),
      ],
    );
  }

  DetectedStaff _findBestStaff(DetectedSymbol symbol, List<DetectedStaff> staffs) {
    final centerY = _symbolCenterY(symbol);

    DetectedStaff? containingStaff;
    for (final staff in staffs) {
      if (centerY >= staff.topY && centerY <= staff.bottomY) {
        containingStaff = staff;
        break;
      }
    }
    if (containingStaff != null) return containingStaff;

    return staffs.reduce((best, candidate) {
      final bestDistance = (_staffMidpoint(best) - centerY).abs();
      final candidateDistance = (_staffMidpoint(candidate) - centerY).abs();
      return candidateDistance < bestDistance ? candidate : best;
    });
  }

  Note? _buildNote(
    DetectedSymbol symbol,
    DetectedStaff staff,
    _StemLink link,
    List<String> warnings,
  ) {
    final type = symbol.type;
    final hasStem = link.stem != null;
    final hasFlag = link.flag != null;

    final noteType = switch (type) {
      'noteheadWhole' => 'whole',
      'noteheadHalf' when hasStem => 'half',
      'noteheadBlack' when hasStem && hasFlag => 'eighth',
      'noteheadBlack' when hasStem => 'quarter',
      _ => null,
    };

    if (noteType == null) {
      warnings.add('Could not infer a supported note value from ${symbol.id} (${symbol.type}).');
      return null;
    }

    final pitch = _pitchFor(symbol, staff);
    if (pitch == null) {
      warnings.add('Could not infer pitch for note ${symbol.id}; the note was omitted.');
      return null;
    }

    return Note(
      step: pitch.step,
      octave: pitch.octave,
      duration: _durationFor(noteType),
      type: noteType,
      staff: 1,
    );
  }

  Rest _buildRest(String type) {
    final restType = switch (type) {
      'restWhole' => 'whole',
      'restHalf' => 'half',
      _ => 'quarter',
    };

    return Rest(
      duration: _durationFor(restType),
      type: restType,
      staff: 1,
    );
  }

  _Pitch? _pitchFor(DetectedSymbol symbol, DetectedStaff staff) {
    if (staff.lineYs.length < 2) return null;

    final sortedLines = [...staff.lineYs]..sort();
    final bottomLineY = sortedLines.last;
    final averageSpacing = _averageLineSpacing(sortedLines);
    if (averageSpacing <= 0) return null;

    final halfStepSpacing = averageSpacing / 2;
    final centerY = _symbolCenterY(symbol);
    final diatonicOffset = ((bottomLineY - centerY) / halfStepSpacing).round();

    return _pitchFromTrebleOffset(diatonicOffset);
  }

  double _averageLineSpacing(List<double> sortedLineYs) {
    if (sortedLineYs.length < 2) return 0;

    var total = 0.0;
    for (var index = 1; index < sortedLineYs.length; index++) {
      total += (sortedLineYs[index] - sortedLineYs[index - 1]).abs();
    }
    return total / (sortedLineYs.length - 1);
  }

  _Pitch _pitchFromTrebleOffset(int diatonicOffset) {
    const steps = ['C', 'D', 'E', 'F', 'G', 'A', 'B'];
    const baseStepIndex = 2; // E
    const baseOctave = 4;

    var absoluteStep = baseStepIndex + diatonicOffset;
    var octave = baseOctave;

    while (absoluteStep < 0) {
      absoluteStep += steps.length;
      octave -= 1;
    }
    while (absoluteStep >= steps.length) {
      absoluteStep -= steps.length;
      octave += 1;
    }

    return _Pitch(step: steps[absoluteStep], octave: octave);
  }

  _StaffOwnedSymbol? _pickClosestStem(
    DetectedSymbol notehead,
    List<_StaffOwnedSymbol> stems,
    Set<String> usedStemIds,
  ) {
    final noteBox = notehead.boundingBox;
    final noteCenterY = _symbolCenterY(notehead);

    _StaffOwnedSymbol? bestStem;
    double? bestDistance;

    for (final stem in stems) {
      if (usedStemIds.contains(stem.symbol.id)) continue;
      final stemBox = stem.symbol.boundingBox;
      if (stemBox == null) continue;

      final overlapsX = noteBox == null
          ? (stem.symbol.x - notehead.x).abs() <= ((notehead.width ?? 12) * 1.5)
          : stemBox.left <= noteBox.right + (noteBox.width * 0.5) &&
              stemBox.right >= noteBox.left - (noteBox.width * 0.5);
      final overlapsY = stemBox.top <= noteCenterY + ((notehead.height ?? 12) * 0.5) &&
          stemBox.bottom >= noteCenterY - ((notehead.height ?? 12) * 0.5);

      if (!overlapsX || !overlapsY) continue;

      final distance = (_symbolCenterX(stem.symbol) - _symbolCenterX(notehead)).abs();
      if (bestDistance == null || distance < bestDistance) {
        bestDistance = distance;
        bestStem = stem;
      }
    }

    return bestStem;
  }

  _StaffOwnedSymbol? _pickClosestFlag(
    DetectedSymbol stem,
    List<_StaffOwnedSymbol> flags,
    Set<String> usedFlagIds,
  ) {
    final stemBox = stem.boundingBox;
    if (stemBox == null) return null;

    _StaffOwnedSymbol? bestFlag;
    double? bestDistance;

    for (final flag in flags) {
      if (usedFlagIds.contains(flag.symbol.id)) continue;
      final flagBox = flag.symbol.boundingBox;
      if (flagBox == null) continue;

      final distance = math.min(
        (flagBox.top - stemBox.top).abs(),
        (flagBox.bottom - stemBox.bottom).abs(),
      );
      final horizontallyClose = (flagBox.center.dx - stemBox.center.dx).abs() <=
          math.max(stemBox.width, flagBox.width) * 2;

      if (!horizontallyClose) continue;

      if (bestDistance == null || distance < bestDistance) {
        bestDistance = distance;
        bestFlag = flag;
      }
    }

    return bestFlag;
  }

  MappingConfidenceSummary _buildConfidenceSummary({
    required DetectionResult detection,
    required int mappedSymbolCount,
  }) {
    final confidences = detection.symbols
        .map((symbol) => symbol.confidence)
        .whereType<double>()
        .toList(growable: false);

    final averageDetectionConfidence = confidences.isEmpty
        ? null
        : confidences.reduce((sum, value) => sum + value) / confidences.length;

    return MappingConfidenceSummary(
      inputSymbolCount: detection.symbols.length,
      mappedSymbolCount: mappedSymbolCount,
      droppedSymbolCount: math.max(0, detection.symbols.length - mappedSymbolCount),
      averageDetectionConfidence: averageDetectionConfidence,
    );
  }

  Score _buildEmptyScore() => const Score(
        id: 'mapped-score',
        title: '',
        composer: '',
        parts: [
          Part(
            id: 'P1',
            name: 'Detected Part',
            measures: [Measure(number: 1, symbols: [])],
          ),
        ],
      );

  static bool _isSupportedTrebleClef(String type) => type == 'gClef' || type == 'clefG';

  static bool _isSupportedRest(String type) =>
      type == 'restQuarter' || type == 'restHalf' || type == 'restWhole';

  static bool _isSupportedFlag(String type) => type == 'flag8thUp' || type == 'flag8thDown';

  static bool _isNotehead(String type) =>
      type == 'noteheadWhole' || type == 'noteheadHalf' || type == 'noteheadBlack';

  static int _durationFor(String type) => switch (type) {
        'whole' => 4,
        'half' => 2,
        'quarter' => 1,
        'eighth' => 1,
        _ => 1,
      };

  static double _staffMidpoint(DetectedStaff staff) => (staff.topY + staff.bottomY) / 2;

  static double _symbolCenterX(DetectedSymbol symbol) => symbol.x + ((symbol.width ?? 0) / 2);

  static double _symbolCenterY(DetectedSymbol symbol) => symbol.y + ((symbol.height ?? 0) / 2);
}

class _StaffOwnedSymbol {
  final DetectedSymbol symbol;
  final DetectedStaff staff;

  const _StaffOwnedSymbol({
    required this.symbol,
    required this.staff,
  });

  double get symbolCenterX => DetectionToScoreMapperService._symbolCenterX(symbol);
}

class _MeasureSymbols {
  final int number;
  final DetectedStaff staff;
  final List<_StaffOwnedSymbol> symbols;

  const _MeasureSymbols({
    required this.number,
    required this.staff,
    required this.symbols,
  });
}

class _SemanticMeasure {
  final int number;
  final Clef? clef;
  final List<ScoreSymbol> symbols;

  const _SemanticMeasure({
    required this.number,
    required this.clef,
    required this.symbols,
  });
}

class _OrderedScoreSymbol {
  final double x;
  final ScoreSymbol symbol;

  const _OrderedScoreSymbol({
    required this.x,
    required this.symbol,
  });
}

class _StemLink {
  final DetectedSymbol? stem;
  final DetectedSymbol? flag;

  const _StemLink({
    this.stem,
    this.flag,
  });
}

class _Pitch {
  final String step;
  final int octave;

  const _Pitch({
    required this.step,
    required this.octave,
  });
}
