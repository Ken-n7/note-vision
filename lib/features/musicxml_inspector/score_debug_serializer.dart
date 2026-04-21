import 'package:note_vision/core/models/clef.dart';
import 'package:note_vision/core/models/measure.dart';
import 'package:note_vision/core/models/note.dart';
import 'package:note_vision/core/models/part.dart';
import 'package:note_vision/core/models/rest.dart';
import 'package:note_vision/core/models/score.dart';
import 'package:note_vision/core/models/score_symbol.dart';
import 'package:note_vision/core/models/time_signature.dart';

/// Converts a [Score] into a structured, JSON-like [Map] for debug inspection.
///
/// Intentionally flat and human-readable — not meant for serialization.
class ScoreDebugSerializer {
  const ScoreDebugSerializer();

  Map<String, dynamic> serialize(Score score) {
    return {
      'id': score.id,
      'title': score.title,
      'composer': score.composer,
      'parts': score.parts.map(_serializePart).toList(),
    };
  }

  Map<String, dynamic> _serializePart(Part part) {
    return {
      'id': part.id,
      'name': part.name,
      'measureCount': part.measures.length,
      'measures': part.measures.map(_serializeMeasure).toList(),
    };
  }

  Map<String, dynamic> _serializeMeasure(Measure measure) {
    return {
      'number': measure.number,
      if (measure.clef != null) 'clef': _serializeClef(measure.clef!),
      if (measure.timeSignature != null)
        'timeSignature': _serializeTimeSignature(measure.timeSignature!),
      if (measure.keySignature != null)
        'keySignature': {'fifths': measure.keySignature!.fifths},
      'symbolCount': measure.symbols.length,
      'symbols': measure.symbols.map(_serializeSymbol).toList(),
    };
  }

  Map<String, dynamic> _serializeClef(Clef clef) {
    return {'sign': clef.sign, 'line': clef.line};
  }

  Map<String, dynamic> _serializeTimeSignature(TimeSignature ts) {
    return {'beats': ts.beats, 'beatType': ts.beatType};
  }

  Map<String, dynamic> _serializeSymbol(ScoreSymbol symbol) {
    if (symbol is Note) {
      return {
        'type': 'note',
        'pitch': '${symbol.step}${_alterLabel(symbol.alter)}${symbol.octave}',
        'duration': symbol.duration,
        'noteType': symbol.type,
        if (symbol.voice != null) 'voice': symbol.voice,
        if (symbol.staff != null) 'staff': symbol.staff,
      };
    }
    if (symbol is Rest) {
      return {
        'type': 'rest',
        'restType': symbol.type,
        'duration': symbol.duration,
        if (symbol.voice != null) 'voice': symbol.voice,
        if (symbol.staff != null) 'staff': symbol.staff,
      };
    }
    return {'type': 'unknown'};
  }

  String _alterLabel(int? alter) {
    if (alter == null || alter == 0) return '';
    if (alter > 0) return '#' * alter;
    return 'b' * alter.abs();
  }
}
