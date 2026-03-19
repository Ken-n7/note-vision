import 'dart:math' as math;
import 'package:note_vision/core/models/clef.dart';
import 'package:note_vision/core/models/key_signature.dart';
import 'package:note_vision/core/models/time_signature.dart';
import 'package:note_vision/features/detection/domain/detected_staff.dart';
import 'mapping_types.dart';
import 'symbol_classifier.dart';

class SignatureInferrer {
  const SignatureInferrer();

  static const double _signatureRegionWidth = 96;

  Clef? inferClef(
    List<StaffOwnedSymbol> symbols, {
    required List<String> warnings,
  }) {
    for (final entry in symbols) {
      if (!SymbolClassifier.isSupportedClef(entry.symbol.type)) continue;
      return entry.symbol.type == 'fClef'
          ? const Clef(sign: 'F', line: 4)
          : const Clef(sign: 'G', line: 2);
    }
    return null;
  }

  TimeSignature? inferTimeSignature(
    DetectedStaff staff,
    List<StaffOwnedSymbol> symbols, {
    required List<String> warnings,
  }) {
    final timeEntries = symbols
        .where((e) => SymbolClassifier.isTimeSignatureSymbol(e.symbol.type))
        .toList();
    if (timeEntries.isEmpty) return null;

    if (timeEntries.any((e) => e.symbol.type == 'timeSigCommon')) {
      return const TimeSignature(beats: 4, beatType: 4);
    }
    if (timeEntries.any((e) => e.symbol.type == 'timeSigCutCommon')) {
      return const TimeSignature(beats: 2, beatType: 2);
    }

    final digits = timeEntries
        .where((e) => SymbolClassifier.timeSigDigit(e.symbol.type) != null)
        .toList()
      ..sort((a, b) => a.symbolCenterX.compareTo(b.symbolCenterX));

    if (digits.isEmpty) {
      warnings.add('Detected time-signature symbols could not be interpreted.');
      return null;
    }

    final midpoint = (staff.topY + staff.bottomY) / 2;
    final centerY = (StaffOwnedSymbol s) =>
        s.symbol.y + ((s.symbol.height ?? 0) / 2);

    final top = digits
        .where((e) => centerY(e) <= midpoint)
        .map((e) => SymbolClassifier.timeSigDigit(e.symbol.type)!)
        .join();
    final bottom = digits
        .where((e) => centerY(e) > midpoint)
        .map((e) => SymbolClassifier.timeSigDigit(e.symbol.type)!)
        .join();

    final beats = int.tryParse(top);
    final beatType = int.tryParse(bottom);

    if (beats == null || beatType == null) {
      warnings.add('Detected time-signature symbols could not be interpreted.');
      return null;
    }

    return TimeSignature(beats: beats, beatType: beatType);
  }

  KeySignature? inferKeySignature(
    List<StaffOwnedSymbol> symbols, {
    required List<String> warnings,
  }) {
    final accidentals = symbols
        .where((e) => SymbolClassifier.isKeySignatureAccidental(e.symbol.type))
        .toList();
    if (accidentals.isEmpty) return null;

    final types = accidentals.map((e) => e.symbol.type).toSet();
    if (types.length > 1 || types.contains('accidentalNatural')) {
      warnings.add('Detected accidentals could not be resolved into a key signature.');
      return null;
    }

    final count = accidentals.length;
    return KeySignature(
      fifths: types.single == 'accidentalFlat' ? -count : count,
    );
  }

  List<StaffOwnedSymbol> collectLeadingSignatureSymbols(
    List<StaffOwnedSymbol> symbols,
  ) {
    if (symbols.isEmpty) return const [];

    final ordered = [...symbols]
      ..sort((a, b) => a.symbolCenterX.compareTo(b.symbolCenterX));

    final firstMusical = ordered.firstWhere(
      (e) =>
          SymbolClassifier.isNotehead(e.symbol.type) ||
          SymbolClassifier.isSupportedRest(e.symbol.type),
      orElse: () => ordered.last,
    );

    final maxX = math.min(
      firstMusical.symbolCenterX,
      ordered.first.symbolCenterX + _signatureRegionWidth,
    );

    return ordered
        .where((e) =>
            SymbolClassifier.isSignatureSymbol(e.symbol.type) &&
            e.symbolCenterX <= maxX)
        .toList(growable: false);
  }
}