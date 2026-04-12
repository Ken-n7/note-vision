import 'dart:convert';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:note_vision/core/models/measure.dart';
import 'package:note_vision/core/models/note.dart';
import 'package:note_vision/core/models/part.dart';
import 'package:note_vision/core/models/rest.dart';
import 'package:note_vision/core/models/score.dart';
import 'package:note_vision/core/utils/export_file_name.dart';
import 'package:xml/xml.dart';

/// Converts a [Score] to a valid MusicXML 3.1 string and saves it to a
/// user-chosen location via the system file picker.
class MusicXmlExportService {
  const MusicXmlExportService();

  // ---------------------------------------------------------------------------
  // Public API
  // ---------------------------------------------------------------------------

  /// Returns a valid MusicXML 3.1 string for the given [score].
  /// Pure function — no I/O, fully unit-testable.
  String toMusicXml(Score score) {
    final builder = XmlBuilder();
    builder.element(
      'score-partwise',
      attributes: {'version': '3.1'},
      nest: () {
        _buildWork(builder, score);
        _buildIdentification(builder, score);
        _buildPartList(builder, score);
        for (final part in score.parts) {
          _buildPart(builder, part);
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
      fileName: '$fileName.musicxml',
      bytes: bytes,
      type: FileType.custom,
      allowedExtensions: ['musicxml', 'xml'],
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
      b.element(
        'creator',
        attributes: {'type': 'composer'},
        nest: score.composer,
      );
      b.element('encoding', nest: () {
        b.element('software', nest: 'Note Vision');
        b.element(
          'encoding-date',
          nest: DateTime.now().toIso8601String().substring(0, 10),
        );
      });
    });
  }

  void _buildPartList(XmlBuilder b, Score score) {
    b.element('part-list', nest: () {
      for (final part in score.parts) {
        b.element('score-part', attributes: {'id': part.id}, nest: () {
          b.element('part-name', nest: part.name);
        });
      }
    });
  }

  void _buildPart(XmlBuilder b, Part part) {
    b.element('part', attributes: {'id': part.id}, nest: () {
      final measures = part.measures;
      for (var i = 0; i < measures.length; i++) {
        _buildMeasure(b, measures[i], isFirst: i == 0);
      }
    });
  }

  void _buildMeasure(XmlBuilder b, Measure measure, {required bool isFirst}) {
    b.element(
      'measure',
      attributes: {'number': measure.number.toString()},
      nest: () {
        final needsAttributes = isFirst ||
            measure.clef != null ||
            measure.timeSignature != null ||
            measure.keySignature != null;

        if (needsAttributes) {
          b.element('attributes', nest: () {
            // divisions: our quarter = 2, so divisions per quarter = 2
            b.element('divisions', nest: '2');

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

            if (measure.clef != null) {
              b.element('clef', nest: () {
                b.element('sign', nest: measure.clef!.sign);
                b.element('line', nest: measure.clef!.line.toString());
              });
            }
          });
        }

        for (final symbol in measure.symbols) {
          if (symbol is Note) {
            _buildNote(b, symbol);
          } else if (symbol is Rest) {
            _buildRest(b, symbol);
          }
        }
      },
    );
  }

  void _buildNote(XmlBuilder b, Note note) {
    b.element('note', nest: () {
      b.element('pitch', nest: () {
        b.element('step', nest: note.step);
        if (note.alter != null && note.alter != 0) {
          b.element('alter', nest: note.alter.toString());
        }
        b.element('octave', nest: note.octave.toString());
      });
      b.element('duration', nest: note.duration.toString());
      if (note.voice != null) {
        b.element('voice', nest: note.voice.toString());
      }
      b.element('type', nest: note.type);
      if (note.staff != null) {
        b.element('staff', nest: note.staff.toString());
      }
    });
  }

  void _buildRest(XmlBuilder b, Rest rest) {
    b.element('note', nest: () {
      b.element('rest');
      b.element('duration', nest: rest.duration.toString());
      if (rest.voice != null) {
        b.element('voice', nest: rest.voice.toString());
      }
      b.element('type', nest: rest.type);
      if (rest.staff != null) {
        b.element('staff', nest: rest.staff.toString());
      }
    });
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
