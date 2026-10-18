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

  /// When the rules fall back to "triple time in a minor key = Kundiman",
  /// the genre model must still give Kundiman at least this much, else the
  /// piece is shown as a Waltz. Without it most minor-key waltzes the model
  /// was unsure about came out as Kundiman: across the data project's
  /// cross-validation, non-kundiman songs called Kundiman fell from 3.7% to
  /// 0.5% (6.1% to 1.5% on 40-note pieces) with no real kundiman lost.
  /// Chosen on validation songs (genre_app_eval.py).
  static const minRuleKundiman = 0.4;

  /// Labels already worked out, per Score (an edit makes a new Score).
  static final _labels = Expando<ScoreLabel>();

  /// The genre the app shows for [score]: Waltz, Kundiman or Jazz, or null
  /// when the score has no notes. See [decide].
  static ScoreLabel? classify(Score score) {
    if (AppFeatures.legacyScoreLabels) return classifyByLegacyRules(score);
    final cached = _labels[score];
    if (cached != null) return cached;
    final label = decide(GenreModel.predict(score), score);
    // A model run costs a few ms and cards rebuild often, so keep the answer.
    if (label != null) _labels[score] = label;
    return label;
  }

  /// The label for [score] given the genre model's [probs] (null when the
  /// model is not loaded or the melody is short).
  ///
  /// The genre model decides when it is at least [minConfidence] sure of one
  /// of the three. Otherwise (it says "other" or is unsure) [classifyByRules]
  /// picks one of the three, and a Kundiman from the rules needs the model's
  /// Kundiman to reach [minRuleKundiman].
  @visibleForTesting
  static ScoreLabel? decide(List<double>? probs, Score score) {
    if (probs != null) {
      var best = 0;
      for (var i = 1; i < probs.length; i++) {
        if (probs[i] > probs[best]) best = i;
      }
      if (probs[best] >= minConfidence) {
        final label = switch (GenreModel.genres[best]) {
          'waltz' => ScoreLabel.waltz,
          'kundiman' => ScoreLabel.kundiman,
          'jazz' => ScoreLabel.jazz,
          _ => null,
        };
        if (label != null) return label;
      }
    }
    final label = classifyByRules(score);
    if (label == ScoreLabel.kundiman &&
        probs != null &&
        probs[GenreModel.genres.indexOf('kundiman')] < minRuleKundiman) {
      return ScoreLabel.waltz;
    }
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

  /// Krumhansl–Schmuckler key finding on `[midi, quarters, ...]` notes:
  /// true when the best-fitting of the 24 keys is a minor key.
  @visibleForTesting
  static bool isMinor(Iterable<List<num>> notes) =>
      GenreModel.keyOf(notes).minor;

  /// The older labels from fixed rules (time signature, key, note values):
  /// Simple Melody, Children's Song, Waltz, March, Classical, General Piece.
  /// Shown only when [AppFeatures.legacyScoreLabels] is on.
  static ScoreLabel classifyByLegacyRules(Score score) {
    final primaryPart = score.parts.isNotEmpty ? score.parts.first : null;
    final firstMeasure = primaryPart != null && primaryPart.measures.isNotEmpty
        ? primaryPart.measures.first
        : null;
    final keySignature = firstMeasure?.keySignature;
    final timeSignature = firstMeasure?.timeSignature;
    final notes = _allNotes(score);
    final pitchRange = _pitchRangeInSemitones(notes);
    final basicNoteRatio = _basicNoteRatio(notes);
    final averageNotesPerMeasure = _averageNotesPerMeasure(primaryPart);
    final hasSimpleKey = keySignature == null || keySignature.fifths.abs() <= 1;
    final hasTwoFour =
        timeSignature?.beats == 2 && timeSignature?.beatType == 4;
    final hasThreeFour =
        timeSignature?.beats == 3 && timeSignature?.beatType == 4;
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
        for (final measure in part.measures) ...measure.notes,
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
