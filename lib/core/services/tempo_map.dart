import '../models/score.dart';
import '../models/score_annotation.dart';
import 'score_timeline.dart';

/// Musical time remains at 500 ms per quarter; this map integrates written
/// tempo changes into real time. The transport's BPM is a relative speed
/// (120 = 100%), and therefore still changes speed without editing the score.
class TempoMap {
  const TempoMap([this.points = const []]);
  final List<(int, double)> points;
  factory TempoMap.forScore(Score score, ScoreTimeline timeline) {
    final written = <int, List<ScoreAnnotation>>{};
    final sequential =
        score.playbackLayout == ScorePlaybackLayout.sequentialStaves;
    final starts = <int>[];
    var next = 0;
    for (final p in score.parts) {
      starts.add(next);
      next += p.measures.length;
    }
    for (final (pi, p) in score.parts.indexed) {
      for (final (m, measure) in p.measures.indexed) {
        for (final a in measure.annotations) {
          if (a.tempo != null &&
              a.tempo!.isFinite &&
              a.tempo! > 0 &&
              !a.offset.isNegative) {
            final entries = written.putIfAbsent(
              sequential ? starts[pi] + m : m,
              () => [],
            );
            if (!entries.any((v) => v.offset == a.offset)) entries.add(a);
          }
        }
      }
    }
    if (written.isEmpty) return const TempoMap();
    for (final list in written.values) {
      list.sort((a, b) => a.offset.compareTo(b.offset));
    }
    final points = <int, double>{0: 120};
    final visited = <(int, int)>{};
    for (final m in timeline.measures) {
      final start = (m.onset.asDouble * 500).round();
      final slot = sequential
          ? starts[m.partIndex] + m.measureIndex
          : m.measureIndex;
      if (!visited.add((start, slot))) continue;
      var bpm = 120.0;
      for (var i = 0; i < slot; i++) {
        if (written[i]?.isNotEmpty ?? false) bpm = written[i]!.last.tempo!;
      }
      points[start] = bpm;
      for (final a in written[slot] ?? <ScoreAnnotation>[]) {
        if (a.offset.compareTo(m.duration) <= 0) {
          points[start + (a.offset.asDouble * 500).round()] = a.tempo!;
        }
      }
    }
    final sorted = points.entries.toList()
      ..sort((a, b) => a.key.compareTo(b.key));
    return TempoMap(
      List.unmodifiable([for (final p in sorted) (p.key, p.value)]),
    );
  }
  int elapsed(int from, int to, [int speed = 120]) {
    if (to <= from) return 0;
    var bpm = 120.0, cursor = from, total = 0.0;
    for (final (at, value) in points) {
      if (at <= from) {
        bpm = value;
        continue;
      }
      if (at >= to) break;
      total += (at - cursor) * 120 / bpm;
      cursor = at;
      bpm = value;
    }
    total += (to - cursor) * 120 / bpm;
    return (total * 120 / speed).round();
  }
}
