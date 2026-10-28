import '../../models/note.dart';
import '../../models/note_value.dart';
import '../../models/rest.dart';
import '../../models/score_symbol.dart';

/// Horizontal columns and stem directions for one bar, shared by the editor
/// and the PDF. With several voices, symbols that start together share a
/// column, so a second voice lines up under the first. A bar with one voice
/// keeps one column per symbol in order (chord tones share their note's).
class VoiceLayout {
  VoiceLayout._(this.columns, this.columnCount, this._voices, this.multiVoice);

  factory VoiceLayout.of(List<ScoreSymbol> symbols) {
    final laneEnds = <(int, int), double>{};
    final onsets = List<double>.filled(symbols.length, 0);
    final voices = List<int>.filled(symbols.length, 1);
    var chordOnset = 0.0;
    for (final (i, symbol) in symbols.indexed) {
      final (voice, staff, length) = switch (symbol) {
        Note(:final voice, :final staff) || Rest(:final voice, :final staff) =>
          (voice ?? 1, staff ?? 1, symbolQuarters(symbol)),
        _ => (1, 1, 0.0),
      };
      voices[i] = voice;
      if (symbol is Note && symbol.isChordTone) {
        onsets[i] = chordOnset;
        continue;
      }
      final onset = laneEnds[(voice, staff)] ?? 0;
      onsets[i] = chordOnset = onset;
      laneEnds[(voice, staff)] = onset + length;
    }
    final multiVoice =
        {
          for (final (i, s) in symbols.indexed)
            if (s is Note || s is Rest) voices[i],
        }.length >
        1;
    if (!multiVoice) {
      final columns = <int>[];
      var column = -1;
      for (final symbol in symbols) {
        if (!(symbol is Note && symbol.isChordTone) || column < 0) column++;
        columns.add(column);
      }
      return VoiceLayout._(columns, column < 0 ? 1 : column + 1, voices, false);
    }
    // Rounded so that tuplet arithmetic does not split a column.
    int key(double onset) => (onset * 960).round();
    final distinct = {for (final o in onsets) key(o)}.toList()..sort();
    final columnOf = {for (final (i, k) in distinct.indexed) k: i};
    return VoiceLayout._(
      [for (final o in onsets) columnOf[key(o)]!],
      distinct.length,
      voices,
      true,
    );
  }

  /// The column of each symbol, by index.
  final List<int> columns;
  final int columnCount;
  final List<int> _voices;

  /// Whether the bar has notes or rests in more than one voice.
  final bool multiVoice;

  /// With several voices, odd voices (1, 3) stem up and even voices down, as
  /// in MuseScore Studio; null leaves the direction to the pitch.
  bool? stemUp(int index) => multiVoice ? (_voices[index] - 1).isEven : null;

  /// Staff spaces to move a rest (negative is up) so voices do not collide.
  double restOffset(int index) =>
      multiVoice ? ((_voices[index] - 1).isEven ? -2 : 2) : 0;
}
