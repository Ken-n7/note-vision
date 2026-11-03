import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:note_vision/core/services/playback_converter.dart';
import 'package:note_vision/features/musicXML/musicxml_export_service.dart';
import 'package:note_vision/features/musicXML/musicxml_score_converter.dart';
import 'package:xml/xml.dart';

void main() {
  // MuseScore's export of a two-staff piano part.
  final source = File(
    'test/musescore_parity/reference/16_grand_staff.musicxml',
  ).readAsStringSync();
  final score = const MusicXmlScoreConverter().convert(
    XmlDocument.parse(source),
  );

  test('a two-staff part becomes linked parts with their own clefs', () {
    expect(
      [for (final p in score.parts) (p.id, p.staff)],
      [('P1', 1), ('P1-staff2', 2)],
    );
    expect(
      [for (final p in score.parts) p.measures.first.clef?.sign],
      ['G', 'F'],
    );
    expect(score.parts.last.measures.first.symbols, hasLength(2));
    // Bindings still address the original <part>.
    expect(score.musicXmlSource!.bindings.map((b) => b.partId).toSet(), {'P1'});
  });

  test('unchanged, it exports the original file and plays both staves', () {
    expect(
      const MusicXmlExportService().toMusicXml(score),
      contains('<staves>2</staves>'),
    );
    final events = const PlaybackConverter().buildEvents(score);
    // Five notes above, a two-note chord and two notes below.
    expect(events.where((e) => !e.isRest), hasLength(9));
    // Both staves start together.
    expect(
      {
        for (final e in events)
          if (e.baseOnsetMs == 0) e.partIndex,
      },
      {0, 1},
    );
  });
}
