import '../models/key_signature.dart';
import '../models/note.dart';
import '../models/part.dart';
import '../models/score.dart';

enum ScoreLabel {
  simpleMelody,
  childrensSong,
  waltz,
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
      ScoreLabel.march => 'March',
      ScoreLabel.classical => 'Classical',
      ScoreLabel.generalPiece => 'General Piece',
    };
  }
}

class ScoreClassifier {
  static ScoreLabel classify(Score score) {
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
