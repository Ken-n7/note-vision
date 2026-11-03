import 'package:flutter/foundation.dart' show setEquals;
import 'dart:convert';

import 'package:xml/xml.dart';

import '../../core/models/note.dart';
import '../../core/models/beam_grouping.dart';
import '../../core/models/rest.dart';
import '../../core/models/score.dart';
import '../../core/models/score_symbol.dart';
import '../../core/services/accidentals.dart';
import 'musicxml_source_reader.dart';
import 'musicxml_instruments.dart';
import 'musicxml_lyrics.dart';
import 'musicxml_annotations.dart';
import '../../core/models/musical_time.dart';
import '../../core/models/score_annotation.dart';

class MusicXmlPreservationException implements Exception {
  const MusicXmlPreservationException([
    this.message =
        'MusicXML export cannot preserve this score after rhythm or structure changes yet. '
        'Undo those changes to export. Saving the project keeps the original notation.',
  ]);
  final String message;
  @override
  String toString() => message;
}

/// Patch supported changes into a copy of the original XML. Unknown notation,
/// source divisions, voices, layout and metadata remain in their original order.
/// A null result permits generated export for fully represented simple scores.
class MusicXmlPreservingExporter {
  const MusicXmlPreservingExporter();

  String? export(Score score) {
    final source = score.musicXmlSource;
    if (source == null) return null;
    final document = XmlDocument.parse(source.xml);
    // exportToDevice writes UTF-8 bytes even when the source was UTF-16/Latin-1.
    for (final declaration in document.children.whereType<XmlDeclaration>()) {
      if (declaration.encoding != null) declaration.encoding = 'UTF-8';
    }
    if (jsonEncode(score.notationProjection()) == source.baselineJson) {
      return document.toXmlString();
    }
    final baseline = Score.fromJson(
      jsonDecode(source.baselineJson) as Map<String, dynamic>,
    );
    if (!_canPatch(baseline, score)) {
      if (source.requiresPreservation) {
        throw const MusicXmlPreservationException();
      }
      return null;
    }
    final root = document.rootElement;
    final parts = musicXmlSourceParts(root);
    final sourceNotes = <String, XmlElement>{};
    for (final binding in source.bindings) {
      final measures = parts[binding.partId];
      if (measures == null || binding.measureIndex >= measures.length) {
        throw const FormatException(
          'Invalid retained MusicXML measure binding',
        );
      }
      final notes = measures[binding.measureIndex]
          .findElements('note')
          .toList();
      if (binding.noteIndex >= notes.length ||
          sourceNotes.containsKey(binding.symbolId)) {
        throw const FormatException('Invalid retained MusicXML note binding');
      }
      sourceNotes[binding.symbolId] = notes[binding.noteIndex];
    }
    final changes =
        <(String, int), (List<ScoreAnnotation>, List<ScoreAnnotation>)>{};
    for (final (p, part) in score.parts.indexed) {
      final ids = baseline.parts[p].measures
          .expand((m) => m.symbols)
          .map(_id)
          .toSet();
      final sourceId =
          source.bindings
              .where((b) => ids.contains(b.symbolId))
              .firstOrNull
              ?.partId ??
          part.id.replaceFirst(RegExp(r'-staff\d+$'), '');
      for (final (m, measure) in part.measures.indexed) {
        final lists = changes.putIfAbsent((
          sourceId,
          m,
        ), () => (<ScoreAnnotation>[], <ScoreAnnotation>[]));
        lists.$1.addAll(baseline.parts[p].measures[m].annotations);
        lists.$2.addAll(measure.annotations);
      }
    }
    for (final entry in parts.entries) {
      var divisions = MusicalTime(2);
      for (final (m, measure) in entry.value.indexed) {
        final positions = MusicXmlAnnotations.positions(measure, divisions);
        if (positions.isNotEmpty) divisions = positions.values.last.$2;
        final change = changes[(entry.key, m)];
        if (change != null && !MusicXmlAnnotations.same(change.$1, change.$2)) {
          try {
            _patchAnnotations(
              measure,
              change.$1,
              change.$2,
              positions,
              divisions,
            );
          } on FormatException catch (error) {
            if (!source.requiresPreservation) return null;
            throw MusicXmlPreservationException(error.message);
          }
        }
      }
    }
    if (baseline.title != score.title) _patchTitle(root, score.title);
    if (baseline.composer != score.composer) {
      _patchComposer(root, score.composer);
    }
    for (var p = 0; p < score.parts.length; p++) {
      final currentPart = score.parts[p];
      if (!currentPart.joinsPrevious) {
        final declaration = root
            .getElement('part-list')
            ?.findElements('score-part')
            .where((e) => e.getAttribute('id') == currentPart.id)
            .firstOrNull;
        if (declaration != null) {
          try {
            MusicXmlInstruments.patch(
              declaration,
              baseline.parts[p].playback,
              currentPart.playback,
            );
          } on FormatException catch (error) {
            throw MusicXmlPreservationException(error.message);
          }
        }
      }
      if (currentPart.name != baseline.parts[p].name) {
        final declaration = root
            .getElement('part-list')
            ?.findElements('score-part')
            .where((e) => e.getAttribute('id') == currentPart.id)
            .firstOrNull;
        if (declaration != null) {
          _setText(declaration, 'part-name', currentPart.name);
        }
      }
      final oldAccidentals = Accidentals(), newAccidentals = Accidentals();
      for (var m = 0; m < currentPart.measures.length; m++) {
        final before = baseline.parts[p].measures[m];
        final after = currentPart.measures[m];
        oldAccidentals.startMeasure(before);
        newAccidentals.startMeasure(after);
        for (var n = 0; n < after.symbols.length; n++) {
          final oldNote = before.symbols[n], newNote = after.symbols[n];
          if (oldNote is! Note || newNote is! Note) continue;
          final oldAlter = oldAccidentals.sounding(oldNote);
          final newAlter = newAccidentals.sounding(newNote);
          final element = sourceNotes[newNote.reviewId];
          if (element == null) {
            throw const FormatException(
              'Missing retained MusicXML note binding',
            );
          }
          if (jsonEncode(oldNote.lyrics.map((l) => l.toJson()).toList()) !=
              jsonEncode(newNote.lyrics.map((l) => l.toJson()).toList())) {
            element.children.removeWhere(
              (c) => c is XmlElement && c.name.local == 'lyric',
            );
            for (final lyric in newNote.lyrics) {
              _insertBefore(element, MusicXmlLyrics.write(lyric), const {
                'play',
                'listen',
              });
            }
          }
          // A drum note's kit piece is declared in the retained part list.
          if (element.getElement('unpitched') != null) {
            if (oldNote.drum != newNote.drum ||
                oldNote.step != newNote.step ||
                oldNote.octave != newNote.octave ||
                oldNote.notehead != newNote.notehead) {
              throw const MusicXmlPreservationException(
                'Changing a drum note in an imported file cannot be exported yet. '
                'Undo the change to export; saving the project keeps it.',
              );
            }
          } else {
            final pitch = element.getElement('pitch');
            if (pitch == null) {
              throw const FormatException('Missing retained MusicXML pitch');
            }
            final pitchChanged =
                oldNote.step != newNote.step ||
                oldNote.octave != newNote.octave ||
                oldAlter != newAlter ||
                oldNote.alter != newNote.alter;
            if (pitchChanged &&
                (element.getElement('tie') != null ||
                    element.findAllElements('tied').isNotEmpty)) {
              throw const MusicXmlPreservationException(
                'This pitch edit affects a tied note. Tied-note editing is not supported yet. '
                'Undo the pitch change to export; saving the project keeps the original notation.',
              );
            }
            if (oldNote.step != newNote.step) {
              _setText(pitch, 'step', newNote.step);
            }
            if (oldNote.octave != newNote.octave) {
              _setText(pitch, 'octave', '${newNote.octave}');
            }
            if (oldAlter != newAlter || oldNote.alter != newNote.alter) {
              _setOptionalText(
                pitch,
                'alter',
                newAlter == 0 ? null : '$newAlter',
                after: 'step',
              );
            }
            // A TAB note's string and fret; it shows no accidental.
            final technical = element
                .getElement('notations')
                ?.getElement('technical');
            final tab = technical?.getElement('fret') != null;
            if (oldNote.string != newNote.string ||
                oldNote.fret != newNote.fret) {
              if (!tab || newNote.string == null || newNote.fret == null) {
                throw const MusicXmlPreservationException();
              }
              _setText(technical!, 'string', '${newNote.string}');
              _setText(technical, 'fret', '${newNote.fret}');
            }
            if (!tab && oldNote.alter != newNote.alter) {
              final accidental = switch (newNote.alter) {
                -2 => 'flat-flat',
                -1 => 'flat',
                0 => 'natural',
                1 => 'sharp',
                2 => 'double-sharp',
                _ => null,
              };
              _setOptionalText(
                element,
                'accidental',
                accidental,
                before: const {
                  'time-modification',
                  'stem',
                  'notehead',
                  'notehead-text',
                  'staff',
                  'beam',
                  'notations',
                  'lyric',
                  'play',
                  'listen',
                },
              );
            }
          }
          if (jsonEncode(
                    oldNote.beams.map((k, v) => MapEntry('$k', v.xmlValue)),
                  ) !=
                  jsonEncode(
                    newNote.beams.map((k, v) => MapEntry('$k', v.xmlValue)),
                  ) ||
              oldNote.beamed != newNote.beamed) {
            // The original source already carries the unchanged beam spelling.
            // Explicit user edits replace only beam elements, never notations.
            element.children.removeWhere(
              (n) => n is XmlElement && n.name.local == 'beam',
            );
            for (final beam in BeamGrouping.valuesFor(
              after.symbols,
              n,
            ).entries) {
              _insertBefore(
                element,
                XmlElement(
                  XmlName('beam'),
                  [XmlAttribute(XmlName('number'), '${beam.key}')],
                  [XmlText(beam.value.xmlValue)],
                ),
                const {'notations', 'lyric', 'play', 'listen'},
              );
            }
          }
        }
      }
    }
    return document.toXmlString();
  }

  void _patchAnnotations(
    XmlElement measure,
    List<ScoreAnnotation> before,
    List<ScoreAnnotation> after,
    Map<XmlElement, (MusicalTime, MusicalTime)> positions,
    MusicalTime divisions,
  ) {
    final original = measure.childElements.toList();
    for (final a in before) {
      if (a.sourceIndex == null || a.sourceIndex! >= original.length) continue;
      final element = original[a.sourceIndex!];
      final next = after
          .where((v) => v.sourceIndex == a.sourceIndex)
          .firstOrNull;
      if (next != null && MusicXmlAnnotations.same([a], [next])) continue;
      final index = measure.children.indexOf(element);
      if (next != null) {
        final place = positions[element]!;
        measure.children[index] = MusicXmlAnnotations.write(
          next,
          cursor: place.$1,
          divisions: place.$2,
        );
      } else if (element.name.local == 'harmony') {
        measure.children.remove(element);
      } else {
        // Removing text/tempo must not remove a dynamic, wedge, pedal or
        // another direction that happened to share the source element.
        for (final type in element.findElements('direction-type').toList()) {
          type.children.removeWhere(
            (n) =>
                n is XmlElement &&
                {'words', 'rehearsal', 'metronome'}.contains(n.name.local),
          );
          if (type.childElements.isEmpty) element.children.remove(type);
        }
        element.getElement('sound')?.setAttribute('tempo', null);
        if (element.findElements('direction-type').isEmpty &&
            (element.getElement('sound')?.attributes.isEmpty ?? true)) {
          measure.children.remove(element);
        }
      }
    }
    final last = original.lastOrNull;
    var end = MusicalTime.zero;
    if (last != null) {
      final place = positions[last]!;
      end = place.$1;
      final duration =
          MusicalTime.decimal(
            MusicXmlAnnotations.text(last, 'duration') ?? '0',
          ) /
          place.$2;
      if (last.name.local == 'forward' ||
          (last.name.local == 'note' &&
              last.getElement('chord') == null &&
              last.getElement('grace') == null)) {
        end += duration;
      }
      if (last.name.local == 'backup') end -= duration;
    }
    for (final a in after.where((a) => a.sourceIndex == null)) {
      measure.children.add(
        MusicXmlAnnotations.write(a, cursor: end, divisions: divisions),
      );
    }
  }

  bool _canPatch(Score before, Score after) {
    // Ties and slurs are not patched into the source yet.
    if (!setEquals(before.spanners.toSet(), after.spanners.toSet())) {
      return false;
    }
    if (before.parts.length != after.parts.length) return false;
    for (var p = 0; p < before.parts.length; p++) {
      final oldPart = before.parts[p], part = after.parts[p];
      if (oldPart.id != part.id ||
          oldPart.staff != part.staff ||
          oldPart.measures.length != part.measures.length) {
        return false;
      }
      for (var m = 0; m < part.measures.length; m++) {
        final oldMeasure = oldPart.measures[m], measure = part.measures[m];
        final oldMeta = oldMeasure.toJson()
          ..remove('symbols')
          ..remove('source')
          ..remove('annotations');
        final newMeta = measure.toJson()
          ..remove('symbols')
          ..remove('source')
          ..remove('annotations');
        if (jsonEncode(oldMeta) != jsonEncode(newMeta) ||
            oldMeasure.symbols.length != measure.symbols.length) {
          return false;
        }
        for (var n = 0; n < measure.symbols.length; n++) {
          final oldSymbol = oldMeasure.symbols[n], symbol = measure.symbols[n];
          if (_id(oldSymbol) != _id(symbol) ||
              oldSymbol.runtimeType != symbol.runtimeType) {
            return false;
          }
          final oldJson = oldSymbol.toJson(), json = symbol.toJson();
          for (final key in [
            'step',
            'octave',
            'alter',
            'confidence',
            'source',
            'beams',
            'beamed',
            'lyrics',
            'string',
            'fret',
          ]) {
            oldJson.remove(key);
            json.remove(key);
          }
          if (jsonEncode(oldJson) != jsonEncode(json)) return false;
          if (symbol is Note &&
              symbol.alter != null &&
              symbol.alter!.abs() > 2) {
            return false;
          }
        }
      }
    }
    return true;
  }

  String? _id(ScoreSymbol symbol) => switch (symbol) {
    Note(:final reviewId) || Rest(:final reviewId) => reviewId,
    _ => null,
  };

  void _patchTitle(XmlElement root, String title) {
    final work = root.getElement('work');
    if (work != null) {
      _setText(work, 'work-title', title);
    } else if (root.getElement('movement-title') != null) {
      _setText(root, 'movement-title', title);
    } else {
      root.children.insert(
        0,
        XmlElement(XmlName('work'), [], [
          XmlElement(XmlName('work-title'), [], [XmlText(title)]),
        ]),
      );
    }
  }

  void _patchComposer(XmlElement root, String composer) {
    var identification = root.getElement('identification');
    if (identification == null) {
      identification = XmlElement(XmlName('identification'));
      _insertBefore(root, identification, const {
        'defaults',
        'credit',
        'part-list',
        'part',
        'measure',
      });
    }
    var creator = identification
        .findElements('creator')
        .where((c) => c.getAttribute('type') == 'composer')
        .firstOrNull;
    if (creator == null) {
      creator = XmlElement(XmlName('creator'), [
        XmlAttribute(XmlName('type'), 'composer'),
      ]);
      identification.children.insert(0, creator);
    }
    creator.children
      ..clear()
      ..add(XmlText(composer));
  }

  void _setText(XmlElement parent, String name, String text) =>
      _setOptionalText(parent, name, text);

  void _setOptionalText(
    XmlElement parent,
    String name,
    String? text, {
    String? after,
    Set<String> before = const {},
  }) {
    var element = parent.getElement(name);
    if (text == null) {
      if (element != null) parent.children.remove(element);
      return;
    }
    if (element == null) {
      element = XmlElement(XmlName(name));
      final previous = after == null ? null : parent.getElement(after);
      if (previous != null) {
        parent.children.insert(parent.children.indexOf(previous) + 1, element);
      } else {
        _insertBefore(parent, element, before);
      }
    }
    element.children
      ..clear()
      ..add(XmlText(text));
  }

  void _insertBefore(XmlElement parent, XmlElement element, Set<String> names) {
    final index = parent.children.indexWhere(
      (n) => n is XmlElement && names.contains(n.name.local),
    );
    if (index < 0) {
      parent.children.add(element);
    } else {
      parent.children.insert(index, element);
    }
  }
}
