import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:note_vision/core/models/note.dart';
import 'package:note_vision/core/models/rest.dart';
import 'package:note_vision/features/musicXML/musicxml_parser_service.dart';
import 'package:note_vision/features/musicXML/musicxml_score_converter.dart';

void main() {
  const parser = MusicXmlParserService();
  const converter = MusicXmlScoreConverter();

  group('MusicXmlScoreConverter.convert', () {
    test('converts a simple score and extracts title/composer', () {
      final xml = File('test/musicxml_testfiles/01_valid_simple.xml').readAsStringSync();

      final parseResult = parser.parse(xml);
      expect(parseResult.success, isTrue);

      final score = converter.convert(parseResult.document!);

      expect(score.title, 'Ode to Joy');
      expect(score.composer, 'Beethoven');
      expect(score.partCount, 1);
      expect(score.parts.first.measureCount, 2);
      expect(score.parts.first.measures.first.notes.length, 4);
      expect(score.parts.first.measures[1].rests.length, 1);
    });

    test('converts multi-measure score and preserves note order', () {
      final xml = File('test/musicxml_testfiles/02_valid_multi_measure.xml').readAsStringSync();

      final parseResult = parser.parse(xml);
      expect(parseResult.success, isTrue);

      final score = converter.convert(parseResult.document!);

      expect(score.parts.single.measureCount, 4);
      final symbols = score.parts.single.measures[1].symbols;

      expect(symbols, hasLength(4));
      expect((symbols[0] as Note).pitch, 'G4');
      expect((symbols[1] as Note).pitch, 'A4');
      expect((symbols[2] as Note).pitch, 'B4');
      expect((symbols[3] as Note).pitch, 'C5');
    });

    test('ignores unsupported tags and still converts supported data', () {
      final xml = File('test/musicxml_testfiles/07_unsupported_tags.xml').readAsStringSync();

      final parseResult = parser.parse(xml);
      expect(parseResult.success, isTrue);

      final score = converter.convert(parseResult.document!);

      expect(score.title, 'Extra Tags Score');
      expect(score.composer, 'Test Composer');
      expect(score.parts.single.measures.single.symbols, hasLength(4));
      expect(
        score.parts.single.measures.single.symbols.every((s) => s is Note || s is Rest),
        isTrue,
      );
      expect(score.parts.single.measures.single.clef?.sign, 'G');
      expect(score.parts.single.measures.single.timeSignature?.beats, 4);
      expect(score.parts.single.measures.single.keySignature?.fifths, 0);
    });

    test('converts score-timewise MusicXML into parts/measures', () {
      const xml = '''<score-timewise>
  <part-list>
    <score-part id="P1"><part-name>Violin</part-name></score-part>
  </part-list>
  <measure number="1">
    <part id="P1">
      <attributes>
        <key><fifths>1</fifths></key>
        <time><beats>3</beats><beat-type>4</beat-type></time>
        <clef><sign>G</sign><line>2</line></clef>
      </attributes>
      <note><pitch><step>C</step><octave>5</octave></pitch><duration>1</duration><type>quarter</type></note>
    </part>
  </measure>
  <measure number="2">
    <part id="P1">
      <note><rest/><duration>2</duration><type>half</type></note>
    </part>
  </measure>
</score-timewise>''';

      final parseResult = parser.parse(xml);
      expect(parseResult.success, isTrue);

      final score = converter.convert(parseResult.document!);

      expect(score.id, 'score-timewise');
      expect(score.partCount, 1);
      expect(score.parts.single.name, 'Violin');
      expect(score.parts.single.measureCount, 2);
      expect(score.parts.single.measures.first.clef?.sign, 'G');
      expect(score.parts.single.measures.first.timeSignature?.beats, 3);
      expect(score.parts.single.measures.first.keySignature?.fifths, 1);
      expect(score.parts.single.measures.first.notes.single.pitch, 'C5');
      expect(score.parts.single.measures[1].rests.single.duration, 2);
    });


    test('uses root tag name as score id when id attribute is absent', () {
      const xml = '''<score-partwise>
  <part-list>
    <score-part id="P1"><part-name>Piano</part-name></score-part>
  </part-list>
  <part id="P1"><measure number="1"/></part>
</score-partwise>''';

      final parseResult = parser.parse(xml);
      expect(parseResult.success, isTrue);

      final score = converter.convert(parseResult.document!);

      expect(score.id, 'score-partwise');
    });

    test('uses fallbacks when optional metadata is missing', () {
      final xml = File('test/musicxml_testfiles/06_missing_metadata.xml').readAsStringSync();

      final parseResult = parser.parse(xml);
      expect(parseResult.success, isTrue);

      final score = converter.convert(parseResult.document!);

      expect(score.title, 'Untitled');
      expect(score.composer, 'Unknown composer');
      expect(score.parts.single.measureCount, 1);
    });
  });
}
