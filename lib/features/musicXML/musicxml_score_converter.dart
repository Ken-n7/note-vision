import 'dart:convert';

import 'package:note_vision/core/models/barline_type.dart';
import 'package:note_vision/core/models/musicxml_source.dart';
import 'package:note_vision/core/models/clef.dart';
import 'package:note_vision/core/models/key_signature.dart';
import 'package:note_vision/core/models/measure.dart';
import 'package:note_vision/core/models/note.dart';
import 'package:note_vision/core/models/note_value.dart';
import 'package:note_vision/core/models/part.dart';
import 'package:note_vision/core/models/rest.dart';
import 'package:note_vision/core/models/score.dart';
import 'package:note_vision/core/models/score_symbol.dart';
import 'package:note_vision/core/models/time_signature.dart';
import 'package:note_vision/core/services/accidentals.dart';
import 'package:note_vision/core/services/notation_review_service.dart';
import 'package:xml/xml.dart';

import 'musicxml_source_reader.dart';

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
    final parts = root.name.local == 'score-timewise'
        ? _buildTimewiseParts(root, partNamesById, sourceIndexes)
        : _buildPartwiseParts(root, partNamesById, sourceIndexes);

    final score = NotationReviewService.ensureIdentity(
      Score(
        id: root.getAttribute('id') ?? root.name.local,
        title: title,
        composer: composer,
        // <alter> is the pitch heard; notes store the accidental written.
        parts: parts.map(Accidentals.writtenFromSounding).toList(),
      ),
    );
    final bindings = <MusicXmlSymbolBinding>[];
    final representedDurations = <String, double>{};
    for (final part in score.parts) {
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
              partId: part.id,
              measureIndex: measureIndex,
              noteIndex: indexes[symbolIndex],
            ),
          );
          final (type, dots, duration) = switch (symbol) {
            Note(:final type, :final dots, :final duration) ||
            Rest(
              :final type,
              :final dots,
              :final duration,
            ) => (type, dots, duration),
            _ => throw StateError('Unexpected imported symbol'),
          };
          representedDurations['${part.id}:$measureIndex:${indexes[symbolIndex]}'] =
              quarterLength(type, dots, duration);
        }
      }
    }
    return score.copyWith(
      musicXmlSource: MusicXmlSource(
        xml: document.toXmlString(),
        baselineJson: jsonEncode(score.notationProjection()),
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
      leftBarlineType: leftBarlineType,
      rightBarlineType: rightBarlineType,
    );
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
    final rawDuration = double.tryParse(
      _firstInnerText(noteElement, 'duration') ?? '',
    );
    final duration = rawDuration == null
        ? null
        : (rawDuration * 2 / divisionsPerQuarter).round();
    var type = _firstInnerText(noteElement, 'type')?.trim();
    var dots = noteElement.findElements('dot').length;
    if (duration == null) return null;

    // A whole-bar rest (<rest measure="yes"/>) often has no <type>, or says
    // "whole" in any time signature; and some files leave <type> out. Take
    // the value from the duration then, so the bar keeps its length.
    final rest = _firstOrNull(noteElement.findElements('rest'));
    final isBarRest = rest?.getAttribute('measure') == 'yes';
    if (type == null || type.isEmpty || isBarRest) {
      final value = _valueForQuarters(rawDuration! / divisionsPerQuarter);
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

    if (noteElement.findElements('rest').isNotEmpty) {
      return Rest(
        duration: duration,
        type: type,
        voice: voice,
        staff: staff,
        dots: dots,
      );
    }

    final pitch = _firstOrNull(noteElement.findElements('pitch'));
    if (pitch == null) {
      return null;
    }

    final step = _firstInnerText(pitch, 'step')?.trim();
    final octave = int.tryParse(_firstInnerText(pitch, 'octave') ?? '');
    final alter = int.tryParse(_firstInnerText(pitch, 'alter') ?? '');

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
      dots: dots,
      isChordTone: isChordTone,
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

  /// The written value (type and dots) that lasts [quarters] quarter notes,
  /// or null when no single note value does.
  (String, int)? _valueForQuarters(double quarters) {
    for (final type in const [
      'whole',
      'half',
      'quarter',
      'eighth',
      'sixteenth',
    ]) {
      for (var dots = 0; dots <= 2; dots++) {
        if ((quarterLength(type, dots, 0) - quarters).abs() < 1e-6) {
          return (type, dots);
        }
      }
    }
    return null;
  }

  Clef? _buildClef(XmlElement? attributes) {
    final clefElement = attributes == null
        ? null
        : _firstOrNull(attributes.findElements('clef'));
    if (clefElement == null) {
      return null;
    }

    final sign = _firstInnerText(clefElement, 'sign')?.trim();
    final line = int.tryParse(_firstInnerText(clefElement, 'line') ?? '');
    if (sign == null || sign.isEmpty || line == null) {
      return null;
    }

    return Clef(sign: sign, line: line);
  }

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

    return TimeSignature(beats: beats, beatType: beatType);
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
