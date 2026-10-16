import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:note_vision/core/models/barline_type.dart';
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

    test('preserves dotted durations and dot metadata', () {
      const xml = '''<score-partwise>
  <part-list>
    <score-part id="P1"><part-name>Piano</part-name></score-part>
  </part-list>
  <part id="P1">
    <measure number="1">
      <attributes>
        <divisions>2</divisions>
        <clef><sign>G</sign><line>2</line></clef>
      </attributes>
      <note>
        <pitch><step>C</step><octave>4</octave></pitch>
        <duration>3</duration>
        <type>quarter</type>
        <dot/>
      </note>
      <note>
        <rest/>
        <duration>6</duration>
        <type>half</type>
        <dot/>
      </note>
    </measure>
  </part>
</score-partwise>''';

      final parseResult = parser.parse(xml);
      expect(parseResult.success, isTrue);

      final score = converter.convert(parseResult.document!);
      final symbols = score.parts.single.measures.single.symbols;

      final note = symbols[0] as Note;
      final rest = symbols[1] as Rest;

      expect(note.duration, 3);
      expect(note.dots, 1);
      expect(rest.duration, 6);
      expect(rest.dots, 1);
    });

    test('keeps whole-bar rests, sizing them to the bar', () {
      const xml = '''<?xml version="1.0" encoding="UTF-8"?>
<score-partwise version="3.1">
  <part-list><score-part id="P1"><part-name>P</part-name></score-part></part-list>
  <part id="P1">
    <measure number="1">
      <attributes><divisions>2</divisions><time><beats>3</beats><beat-type>4</beat-type></time></attributes>
      <note><rest measure="yes"/><duration>6</duration></note>
    </measure>
    <measure number="2">
      <note><rest measure="yes"/><duration>6</duration><type>whole</type></note>
    </measure>
    <measure number="3">
      <note><pitch><step>C</step><octave>4</octave></pitch><duration>1</duration></note>
    </measure>
  </part>
</score-partwise>''';
      final score = converter.convert(parser.parse(xml).document!);
      final measures = score.parts.single.measures;
      for (final m in measures.take(2)) {
        final rest = m.symbols.single as Rest;
        // Three beats of 3/4: a dotted half, not a four-beat whole rest.
        expect(rest.type, 'half');
        expect(rest.dots, 1);
      }
      // A note without <type> takes its value from the duration.
      expect((measures[2].symbols.single as Note).type, 'eighth');
    });

    test('reads beams and spells a 16th the way scans do', () {
      const xml = '''<score-partwise version="3.1">
  <part-list><score-part id="P1"><part-name>P</part-name></score-part></part-list>
  <part id="P1">
    <measure number="1">
      <attributes><divisions>4</divisions></attributes>
      <note><pitch><step>C</step><octave>5</octave></pitch><duration>2</duration><type>eighth</type><beam number="1">begin</beam></note>
      <note><pitch><step>D</step><octave>5</octave></pitch><duration>1</duration><type>16th</type><beam number="1">end</beam><beam number="2">backward hook</beam></note>
      <note><pitch><step>E</step><octave>5</octave></pitch><duration>2</duration><type>eighth</type></note>
      <note><rest/><duration>1</duration><type>16th</type></note>
    </measure>
  </part>
</score-partwise>''';
      final symbols =
          converter.convert(parser.parse(xml).document!).parts.single.measures.single.symbols;
      final notes = symbols.whereType<Note>().toList();
      expect(notes.map((n) => n.beamed), [true, true, false]);
      expect(notes[1].type, 'sixteenth');
      expect((symbols.last as Rest).type, 'sixteenth');
    });

    test('marks chord notes when MusicXML note contains chord tag', () {
      const xml = '''<score-partwise>
  <part-list>
    <score-part id="P1"><part-name>Piano</part-name></score-part>
  </part-list>
  <part id="P1">
    <measure number="1">
      <attributes>
        <divisions>2</divisions>
        <clef><sign>G</sign><line>2</line></clef>
      </attributes>
      <note>
        <pitch><step>C</step><octave>4</octave></pitch>
        <duration>2</duration>
        <type>quarter</type>
      </note>
      <note>
        <chord/>
        <pitch><step>E</step><octave>4</octave></pitch>
        <duration>2</duration>
        <type>quarter</type>
      </note>
    </measure>
  </part>
</score-partwise>''';

      final parseResult = parser.parse(xml);
      expect(parseResult.success, isTrue);

      final score = converter.convert(parseResult.document!);
      final notes = score.parts.single.measures.single.notes;

      expect(notes, hasLength(2));
      expect(notes[0].isChordTone, isFalse);
      expect(notes[1].isChordTone, isTrue);
    });

    test('imports repeat barlines from left and right barline elements', () {
      const xml = '''<score-partwise>
  <part-list>
    <score-part id="P1"><part-name>Piano</part-name></score-part>
  </part-list>
  <part id="P1">
    <measure number="1">
      <note>
        <pitch><step>C</step><octave>4</octave></pitch>
        <duration>2</duration><type>quarter</type>
      </note>
      <barline location="right">
        <repeat direction="backward"/>
      </barline>
    </measure>
    <measure number="2">
      <barline location="left">
        <repeat direction="forward"/>
      </barline>
      <note>
        <pitch><step>D</step><octave>4</octave></pitch>
        <duration>2</duration><type>quarter</type>
      </note>
    </measure>
  </part>
</score-partwise>''';

      final parseResult = parser.parse(xml);
      expect(parseResult.success, isTrue);

      final score = converter.convert(parseResult.document!);
      final measures = score.parts.single.measures;

      expect(measures[0].rightBarlineType, BarlineType.repeatEnd);
      expect(measures[1].leftBarlineType, BarlineType.repeatStart);
    });
  });
}
