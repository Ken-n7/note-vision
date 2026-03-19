import 'dart:math' as math;

import 'package:note_vision/core/models/clef.dart';
import 'package:note_vision/core/models/key_signature.dart';
import 'package:note_vision/core/models/measure.dart';
import 'package:note_vision/core/models/note.dart';
import 'package:note_vision/core/models/part.dart';
import 'package:note_vision/core/models/rest.dart';
import 'package:note_vision/core/models/score.dart';
import 'package:note_vision/core/models/score_symbol.dart';
import 'package:note_vision/core/models/time_signature.dart';
import 'package:note_vision/features/detection/domain/detected_staff.dart';
import 'package:note_vision/features/detection/domain/detected_symbol.dart';
import 'package:note_vision/features/detection/domain/detection_result.dart';

import 'mapping_confidence_summary.dart';
import 'mapping_result.dart';
import 'score_mapper_service.dart';

class DetectionToScoreMapperService extends ScoreMapperService {
  const DetectionToScoreMapperService();

  static const double _signatureRegionWidth = 96;
  
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
        .where(
          (barline) => barline.staffId == null || barline.staffId == primaryStaff.id,
        )
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
          if (notehead.symbol.type != 'noteheadWhole') {
            warnings.add(
              'Could not confidently pair notehead ${notehead.symbol.id} with a nearby stem.',
            );
          }
          continue;
        }

        usedStemIds.add(stem.symbol.id);
        final flag = _pickClosestFlag(stem.symbol, flags, usedFlagIds);
        if (flag != null) {
          usedFlagIds.add(flag.symbol.id);
        }

        result[notehead.symbol.id] = _StemLink(stem: stem.symbol, flag: flag?.symbol);
      }

      final unclaimedStems = stems.where((entry) => !usedStemIds.contains(entry.symbol.id));
      for (final stem in unclaimedStems) {
        warnings.add('Stem ${stem.symbol.id} could not be paired with a plausible notehead.');
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
      final signatureSymbols = _collectLeadingSignatureSymbols(measure.symbols);
      final clef = _inferClef(signatureSymbols, warnings: warnings);
      final timeSignature = _inferTimeSignature(measure.staff, signatureSymbols, warnings: warnings);
      final keySignature = _inferKeySignature(signatureSymbols, warnings: warnings);

      for (final entry in measure.symbols) {
        final symbol = entry.symbol;
        final type = symbol.type;

        if (_isSignatureSymbol(type) || type == 'stem' || _isSupportedFlag(type)) {
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

        warnings.add('Unsupported symbol "$type" was ignored during Sprint 4 mapping.');
      }

      if (clef == null && measure.symbols.any((entry) => _isNotehead(entry.symbol.type))) {
        warnings.add(
          'No supported clef detected near the staff start; note pitch reconstruction may be ambiguous.',
        );
      } else if (clef?.sign == 'F' && measure.symbols.any((entry) => _isNotehead(entry.symbol.type))) {
        warnings.add(
          'Bass-clef notes are recognized, but Sprint 4 pitch reconstruction still assumes treble-style placement.',
        );
      }

      semanticSymbols.sort((left, right) => left.x.compareTo(right.x));

      return _SemanticMeasure(
        number: measure.number,
        clef: clef,
        timeSignature: timeSignature,
        keySignature: keySignature,
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
                        timeSignature: measure.timeSignature,
                        keySignature: measure.keySignature,
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
      warnings.add(
        'Could not infer a supported note value from ${symbol.id} (${symbol.type}); leaving it unresolved.',
      );
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

  Clef? _inferClef(
    List<_StaffOwnedSymbol> signatureSymbols, {
    required List<String> warnings,
  }) {
    for (final entry in signatureSymbols) {
      if (!_isSupportedClef(entry.symbol.type)) continue;
      return switch (entry.symbol.type) {
        'fClef' => const Clef(sign: 'F', line: 4),
        _ => const Clef(sign: 'G', line: 2),
      };
    }
    return null;
  }

  TimeSignature? _inferTimeSignature(
    DetectedStaff staff,
    List<_StaffOwnedSymbol> signatureSymbols, {
    required List<String> warnings,
  }) {
    final timeEntries = signatureSymbols.where((entry) => _isTimeSignatureSymbol(entry.symbol.type)).toList();
    if (timeEntries.isEmpty) {
      return null;
    }

    final common = timeEntries.where((entry) => entry.symbol.type == 'timeSigCommon');
    if (common.isNotEmpty) {
      return const TimeSignature(beats: 4, beatType: 4);
    }

    final cutCommon = timeEntries.where((entry) => entry.symbol.type == 'timeSigCutCommon');
    if (cutCommon.isNotEmpty) {
      return const TimeSignature(beats: 2, beatType: 2);
    }

    final digitEntries = timeEntries.where((entry) => _timeSigDigit(entry.symbol.type) != null).toList();
    if (digitEntries.isEmpty) {
      warnings.add('Detected time-signature symbols could not be interpreted.');
      return null;
    }

    digitEntries.sort((left, right) => left.symbolCenterX.compareTo(right.symbolCenterX));
    final staffMidpoint = _staffMidpoint(staff);
    final numeratorDigits = digitEntries
        .where((entry) => _symbolCenterY(entry.symbol) <= staffMidpoint)
        .map((entry) => _timeSigDigit(entry.symbol.type)!)
        .join();
    final denominatorDigits = digitEntries
        .where((entry) => _symbolCenterY(entry.symbol) > staffMidpoint)
        .map((entry) => _timeSigDigit(entry.symbol.type)!)
        .join();

    final beats = int.tryParse(numeratorDigits);
    final beatType = int.tryParse(denominatorDigits);
    if (beats == null || beatType == null) {
      warnings.add('Detected time-signature symbols could not be interpreted.');
      return null;
    }

    return TimeSignature(beats: beats, beatType: beatType);
  }

  KeySignature? _inferKeySignature(
    List<_StaffOwnedSymbol> signatureSymbols, {
    required List<String> warnings,
  }) {
    final accidentalEntries = signatureSymbols.where((entry) => _isKeySignatureAccidental(entry.symbol.type)).toList();
    if (accidentalEntries.isEmpty) {
      return null;
    }

    final types = accidentalEntries.map((entry) => entry.symbol.type).toSet();
    if (types.length > 1 || types.contains('accidentalNatural')) {
      warnings.add('Detected accidentals near the clef could not be resolved into a basic key signature.');
      return null;
    }

    final type = types.single;
    final count = accidentalEntries.length;
    return KeySignature(
      fifths: switch (type) {
        'accidentalFlat' => -count,
        'accidentalSharp' => count,
        _ => 0,
      },
    );
  }

  List<_StaffOwnedSymbol> _collectLeadingSignatureSymbols(List<_StaffOwnedSymbol> symbols) {
    if (symbols.isEmpty) return const [];

    final ordered = [...symbols]..sort((left, right) => left.symbolCenterX.compareTo(right.symbolCenterX));
    final firstMusicalEvent = ordered.firstWhere(
      (entry) => _isNotehead(entry.symbol.type) || _isSupportedRest(entry.symbol.type),
      orElse: () => ordered.last,
    );
    final maxSignatureX = math.min(
      firstMusicalEvent.symbolCenterX,
      ordered.first.symbolCenterX + _signatureRegionWidth,
    );

    return ordered
        .where(
          (entry) => _isSignatureSymbol(entry.symbol.type) && entry.symbolCenterX <= maxSignatureX,
        )
        .toList(growable: false);
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
    const baseStepIndex = 2;
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

  static bool _isSupportedClef(String type) => type == 'gClef' || type == 'clefG' || type == 'fClef';

  static bool _isSupportedRest(String type) =>
      type == 'restQuarter' || type == 'restHalf' || type == 'restWhole';

  static bool _isSupportedFlag(String type) => type == 'flag8thUp' || type == 'flag8thDown';

  static bool _isNotehead(String type) =>
      type == 'noteheadWhole' || type == 'noteheadHalf' || type == 'noteheadBlack';

  static bool _isTimeSignatureSymbol(String type) =>
      type == 'timeSigCommon' ||
      type == 'timeSigCutCommon' ||
      _timeSigDigit(type) != null ||
      type == 'combTimeSignature';

  static bool _isKeySignatureAccidental(String type) =>
      type == 'accidentalFlat' || type == 'accidentalSharp' || type == 'accidentalNatural';

  static bool _isSignatureSymbol(String type) =>
      _isSupportedClef(type) || _isTimeSignatureSymbol(type) || _isKeySignatureAccidental(type);

  static String? _timeSigDigit(String type) {
    const digits = {
      'timeSig0': '0',
      'timeSig1': '1',
      'timeSig2': '2',
      'timeSig3': '3',
      'timeSig4': '4',
      'timeSig5': '5',
      'timeSig6': '6',
      'timeSig7': '7',
      'timeSig8': '8',
      'timeSig9': '9',
    };
    return digits[type];
  }
  
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
  final TimeSignature? timeSignature;
  final KeySignature? keySignature;
  final List<ScoreSymbol> symbols;

  const _SemanticMeasure({
    required this.number,
    required this.clef,
    required this.timeSignature,
    required this.keySignature,
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
