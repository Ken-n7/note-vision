import 'dart:math' as math;
import 'package:note_vision/features/detection/domain/detected_symbol.dart';
import 'mapping_types.dart';
import 'symbol_classifier.dart';

class StemAssociator {
  const StemAssociator();

  Map<String, StemLink> associate(
    List<MeasureSymbols> measures, {
    required List<String> warnings,
  }) {
    final result = <String, StemLink>{};

    for (final measure in measures) {
      final noteheads = measure.symbols
          .where((e) => SymbolClassifier.isNotehead(e.symbol.type))
          .toList();
      final stems = measure.symbols
          .where((e) => e.symbol.type == 'stem')
          .toList();
      final flags = measure.symbols
          .where((e) => SymbolClassifier.isSupportedFlag(e.symbol.type))
          .toList();
      final beams = measure.symbols
          .where((e) => e.symbol.type == 'beam')
          .toList();

      final usedStemIds = <String>{};
      final usedFlagIds = <String>{};

      for (final notehead in noteheads) {
        final stem = _pickClosestStem(notehead.symbol, stems, usedStemIds);

        if (stem == null) {
          result[notehead.symbol.id] = const StemLink();
          if (notehead.symbol.type != 'noteheadWhole') {
            warnings.add(
              'Could not confidently pair notehead ${notehead.symbol.id} with a nearby stem.',
            );
          }
          continue;
        }

        usedStemIds.add(stem.symbol.id);
        final flag = _pickClosestFlag(stem.symbol, flags, usedFlagIds);
        if (flag != null) usedFlagIds.add(flag.symbol.id);

        final hasBeam = _hasNearbyBeam(stem.symbol, beams);

        result[notehead.symbol.id] = StemLink(
          stem: stem.symbol,
          flag: flag?.symbol,
          hasBeam: hasBeam,
        );
      }

      _warnUnclaimed(stems, usedStemIds, 'Stem', warnings);
      _warnUnclaimed(flags, usedFlagIds, 'Flag', warnings);
    }

    return result;
  }

  void _warnUnclaimed(
    List<StaffOwnedSymbol> symbols,
    Set<String> usedIds,
    String label,
    List<String> warnings,
  ) {
    for (final entry in symbols) {
      if (!usedIds.contains(entry.symbol.id)) {
        if (label == 'Stem') {
          warnings.add(
            'Stem ${entry.symbol.id} could not be paired with a plausible notehead.',
          );
        } else {
          warnings.add(
            'Unsupported or unclaimed flag ${entry.symbol.id} was ignored during mapping.',
          );
        }
      }
    }
  }

  StaffOwnedSymbol? _pickClosestStem(
    DetectedSymbol notehead,
    List<StaffOwnedSymbol> stems,
    Set<String> usedIds,
  ) {
    final noteBox = notehead.boundingBox;
    final noteCenterY = notehead.y + ((notehead.height ?? 0) / 2);

    StaffOwnedSymbol? best;
    double? bestDistance;

    for (final stem in stems) {
      if (usedIds.contains(stem.symbol.id)) continue;
      final stemBox = stem.symbol.boundingBox;
      if (stemBox == null) continue;

      final overlapsX = noteBox == null
          ? (stem.symbol.x - notehead.x).abs() <= ((notehead.width ?? 12) * 1.5)
          : stemBox.left <= noteBox.right + (noteBox.width * 0.5) &&
                stemBox.right >= noteBox.left - (noteBox.width * 0.5);

      final overlapsY =
          stemBox.top <= noteCenterY + ((notehead.height ?? 12) * 0.5) &&
          stemBox.bottom >= noteCenterY - ((notehead.height ?? 12) * 0.5);

      if (!overlapsX || !overlapsY) continue;

      final distance =
          (stem.symbolCenterX - (notehead.x + (notehead.width ?? 0) / 2)).abs();
      if (bestDistance == null || distance < bestDistance) {
        bestDistance = distance;
        best = stem;
      }
    }

    return best;
  }

  /// Returns true when any beam symbol's X range overlaps the stem's X range,
  /// meaning this stem is part of a beamed eighth-note group.
  bool _hasNearbyBeam(DetectedSymbol stem, List<StaffOwnedSymbol> beams) {
    final stemBox = stem.boundingBox;
    if (stemBox == null) return false;

    for (final beam in beams) {
      final beamBox = beam.symbol.boundingBox;
      if (beamBox == null) continue;
      // A beam is a wide horizontal stroke that physically crosses its stems.
      // A generous 1× stem-width tolerance handles slight misalignment.
      if (beamBox.left <= stemBox.right + stemBox.width &&
          beamBox.right >= stemBox.left - stemBox.width) {
        return true;
      }
    }
    return false;
  }

  StaffOwnedSymbol? _pickClosestFlag(
    DetectedSymbol stem,
    List<StaffOwnedSymbol> flags,
    Set<String> usedIds,
  ) {
    final stemBox = stem.boundingBox;
    if (stemBox == null) return null;

    StaffOwnedSymbol? best;
    double? bestDistance;

    for (final flag in flags) {
      if (usedIds.contains(flag.symbol.id)) continue;
      final flagBox = flag.symbol.boundingBox;
      if (flagBox == null) continue;

      final horizontallyClose =
          (flagBox.center.dx - stemBox.center.dx).abs() <=
          math.max(stemBox.width, flagBox.width) * 2;
      if (!horizontallyClose) continue;

      final distance = math.min(
        (flagBox.top - stemBox.top).abs(),
        (flagBox.bottom - stemBox.bottom).abs(),
      );

      if (bestDistance == null || distance < bestDistance) {
        bestDistance = distance;
        best = flag;
      }
    }

    return best;
  }
}
