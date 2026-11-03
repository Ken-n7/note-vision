import 'dart:math' as math;
import 'dart:convert';

import 'package:note_vision/core/models/barline_type.dart';
import 'package:note_vision/core/models/musicxml_source.dart';
import 'package:note_vision/core/models/clef.dart';
import 'package:note_vision/core/models/key_signature.dart';
import 'package:note_vision/core/models/measure.dart';
import 'package:note_vision/core/models/navigation_mark.dart';
import 'package:note_vision/core/models/drum_kit.dart';
import 'package:note_vision/core/models/note.dart';
import 'package:note_vision/core/models/note_value.dart';
import 'package:note_vision/core/models/part.dart';
import 'package:note_vision/core/models/rest.dart';
import 'package:note_vision/core/models/score.dart';
import 'package:note_vision/core/models/score_symbol.dart';
import 'package:note_vision/core/models/time_signature.dart';
import 'package:note_vision/core/services/accidentals.dart';
import 'package:note_vision/core/services/notation_review_service.dart';
import 'package:note_vision/core/services/score_timeline.dart';
import 'package:note_vision/core/services/spanners.dart';
import 'package:xml/xml.dart';

import 'musicxml_source_reader.dart';
import 'musicxml_instruments.dart';
import 'musicxml_lyrics.dart';
import 'musicxml_annotations.dart';

/// Converts a validated MusicXML document into internal score models.
class MusicXmlScoreConverter {
  const MusicXmlScoreConverter();

  Score convert(XmlDocument document) {
    final root = document.rootElement;

    final title = _readTitle(root);
    final composer = _readComposer(root);
    final partNamesById = _readPartNames(root);
    final sourceIndexes = <String, List<List<int>>>{};
    const reader = MusicXmlSourceReader();
    final events = reader.readTimeline(document);
    final sourcePartIds = <String, String>{};
    final parts = _splitStaves(
      root.name.local == 'score-timewise'
          ? _buildTimewiseParts(root, partNamesById, sourceIndexes)
          : _buildPartwiseParts(root, partNamesById, sourceIndexes),
      root,
      sourceIndexes,
      sourcePartIds,
    );

    final score = NotationReviewService.ensureIdentity(
      Score(
        id: root.getAttribute('id') ?? root.name.local,
        title: title,
        composer: composer,
        // <alter> is the pitch heard; notes store the accidental written.
        parts: parts.map((part) {
          final sourceId = sourcePartIds[part.id] ?? part.id;
          final declaration = root
              .getElement('part-list')
              ?.findElements('score-part')
              .where((e) => e.getAttribute('id') == sourceId)
              .firstOrNull;
          // A transposing part's first <transpose>: notes stay as written.
          final transpose = root
              .findAllElements('part')
              .where((e) => e.getAttribute('id') == sourceId)
              .expand((e) => e.findAllElements('transpose'))
              .firstOrNull;
          int read(String name) =>
              int.tryParse(_firstInnerText(transpose, name)?.trim() ?? '') ??
              0;
          return Accidentals.writtenFromSounding(
            part.copyWith(
              playback: MusicXmlInstruments.read(declaration),
              transposition: transpose == null
                  ? null
                  : Transposition(
                      diatonic: read('diatonic'),
                      chromatic: read('chromatic'),
                      octave: read('octave-change'),
                    ),
            ),
          );
        }).toList(),
      ),
    );
    final bindings = <MusicXmlSymbolBinding>[];
    final representedDurations = <String, double>{};
    for (final part in score.parts) {
      final sourcePartId = sourcePartIds[part.id] ?? part.id;
      for (final (measureIndex, measure) in part.measures.indexed) {
        final indexes = sourceIndexes[part.id]![measureIndex];
        for (final (symbolIndex, symbol) in measure.symbols.indexed) {
          final id = switch (symbol) {
            Note(:final reviewId) || Rest(:final reviewId) => reviewId!,
            _ => throw StateError('Unexpected imported symbol'),
          };
          bindings.add(
            MusicXmlSymbolBinding(
              symbolId: id,
              partId: sourcePartId,
              measureIndex: measureIndex,
              noteIndex: indexes[symbolIndex],
            ),
          );
          representedDurations['$sourcePartId:$measureIndex:${indexes[symbolIndex]}'] =
              symbolQuarters(symbol);
        }
      }
    }
    final dynamics = <String, String>{};
    final notated = _withDynamics(
      score.copyWith(spanners: _readSpanners(root, score, bindings, dynamics)),
      dynamics,
    );
    return notated.copyWith(
      musicXmlSource: MusicXmlSource(
        xml: document.toXmlString(),
        baselineJson: jsonEncode(notated.notationProjection()),
        bindings: bindings,
        events: events,
        requiresPreservation:
            reader.requiresPreservation(document) ||
            events.length != bindings.length ||
            events.any(
              (e) =>
                  ((representedDurations['${e.partId}:${e.measureIndex}:${e.noteIndex}'] ??
                              -1) -
                          e.duration.asDouble)
                      .abs() >
                  1e-10,
            ),
      ),
    );
  }

  /// Ties and slurs between imported notes. Slurs pair by `number` within a
  /// `<part>`; a tie joins the next note in the same voice with the same
  /// pitch that ends a tie.
  ///
  /// Dynamics and hairpins come from `<direction>`s: a dynamic belongs to the
  /// next note or rest on its staff (collected in [dynamics] by review ID); a
  /// hairpin runs from the next note after its start to the last one before
  /// its stop.
  List<Spanner> _readSpanners(
    XmlElement root,
    Score score,
    List<MusicXmlSymbolBinding> bindings,
    Map<String, String> dynamics,
  ) {
    final ids = {
      for (final b in bindings)
        (b.partId, b.measureIndex, b.noteIndex): b.symbolId,
    };
    bool tie(XmlElement note, String type) =>
        note.findElements('tie').any((t) => t.getAttribute('type') == type) ||
        note
            .findElements('notations')
            .expand((n) => n.findElements('tied'))
            .any((t) => t.getAttribute('type') == type);
    final spanners = <Spanner>[];
    final tieStarts = <String>[];
    final tieStops = <String>{};
    for (final MapEntry(key: partId, value: measures) in musicXmlSourceParts(
      root,
    ).entries) {
      final open = <String, String>{};
      final pendingDynamic = <int, String>{};
      final pendingWedges = <int, List<(SpannerKind, String)>>{};
      final openWedges = <String, (SpannerKind, String)>{};
      final lastId = <int, String>{};
      int staffOf(XmlElement e) =>
          int.tryParse(_firstInnerText(e, 'staff') ?? '') ?? 1;
      for (final (m, measure) in measures.indexed) {
        var n = -1;
        for (final element in measure.childElements) {
          if (element.name.local == 'direction') {
            final staff = staffOf(element);
            for (final type in element.findElements('direction-type')) {
              for (final dynamics in type.findElements('dynamics')) {
                final name = dynamics.childElements.firstOrNull?.name.local;
                if (name != null) pendingDynamic[staff] = name;
              }
              for (final wedge in type.findElements('wedge')) {
                final number = wedge.getAttribute('number') ?? '1';
                final kind = switch (wedge.getAttribute('type')) {
                  'crescendo' => SpannerKind.crescendo,
                  'diminuendo' => SpannerKind.diminuendo,
                  _ => null,
                };
                if (kind != null) {
                  pendingWedges.putIfAbsent(staff, () => []).add((
                    kind,
                    number,
                  ));
                } else if (wedge.getAttribute('type') == 'stop') {
                  final start = openWedges.remove(number);
                  final end = lastId[staff];
                  if (start != null && end != null) {
                    spanners.add(Spanner(start.$1, start.$2, end));
                  }
                }
              }
            }
            continue;
          }
          if (element.name.local != 'note') continue;
          n++;
          final note = element;
          final id = ids[(partId, m, n)];
          if (id == null) continue;
          final staff = staffOf(note);
          if (note.findElements('chord').isEmpty) {
            if (pendingDynamic.remove(staff) case final name?) {
              dynamics[id] = name;
            }
            for (final (kind, number)
                in pendingWedges.remove(staff) ?? <(SpannerKind, String)>[]) {
              openWedges[number] = (kind, id);
            }
            lastId[staff] = id;
          }
          if (tie(note, 'start')) tieStarts.add(id);
          if (tie(note, 'stop')) tieStops.add(id);
          final slurs = note
              .findElements('notations')
              .expand((x) => x.findElements('slur'))
              .toList();
          // A note can end one slur and start the next.
          for (final type in ['stop', 'start']) {
            for (final slur in slurs) {
              if (slur.getAttribute('type') != type) continue;
              final number = slur.getAttribute('number') ?? '1';
              if (type == 'start') {
                open[number] = id;
              } else if (open.remove(number) case final start?
                  when start != id) {
                spanners.add(Spanner(SpannerKind.slur, start, id));
              }
            }
          }
        }
      }
    }
    final index = SpannerIndex(score);
    for (final id in tieStarts) {
      final from = index.notes[id]!;
      final start = index.noteAt(from)!;
      final lane = ScoreTimelineBuilder.lane(start);
      final measures = score.parts[from.part].measures;
      String? target;
      search:
      for (var m = from.measure; m < measures.length; m++) {
        for (final (i, symbol) in measures[m].symbols.indexed) {
          if (m == from.measure && i <= from.symbol) continue;
          if (symbol is Note &&
              tieStops.contains(symbol.reviewId) &&
              ScoreTimelineBuilder.lane(symbol) == lane &&
              (symbol.step, symbol.octave) == (start.step, start.octave)) {
            target = symbol.reviewId;
            break search;
          }
        }
      }
      if (target != null) spanners.add(Spanner(SpannerKind.tie, id, target));
    }
    return spanners;
  }

  static Score _withDynamics(Score score, Map<String, String> dynamics) =>
      dynamics.isEmpty
      ? score
      : score.copyWith(
          parts: [
            for (final part in score.parts)
              part.copyWith(
                measures: [
                  for (final m in part.measures)
                    m.withContent(
                      keySignature: m.keySignature,
                      symbols: [
                        for (final s in m.symbols)
                          switch (s) {
                            Note(:final reviewId?)
                                when dynamics.containsKey(reviewId) =>
                              s.copyWith(dynamicMark: dynamics[reviewId]),
                            Rest(:final reviewId?)
                                when dynamics.containsKey(reviewId) =>
                              s.copyWith(dynamicMark: dynamics[reviewId]),
                            _ => s,
                          },
                      ],
                    ),
                ],
              ),
          ],
        );

  /// A part written on several staves (a piano) becomes one linked part per
  /// staff ([Part.staff]), so every editing tool works per staff. Symbols
  /// keep their staff and voice numbers; each staff takes its own clefs.
  /// [sourcePartIds] maps each new part to the `<part>` it came from.
  List<Part> _splitStaves(
    List<Part> parts,
    XmlElement root,
    Map<String, List<List<int>>> sourceIndexes,
    Map<String, String> sourcePartIds,
  ) {
    final sourceMeasures = musicXmlSourceParts(root);
    int staffOf(ScoreSymbol s) => switch (s) {
      Note(:final staff) || Rest(:final staff) => staff ?? 1,
      _ => 1,
    };
    final result = <Part>[];
    for (final part in parts) {
      final elements = sourceMeasures[part.id] ?? const <XmlElement>[];
      final declared = elements
          .expand((m) => m.findElements('attributes'))
          .expand((a) => a.findElements('staves'))
          .map((e) => int.tryParse(e.innerText.trim()) ?? 1)
          .fold(1, math.max);
      final count = part.measures
          .expand((m) => m.symbols)
          .map(staffOf)
          .fold(declared, math.max);
      if (count <= 1) {
        result.add(part);
        continue;
      }
      final indexes = sourceIndexes[part.id]!;
      for (var staff = 1; staff <= count; staff++) {
        final id = staff == 1 ? part.id : '${part.id}-staff$staff';
        sourcePartIds[id] = part.id;
        final staffIndexes = <List<int>>[];
        final measures = <Measure>[];
        for (final (i, m) in part.measures.indexed) {
          final keep = [
            for (final (k, symbol) in m.symbols.indexed)
              if (staffOf(symbol) == staff) k,
          ];
          staffIndexes.add([for (final k in keep) indexes[i][k]]);
          measures.add(
            m.copyWith(
              clef: i < elements.length ? _staffClef(elements[i], staff) : null,
              symbols: [for (final k in keep) m.symbols[k]],
              annotations: [
                for (final a in m.annotations)
                  if (a.staff == staff) a,
              ],
            ),
          );
        }
        sourceIndexes[id] = staffIndexes;
        result.add(part.copyWith(id: id, staff: staff, measures: measures));
      }
    }
    return result;
  }

  /// The first clef in [measure] for [staff]; an unnumbered clef is staff 1.
  Clef? _staffClef(XmlElement measure, int staff) {
    for (final attributes in measure.findElements('attributes')) {
      for (final clef in attributes.findElements('clef')) {
        if ((int.tryParse(clef.getAttribute('number') ?? '') ?? 1) != staff) {
          continue;
        }
        final sign = _firstInnerText(clef, 'sign')?.trim();
        final line =
            int.tryParse(_firstInnerText(clef, 'line') ?? '') ??
            (sign == 'percussion' ? 3 : null);
        if (sign != null && sign.isNotEmpty && line != null) {
          return Clef(sign: sign, line: line, octave: _clefOctave(clef));
        }
      }
    }
    return null;
  }

  List<Part> _buildPartwiseParts(
    XmlElement root,
    Map<String, String> partNamesById,
    Map<String, List<List<int>>> sourceIndexes,
  ) {
    return root.findElements('part').map((partElement) {
      final partId = partElement.getAttribute('id') ?? 'unknown-part';
      final partName = partNamesById[partId] ?? partId;
      final measures = _buildPartMeasures(
        partElement.findElements('measure'),
        sourceNoteIndexes: sourceIndexes.putIfAbsent(partId, () => []),
      );
      return Part(id: partId, name: partName, measures: measures);
    }).toList();
  }

  List<Measure> _buildPartMeasures(
    Iterable<XmlElement> measureElements, {
    int? explicitNumberOverride,
    required List<List<int>> sourceNoteIndexes,
  }) {
    var divisionsPerQuarter = 2.0;
    return measureElements.map((m) {
      final indexes = <int>[];
      sourceNoteIndexes.add(indexes);
      final measure = _buildMeasure(
        m,
        divisionsPerQuarter: divisionsPerQuarter,
        explicitNumber: explicitNumberOverride,
        sourceNoteIndexes: indexes,
      );
      divisionsPerQuarter = _endingDivisions(m, divisionsPerQuarter);
      return measure;
    }).toList();
  }

  List<Part> _buildTimewiseParts(
    XmlElement root,
    Map<String, String> partNamesById,
    Map<String, List<List<int>>> sourceIndexes,
  ) {
    final measuresByPartId = <String, List<Measure>>{};
    final divisionsPerQuarterByPartId = <String, double>{};

    for (final measureElement in root.findElements('measure')) {
      final measureNumber =
          int.tryParse(measureElement.getAttribute('number') ?? '') ?? 0;

      for (final partInMeasure in measureElement.findElements('part')) {
        final partId = partInMeasure.getAttribute('id') ?? 'unknown-part';
        final divisionsPerQuarter = divisionsPerQuarterByPartId[partId] ?? 2.0;
        final indexes = <int>[];
        sourceIndexes.putIfAbsent(partId, () => []).add(indexes);
        final rebuiltMeasure = _buildMeasure(
          partInMeasure,
          explicitNumber: measureNumber,
          divisionsPerQuarter: divisionsPerQuarter,
          sourceNoteIndexes: indexes,
        );
        divisionsPerQuarterByPartId[partId] = _endingDivisions(
          partInMeasure,
          divisionsPerQuarter,
        );
        measuresByPartId
            .putIfAbsent(partId, () => <Measure>[])
            .add(rebuiltMeasure);
      }
    }

    return measuresByPartId.entries.map((entry) {
      final partId = entry.key;
      final partName = partNamesById[partId] ?? partId;

      return Part(id: partId, name: partName, measures: entry.value);
    }).toList();
  }

  String _readTitle(XmlElement root) {
    final workElement = _firstOrNull(root.findElements('work'));
    final workTitle = _firstInnerText(workElement, 'work-title')?.trim();

    if (workTitle != null && workTitle.isNotEmpty) {
      return workTitle;
    }

    final movementTitle = _firstInnerText(root, 'movement-title')?.trim();
    if (movementTitle != null && movementTitle.isNotEmpty) {
      return movementTitle;
    }

    return 'Untitled';
  }

  String _readComposer(XmlElement root) {
    final identification = _firstOrNull(root.findElements('identification'));
    if (identification == null) {
      return '';
    }

    for (final creator in identification.findElements('creator')) {
      if (creator.getAttribute('type') == 'composer') {
        final value = creator.innerText.trim();
        if (value.isNotEmpty) {
          return value;
        }
      }
    }

    return '';
  }

  Map<String, String> _readPartNames(XmlElement root) {
    final partNamesById = <String, String>{};

    final partList = _firstOrNull(root.findElements('part-list'));
    if (partList == null) {
      return partNamesById;
    }

    for (final scorePart in partList.findElements('score-part')) {
      final id = scorePart.getAttribute('id');
      final partName = _firstInnerText(scorePart, 'part-name')?.trim();
      if (id != null &&
          id.isNotEmpty &&
          partName != null &&
          partName.isNotEmpty) {
        partNamesById[id] = partName;
      }
    }

    return partNamesById;
  }

  Measure _buildMeasure(
    XmlElement measureElement, {
    int? explicitNumber,
    double divisionsPerQuarter = 2,
    required List<int> sourceNoteIndexes,
  }) {
    final number =
        explicitNumber ??
        int.tryParse(measureElement.getAttribute('number') ?? '') ??
        0;

    final attributes = _firstOrNull(measureElement.findElements('attributes'));
    final clef = _buildClef(attributes);
    final timeSignature = _buildTimeSignature(attributes);
    final keySignature = _buildKeySignature(attributes);
    final leftBarlineType = _buildBarlineType(measureElement, 'left');
    final rightBarlineType = _buildBarlineType(measureElement, 'right');

    final annotations = MusicXmlAnnotations.readMeasure(
      measureElement,
      divisionsPerQuarter,
    );
    final symbols = <ScoreSymbol>[];

    var noteIndex = 0;
    for (final noteElement in measureElement.childElements) {
      if (noteElement.name.local == 'attributes') {
        divisionsPerQuarter = _endingDivisions(
          measureElement,
          divisionsPerQuarter,
          attributes: noteElement,
        );
      }
      if (noteElement.name.local != 'note') continue;
      final symbol = _buildSymbol(
        noteElement,
        divisionsPerQuarter: divisionsPerQuarter,
      );
      if (symbol != null) {
        symbols.add(symbol);
        sourceNoteIndexes.add(noteIndex);
      }
      noteIndex++;
    }

    final printEl = _firstOrNull(measureElement.findElements('print'));
    final startsNewPage = printEl?.getAttribute('new-page') == 'yes';
    final startsNewSystem = printEl?.getAttribute('new-system') == 'yes';

    return Measure(
      number: number,
      clef: clef,
      timeSignature: timeSignature,
      keySignature: keySignature,
      symbols: symbols,
      startsNewPage: startsNewPage,
      startsNewSystem: startsNewSystem,
      implicit: measureElement.getAttribute('implicit') == 'yes',
      leftBarlineType: leftBarlineType,
      rightBarlineType: rightBarlineType,
      endingStart: _endingStart(measureElement),
      endingEnd: _endingEnd(measureElement),
      navigation: _navigation(measureElement),
      annotations: annotations,
    );
  }

  /// The numbers of an `<ending type="start">` ("1, 2" is both).
  List<int> _endingStart(XmlElement measure) => [
    for (final barline in measure.findElements('barline'))
      for (final ending in barline.findElements('ending'))
        if (ending.getAttribute('type') == 'start')
          for (final n in (ending.getAttribute('number') ?? '').split(
            RegExp(r'[,\s]+'),
          ))
            ?int.tryParse(n),
  ];

  EndingEnd? _endingEnd(XmlElement measure) {
    for (final barline in measure.findElements('barline')) {
      for (final ending in barline.findElements('ending')) {
        switch (ending.getAttribute('type')) {
          case 'stop':
            return EndingEnd.closed;
          case 'discontinue':
            return EndingEnd.open;
        }
      }
    }
    return null;
  }

  /// Segno, coda, Fine, To Coda, D.C. and D.S.: from `<segno>`, `<coda>`
  /// and the `<sound>` that makes them play, or from their words.
  List<NavigationMark> _navigation(XmlElement measure) {
    final marks = <NavigationMark>{};
    for (final direction in measure.findElements('direction')) {
      final types = direction.findElements('direction-type');
      final sound = direction.getElement('sound');
      final words = types
          .expand((t) => t.findElements('words'))
          .map((w) => w.innerText.trim().toLowerCase())
          .join(' ');
      final alFine = words.contains('fine') && !words.startsWith('fine');
      final alCoda = words.contains('coda');
      // MusicXML 4 also writes them as <symbol>segno</symbol>.
      bool sign(String name) => types.any(
        (t) =>
            t.getElement(name) != null ||
            t.findElements('symbol').any((s) => s.innerText.trim() == name),
      );
      final toCoda =
          sound?.getAttribute('tocoda') != null || words.contains('to coda');
      if (sign('segno')) marks.add(NavigationMark.segno);
      if (sign('coda') && !toCoda) marks.add(NavigationMark.coda);
      if (toCoda) marks.add(NavigationMark.toCoda);
      // MuseScore 4.7 writes <sound fine="yes"/> beside every marker it
      // exports, so the sign or words decide.
      if (words == 'fine' ||
          (sound?.getAttribute('fine') != null &&
              !sign('segno') &&
              !sign('coda') &&
              !toCoda &&
              words.isEmpty)) {
        marks.add(NavigationMark.fine);
      }
      if (sound?.getAttribute('dacapo') == 'yes' || words.startsWith('d.c')) {
        marks.add(
          alFine
              ? NavigationMark.daCapoAlFine
              : alCoda
              ? NavigationMark.daCapoAlCoda
              : NavigationMark.daCapo,
        );
      }
      if (sound?.getAttribute('dalsegno') != null || words.startsWith('d.s')) {
        marks.add(
          alFine
              ? NavigationMark.dalSegnoAlFine
              : alCoda
              ? NavigationMark.dalSegnoAlCoda
              : NavigationMark.dalSegno,
        );
      }
    }
    return marks.toList()..sort((a, b) => a.index - b.index);
  }

  double _endingDivisions(
    XmlElement measure,
    double current, {
    XmlElement? attributes,
  }) {
    for (final attrs
        in attributes == null
            ? measure.findElements('attributes')
            : [attributes]) {
      final value = double.tryParse(
        attrs.getElement('divisions')?.innerText ?? '',
      );
      if (value != null) current = value;
    }
    return current;
  }

  ScoreSymbol? _buildSymbol(
    XmlElement noteElement, {
    double divisionsPerQuarter = 2,
  }) {
    // A grace note has no <duration>: it takes no time in the bar.
    final graceElement = _firstOrNull(noteElement.findElements('grace'));
    final grace = graceElement == null
        ? null
        : graceElement.getAttribute('slash') == 'yes'
        ? Grace.acciaccatura
        : Grace.appoggiatura;
    final rawDuration = grace != null
        ? 0.0
        : double.tryParse(_firstInnerText(noteElement, 'duration') ?? '');
    final duration = rawDuration == null
        ? null
        : (rawDuration * 2 / divisionsPerQuarter).round();
    var type = _firstInnerText(noteElement, 'type')?.trim();
    if (grace != null && (type == null || type.isEmpty)) type = 'eighth';
    var dots = noteElement.findElements('dot').length;
    if (duration == null) return null;

    // A whole-bar rest (<rest measure="yes"/>) often has no <type>, or says
    // "whole" in any time signature; and some files leave <type> out. Take
    // the value from the duration then, so the bar keeps its length.
    final rest = _firstOrNull(noteElement.findElements('rest'));
    final isBarRest = rest?.getAttribute('measure') == 'yes';
    if (type == null || type.isEmpty || isBarRest) {
      final value = valueForQuarters(rawDuration! / divisionsPerQuarter);
      if (value != null) {
        (type, dots) = value;
      } else if (isBarRest || rest != null) {
        (type, dots) = ('whole', 0);
      } else {
        return null;
      }
    }
    // The app calls a sixteenth 'sixteenth', as scans do; export writes 16th.
    if (type.toLowerCase() == '16th') type = 'sixteenth';

    final voice = int.tryParse(_firstInnerText(noteElement, 'voice') ?? '');
    final staff = int.tryParse(_firstInnerText(noteElement, 'staff') ?? '');
    final isChordTone = noteElement.findElements('chord').isNotEmpty;
    final tuplet = _readTuplet(noteElement);
    final marks = _readMarks(noteElement);

    if (noteElement.findElements('rest').isNotEmpty) {
      return Rest(
        duration: duration,
        type: type,
        voice: voice,
        staff: staff,
        dots: dots,
        tuplet: tuplet,
        marks: marks,
        measureRest: isBarRest,
      );
    }

    // A drum note is written at a display position and sounds its kit
    // piece.
    final unpitched = _firstOrNull(noteElement.findElements('unpitched'));
    final pitch =
        unpitched ?? _firstOrNull(noteElement.findElements('pitch'));
    if (pitch == null) {
      return null;
    }

    final prefix = unpitched == null ? '' : 'display-';
    final step = _firstInnerText(pitch, '${prefix}step')?.trim();
    final octave = int.tryParse(
      _firstInnerText(pitch, '${prefix}octave') ?? '',
    );
    final alter = unpitched == null
        ? int.tryParse(_firstInnerText(pitch, 'alter') ?? '')
        : null;
    final head = _firstInnerText(noteElement, 'notehead')?.trim();
    final notehead = head == null || head == 'normal' ? null : head;

    if (step == null || step.isEmpty || octave == null) {
      return null;
    }

    return Note(
      step: step,
      octave: octave,
      alter: alter,
      duration: duration,
      type: type,
      voice: voice,
      staff: staff,
      beamed: noteElement.findElements('beam').isNotEmpty,
      beams: _readBeams(noteElement),
      lyrics: noteElement
          .findElements('lyric')
          .map(MusicXmlLyrics.read)
          .toList(),
      dots: dots,
      isChordTone: isChordTone,
      tuplet: tuplet,
      marks: marks,
      grace: grace,
      notehead: notehead,
      drum: unpitched == null
          ? null
          : _drumKey(noteElement, step, octave, notehead),
    );
  }

  /// A drum note's General MIDI key: its instrument's `<midi-unpitched>`
  /// (1-based), else the kit piece written at its position.
  int? _drumKey(XmlElement note, String step, int octave, String? head) {
    final id = note.getElement('instrument')?.getAttribute('id');
    final declared = note.root
        .findAllElements('midi-instrument')
        .where((m) => m.getAttribute('id') == id)
        .map((m) => int.tryParse(_firstInnerText(m, 'midi-unpitched') ?? ''))
        .nonNulls
        .firstOrNull;
    if (declared != null) return declared - 1;
    final here = drumKit.where((d) => d.step == step && d.octave == octave);
    return (here.where((d) => d.notehead == head).firstOrNull ??
            here.firstOrNull)
        ?.key;
  }

  /// Articulations, ornaments and fermatas the app knows, in the editor's
  /// order; others stay only in the retained source.
  List<Articulation> _readMarks(XmlElement note) => {
    for (final notations in note.findElements('notations'))
      for (final child in notations.childElements)
        if (child.name.local == 'fermata')
          Articulation.fermata
        else if (child.name.local == 'articulations' ||
            child.name.local == 'ornaments')
          for (final mark in child.childElements)
            ?Articulation.fromXml(mark.name.local),
  }.toList()..sort((a, b) => a.index - b.index);

  /// `<time-modification>` gives the ratio; `<tuplet>` notations mark the
  /// first and last notes of the bracket.
  Tuplet? _readTuplet(XmlElement note) {
    final mod = _firstOrNull(note.findElements('time-modification'));
    if (mod == null) return null;
    final actual = int.tryParse(_firstInnerText(mod, 'actual-notes') ?? '');
    final normal = int.tryParse(_firstInnerText(mod, 'normal-notes') ?? '');
    if (actual == null || normal == null || actual <= 0 || normal <= 0) {
      return null;
    }
    final marks = note
        .findElements('notations')
        .expand((n) => n.findElements('tuplet'))
        .map((t) => t.getAttribute('type'))
        .toSet();
    return Tuplet(
      actual,
      normal,
      start: marks.contains('start'),
      stop: marks.contains('stop'),
    );
  }

  Map<int, BeamValue> _readBeams(XmlElement note) {
    final values = <int, BeamValue>{};
    for (final beam in note.findElements('beam')) {
      final level = int.tryParse(beam.getAttribute('number') ?? '1');
      final value = BeamValue.parse(beam.innerText);
      if (level != null && level >= 1 && level <= 8 && value != null) {
        values[level] = value;
      }
    }
    return Map.unmodifiable(values);
  }

  Clef? _buildClef(XmlElement? attributes) {
    final clefElement = attributes == null
        ? null
        : _firstOrNull(attributes.findElements('clef'));
    if (clefElement == null) {
      return null;
    }

    final sign = _firstInnerText(clefElement, 'sign')?.trim();
    final line =
        int.tryParse(_firstInnerText(clefElement, 'line') ?? '') ??
        (sign == 'percussion' ? 3 : null);
    if (sign == null || sign.isEmpty || line == null) {
      return null;
    }

    return Clef(sign: sign, line: line, octave: _clefOctave(clefElement));
  }

  int _clefOctave(XmlElement clef) =>
      int.tryParse(_firstInnerText(clef, 'clef-octave-change') ?? '') ?? 0;

  TimeSignature? _buildTimeSignature(XmlElement? attributes) {
    final timeElement = attributes == null
        ? null
        : _firstOrNull(attributes.findElements('time'));
    if (timeElement == null) {
      return null;
    }

    final beats = int.tryParse(_firstInnerText(timeElement, 'beats') ?? '');
    final beatType = int.tryParse(
      _firstInnerText(timeElement, 'beat-type') ?? '',
    );
    if (beats == null || beatType == null) {
      return null;
    }

    return TimeSignature(
      beats: beats,
      beatType: beatType,
      symbol: TimeSymbol.values
          .where((s) => s.name == timeElement.getAttribute('symbol'))
          .firstOrNull,
    );
  }

  KeySignature? _buildKeySignature(XmlElement? attributes) {
    final keyElement = attributes == null
        ? null
        : _firstOrNull(attributes.findElements('key'));
    if (keyElement == null) {
      return null;
    }

    final fifths = int.tryParse(_firstInnerText(keyElement, 'fifths') ?? '');
    if (fifths == null) {
      return null;
    }

    return KeySignature(fifths: fifths);
  }

  BarlineType? _buildBarlineType(XmlElement measureElement, String location) {
    for (final barline in measureElement.findElements('barline')) {
      final barlineLocation =
          barline.getAttribute('location')?.trim() ?? 'right';
      if (barlineLocation != location) {
        continue;
      }

      final repeat = _firstOrNull(barline.findElements('repeat'));
      final direction = repeat?.getAttribute('direction')?.trim();
      if (direction == 'forward') {
        return BarlineType.repeatStart;
      }
      if (direction == 'backward') {
        return BarlineType.repeatEnd;
      }
      switch (_firstInnerText(barline, 'bar-style')?.trim()) {
        case 'light-heavy':
          return BarlineType.finalBar;
        case 'light-light':
          return BarlineType.doubleBar;
      }
    }

    return null;
  }

  XmlElement? _firstOrNull(Iterable<XmlElement> elements) {
    return elements.isEmpty ? null : elements.first;
  }

  String? _firstInnerText(XmlElement? parent, String tagName) {
    if (parent == null) {
      return null;
    }
    final child = _firstOrNull(parent.findElements(tagName));
    return child?.innerText;
  }
}
