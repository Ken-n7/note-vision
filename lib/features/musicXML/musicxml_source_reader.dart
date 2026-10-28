import 'package:xml/xml.dart';

import '../../core/models/musical_time.dart';
import '../../core/models/musicxml_source.dart';
import '../../core/models/note_beam.dart';

/// The same part-local source addressing works for partwise and timewise files.
Map<String, List<XmlElement>> musicXmlSourceParts(XmlElement root) {
  final parts = <String, List<XmlElement>>{};
  if (root.name.local == 'score-partwise') {
    for (final part in root.findElements('part')) {
      final id = part.getAttribute('id') ?? 'unknown-part';
      if (parts.containsKey(id)) {
        throw FormatException('Duplicate part id: $id');
      }
      parts[id] = part.findElements('measure').toList();
    }
  } else {
    for (final measure in root.findElements('measure')) {
      for (final part in measure.findElements('part')) {
        final id = part.getAttribute('id') ?? 'unknown-part';
        parts.putIfAbsent(id, () => []).add(part);
      }
    }
  }
  return parts;
}

class MusicXmlSourceReader {
  const MusicXmlSourceReader();

  /// Walk document order, honoring cursor movements and inherited divisions.
  List<SourceScoreEvent> readTimeline(XmlDocument document) {
    final events = <SourceScoreEvent>[];
    for (final part in musicXmlSourceParts(document.rootElement).entries) {
      var divisions = MusicalTime(2);
      for (final (measureIndex, measure) in part.value.indexed) {
        var cursor = MusicalTime.zero;
        MusicalTime? previousOnset;
        var noteIndex = 0;
        for (final child in measure.childElements) {
          switch (child.name.local) {
            case 'attributes':
              final value = child.getElement('divisions')?.innerText;
              if (value != null) divisions = _positive(value, 'divisions');
            case 'backup':
            case 'forward':
              final amount =
                  _positive(
                    child.getElement('duration')?.innerText,
                    child.name.local,
                  ) /
                  divisions;
              cursor = child.name.local == 'backup'
                  ? cursor - amount
                  : cursor + amount;
              if (cursor.isNegative) {
                throw const FormatException(
                  'MusicXML backup precedes the start of its measure',
                );
              }
              previousOnset = null;
            case 'note':
              final grace = child.getElement('grace') != null;
              final chord = child.getElement('chord') != null;
              if (chord && previousOnset == null) {
                throw const FormatException(
                  'MusicXML chord has no preceding note',
                );
              }
              final duration = grace
                  ? MusicalTime.zero
                  : _positive(
                          child.getElement('duration')?.innerText,
                          'note duration',
                        ) /
                        divisions;
              final onset = chord ? previousOnset! : cursor;
              events.add(
                SourceScoreEvent(
                  partId: part.key,
                  measureIndex: measureIndex,
                  noteIndex: noteIndex++,
                  onset: onset,
                  duration: duration,
                  voice: child.getElement('voice')?.innerText.trim() ?? '1',
                  staff:
                      int.tryParse(
                        child.getElement('staff')?.innerText ?? '',
                      ) ??
                      1,
                  isRest: child.getElement('rest') != null,
                  isGrace: grace,
                  isChordTone: chord,
                ),
              );
              previousOnset = onset;
              if (!chord && !grace) cursor = cursor + duration;
          }
        }
      }
    }
    return List.unmodifiable(events);
  }

  MusicalTime _positive(String? value, String name) {
    if (value == null) throw FormatException('Missing MusicXML $name');
    final time = MusicalTime.decimal(value);
    if (time.isNegative || time.isZero) {
      throw FormatException('MusicXML $name must be positive');
    }
    return time;
  }

  /// Generated export can replace the source only when all its contents are
  /// represented by the legacy model. Layout and extra attributes count too.
  bool requiresPreservation(XmlDocument document) {
    final root = document.rootElement;
    if (root.getElement('movement-title') != null &&
        root.getElement('work')?.getElement('work-title') != null) {
      return true;
    }
    if (root.name.local == 'score-timewise' &&
        musicXmlSourceParts(root).values.any(
          (measures) => measures.length != root.findElements('measure').length,
        )) {
      return true;
    }
    const modeled = {
      'score-partwise',
      'score-timewise',
      'work',
      'work-title',
      'movement-title',
      'identification',
      'creator',
      'encoding',
      'software',
      'encoding-date',
      'part-list',
      'score-part',
      'part-name',
      'part',
      'measure',
      'attributes',
      'divisions',
      'key',
      'fifths',
      'time',
      'beats',
      'beat-type',
      'clef',
      'sign',
      'line',
      'print',
      'note',
      'pitch',
      'step',
      'alter',
      'octave',
      'rest',
      'duration',
      'voice',
      'type',
      'dot',
      'staff',
      'chord',
      'beam',
      'barline',
      'bar-style',
      'repeat',
    };
    const attributes = {
      'score-partwise': {'version', 'id'},
      'score-timewise': {'version', 'id'},
      'creator': {'type'},
      'score-part': {'id'},
      'part': {'id'},
      'measure': {'number'},
      'print': {'new-page', 'new-system'},
      'beam': {'number'},
      'barline': {'location'},
      'repeat': {'direction'},
    };
    for (final element in document.descendants.whereType<XmlElement>()) {
      final name = element.name.local;
      // Pitched-note lyrics retain their complete XML in the note model, so
      // rich lyric formatting is also safe when a rhythm edit rebuilds a file.
      final lyric = name == 'lyric'
          ? element
          : element.ancestors
                .whereType<XmlElement>()
                .where((e) => e.name.local == 'lyric')
                .firstOrNull;
      if (lyric?.parentElement?.getElement('pitch') != null) continue;
      if (!modeled.contains(name)) return true;
      if (name == 'attributes' &&
          (element.findElements('clef').length > 1 ||
              (element.parentElement?.findElements('attributes').length ?? 0) >
                  1)) {
        return true;
      }
      if (element.attributes.any(
        (a) =>
            !(attributes[name] ?? const <String>{}).contains(a.name.qualified),
      )) {
        return true;
      }
      if (name == 'creator' && element.getAttribute('type') != 'composer') {
        return true;
      }
      if ({
            'alter',
            'voice',
            'fifths',
            'beats',
            'beat-type',
            'staff',
            'line',
          }.contains(name) &&
          int.tryParse(element.innerText.trim()) == null) {
        return true;
      }
      if (name == 'barline') {
        final repeat = element.getElement('repeat');
        final expectedStyle = repeat?.getAttribute('direction') == 'forward'
            ? 'heavy-light'
            : 'light-heavy';
        if (repeat == null ||
            !{'left', 'right'}.contains(element.getAttribute('location')) ||
            element.getElement('bar-style')?.innerText != expectedStyle) {
          return true;
        }
      }
      if (name == 'repeat' &&
          !{
            'forward',
            'backward',
          }.contains(element.getAttribute('direction'))) {
        return true;
      }
      if (name == 'beam' &&
          (BeamValue.parse(element.innerText) == null ||
              (int.tryParse(element.getAttribute('number') ?? '1') ?? 0) < 1 ||
              (int.tryParse(element.getAttribute('number') ?? '1') ?? 0) > 8)) {
        return true;
      }
      if (name == 'clef' &&
          !['G', 'F', 'C'].contains(element.getElement('sign')?.innerText)) {
        return true;
      }
      if (name == 'type' &&
          ![
            'whole',
            'half',
            'quarter',
            'eighth',
            '16th',
            'sixteenth',
            '32nd',
            'breve',
          ].contains(element.innerText)) {
        return true;
      }
    }
    if (document
            .findAllElements('creator')
            .where((e) => e.getAttribute('type') == 'composer')
            .length >
        1) {
      return true;
    }
    return false;
  }
}
