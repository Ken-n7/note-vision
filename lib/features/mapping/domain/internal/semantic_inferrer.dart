import 'package:note_vision/core/models/score_review.dart';
import 'package:note_vision/core/models/clef.dart';
import 'package:note_vision/core/models/note.dart';
import 'package:note_vision/core/models/rest.dart';
import 'package:note_vision/features/detection/domain/detected_symbol.dart';
import 'mapping_types.dart';
import 'pitch_calculator.dart';
import 'signature_inferrer.dart';
import 'symbol_classifier.dart';

class SemanticInferrer {
  static const int _defaultStaff = 1;

  final PitchCalculator _pitchCalculator;
  final SignatureInferrer _signatureInferrer;

  const SemanticInferrer({
    PitchCalculator pitchCalculator = const PitchCalculator(),
    SignatureInferrer signatureInferrer = const SignatureInferrer(),
  }) : _pitchCalculator = pitchCalculator,
       _signatureInferrer = signatureInferrer;

  List<SemanticMeasure> infer({
    required List<MeasureSymbols> measures,
    required Map<String, StemLink> stemLinks,
    required List<String> warnings,
    Clef? fallbackClef,
  }) {
    // Used until the staff shows a clef of its own.
    Clef? activeClef = fallbackClef;

    return measures
        .map((measure) {
          var signatureSymbols = _signatureInferrer
              .collectLeadingSignatureSymbols(measure.symbols);

          final inferredClef = _signatureInferrer.inferClef(
            signatureSymbols,
            warnings: warnings,
          );
          activeClef = inferredClef ?? activeClef;
          final clef = activeClef;
          final leadingAccidental = _signatureInferrer.leadingNoteAccidental(
            measure,
            signatureSymbols,
            clef: clef,
          );
          if (leadingAccidental != null) {
            signatureSymbols = signatureSymbols
                .where((e) => e.symbol.id != leadingAccidental.accidentalId)
                .toList();
          }
          final signatureIds = signatureSymbols.map((e) => e.symbol.id).toSet();
          final timeSignature = _signatureInferrer.inferTimeSignature(
            measure.staff,
            signatureSymbols,
            warnings: warnings,
          );
          final keySignature = _signatureInferrer.inferKeySignature(
            signatureSymbols,
            warnings: warnings,
          );

          // Accidentals that are NOT in the signature zone are note-level
          // accidentals (e.g. a sharp before a single notehead mid-measure).
          final bodyAccidentals = measure.symbols
              .where(
                (e) =>
                    SymbolClassifier.isAnyAccidental(e.symbol.type) &&
                    !signatureIds.contains(e.symbol.id) &&
                    e.symbol.id != leadingAccidental?.accidentalId,
              )
              .toList();
          final augmentationDots = measure.symbols
              .where(
                (e) =>
                    SymbolClassifier.isAugmentationDot(e.symbol.type) &&
                    !signatureIds.contains(e.symbol.id),
              )
              .toList();
          final ledgerLines = measure.symbols
              .where((e) => e.symbol.type == 'ledgerLine')
              .map((e) => e.symbol)
              .toList(growable: false);
          final bodyBindings = _matchAccidentalsToNoteheads(
            bodyAccidentals,
            measure.symbols,
          );
          final noteAlters = {
            for (final binding in bodyBindings.entries)
              binding.key: binding.value.alter,
            // Leading glyphs were excluded from body matching above, so a
            // continuation-note accidental is consumed only once.
            if (leadingAccidental != null)
              leadingAccidental.noteId: leadingAccidental.alter,
          };
          final symbolDots = _matchAugmentationDots(
            augmentationDots,
            measure.symbols,
          );

          final musicalCount = measure.symbols.where((e) {
            if (signatureIds.contains(e.symbol.id)) return false;
            if (SymbolClassifier.isSupportedRest(e.symbol.type)) return true;
            if (!SymbolClassifier.isNotehead(e.symbol.type)) return false;
            return !(stemLinks[e.symbol.id]?.isChordTone ?? false);
          }).length;
          final beatsPerMeasure = timeSignature?.beats ?? 4;
          var beatsUsed = 0.0;
          var musicalIndex = 0;

          final ordered = <OrderedScoreSymbol>[];

          for (final entry in measure.symbols) {
            final type = entry.symbol.type;

            // Signature-zone symbols already consumed above.
            if (signatureIds.contains(entry.symbol.id)) continue;
            // Stems and flags consumed by StemAssociator.
            if (type == 'stem' || SymbolClassifier.isSupportedFlag(type)) {
              continue;
            }
            // All accidentals (body or otherwise) are pre-processed; skip.
            if (SymbolClassifier.isAnyAccidental(type)) continue;
            if (SymbolClassifier.isAugmentationDot(type)) continue;
            // Beams consumed by StemAssociator (via hasBeam flag).
            if (type == 'beam') continue;

            if (SymbolClassifier.isSupportedRest(type)) {
              final rest = _buildRest(
                type: type,
                source: _source(entry.symbol),
                reviewId: entry.symbol.id,
                dots: symbolDots[entry.symbol.id] ?? 0,
                confidence: entry.symbol.confidence,
              );
              ordered.add(
                OrderedScoreSymbol(x: entry.symbolCenterX, symbol: rest),
              );
              beatsUsed += _beatValueFor(rest.type, rest.dots);
              musicalIndex++;
              continue;
            }

            if (SymbolClassifier.isNotehead(type)) {
              final link = stemLinks[entry.symbol.id] ?? const StemLink();
              final note = _buildNote(
                entry: entry,
                activeClef: clef,
                link: link,
                alter: noteAlters[entry.symbol.id],
                dots: symbolDots[entry.symbol.id] ?? 0,
                ledgerLines: ledgerLines,
                warnings: warnings,
                beatsUsed: beatsUsed,
                beatsPerMeasure: beatsPerMeasure,
                isLastMusical: musicalIndex == musicalCount - 1,
                isOnlyMusical: musicalCount == 1,
              );
              if (note != null) {
                ordered.add(
                  OrderedScoreSymbol(x: entry.symbolCenterX, symbol: note),
                );
                if (!note.isChordTone) {
                  beatsUsed += _beatValueFor(note.type, note.dots);
                }
              }
              if (!link.isChordTone) {
                musicalIndex++;
              }
              continue;
            }

            // Only warn for types outside the model's class taxonomy entirely.
            // Known-but-unhandled classes (articulations, dynamics, ornaments,
            // ties, slurs, tuplets, etc.) are silently skipped.
            if (entry.symbol.musicSymbol == null) {
              warnings.add(
                'Unknown symbol type "$type" was ignored during mapping.',
              );
            }
          }

          _warnAboutClef(clef, measure, warnings);
          ordered.sort((a, b) => a.x.compareTo(b.x));
          final builtNotes = ordered
              .map((e) => e.symbol)
              .whereType<Note>()
              .map((n) => n.reviewId)
              .toSet();
          final consumed = {
            for (final binding in bodyBindings.entries)
              if (builtNotes.contains(binding.key) &&
                  binding.key != leadingAccidental?.noteId)
                binding.value.accidentalId,
          };

          return SemanticMeasure(
            number: measure.number,
            unresolvedBarlines: measure.unresolvedBarlines,
            unassignedAccidentals: [
              for (final accidental in bodyAccidentals)
                if (!consumed.contains(accidental.symbol.id))
                  UnassignedAccidental(
                    id: accidental.symbol.id,
                    alter: SymbolClassifier.alterFor(accidental.symbol.type)!,
                    source: _source(accidental.symbol),
                  ),
            ],
            clef: clef,
            timeSignature: timeSignature,
            keySignature: keySignature,
            symbols: ordered.map((e) => e.symbol).toList(growable: false),
            leftBarlineType: measure.leftBarlineType,
            rightBarlineType: measure.rightBarlineType,
          );
        })
        .toList(growable: false);
  }

  /// Prefer a unique, pitch-aligned tight overlap. Otherwise retain the
  /// ordinary nearest notehead to the right (2× head widths + 20 px).
  Map<String, ({int alter, String accidentalId})> _matchAccidentalsToNoteheads(
    List<StaffOwnedSymbol> accidentals,
    List<StaffOwnedSymbol> allSymbols,
  ) {
    if (accidentals.isEmpty) return const {};

    final noteheads =
        allSymbols
            .where((e) => SymbolClassifier.isNotehead(e.symbol.type))
            .toList()
          ..sort((a, b) => a.symbolCenterX.compareTo(b.symbolCenterX));

    final ordinary = {
      for (final acc in accidentals)
        acc.symbol.id: _nearestRightNotehead(acc, noteheads),
    };
    final overlapping = {
      for (final acc in accidentals)
        acc.symbol.id: _tightOverlappingNotehead(acc, noteheads),
    };

    final result = <String, ({int alter, String accidentalId})>{};
    for (final acc in accidentals) {
      final alter = SymbolClassifier.alterFor(acc.symbol.type);
      if (alter == null) continue;
      var target = overlapping[acc.symbol.id];
      final targetId = target?.symbol.id;
      if (targetId != null &&
          accidentals.any(
            (other) =>
                other.symbol.id != acc.symbol.id &&
                (overlapping[other.symbol.id]?.symbol.id == targetId ||
                    ordinary[other.symbol.id]?.symbol.id == targetId),
          )) {
        // Do not steal an existing binding or resolve competing glyphs by
        // iteration order. Ambiguity retains the prior association.
        target = null;
      }
      target ??= ordinary[acc.symbol.id];
      if (target != null) {
        result[target.symbol.id] = (alter: alter, accidentalId: acc.symbol.id);
      }
    }
    return result;
  }

  StaffOwnedSymbol? _nearestRightNotehead(
    StaffOwnedSymbol acc,
    List<StaffOwnedSymbol> noteheads,
  ) {
    final accRight = acc.symbol.x + (acc.symbol.width ?? 8.0);
    StaffOwnedSymbol? nearest;
    double? nearestDist;
    for (final notehead in noteheads) {
      final dist = notehead.symbol.x - accRight;
      if (dist < 0) continue;
      final threshold = (notehead.symbol.width ?? 12.0) * 2 + 20;
      if (dist > threshold) continue;
      if (nearestDist == null || dist < nearestDist) {
        nearestDist = dist;
        nearest = notehead;
      }
    }
    return nearest;
  }

  StaffOwnedSymbol? _tightOverlappingNotehead(
    StaffOwnedSymbol acc,
    List<StaffOwnedSymbol> noteheads,
  ) {
    final box = acc.symbol.boundingBox;
    final alter = SymbolClassifier.alterFor(acc.symbol.type);
    final staff = acc.staff;
    if (box == null ||
        box.isEmpty ||
        alter == null ||
        staff.lineYs.length != 5 ||
        !staff.lineYs.every((y) => y.isFinite) ||
        ![box.left, box.top, box.right, box.bottom].every((v) => v.isFinite)) {
      return null;
    }
    final lines = [...staff.lineYs]..sort();
    final spacing = (lines.last - lines.first) / 4;
    if (spacing <= 0 ||
        !spacing.isFinite ||
        box.width > spacing * 1.5 ||
        box.height < spacing * .5 ||
        box.height > spacing * 3) {
      return null;
    }
    final accidentalY =
        box.top +
        box.height * (alter < 0 ? .8 : .5) -
        staff.offsetAt(box.center.dx);
    StaffOwnedSymbol? match;
    for (final note in noteheads) {
      final head = note.symbol.boundingBox;
      final pitchHead = note.symbol.pitchBoundingBox;
      if (head == null ||
          head.isEmpty ||
          pitchHead == null ||
          pitchHead.isEmpty ||
          note.staff.id != staff.id ||
          ![
            head.left,
            head.top,
            head.right,
            head.bottom,
            pitchHead.center.dx,
            pitchHead.center.dy,
          ].every((v) => v.isFinite) ||
          head.width > spacing * 2 ||
          head.height > spacing * 1.2) {
        continue;
      }
      final gap = head.left - box.right;
      final noteY = pitchHead.center.dy - staff.offsetAt(pitchHead.center.dx);
      if (gap < 0 &&
          gap >= -head.width / 4 &&
          box.center.dx < head.center.dx &&
          (noteY - accidentalY).abs() <= spacing * .35) {
        if (match != null) return null;
        match = note;
      }
    }
    return match;
  }

  Map<String, int> _matchAugmentationDots(
    List<StaffOwnedSymbol> dots,
    List<StaffOwnedSymbol> allSymbols,
  ) {
    if (dots.isEmpty) return const {};

    final candidates =
        allSymbols
            .where(
              (e) =>
                  SymbolClassifier.isNotehead(e.symbol.type) ||
                  SymbolClassifier.isSupportedRest(e.symbol.type),
            )
            .toList()
          ..sort((a, b) => a.symbolCenterX.compareTo(b.symbolCenterX));

    final result = <String, int>{};

    for (final dot in dots) {
      final dotCenterY = dot.symbol.y + ((dot.symbol.height ?? 0) / 2);
      StaffOwnedSymbol? nearest;
      double? nearestScore;

      for (final candidate in candidates) {
        final candidateRight =
            candidate.symbol.x + (candidate.symbol.width ?? 12.0);
        final horizontalDistance = dot.symbol.x - candidateRight;
        if (horizontalDistance < -4) continue;

        final maxHorizontalDistance = (candidate.symbol.width ?? 12.0) * 2 + 18;
        if (horizontalDistance > maxHorizontalDistance) continue;

        final candidateCenterY =
            candidate.symbol.y + ((candidate.symbol.height ?? 0) / 2);
        final verticalDistance = (candidateCenterY - dotCenterY).abs();
        final maxVerticalDistance =
            ((candidate.symbol.height ?? 10.0) + (dot.symbol.height ?? 6.0)) *
                1.5 +
            10;
        if (verticalDistance > maxVerticalDistance) continue;

        final score = horizontalDistance + (verticalDistance * 0.6);
        if (nearestScore == null || score < nearestScore) {
          nearestScore = score;
          nearest = candidate;
        }
      }

      if (nearest != null) {
        result.update(
          nearest.symbol.id,
          (value) => value + 1,
          ifAbsent: () => 1,
        );
      }
    }

    return result;
  }

  Note? _buildNote({
    required StaffOwnedSymbol entry,
    required Clef? activeClef,
    required StemLink link,
    required int? alter,
    required int dots,
    required List<DetectedSymbol> ledgerLines,
    required List<String> warnings,
    required double beatsUsed,
    required int beatsPerMeasure,
    required bool isLastMusical,
    required bool isOnlyMusical,
  }) {
    final type = entry.symbol.type;
    final hasStem = link.stem != null;
    final hasFlag = link.flag != null;
    final hasBeam = link.hasBeam;

    // Whole-symbol models (one box per note) report the value directly.
    final noteType =
        entry.symbol.metadata?['noteType'] as String? ??
        switch (type) {
          'noteheadDoubleWholeInSpace' ||
          'noteheadDoubleWholeOnLine' => 'breve',
          'noteheadWholeInSpace' || 'noteheadWholeOnLine' => 'whole',
          'noteheadHalfInSpace' || 'noteheadHalfOnLine' when hasStem => 'half',
          // Flag OR beam both indicate an eighth note.
          'noteheadBlackInSpace' || 'noteheadBlackOnLine'
              when hasStem && (hasFlag || hasBeam) =>
            'eighth',
          'noteheadBlackInSpace' ||
          'noteheadBlackOnLine' when hasStem => 'quarter',
          // Beam detected even without a stem — beams are thicker and easier for
          // the model to detect than thin stems; trust the beam evidence.
          'noteheadBlackInSpace' ||
          'noteheadBlackOnLine' when hasBeam => 'eighth',
          // No stem and no beam — use remaining-beat context to infer duration.
          // Falls back to quarter when context is ambiguous.
          'noteheadBlackInSpace' ||
          'noteheadBlackOnLine' => _stemlessNoteDuration(
            beatsUsed: beatsUsed,
            beatsPerMeasure: beatsPerMeasure,
            isLastMusical: isLastMusical,
            isOnlyMusical: isOnlyMusical,
          ),
          _ => null,
        };

    if (noteType == null) {
      warnings.add(
        'Could not infer a supported note value from ${entry.symbol.id} ($type); leaving it unresolved.',
      );
      return null;
    }

    final pitch = _pitchCalculator.calculate(
      symbol: entry.symbol,
      staff: entry.staff,
      clef: activeClef,
      ledgerLines: ledgerLines,
    );
    if (pitch == null) {
      warnings.add(
        'Could not calculate pitch for ${entry.symbol.id}; skipping.',
      );
      return null;
    }

    return Note(
      step: pitch.step,
      octave: pitch.octave,
      alter: alter,
      duration: _effectiveDuration(
        SymbolClassifier.durationFor(noteType),
        dots,
      ),
      type: noteType,
      staff: _defaultStaff,
      // Whole-symbol scans mark beamed notes in metadata; older models
      // detected the beam itself.
      beamed:
          (noteType == 'eighth' || noteType == 'sixteenth') &&
          (hasBeam || entry.symbol.metadata?['beamed'] == true),
      dots: dots,
      isChordTone: link.isChordTone,
      confidence: entry.symbol.confidence,
      reviewId: entry.symbol.id,
      source: _source(entry.symbol),
    );
  }

  Rest _buildRest({
    required String type,
    required int dots,
    double? confidence,
    SourceRegion? source,
    String? reviewId,
  }) {
    final restType = switch (type) {
      'restWhole' => 'whole',
      'restHalf' => 'half',
      'rest8th' => 'eighth',
      'rest16th' => 'sixteenth',
      _ => 'quarter',
    };
    return Rest(
      duration: _effectiveDuration(
        SymbolClassifier.durationFor(restType),
        dots,
      ),
      type: restType,
      staff: _defaultStaff,
      dots: dots,
      confidence: confidence,
      source: source,
      reviewId: reviewId,
    );
  }

  static SourceRegion _source(DetectedSymbol symbol) {
    final full = symbol.metadata?[DetectedSymbol.fullBoxKey];
    if (full is List && full.length == 4) {
      final v = full.map((e) => (e as num).toDouble()).toList();
      return SourceRegion(
        pageId: '',
        x: v[0],
        y: v[1],
        width: v[2] - v[0],
        height: v[3] - v[1],
      );
    }
    return SourceRegion(
      pageId: '',
      x: symbol.x,
      y: symbol.y,
      width: symbol.width ?? 1,
      height: symbol.height ?? 1,
    );
  }

  String _stemlessNoteDuration({
    required double beatsUsed,
    required int beatsPerMeasure,
    required bool isLastMusical,
    required bool isOnlyMusical,
  }) {
    final remaining = beatsPerMeasure - beatsUsed;
    if (isOnlyMusical && remaining >= 4) return 'whole';
    if (isLastMusical && remaining == 2) return 'half';
    return 'quarter';
  }

  double _beatValueFor(String type, int dots) {
    var value = SymbolClassifier.beatValueFor(type);
    var increment = value / 2;
    for (var i = 0; i < dots; i++) {
      value += increment;
      increment /= 2;
    }
    return value;
  }

  int _effectiveDuration(int baseDuration, int dots) {
    var total = baseDuration.toDouble();
    var increment = baseDuration / 2;
    for (var i = 0; i < dots; i++) {
      total += increment;
      increment /= 2;
    }
    return total.round();
  }

  void _warnAboutClef(
    Clef? clef,
    MeasureSymbols measure,
    List<String> warnings,
  ) {
    final hasNoteheads = measure.symbols.any(
      (e) => SymbolClassifier.isNotehead(e.symbol.type),
    );
    if (!hasNoteheads) return;

    if (clef == null) {
      warnings.add(
        'No clef detected; pitch reconstruction is unsupported for this measure.',
      );
    }
    // G and F clefs are both supported — no warning needed for either.
  }
}
