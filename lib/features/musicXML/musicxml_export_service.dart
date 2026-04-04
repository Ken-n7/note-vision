import 'dart:io';

import 'package:note_vision/core/models/measure.dart';
import 'package:note_vision/core/models/note.dart';
import 'package:note_vision/core/models/part.dart';
import 'package:note_vision/core/models/rest.dart';
import 'package:note_vision/core/models/score.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:xml/xml.dart';

/// Converts a [Score] to a valid MusicXML 3.1 string and can share it as a
/// .musicxml file via the system share sheet.
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

  /// Writes the score to a temp .musicxml file and opens the system share sheet.
  Future<void> exportAndShare(Score score) async {
    final xml = toMusicXml(score);
    final dir = await getTemporaryDirectory();
    final fileName = _safeFileName(score.title);
    final file = File('${dir.path}/$fileName.musicxml');
    await file.writeAsString(xml, flush: true);

    await SharePlus.instance.share(
      ShareParams(
        files: [
          XFile(
            file.path,
            mimeType: 'application/vnd.recordare.musicxml+xml',
            name: '$fileName.musicxml',
          ),
        ],
        subject: score.title.isEmpty ? 'Score' : score.title,
      ),
    );
  }

  /// Saves the score as a .musicxml file directly to a user-accessible
  /// location and returns the saved [File].
  ///
  /// - Android: Downloads folder (`/storage/emulated/0/Download`)
  /// - iOS: app Documents directory (visible in Files app under "On My iPhone")
  ///
  /// Throws if the directory cannot be resolved or the write fails.
  Future<File> exportToDevice(Score score) async {
    final xml = toMusicXml(score);
    final fileName = _safeFileName(score.title);

    final Directory dir;
    if (Platform.isAndroid) {
      dir = await getDownloadsDirectory() ?? await getApplicationDocumentsDirectory();
    } else {
      // iOS: Documents directory is accessible via the Files app.
      dir = await getApplicationDocumentsDirectory();
    }

    final file = File('${dir.path}/$fileName.musicxml');
    await file.writeAsString(xml, flush: true);
    return file;
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

  String _safeFileName(String title) {
    final trimmed = title.trim();
    if (trimmed.isEmpty) return 'score';
    return trimmed.replaceAll(RegExp(r'[^\w\-]'), '_');
  }

  static const String _xmlHeader =
      '<?xml version="1.0" encoding="UTF-8"?>\n'
      '<!DOCTYPE score-partwise PUBLIC\n'
      '  "-//Recordare//DTD MusicXML 3.1 Partwise//EN"\n'
      '  "http://www.musicxml.org/dtds/partwise.dtd">\n';
}
