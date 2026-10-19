// MusicXML <alter> is the pitch heard (key signature included); Note.alter is
// the accidental written, which the editor draws. Import and export convert.

import 'package:flutter_test/flutter_test.dart';
import 'package:note_vision/core/models/note.dart';
import 'package:note_vision/features/musicXML/musicxml_export_service.dart';
import 'package:note_vision/features/musicXML/musicxml_score_converter.dart';
import 'package:xml/xml.dart';

String _note(String step, {int? alter}) => '''
<note><pitch><step>$step</step>${alter == null ? '' : '<alter>$alter</alter>'}<octave>4</octave></pitch>
<duration>2</duration><type>quarter</type></note>''';

void main() {
  // D major. Heard: F#, F natural, F (natural again: carried), C#.
  final xml = '''<?xml version="1.0"?>
<score-partwise version="3.1">
  <part-list><score-part id="P1"><part-name>P</part-name></score-part></part-list>
  <part id="P1">
    <measure number="1">
      <attributes><divisions>2</divisions><key><fifths>2</fifths></key></attributes>
      ${_note('F', alter: 1)}${_note('F')}${_note('F')}${_note('C', alter: 1)}
    </measure>
    <measure number="2">${_note('F', alter: 1)}</measure>
  </part>
</score-partwise>''';

  test('import writes only the accidentals a reader needs', () {
    final score = MusicXmlScoreConverter().convert(XmlDocument.parse(xml));
    final alters = [
      for (final m in score.parts.single.measures)
        for (final s in m.symbols) (s as Note).alter,
    ];
    // F# is in the key; the first F natural needs a natural sign, the second
    // is carried to the barline; C# is in the key; a new bar resets.
    expect(alters, [null, 0, null, null, null]);
  });

  test('export writes the pitch heard, and the round trip is exact', () {
    final score = MusicXmlScoreConverter().convert(XmlDocument.parse(xml));
    final out = MusicXmlExportService().toMusicXml(score);
    final heard = [
      for (final p in XmlDocument.parse(out).findAllElements('pitch'))
        '${p.getElement('step')!.innerText}'
            '${p.getElement('alter')?.innerText ?? ''}',
    ];
    expect(heard, ['F1', 'F', 'F', 'C1', 'F1']);
  });
}
