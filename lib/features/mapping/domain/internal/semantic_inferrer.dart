import 'package:note_vision/core/models/clef.dart';
import 'package:note_vision/core/models/note.dart';
import 'package:note_vision/core/models/rest.dart';
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
  }) {
    Clef? activeClef;

    return measures
        .map((measure) {
          final signatureSymbols = _signatureInferrer
              .collectLeadingSignatureSymbols(measure.symbols);
          final signatureIds =
              signatureSymbols.map((e) => e.symbol.id).toSet();

          final inferredClef = _signatureInferrer.inferClef(
            signatureSymbols,
            warnings: warnings,
          );
          activeClef = inferredClef ?? activeClef;
          final clef = activeClef;
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
                    !signatureIds.contains(e.symbol.id),
              )
              .toList();
          final noteAlters = _matchAccidentalsToNoteheads(
            bodyAccidentals,
            measure.symbols,
          );

          final musicalCount = measure.symbols
              .where(
                (e) =>
                    !signatureIds.contains(e.symbol.id) &&
                    (SymbolClassifier.isNotehead(e.symbol.type) ||
                        SymbolClassifier.isSupportedRest(e.symbol.type)),
              )
              .length;
          final beatsPerMeasure = timeSignature?.beats ?? 4;
          var beatsUsed = 0;
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
            // Beams consumed by StemAssociator (via hasBeam flag).
            if (type == 'beam') continue;

            if (SymbolClassifier.isSupportedRest(type)) {
              final rest = _buildRest(type: type);
              ordered.add(
                OrderedScoreSymbol(x: entry.symbolCenterX, symbol: rest),
              );
              beatsUsed += SymbolClassifier.durationFor(rest.type);
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
                beatsUsed += SymbolClassifier.durationFor(note.type);
              }
              musicalIndex++;
              continue;
            }

            warnings.add('Unsupported symbol "$type" was ignored during mapping.');
          }

          _warnAboutClef(clef, measure, warnings);
          ordered.sort((a, b) => a.x.compareTo(b.x));

          return SemanticMeasure(
            number: measure.number,
            clef: clef,
            timeSignature: timeSignature,
            keySignature: keySignature,
            symbols: ordered.map((e) => e.symbol).toList(growable: false),
          );
        })
        .toList(growable: false);
  }

  /// For each body accidental, finds the nearest notehead immediately to its
  /// right (within 2× notehead widths + 20 px) and returns a map from
  /// notehead ID to the corresponding MusicXML `alter` value.
  Map<String, int> _matchAccidentalsToNoteheads(
    List<StaffOwnedSymbol> accidentals,
    List<StaffOwnedSymbol> allSymbols,
  ) {
    if (accidentals.isEmpty) return const {};

    final noteheads = allSymbols
        .where((e) => SymbolClassifier.isNotehead(e.symbol.type))
        .toList()
      ..sort((a, b) => a.symbolCenterX.compareTo(b.symbolCenterX));

    final result = <String, int>{};

    for (final acc in accidentals) {
      final alter = SymbolClassifier.alterFor(acc.symbol.type);
      if (alter == null) continue;

      final accRight = acc.symbol.x + (acc.symbol.width ?? 8.0);

      StaffOwnedSymbol? nearest;
      double? nearestDist;

      for (final notehead in noteheads) {
        final dist = notehead.symbol.x - accRight;
        if (dist < 0) continue; // accidental must be to the left
        final threshold =
            (notehead.symbol.width ?? 12.0) * 2 + 20;
        if (dist > threshold) continue;

        if (nearestDist == null || dist < nearestDist) {
          nearestDist = dist;
          nearest = notehead;
        }
      }

      if (nearest != null) {
        result[nearest.symbol.id] = alter;
      }
    }

    return result;
  }

  Note? _buildNote({
    required StaffOwnedSymbol entry,
    required Clef? activeClef,
    required StemLink link,
    required int? alter,
    required List<String> warnings,
    required int beatsUsed,
    required int beatsPerMeasure,
    required bool isLastMusical,
    required bool isOnlyMusical,
  }) {
    final type = entry.symbol.type;
    final hasStem = link.stem != null;
    final hasFlag = link.flag != null;
    final hasBeam = link.hasBeam;

    final noteType = switch (type) {
      'noteheadWhole' => 'whole',
      'noteheadHalf' when hasStem => 'half',
      // Flag OR beam both indicate an eighth note.
      'noteheadBlack' when hasStem && (hasFlag || hasBeam) => 'eighth',
      'noteheadBlack' when hasStem => 'quarter',
      // Beam detected even without a stem — beams are thicker and easier for
      // the model to detect than thin stems; trust the beam evidence.
      'noteheadBlack' when hasBeam => 'eighth',
      // No stem and no beam — use remaining-beat context to infer duration.
      // Falls back to quarter when context is ambiguous.
      'noteheadBlack' => _stemlessNoteDuration(
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
      duration: SymbolClassifier.durationFor(noteType),
      type: noteType,
      staff: _defaultStaff,
      beamed: noteType == 'eighth' && hasBeam,
    );
  }

  Rest _buildRest({required String type}) {
    final restType = switch (type) {
      'restWhole' => 'whole',
      'restHalf' => 'half',
      'rest8th' => 'eighth',
      'rest16th' => 'sixteenth',
      _ => 'quarter',
    };
    return Rest(
      duration: SymbolClassifier.durationFor(restType),
      type: restType,
      staff: _defaultStaff,
    );
  }

  String _stemlessNoteDuration({
    required int beatsUsed,
    required int beatsPerMeasure,
    required bool isLastMusical,
    required bool isOnlyMusical,
  }) {
    final remaining = beatsPerMeasure - beatsUsed;
    if (isOnlyMusical && remaining >= 4) return 'whole';
    if (isLastMusical && remaining == 2) return 'half';
    return 'quarter';
  }

  void _warnAboutClef(Clef? clef, MeasureSymbols measure, List<String> warnings) {
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
