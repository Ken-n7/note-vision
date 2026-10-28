import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:note_vision/core/models/score.dart';
import 'package:note_vision/core/services/playback_converter.dart';
import 'package:note_vision/features/musicXML/musicxml_export_service.dart';
import 'package:note_vision/features/musicXML/musicxml_parser_service.dart';
import 'package:note_vision/features/musicXML/musicxml_score_converter.dart';
import 'package:xml/xml.dart';

import 'parity_facts.dart';

/// Compares Note Vision with MuseScore Studio on the scores in `cases/`.
///
/// `reference/` holds MuseScore's MusicXML and MIDI export of each case
/// (regenerate with `tool/musescore_reference.sh`). Note Vision imports the
/// MuseScore file, saves and reopens it as a project, then exports MusicXML
/// from its own model and builds its playback. Both sides are reduced to
/// facts; `baseline/` records the differences that remain. The test fails
/// when that list changes. After an improvement, rerun with
/// `NV_UPDATE_PARITY=1` and commit the smaller baseline.
void main() {
  const root = 'test/musescore_parity';
  final update = Platform.environment['NV_UPDATE_PARITY'] == '1';
  final cases =
      Directory('$root/cases')
          .listSync()
          .map((f) => f.uri.pathSegments.last)
          .where((name) => name.endsWith('.musicxml'))
          .map((name) => name.substring(0, name.length - '.musicxml'.length))
          .toList()
        ..sort();

  for (final name in cases) {
    test(name, () {
      final referenceXml = File('$root/reference/$name.musicxml');
      final referenceMidi = File('$root/reference/$name.mid');
      if (!referenceXml.existsSync() || !referenceMidi.existsSync()) {
        fail(
          'No MuseScore reference for $name: run tool/musescore_reference.sh',
        );
      }
      final report = parityReport(
        name,
        referenceXml.readAsStringSync(),
        referenceMidi.readAsBytesSync(),
      );
      final baseline = File('$root/baseline/$name.txt');
      if (update) {
        baseline.writeAsStringSync(report);
        return;
      }
      expect(
        report,
        baseline.existsSync() ? baseline.readAsStringSync() : '<no baseline>',
        reason:
            'Note Vision now differs from MuseScore in a new way. If this is '
            'an improvement, rerun with NV_UPDATE_PARITY=1 and commit '
            '$root/baseline/$name.txt.',
      );
    });
  }
}

String parityReport(String name, String referenceXml, List<int> referenceMidi) {
  final reference = XmlDocument.parse(referenceXml);
  final parsed = const MusicXmlParserService().parse(referenceXml);
  final out = StringBuffer('# $name — ${_version()} vs Note Vision\n');
  if (!parsed.success) {
    return '$out## import failed: ${parsed.errorMessage}\n';
  }
  final imported = Score.fromJson(
    jsonDecode(
          jsonEncode(
            const MusicXmlScoreConverter().convert(parsed.document!).toJson(),
          ),
        )
        as Map<String, dynamic>,
  );
  // Without the retained source the exporter writes what the model holds,
  // which is what the editor can show and edit.
  final modelOnly = Score(
    id: imported.id,
    title: imported.title,
    composer: imported.composer,
    parts: imported.parts,
  );
  out
    ..writeln(
      compareFacts(
        'notation',
        notationFacts(reference),
        notationFacts(
          XmlDocument.parse(
            const MusicXmlExportService().toMusicXml(modelOnly),
          ),
        ),
      ),
    )
    ..writeln(
      _playback(
        midiFacts(Uint8List.fromList(referenceMidi)),
        () => playbackFacts(const PlaybackConverter().buildPlan(imported)),
      ),
    );
  return out.toString();
}

String _playback(List<String> reference, List<String> Function() ours) {
  try {
    return compareFacts('playback', reference, ours());
  } on Object catch (e) {
    return '## playback: failed in Note Vision: $e';
  }
}

String _version() {
  final file = File('test/musescore_parity/reference/VERSION');
  return file.existsSync() ? file.readAsStringSync().trim() : '(unknown)';
}
