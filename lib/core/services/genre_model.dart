import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:tflite_flutter/tflite_flutter.dart';

import '../models/note.dart';
import '../models/note_value.dart';
import '../models/rest.dart';
import '../models/score.dart';
import '../models/time_signature.dart';
import 'accidentals.dart';
import 'playback_converter.dart';

/// The genre LSTM (`assets/models/genre_lstm.tflite`), trained in the
/// note-vision-data project by `scripts/genre_train.py` on folk waltzes,
/// jazz lead sheets, kundiman transcribed from IMSLP scores and other tunes.
///
/// It reads the first part's melody as steps, lengths and places in the bar,
/// so the key and the octave do not matter. [features] must match
/// `features()` in genre_train.py number for number.
class GenreModel {
  GenreModel._();

  static const genres = ['waltz', 'kundiman', 'jazz', 'other'];
  static const window = 64;
  static const _meters = [2, 3, 4, 6];
  /// Step, rest, length, place in bar, meter (5), then where the note sits
  /// in the key: 12 scale degrees and a minor flag.
  static const featureCount = 4 + 4 + 1 + 13;

  // Krumhansl–Kessler key profiles, index 0 = tonic.
  static const _majorProfile = [
    6.35, 2.23, 3.48, 2.33, 4.38, 4.09, 2.52, 5.19, 2.39, 3.66, 2.29, 2.88,
  ];
  static const _minorProfile = [
    6.33, 2.68, 3.52, 5.38, 2.60, 3.53, 2.54, 4.75, 3.98, 2.69, 3.34, 3.17,
  ];

  /// Fewer sounding notes than this say too little to name a genre.
  static const minNotes = 16;

  /// The model reads at most this many notes from the start, so a run stays
  /// at a few milliseconds even for long scores.
  static const maxNotes = 320;

  static Interpreter? _interpreter;

  static Future<void> load() async {
    try {
      _interpreter = await Interpreter.fromAsset(
        'assets/models/genre_lstm.tflite',
      );
    } catch (e) {
      debugPrint('Genre model not loaded, using the rule labels: $e');
    }
  }

  /// One probability per [genres], averaged over every 64-note stretch of
  /// the melody stepping 32, as the model was scored; null when the model is
  /// not loaded or the melody is too short.
  static List<double>? predict(Score score) {
    final interpreter = _interpreter;
    if (interpreter == null) return null;
    final notes = melody(score);
    final rows = features(
      notes.length > maxNotes ? notes.sublist(0, maxNotes) : notes,
    );
    if (rows.where((r) => r[1] == 0).length < minNotes) return null;
    final sum = List<double>.filled(genres.length, 0);
    var count = 0;
    for (
      var end = math.min(window, rows.length);
      end <= rows.length;
      end += window ~/ 2
    ) {
      final output = [List<double>.filled(genres.length, 0)];
      interpreter.run([pad(rows.sublist(0, end))], output);
      for (var i = 0; i < genres.length; i++) {
        sum[i] += output[0][i];
      }
      count++;
    }
    return [for (final s in sum) s / count];
  }

  /// Every part, one after another as playback plays them, as
  /// `[midi (-1 rest), quarters, place in bar, beats]` per note or rest; a
  /// chord keeps its top note.
  // ponytail: a scan makes one part per staff of the same melody, so parts
  // run in sequence; an imported piano score would get its bass appended
  // after the melody. Read only the top part there if that ever matters.
  static List<List<num>> melody(Score score) {
    const converter = PlaybackConverter();
    final out = <List<num>>[];
    for (final part in score.parts) {
      final accidentals = Accidentals();
      TimeSignature? time;
      for (final measure in part.measures) {
        accidentals.startMeasure(measure);
        time = measure.timeSignature ?? time;
        final beats = time?.beats ?? 4;
        final barLength = beats * 4 / (time?.beatType ?? 4);
        var at = 0.0;
        for (final symbol in measure.symbols) {
          if (symbol is Note) {
            final midi = converter.noteToMidi(
              Note(
                step: symbol.step,
                octave: symbol.octave,
                alter: accidentals.sounding(symbol),
                duration: symbol.duration,
                type: symbol.type,
              ),
            );
            if (symbol.isChordTone && out.isNotEmpty) {
              out.last[0] = math.max(out.last[0] as int, midi);
              continue;
            }
            final length = quarterLength(
              symbol.type,
              symbol.dots,
              symbol.duration,
            );
            out.add([midi, length, math.min(at / barLength, 0.999), beats]);
            at += length;
          } else if (symbol is Rest) {
            final length = quarterLength(
              symbol.type,
              symbol.dots,
              symbol.duration,
            );
            out.add([-1, length, math.min(at / barLength, 0.999), beats]);
            at += length;
          }
        }
      }
    }
    // As in training: whole bars of rest say nothing; at most one rest in a
    // row, none at the start.
    final trimmed = <List<num>>[];
    for (final n in out) {
      if (n[0] == -1 && (trimmed.isEmpty || trimmed.last[0] == -1)) continue;
      trimmed.add(n);
    }
    return trimmed;
  }

  static List<List<double>> features(List<List<num>> notes) {
    final out = <List<double>>[];
    int? last;
    for (final n in notes) {
      final row = List<double>.filled(featureCount, 0);
      final midi = n[0].toInt();
      if (midi >= 0) {
        if (last != null) row[0] = ((midi - last) / 12).clamp(-1.0, 1.0);
        last = midi;
      } else {
        row[1] = 1;
      }
      row[2] = math.log(math.max(n[1].toDouble(), 1 / 16)) / math.ln2 / 2;
      row[3] = n[2].toDouble();
      final meter = _meters.indexOf(n[3].toInt());
      row[4 + (meter < 0 ? _meters.length : meter)] = 1;
      out.add(row);
    }
    final key = keyOf(notes);
    for (var i = 0; i < notes.length; i++) {
      final midi = notes[i][0].toInt();
      if (midi >= 0) out[i][9 + (midi - key.tonic) % 12] = 1;
      out[i][21] = key.minor ? 1 : 0;
    }
    return out;
  }

  /// Krumhansl–Schmuckler key of `[midi, quarters, ...]` notes: pitch
  /// classes weighted by length, rests left out. Majors are tried before
  /// minors and lower tonics first; a later key must fit strictly better.
  /// `key_of` in genre_train.py does exactly the same.
  static ({int tonic, bool minor}) keyOf(Iterable<List<num>> notes) {
    final histogram = List<double>.filled(12, 0);
    for (final n in notes) {
      final midi = n[0].toInt();
      if (midi >= 0) histogram[midi % 12] += n[1].toDouble();
    }
    var best = -2.0;
    var key = (tonic: 0, minor: false);
    for (final minor in const [false, true]) {
      final profile = minor ? _minorProfile : _majorProfile;
      for (var tonic = 0; tonic < 12; tonic++) {
        final fit = _correlation(histogram, [
          for (var pc = 0; pc < 12; pc++) profile[(pc - tonic + 12) % 12],
        ]);
        if (fit > best) {
          best = fit;
          key = (tonic: tonic, minor: minor);
        }
      }
    }
    return key;
  }

  static double _correlation(List<double> a, List<double> b) {
    final meanA = a.reduce((x, y) => x + y) / a.length;
    final meanB = b.reduce((x, y) => x + y) / b.length;
    var cov = 0.0, varA = 0.0, varB = 0.0;
    for (var i = 0; i < a.length; i++) {
      cov += (a[i] - meanA) * (b[i] - meanB);
      varA += (a[i] - meanA) * (a[i] - meanA);
      varB += (b[i] - meanB) * (b[i] - meanB);
    }
    if (varA == 0 || varB == 0) return 0;
    return cov / math.sqrt(varA * varB);
  }

  /// The last [window] rows, zero rows in front when shorter.
  static List<List<double>> pad(List<List<double>> rows) {
    final tail = rows.length > window
        ? rows.sublist(rows.length - window)
        : rows;
    return [
      for (var i = tail.length; i < window; i++)
        List<double>.filled(featureCount, 0),
      ...tail,
    ];
  }
}
