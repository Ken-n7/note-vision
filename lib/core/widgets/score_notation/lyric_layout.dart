import 'dart:math' as math;
import '../../models/note.dart';
import '../../models/measure.dart';
import 'engraving_layout.dart';

/// Geometry in editor coordinates (y down), reused by the screen and PDF.
/// Call with notes from the entire part, including notes outside this page,
/// so hyphens and melismas continue over system and page boundaries.
class LyricAnchor {
  const LyricAnchor(this.note, this.system, this.x);
  final Note note;
  final int system;
  final double x;
}

class LyricTextLayout {
  const LyricTextLayout(this.note, this.text, this.x, this.y);
  final Note note;
  final String text;
  final double x, y;
}

class LyricLineLayout {
  const LyricLineLayout(this.x1, this.x2, this.y);
  final double x1, x2, y;
}

class LyricDrawing {
  final texts = <LyricTextLayout>[];
  final lines = <LyricLineLayout>[];
}

abstract final class LyricLayout {
  static const fontSize = 12.0;
  static const lineHeight = 18.0;
  // Leave the dynamic/hairpin lane free above the lyrics.
  static const below = 46.0;

  static List<(int, int, String, bool)> lanes(Iterable<Note> notes) {
    final result = {
      for (final n in notes)
        for (final l in n.lyrics)
          if (!l.hidden) (n.voice ?? 1, n.staff ?? 1, l.verse, l.above),
    }.toList();
    result.sort((a, b) {
      var order = a.$1.compareTo(b.$1);
      if (order == 0) order = a.$2.compareTo(b.$2);
      if (order == 0) {
        final ai = int.tryParse(a.$3), bi = int.tryParse(b.$3);
        order = ai != null && bi != null
            ? ai.compareTo(bi)
            : a.$3.compareTo(b.$3);
      }
      return order == 0 ? a.$4.toString().compareTo(b.$4.toString()) : order;
    });
    return result;
  }

  /// Extra space is shared by every staff, preserving alignment/hit testing.
  static double extraHeight(Iterable<Iterable<Measure>> parts) {
    var extra = 0.0;
    for (final part in parts) {
      final ls = lanes(part.expand((m) => m.symbols).whereType<Note>());
      final belowCount = ls.where((l) => !l.$4).length;
      final aboveCount = ls.where((l) => l.$4).length;
      extra = math.max(
        extra,
        math.max(0, belowCount - 1) * lineHeight + aboveCount * lineHeight,
      );
    }
    return extra;
  }

  static double aboveHeight(Iterable<Iterable<Measure>> parts) {
    var count = 0;
    for (final part in parts) {
      count = math.max(
        count,
        lanes(
          part.expand((m) => m.symbols).whereType<Note>(),
        ).where((l) => l.$4).length,
      );
    }
    return count * lineHeight;
  }

  static List<LyricAnchor> anchors({
    required List<Measure> measures,
    required List<Measure> pageMeasures,
    required int firstMeasure,
    required int perRow,
    required double contentX,
    required double measureWidth,
    required double prefixWidth,
    EngravingLayout? engraving,
    int part = 0,
  }) {
    final result = <LyricAnchor>[];
    final systems = (pageMeasures.length / perRow).ceil();
    for (final (m, measure) in measures.indexed) {
      final relative = m - firstMeasure;
      final system = relative < 0
          ? -1
          : relative >= pageMeasures.length
          ? systems
          : relative ~/ perRow;
      final inPage = relative >= 0 && relative < pageMeasures.length;
      final column = inPage ? relative % perRow : 0;
      final spacing = engraving ?? EngravingLayout([pageMeasures]);
      for (final (i, note) in measure.symbols.indexed) {
        if (note is! Note) continue;
        result.add(
          LyricAnchor(
            note,
            system,
            contentX +
                column * measureWidth +
                (inPage
                    ? spacing
                          .place(relative, measureWidth, perRow, prefixWidth)
                          .symbolX(part, i)
                    : 0),
          ),
        );
      }
    }
    return result;
  }

  static LyricDrawing build({
    required List<LyricAnchor> notes,
    required int system,
    required double staffTop,
    required double staffBottom,
    required double left,
    required double right,
    required double Function(String) textWidth,
    double aboveClearance = 0,
    double belowClearance = 0,
  }) {
    final result = LyricDrawing();
    final allLanes = lanes(notes.map((a) => a.note));
    for (final lane in allLanes) {
      final side = allLanes
          .where((l) => l.$4 == lane.$4)
          .toList()
          .indexOf(lane);
      final y = lane.$4
          ? staffTop - 38 - aboveClearance - side * lineHeight
          : staffBottom + below + belowClearance + side * lineHeight;
      final voice = notes
          .where(
            (a) =>
                (a.note.voice ?? 1) == lane.$1 &&
                (a.note.staff ?? 1) == lane.$2,
          )
          .toList();
      final syllables = <(int, Lyric)>[
        for (final (i, a) in voice.indexed)
          for (final l in a.note.lyrics)
            if (l.verse == lane.$3 && l.above == lane.$4 && !l.hidden) (i, l),
      ];
      void line(
        LyricAnchor a,
        LyricAnchor b,
        double from,
        double to,
        bool hyphen,
      ) {
        if (system < a.system || system > b.system) return;
        final x1 = a.system == system ? from : left;
        final x2 = b.system == system ? to : right;
        if (x2 <= x1 + 3) return;
        if (hyphen) {
          final mid = (x1 + x2) / 2;
          result.lines.add(LyricLineLayout(mid - 2, mid + 2, y - 4));
        } else {
          result.lines.add(LyricLineLayout(x1, x2, y + 2));
        }
      }

      for (final (k, (i, lyric)) in syllables.indexed) {
        final a = voice[i];
        final width = textWidth(lyric.text);
        if (a.system == system && lyric.text.isNotEmpty) {
          result.texts.add(
            LyricTextLayout(a.note, lyric.text, a.x - width / 2, y),
          );
        }
        final next = k + 1 < syllables.length ? syllables[k + 1] : null;
        if ((lyric.syllabic == Syllabic.begin ||
                lyric.syllabic == Syllabic.middle) &&
            next != null &&
            lyric.extend == null) {
          final b = voice[next.$1];
          line(
            a,
            b,
            a.x + width / 2 + 3,
            b.x - textWidth(next.$2.text) / 2 - 3,
            true,
          );
        }
        if (lyric.extend == LyricExtend.start ||
            lyric.extend == LyricExtend.continueLine) {
          // An untyped <extend/> runs to the last note before the next word,
          // or the final note. Explicit stop/continue elements supply endpoints.
          final end = next == null
              ? voice.length - 1
              : next.$2.text.isEmpty
              ? next.$1
              : math.max(i, next.$1 - 1);
          final b = voice[end];
          line(
            a,
            b,
            a.x + width / 2 + (lyric.text.isEmpty ? 0 : 3),
            b.x + 8,
            false,
          );
        }
      }
    }
    return result;
  }
}
