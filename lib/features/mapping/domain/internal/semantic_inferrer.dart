import 'package:note_vision/core/models/note.dart';
import 'package:note_vision/core/models/rest.dart';
import 'mapping_types.dart';
import 'pitch_calculator.dart';
import 'signature_inferrer.dart';
import 'symbol_classifier.dart';

class SemanticInferrer {
  final PitchCalculator _pitchCalculator;
  final SignatureInferrer _signatureInferrer;

  const SemanticInferrer({
    PitchCalculator pitchCalculator = const PitchCalculator(),
    SignatureInferrer signatureInferrer = const SignatureInferrer(),
  })  : _pitchCalculator = pitchCalculator,
        _signatureInferrer = signatureInferrer;

  List<SemanticMeasure> infer({
    required List<MeasureSymbols> measures,
    required Map<String, StemLink> stemLinks,
    required List<String> warnings,
  }) {
    return measures.map((measure) {
      final signatureSymbols =
          _signatureInferrer.collectLeadingSignatureSymbols(measure.symbols);

      final clef = _signatureInferrer.inferClef(
        signatureSymbols,
        warnings: warnings,
      );
      final timeSignature = _signatureInferrer.inferTimeSignature(
        measure.staff,
        signatureSymbols,
        warnings: warnings,
      );
      final keySignature = _signatureInferrer.inferKeySignature(
        signatureSymbols,
        warnings: warnings,
      );

      final ordered = <OrderedScoreSymbol>[];

      for (final entry in measure.symbols) {
        final type = entry.symbol.type;

        if (SymbolClassifier.isSignatureSymbol(type) ||
            type == 'stem' ||
            SymbolClassifier.isSupportedFlag(type)) continue;

        if (SymbolClassifier.isSupportedRest(type)) {
          ordered.add(OrderedScoreSymbol(
            x: entry.symbolCenterX,
            symbol: _buildRest(type),
          ));
          continue;
        }

        if (SymbolClassifier.isNotehead(type)) {
          final link = stemLinks[entry.symbol.id] ?? const StemLink();
          final note = _buildNote(entry, link, warnings);
          if (note != null) {
            ordered.add(OrderedScoreSymbol(
              x: entry.symbolCenterX,
              symbol: note,
            ));
          }
          continue;
        }

        warnings.add('Unsupported symbol "$type" was ignored during Sprint 4 mapping.');
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
    }).toList(growable: false);
  }

  Note? _buildNote(
    StaffOwnedSymbol entry,
    StemLink link,
    List<String> warnings,
  ) {
    final type = entry.symbol.type;
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
        'Could not infer a supported note value from ${entry.symbol.id} ($type); leaving it unresolved.',
      );
      return null;
    }

    final pitch = _pitchCalculator.calculate(entry.symbol, entry.staff);
    if (pitch == null) {
      warnings.add('Could not infer pitch for ${entry.symbol.id}; skipping.');
      return null;
    }

    return Note(
      step: pitch.step,
      octave: pitch.octave,
      duration: SymbolClassifier.durationFor(noteType),
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
      duration: SymbolClassifier.durationFor(restType),
      type: restType,
      staff: 1,
    );
  }

  void _warnAboutClef(
    clef,
    MeasureSymbols measure,
    List<String> warnings,
  ) {
    final hasNoteheads =
        measure.symbols.any((e) => SymbolClassifier.isNotehead(e.symbol.type));
    if (!hasNoteheads) return;

    if (clef == null) {
      warnings.add(
        'No supported clef detected; pitch reconstruction may be ambiguous.',
      );
    } else if (clef.sign == 'F') {
      warnings.add(
        'Bass-clef notes detected; Sprint 4 pitch reconstruction still assumes treble placement.',
      );
    }
  }
}