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
      return entry.symbol.type == 'clefF'
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
      return TimeSignature.common;
    }
    if (timeEntries.any((e) => e.symbol.type == 'timeSigCutCommon')) {
      return TimeSignature.cut;
    }

    final digits =
        timeEntries
            .where((e) => SymbolClassifier.timeSigDigit(e.symbol.type) != null)
            .toList()
          ..sort((a, b) => a.symbolCenterX.compareTo(b.symbolCenterX));

    if (digits.isEmpty) {
      warnings.add('Detected time-signature symbols could not be interpreted.');
      return null;
    }

    final midpoint = (staff.topY + staff.bottomY) / 2;
    // Level with the staff where the digit stands, so a sloped staff still
    // splits its digits into upper and lower.
    double centerY(StaffOwnedSymbol symbol) =>
        symbol.symbol.y +
        ((symbol.symbol.height ?? 0) / 2) -
        staff.offsetAt(symbol.symbolCenterX);

    final top = _numbers(
      digits.where((e) => centerY(e) <= midpoint).toList(),
      centerY,
    );
    final bottom = _numbers(
      digits.where((e) => centerY(e) > midpoint).toList(),
      centerY,
    );
    final candidates =
        <({_DigitNumber top, _DigitNumber bottom, double alignment})>[];
    for (final upper in top) {
      for (final lower in bottom) {
        // A fraction is centered as a stack. Joining every digit on each
        // side of the middle line can turn a nearby key glyph into 44/4.
        final alignment =
            (upper.centerX - lower.centerX).abs() /
            math.min(upper.width, lower.width);
        if (alignment > .5 ||
            lower.centerY - upper.centerY <
                math.min(upper.height, lower.height) / 2) {
          continue;
        }
        candidates.add((top: upper, bottom: lower, alignment: alignment));
      }
    }
    candidates.sort((a, b) => a.alignment.compareTo(b.alignment));
    if (candidates.isEmpty) {
      warnings.add('Detected time-signature symbols could not be interpreted.');
      return null;
    }
    final best = candidates.first;
    // Repeated detections giving the same reading are harmless. Competing
    // readings within a tenth of a digit width are not enough evidence to
    // choose a meter, regardless of confidence or the notes' beat totals.
    if (candidates.any(
      (c) =>
          c.alignment <= best.alignment + .1 &&
          (c.top.value != best.top.value ||
              c.bottom.value != best.bottom.value),
    )) {
      warnings.add(
        'Detected time-signature stacks are ambiguous; check the original.',
      );
      return null;
    }
    if (best.top.entries.length + best.bottom.entries.length < digits.length) {
      warnings.add('Unaligned or repeated time-signature digits were ignored.');
    }
    return TimeSignature(beats: best.top.value, beatType: best.bottom.value);
  }

  /// Contiguous digits on one row can form a multi-digit number, but
  /// overlapping alternative detections must never become adjacent digits.
  static List<_DigitNumber> _numbers(
    List<StaffOwnedSymbol> digits,
    double Function(StaffOwnedSymbol) centerY,
  ) {
    final numbers = <_DigitNumber>[];
    for (var start = 0; start < digits.length; start++) {
      var text = '', right = double.negativeInfinity;
      var width = 0.0, height = 0.0, level = 0.0;
      for (var end = start; end < digits.length; end++) {
        final digit = digits[end], box = digit.symbol.boundingBox;
        if (box == null || box.width <= 0 || box.height <= 0) break;
        if (end > start) {
          final previous = digits[end - 1].symbol.boundingBox!;
          final gap = box.left - previous.right;
          final cell = math.min(previous.width, box.width);
          if (gap < -cell / 2 ||
              gap > cell / 2 ||
              (centerY(digit) - centerY(digits[start])).abs() >
                  math.min(box.height, digits[start].symbol.height!) / 2) {
            break;
          }
        }
        text += SymbolClassifier.timeSigDigit(digit.symbol.type)!;
        right = math.max(right, box.right);
        width += box.width;
        height += box.height;
        level += centerY(digit);
        final count = end - start + 1, value = int.tryParse(text);
        if (value == null || value <= 0) continue;
        numbers.add((
          entries: List.unmodifiable(digits.sublist(start, end + 1)),
          value: value,
          centerX: (digits[start].symbol.x + right) / 2,
          centerY: level / count,
          width: width / count,
          height: height / count,
        ));
      }
    }
    return numbers;
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
      warnings.add(
        'Detected accidentals could not be resolved into a key signature.',
      );
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
        .where(
          (e) =>
              SymbolClassifier.isSignatureSymbol(e.symbol.type) &&
              e.symbolCenterX <= maxX,
        )
        .toList(growable: false);
  }
}

typedef _DigitNumber = ({
  List<StaffOwnedSymbol> entries,
  int value,
  double centerX,
  double centerY,
  double width,
  double height,
});
