import 'package:note_vision/core/models/clef.dart';
import 'package:note_vision/core/models/key_signature.dart';
import 'package:note_vision/core/models/score_symbol.dart';
import 'package:note_vision/core/models/time_signature.dart';
import 'package:note_vision/features/detection/domain/detected_staff.dart';
import 'package:note_vision/features/detection/domain/detected_symbol.dart';

class StaffOwnedSymbol {
  final DetectedSymbol symbol;
  final DetectedStaff staff;

  const StaffOwnedSymbol({
    required this.symbol,
    required this.staff,
  });

  double get symbolCenterX => symbol.x + ((symbol.width ?? 0) / 2);
}

class MeasureSymbols {
  final int number;
  final DetectedStaff staff;
  final List<StaffOwnedSymbol> symbols;

  const MeasureSymbols({
    required this.number,
    required this.staff,
    required this.symbols,
  });
}

class SemanticMeasure {
  final int number;
  final Clef? clef;
  final TimeSignature? timeSignature;
  final KeySignature? keySignature;
  final List<ScoreSymbol> symbols;

  const SemanticMeasure({
    required this.number,
    required this.clef,
    required this.timeSignature,
    required this.keySignature,
    required this.symbols,
  });
}

class OrderedScoreSymbol {
  final double x;
  final ScoreSymbol symbol;

  const OrderedScoreSymbol({required this.x, required this.symbol});
}

class StemLink {
  final DetectedSymbol? stem;
  final DetectedSymbol? flag;

  /// True when at least one beam symbol was found adjacent to this stem,
  /// indicating the notehead belongs to a beamed eighth-note group.
  final bool hasBeam;

  const StemLink({this.stem, this.flag, this.hasBeam = false});
}

class Pitch {
  final String step;
  final int octave;

  const Pitch({required this.step, required this.octave});
}