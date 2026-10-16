import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import '../config/app_features.dart';
import '../models/key_signature.dart';
import '../models/note.dart';
import '../models/part.dart';
import '../models/score.dart';
import 'genre_model.dart';

/// Labels a score can get. The app shows only the genre model's three
/// genres ([waltz], [kundiman], [jazz]); the others belong to the older
/// rules and stay hidden behind [AppFeatures.legacyScoreLabels].
enum ScoreLabel {
  simpleMelody,
  childrensSong,
  waltz,
  kundiman,
  jazz,
  march,
  classical,
  generalPiece,
}

extension ScoreLabelText on ScoreLabel {
  String get displayName {
    return switch (this) {
      ScoreLabel.simpleMelody => 'Simple Melody',
      ScoreLabel.childrensSong => "Children's Song",
      ScoreLabel.waltz => 'Waltz',
      ScoreLabel.kundiman => 'Kundiman',
      ScoreLabel.jazz => 'Jazz',
      ScoreLabel.march => 'March',
      ScoreLabel.classical => 'Classical',
      ScoreLabel.generalPiece => 'General Piece',
    };
  }
}

class ScoreClassifier {
  /// Below this the genre model is not sure enough and the rules decide.
  static const minConfidence = 0.7;

  /// Labels already worked out, per Score (an edit makes a new Score).
  static final _labels = Expando<ScoreLabel>();

  /// The genre the app shows for [score]: Waltz, Kundiman or Jazz, or null
  /// when the score has no notes.
  ///
  /// The genre model decides when it is at least [minConfidence] sure of one
  /// of the three. Otherwise (it says "other", is unsure, is not loaded, or
  /// the melody is short) [classifyByRules] picks one of the three.
  static ScoreLabel? classify(Score score) {
    if (AppFeatures.legacyScoreLabels) return classifyByLegacyRules(score);
    final cached = _labels[score];
    if (cached != null) return cached;

    ScoreLabel? label;
    final probs = GenreModel.predict(score);
    if (probs != null) {
      var best = 0;
      for (var i = 1; i < probs.length; i++) {
        if (probs[i] > probs[best]) best = i;
      }
      if (probs[best] >= minConfidence) {
        label = switch (GenreModel.genres[best]) {
          'waltz' => ScoreLabel.waltz,
          'kundiman' => ScoreLabel.kundiman,
          'jazz' => ScoreLabel.jazz,
          _ => null,
        };
      }
    }
    label ??= classifyByRules(score);
    // A model run costs a few ms and cards rebuild often, so keep the answer.
    if (label != null) _labels[score] = label;
    return label;
  }

  /// One of the three genres from the melody alone: music not in triple time
  /// is Jazz; triple time (3, 6 or 9 beats in the bar) is Kundiman when its
  /// first half is in a minor key (kundiman open in minor), else Waltz.
  /// Null when the score has no notes.
  static ScoreLabel? classifyByRules(Score score) {
    final notes = [
      for (final n in GenreModel.melody(score))
        if (n[0] >= 0) n,
    ];
    if (notes.isEmpty) return null;

    final timeByBeats = <int, double>{};
    for (final n in notes) {
      final beats = n[3].toInt();
      timeByBeats[beats] = (timeByBeats[beats] ?? 0) + n[1].toDouble();
    }
    final beats = timeByBeats.entries
        .reduce((a, b) => b.value > a.value ? b : a)
        .key;
    if (beats != 3 && beats != 6 && beats != 9) return ScoreLabel.jazz;

    final firstHalf = notes.take(math.max(16, notes.length ~/ 2));
    return isMinor(firstHalf) ? ScoreLabel.kundiman : ScoreLabel.waltz;
  }

  // Krumhansl–Kessler key profiles, index 0 = tonic.
  static const _majorProfile = [
    6.35, 2.23, 3.48, 2.33, 4.38, 4.09, 2.52, 5.19, 2.39, 3.66, 2.29, 2.88,
  ];
  static const _minorProfile = [
    6.33, 2.68, 3.52, 5.38, 2.60, 3.53, 2.54, 4.75, 3.98, 2.69, 3.34, 3.17,
  ];

  /// Krumhansl–Schmuckler key finding on `[midi, quarters, ...]` notes:
  /// true when the best-fitting of the 24 keys is a minor key.
  @visibleForTesting
  static bool isMinor(Iterable<List<num>> notes) {
    final histogram = List<double>.filled(12, 0);
    for (final n in notes) {
      histogram[n[0].toInt() % 12] += n[1].toDouble();
    }
    double bestFit(List<double> profile) {
      var best = double.negativeInfinity;
      for (var tonic = 0; tonic < 12; tonic++) {
        final rotated = [
          for (var pc = 0; pc < 12; pc++) profile[(pc - tonic + 12) % 12],
        ];
        best = math.max(best, _correlation(histogram, rotated));
      }
      return best;
    }

    return bestFit(_minorProfile) > bestFit(_majorProfile);
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

  /// The older labels from fixed rules (time signature, key, note values):
  /// Simple Melody, Children's Song, Waltz, March, Classical, General Piece.
  /// Shown only when [AppFeatures.legacyScoreLabels] is on.
  static ScoreLabel classifyByLegacyRules(Score score) {
    final primaryPart = score.parts.isNotEmpty ? score.parts.first : null;
    final firstMeasure =
        primaryPart != null && primaryPart.measures.isNotEmpty
            ? primaryPart.measures.first
            : null;
    final keySignature = firstMeasure?.keySignature;
    final timeSignature = firstMeasure?.timeSignature;
    final notes = _allNotes(score);
    final pitchRange = _pitchRangeInSemitones(notes);
    final basicNoteRatio = _basicNoteRatio(notes);
    final averageNotesPerMeasure = _averageNotesPerMeasure(primaryPart);
    final hasSimpleKey = keySignature == null || keySignature.fifths.abs() <= 1;
    final hasTwoFour = timeSignature?.beats == 2 && timeSignature?.beatType == 4;
    final hasThreeFour = timeSignature?.beats == 3 && timeSignature?.beatType == 4;
    final hasSixteenthOrBeamedNotes = notes.any(
      (note) => note.type == 'sixteenth' || note.beamed,
    );

    if (score.parts.length == 1 &&
        hasTwoFour &&
        hasSimpleKey &&
        averageNotesPerMeasure != null &&
        averageNotesPerMeasure <= 4) {
      return ScoreLabel.childrensSong;
    }

    if (score.parts.length == 1 &&
        hasSimpleKey &&
        notes.isNotEmpty &&
        basicNoteRatio >= 0.75 &&
        pitchRange != null &&
        pitchRange <= 8) {
      return ScoreLabel.simpleMelody;
    }

    if (hasThreeFour) {
      return ScoreLabel.waltz;
    }

    if (hasTwoFour) {
      return ScoreLabel.march;
    }

    if (score.parts.length >= 2 ||
        _hasComplexKey(keySignature) ||
        hasSixteenthOrBeamedNotes) {
      return ScoreLabel.classical;
    }

    return ScoreLabel.generalPiece;
  }

  static List<Note> _allNotes(Score score) {
    return [
      for (final part in score.parts)
        for (final measure in part.measures)
          ...measure.notes,
    ];
  }

  static int? _pitchRangeInSemitones(List<Note> notes) {
    if (notes.isEmpty) {
      return null;
    }

    final pitches = notes.map(_pitchToSemitone).toList(growable: false);
    final minPitch = pitches.reduce((a, b) => a < b ? a : b);
    final maxPitch = pitches.reduce((a, b) => a > b ? a : b);
    return maxPitch - minPitch;
  }

  static double _basicNoteRatio(List<Note> notes) {
    if (notes.isEmpty) {
      return 0;
    }

    final basicCount = notes.where((note) {
      return note.type == 'whole' ||
          note.type == 'half' ||
          note.type == 'quarter';
    }).length;
    return basicCount / notes.length;
  }

  static double? _averageNotesPerMeasure(Part? part) {
    if (part == null || part.measures.isEmpty) {
      return null;
    }

    final noteCount = part.measures.fold<int>(
      0,
      (sum, measure) => sum + measure.notes.length,
    );
    return noteCount / part.measures.length;
  }

  static bool _hasComplexKey(KeySignature? keySignature) {
    return keySignature != null && keySignature.fifths.abs() >= 3;
  }

  static int _pitchToSemitone(Note note) {
    final base = switch (note.step) {
      'C' => 0,
      'D' => 2,
      'E' => 4,
      'F' => 5,
      'G' => 7,
      'A' => 9,
      'B' => 11,
      _ => 0,
    };
    return note.octave * 12 + base + (note.alter ?? 0);
  }
}
