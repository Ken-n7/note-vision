import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:note_vision/core/models/barline_type.dart';
import 'package:note_vision/core/models/beam_grouping.dart';
import 'package:note_vision/core/models/measure.dart';
import 'package:note_vision/core/models/navigation_mark.dart';
import 'package:note_vision/core/models/note.dart';
import 'package:note_vision/core/models/note_value.dart';
import 'package:note_vision/core/models/part.dart';
import 'package:note_vision/core/models/rest.dart';
import 'package:note_vision/core/models/score.dart';
import 'package:note_vision/core/models/score_symbol.dart';
import 'package:note_vision/core/utils/export_file_name.dart';
import 'package:note_vision/core/services/accidentals.dart';
import 'package:note_vision/core/services/score_timeline.dart';
import 'package:note_vision/core/services/spanners.dart';
import 'package:xml/xml.dart';
import 'musicxml_preserving_exporter.dart';
import 'musicxml_lyrics.dart';

/// Converts a [Score] to a valid MusicXML 3.1 string and saves it to a
/// user-chosen location via the system file picker.
class MusicXmlExportService {
  const MusicXmlExportService();

  /// Divisions per quarter note in exported files: fine enough for
  /// sixteenths, dotted eighths and dotted sixteenths. A score with tuplets
  /// multiplies this by their sizes so every duration stays whole.
  static const divisionsPerQuarter = 8;

  /// MusicXML's name for a note value: scans call a sixteenth 'sixteenth',
  /// MusicXML calls it '16th'.
  static String musicXmlType(String type) =>
      type.trim().toLowerCase() == 'sixteenth' ? '16th' : type;


  // ---------------------------------------------------------------------------
  // Public API
  // ---------------------------------------------------------------------------

  /// Returns a valid MusicXML 3.1 string for the given [score].
  /// Pure function — no I/O, fully unit-testable.
  String toMusicXml(Score score) {
    final preserved = const MusicXmlPreservingExporter().export(score);
    if (preserved != null) return preserved;
    final builder = XmlBuilder();
    builder.element(
      'score-partwise',
      attributes: {'version': '3.1'},
      nest: () {
        _buildWork(builder, score);
        _buildIdentification(builder, score);
        final instruments = _instruments(score);
        final marks = _Marks(score);
        _buildPartList(builder, instruments);
        for (final staves in instruments) {
          _buildPart(builder, staves, marks);
        }
      },
    );

    final body = builder.buildDocument().toXmlString(pretty: true, indent: '  ');
    return _xmlHeader + body;
  }

  /// Opens the system save dialog so the user picks a location, then writes
  /// the score as a .musicxml file to that location.
  ///
  /// Returns the saved file path, or `null` if the user cancelled.
  Future<String?> exportToDevice(Score score) async {
    final xml = toMusicXml(score);
    final fileName = safeExportFileName(score.title);
    final bytes = Uint8List.fromList(utf8.encode(xml));

    return FilePicker.platform.saveFile(
      fileName: '$fileName.xml',
      bytes: bytes,
      type: FileType.custom,
      allowedExtensions: ['xml'],
    );
  }

  // ---------------------------------------------------------------------------
  // XML construction
  // ---------------------------------------------------------------------------

  void _buildWork(XmlBuilder b, Score score) {
    b.element('work', nest: () {
      b.element('work-title', nest: score.title);
    });
  }

  void _buildIdentification(XmlBuilder b, Score score) {
    b.element('identification', nest: () {
      if (score.composer.trim().isNotEmpty) {
        b.element(
          'creator',
          attributes: {'type': 'composer'},
          nest: score.composer,
        );
      }
      b.element('encoding', nest: () {
        b.element('software', nest: 'Note Vision');
        b.element(
          'encoding-date',
          nest: DateTime.now().toIso8601String().substring(0, 10),
        );
      });
    });
  }

  /// Parts grouped by instrument: a part that joins the previous one is a
  /// further staff of the same MusicXML `<part>`.
  static List<List<Part>> _instruments(Score score) {
    final instruments = <List<Part>>[];
    for (final part in score.parts) {
      if (part.joinsPrevious && instruments.isNotEmpty) {
        instruments.last.add(part);
      } else {
        instruments.add([part]);
      }
    }
    return instruments;
  }

  void _buildPartList(XmlBuilder b, List<List<Part>> instruments) {
    b.element('part-list', nest: () {
      for (final [part, ...] in instruments) {
        b.element('score-part', attributes: {'id': part.id}, nest: () {
          b.element('part-name', nest: part.name);
        });
      }
    });
  }

  void _buildPart(XmlBuilder b, List<Part> parts, _Marks marks) {
    // Symbols keep their staff numbers; those of a joined staff without one
    // are on that staff, in voices 5–8 for staff 2 and so on, as MuseScore
    // writes them.
    final linked = parts.length > 1;
    final staffParts = [
      for (final (k, part) in parts.indexed)
        linked ? _onStaff(part, k + 1) : part,
    ];
    b.element('part', attributes: {'id': parts.first.id}, nest: () {
      final measures = parts.first.measures;
      final accidentals = [for (final _ in staffParts) Accidentals()];
      final staves = linked
          ? parts.length
          : measures
                .expand((m) => m.symbols)
                .fold(1, (n, s) => max(n, ScoreTimelineBuilder.lane(s).$2));
      // The numbers of the ending in progress, for its closing barline.
      var endingNumbers = '1';
      for (var i = 0; i < measures.length; i++) {
        if (measures[i].endingStart.isNotEmpty) {
          endingNumbers = measures[i].endingStart.join(', ');
        }
        final staffMeasures = [
          for (final part in staffParts)
            if (i < part.measures.length) part.measures[i],
        ];
        for (final (k, m) in staffMeasures.indexed) {
          accidentals[k].startMeasure(m);
        }
        _buildMeasure(
          b,
          staffMeasures,
          isFirst: i == 0,
          staves: staves,
          accidentals: accidentals,
          marks: marks,
          endingNumbers: endingNumbers,
        );
      }
    });
  }

  static Part _onStaff(Part part, int staff) => Part(
    id: part.id,
    name: part.name,
    staff: part.staff,
    measures: [
      for (final m in part.measures)
        m.withContent(
          keySignature: m.keySignature,
          symbols: [
            for (final s in m.symbols)
              switch (s) {
                Note() when s.staff == null => s.copyWith(
                  voice: s.voice ?? 1 + 4 * (staff - 1),
                  staff: staff,
                ),
                Rest() when s.staff == null => s.copyWith(
                  voice: s.voice ?? 1 + 4 * (staff - 1),
                  staff: staff,
                ),
                _ => s,
              },
          ],
        ),
    ],
  );

  /// One `<measure>` from the same bar of each of an instrument's staves.
  void _buildMeasure(
    XmlBuilder b,
    List<Measure> staffMeasures, {
    required bool isFirst,
    required int staves,
    required List<Accidentals> accidentals,
    required _Marks marks,
    String endingNumbers = '1',
  }) {
    final measure = staffMeasures.first;
    b.element(
      'measure',
      attributes: {'number': measure.number.toString()},
      nest: () {
        if (!isFirst && (measure.startsNewPage || measure.startsNewSystem)) {
          b.element('print', attributes: {
            if (measure.startsNewPage) 'new-page': 'yes',
            if (measure.startsNewSystem) 'new-system': 'yes',
          });
        }

        final needsAttributes = isFirst ||
            staffMeasures.any((m) => m.clef != null) ||
            measure.timeSignature != null ||
            measure.keySignature != null;

        if (needsAttributes) {
          b.element('attributes', nest: () {
            b.element('divisions', nest: '${marks.divisions}');

            if (measure.keySignature != null) {
              b.element('key', nest: () {
                b.element('fifths', nest: measure.keySignature!.fifths.toString());
              });
            }

            if (measure.timeSignature != null) {
              b.element('time', nest: () {
                b.element('beats', nest: measure.timeSignature!.beats.toString());
                b.element('beat-type', nest: measure.timeSignature!.beatType.toString());
              });
            }

            if (isFirst && staves > 1) {
              b.element('staves', nest: '$staves');
            }

            for (final (k, m) in staffMeasures.indexed) {
              final clef = m.clef;
              if (clef == null) continue;
              b.element('clef', attributes: {
                if (staves > 1) 'number': '${k + 1}',
              }, nest: () {
                b.element('sign', nest: clef.sign);
                b.element('line', nest: clef.line.toString());
              });
            }
          });
        }

        if (measure.leftBarlineType != null ||
            measure.endingStart.isNotEmpty) {
          _buildBarline(
            b,
            location: 'left',
            type: measure.leftBarlineType,
            ending: measure.endingStart.isEmpty
                ? null
                : (measure.endingStart.join(', '), 'start'),
          );
        }
        _buildNavigation(b, measure, atEnd: false);

        // Each voice/staff lane starts at the bar line; <backup> and
        // <forward> move the cursor to where the next lane's symbol starts.
        final laneEnds = <VoiceLane, int>{};
        var cursor = 0;
        for (final (k, staffMeasure) in staffMeasures.indexed) {
          final symbols = staffMeasure.symbols;
          for (var i = 0; i < symbols.length; i++) {
            final symbol = symbols[i];
            final length = switch (symbol) {
              Note(isChordTone: true) => null,
              Note() || Rest() => marks.duration(symbol),
              _ => null,
            };
            if (length != null) {
              final lane = ScoreTimelineBuilder.lane(symbol);
              final onset = laneEnds[lane] ?? 0;
              if (onset != cursor) {
                b.element(onset < cursor ? 'backup' : 'forward', nest: () {
                  b.element('duration', nest: '${(cursor - onset).abs()}');
                });
              }
              cursor = onset + length;
              laneEnds[lane] = cursor;
              _buildDirections(b, symbol, marks, before: true);
            }
            if (symbol is Note) {
              _buildNote(
                b,
                symbol,
                soundingAlter: accidentals[k].sounding(symbol),
                beamValues: BeamGrouping.valuesFor(symbols, i),
                marks: marks,
              );
            } else if (symbol is Rest) {
              _buildRest(b, symbol, marks);
            }
            if (length != null) {
              _buildDirections(b, symbol, marks, before: false);
            }
          }
        }

        _buildNavigation(b, measure, atEnd: true);
        if (measure.rightBarlineType != null || measure.endingEnd != null) {
          _buildBarline(
            b,
            location: 'right',
            type: measure.rightBarlineType,
            ending: switch (measure.endingEnd) {
              null => null,
              final end => (
                endingNumbers,
                end == EndingEnd.open ? 'discontinue' : 'stop',
              ),
            },
          );
        }
      },
    );
  }

  /// [soundingAlter] goes in `<alter>`, which MusicXML reads as the pitch
  /// heard, key signature included.
  void _buildNote(
    XmlBuilder b,
    Note note, {
    required int soundingAlter,
    Map<int, BeamValue> beamValues = const {},
    _Marks? marks,
  }) {
    final id = note.reviewId;
    final tieStop = id != null && (marks?.tieStops.contains(id) ?? false);
    final tieStart = id != null && (marks?.tieStarts.contains(id) ?? false);
    final slurs = id == null ? const <(String, int)>[] : marks?.slurs[id] ?? [];
    b.element('note', nest: () {
      if (note.isChordTone) {
        b.element('chord');
      }
      b.element('pitch', nest: () {
        b.element('step', nest: note.step);
        if (soundingAlter != 0) {
          b.element('alter', nest: soundingAlter.toString());
        }
        b.element('octave', nest: note.octave.toString());
      });
      b.element('duration', nest: '${marks?.duration(note) ?? 0}');
      if (tieStop) b.element('tie', attributes: {'type': 'stop'});
      if (tieStart) b.element('tie', attributes: {'type': 'start'});
      if (note.voice != null) {
        b.element('voice', nest: note.voice.toString());
      }
      b.element('type', nest: musicXmlType(note.type));
      if (note.dots > 0) {
        for (var i = 0; i < note.dots; i++) {
          b.element('dot');
        }
      }
      // [Note.alter] is the accidental written before the note.
      final accidental = switch (note.alter) {
        -2 => 'flat-flat',
        -1 => 'flat',
        0 => 'natural',
        1 => 'sharp',
        2 => 'double-sharp',
        _ => null,
      };
      if (accidental != null) b.element('accidental', nest: accidental);
      _buildTimeModification(b, note.tuplet);
      if (note.staff != null) {
        b.element('staff', nest: note.staff.toString());
      }
      for (final entry in beamValues.entries) {
        b.element(
          'beam',
          attributes: {'number': '${entry.key}'},
          nest: entry.value.xmlValue,
        );
      }
      final bracket = note.tuplet != null &&
          (note.tuplet!.start || note.tuplet!.stop);
      if (tieStop ||
          tieStart ||
          slurs.isNotEmpty ||
          bracket ||
          note.marks.isNotEmpty) {
        b.element('notations', nest: () {
          if (tieStop) b.element('tied', attributes: {'type': 'stop'});
          if (tieStart) b.element('tied', attributes: {'type': 'start'});
          for (final (type, number) in slurs) {
            b.element(
              'slur',
              attributes: {'type': type, 'number': '$number'},
            );
          }
          _buildTupletMarks(b, note.tuplet);
          _buildMarks(b, note.marks);
        });
      }
      for (final lyric in note.lyrics) {
        b.xml(MusicXmlLyrics.write(lyric).toXmlString());
      }
    });
  }

  /// A note or rest's dynamic and hairpin starts (before it), or the
  /// hairpins it ends (after it).
  void _buildDirections(
    XmlBuilder b,
    ScoreSymbol symbol,
    _Marks marks, {
    required bool before,
  }) {
    final (id, dynamic, staff) = switch (symbol) {
      Note(:final reviewId, :final dynamicMark, :final staff) ||
      Rest(:final reviewId, :final dynamicMark, :final staff) => (
        reviewId,
        dynamicMark,
        staff,
      ),
      _ => (null, null, null),
    };
    void direction(void Function() type) =>
        b.element('direction', attributes: {'placement': 'below'}, nest: () {
          b.element('direction-type', nest: type);
          if (staff != null) b.element('staff', nest: '$staff');
        });
    void wedge(String type, int number) => direction(
      () => b.element('wedge', attributes: {'type': type, 'number': '$number'}),
    );
    if (!before) {
      for (final number in marks.wedgeStops[id] ?? const <int>[]) {
        wedge('stop', number);
      }
      return;
    }
    if (dynamic != null) {
      direction(() => b.element('dynamics', nest: () => b.element(dynamic)));
    }
    for (final (type, number) in marks.wedgeStarts[id] ?? const <(String, int)>[]) {
      wedge(type, number);
    }
  }

  void _buildMarks(XmlBuilder b, List<Articulation> marks) {
    for (final group in ['ornaments', 'articulations']) {
      final members = [
        for (final m in marks)
          if (m.group == group) m,
      ];
      if (members.isEmpty) continue;
      b.element(group, nest: () {
        for (final m in members) {
          b.element(m.xmlName);
        }
      });
    }
    if (marks.contains(Articulation.fermata)) {
      b.element('fermata', attributes: {'type': 'upright'});
    }
  }

  void _buildTimeModification(XmlBuilder b, Tuplet? tuplet) {
    if (tuplet == null) return;
    b.element('time-modification', nest: () {
      b.element('actual-notes', nest: '${tuplet.actual}');
      b.element('normal-notes', nest: '${tuplet.normal}');
    });
  }

  void _buildTupletMarks(XmlBuilder b, Tuplet? tuplet) {
    if (tuplet == null) return;
    if (tuplet.start) b.element('tuplet', attributes: {'type': 'start'});
    if (tuplet.stop) b.element('tuplet', attributes: {'type': 'stop'});
  }

  void _buildRest(XmlBuilder b, Rest rest, _Marks marks) {
    b.element('note', nest: () {
      b.element('rest');
      b.element('duration', nest: '${marks.duration(rest)}');
      if (rest.voice != null) {
        b.element('voice', nest: rest.voice.toString());
      }
      b.element('type', nest: musicXmlType(rest.type));
      if (rest.dots > 0) {
        for (var i = 0; i < rest.dots; i++) {
          b.element('dot');
        }
      }
      _buildTimeModification(b, rest.tuplet);
      if (rest.staff != null) {
        b.element('staff', nest: rest.staff.toString());
      }
      final bracket = rest.tuplet != null &&
          (rest.tuplet!.start || rest.tuplet!.stop);
      if (bracket || rest.marks.isNotEmpty) {
        b.element('notations', nest: () {
          _buildTupletMarks(b, rest.tuplet);
          _buildMarks(b, rest.marks);
        });
      }
    });
  }

  void _buildBarline(
    XmlBuilder b, {
    required String location,
    required BarlineType? type,
    (String, String)? ending,
  }) {
    b.element('barline', attributes: {'location': location}, nest: () {
      final style = switch (type) {
        BarlineType.repeatStart => 'heavy-light',
        BarlineType.repeatEnd || BarlineType.finalBar => 'light-heavy',
        BarlineType.doubleBar => 'light-light',
        null => null,
      };
      if (style != null) b.element('bar-style', nest: style);
      if (ending case (final numbers, final kind)) {
        b.element(
          'ending',
          attributes: {'number': numbers, 'type': kind},
          nest: kind == 'start' ? '${numbers.replaceAll(' ', '')}.' : null,
        );
      }
      if (type == BarlineType.repeatStart) {
        b.element('repeat', attributes: {'direction': 'forward'});
      } else if (type == BarlineType.repeatEnd) {
        b.element('repeat', attributes: {'direction': 'backward'});
      }
    });
  }

  /// Segno and coda before a bar's notes; Fine, To Coda, D.C. and D.S. after
  /// them, with the `<sound>` that makes them play.
  void _buildNavigation(XmlBuilder b, Measure measure, {required bool atEnd}) {
    for (final mark in measure.navigation.where((m) => m.atEnd == atEnd)) {
      b.element('direction', attributes: {'placement': 'above'}, nest: () {
        b.element('direction-type', nest: () {
          switch (mark) {
            case NavigationMark.segno:
              b.element('segno');
            case NavigationMark.coda:
              b.element('coda');
            default:
              b.element('words', nest: mark.text);
          }
        });
        final sound = switch (mark) {
          NavigationMark.segno => {'segno': 'segno'},
          NavigationMark.coda => {'coda': 'coda'},
          NavigationMark.fine => {'fine': 'yes'},
          NavigationMark.toCoda => {'tocoda': 'coda'},
          _ when mark.toSegno => {'dalsegno': 'segno'},
          _ => {'dacapo': 'yes'},
        };
        b.element('sound', attributes: sound);
      });
    }
  }

  // ---------------------------------------------------------------------------
  // Helpers
  // ---------------------------------------------------------------------------

  static const String _xmlHeader =
      '<?xml version="1.0" encoding="UTF-8"?>\n'
      '<!DOCTYPE score-partwise PUBLIC\n'
      '  "-//Recordare//DTD MusicXML 3.1 Partwise//EN"\n'
      '  "http://www.musicxml.org/dtds/partwise.dtd">\n';

}

/// Divisions, ties and slurs to write.
class _Marks {
  _Marks(Score score)
    : divisions =
          MusicXmlExportService.divisionsPerQuarter *
          [
            for (final p in score.parts)
              for (final m in p.measures)
                for (final s in m.symbols)
                  if (s case Note(:final tuplet?) || Rest(:final tuplet?))
                    tuplet.actual,
          ].fold(1, (a, b) => a * b ~/ a.gcd(b)) {
    final live = SpannerIndex(score).live;
    // Overlapping slurs need different numbers; a number is free again once
    // its slur has ended.
    final active = <(int, NotePosition)>[];
    final slurs = [
      for (final s in live)
        if (s.$1.kind == SpannerKind.slur) s,
    ]..sort((a, b) => _compare(a.$2, b.$2));
    for (final (spanner, _, _) in live) {
      if (spanner.kind == SpannerKind.tie) {
        tieStarts.add(spanner.from);
        tieStops.add(spanner.to);
      }
    }
    for (final (spanner, from, to) in slurs) {
      active.removeWhere((a) => _compare(a.$2, from) < 0);
      var number = 1;
      while (active.any((a) => a.$1 == number)) {
        number++;
      }
      active.add((number, to));
      this.slurs.putIfAbsent(spanner.from, () => []).add(('start', number));
      this.slurs.putIfAbsent(spanner.to, () => []).add(('stop', number));
    }
    // A hairpin's stop goes after its last note, as MuseScore writes it.
    final hairpins = [
      for (final s in live)
        if (s.$1.kind == SpannerKind.crescendo ||
            s.$1.kind == SpannerKind.diminuendo)
          s,
    ]..sort((a, b) => _compare(a.$2, b.$2));
    final open = <(int, NotePosition)>[];
    for (final (spanner, from, to) in hairpins) {
      open.removeWhere((a) => _compare(a.$2, from) < 0);
      var number = 1;
      while (open.any((a) => a.$1 == number)) {
        number++;
      }
      open.add((number, to));
      wedgeStarts.putIfAbsent(spanner.from, () => []).add((
        spanner.kind == SpannerKind.crescendo ? 'crescendo' : 'diminuendo',
        number,
      ));
      wedgeStops.putIfAbsent(spanner.to, () => []).add(number);
    }
  }

  final wedgeStarts = <String, List<(String, int)>>{};
  final wedgeStops = <String, List<int>>{};

  static int _compare(NotePosition a, NotePosition b) =>
      a.part != b.part
      ? a.part - b.part
      : a.measure != b.measure
      ? a.measure - b.measure
      : a.symbol - b.symbol;

  /// `<divisions>` per quarter: whole numbers for every tuplet in the score.
  final int divisions;

  /// A note or rest's `<duration>`.
  int duration(ScoreSymbol symbol) =>
      (symbolQuarters(symbol) * divisions).round();

  final tieStarts = <String>{};
  final tieStops = <String>{};
  final slurs = <String, List<(String, int)>>{};
}
