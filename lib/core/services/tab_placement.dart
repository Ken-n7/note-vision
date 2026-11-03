import '../models/note.dart';
import '../models/score.dart';
import '../models/tablature.dart';
import 'accidentals.dart';

/// Gives every note on a tablature staff the string and fret that play its
/// sounding pitch, keeping its own string where it can; returns [score]
/// itself when nothing changes.
Score placeTabNotes(Score score) {
  if (!score.parts.any((p) => p.isTab && p.tabTuning != null)) return score;
  var changed = false;
  final parts = [
    for (final part in score.parts)
      if (!part.isTab || part.tabTuning == null)
        part
      else
        () {
          final accidentals = Accidentals();
          return part.copyWith(
            measures: [
              for (final m in part.measures)
                () {
                  accidentals.startMeasure(m);
                  return m.copyWith(
                    symbols: [
                      for (final s in m.symbols)
                        if (s is Note)
                          () {
                            final place = tabPlace(
                              s.step,
                              accidentals.sounding(s),
                              s.octave,
                              part.tabTuning!,
                              string: s.string,
                            );
                            if (place == null ||
                                (place.string == s.string &&
                                    place.fret == s.fret)) {
                              return s;
                            }
                            changed = true;
                            return s.copyWith(
                              string: place.string,
                              fret: place.fret,
                            );
                          }()
                        else
                          s,
                    ],
                  );
                }(),
            ],
          );
        }(),
  ];
  return changed ? score.copyWith(parts: parts) : score;
}
