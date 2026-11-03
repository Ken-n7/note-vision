import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:xml/xml.dart';
import 'package:note_vision/core/models/musical_time.dart';
import 'package:note_vision/core/models/note.dart';
import 'package:note_vision/core/models/project.dart';
import 'package:note_vision/core/models/rest.dart';
import 'package:note_vision/core/models/score.dart';
import 'package:note_vision/core/services/notation_review_service.dart';
import 'package:note_vision/core/services/project_storage_service.dart';
import 'package:note_vision/features/editor/domain/editor_actions.dart';
import 'package:note_vision/features/editor/model/editor_state.dart';
import 'package:note_vision/features/musicXML/musicxml_export_service.dart';
import 'package:note_vision/features/musicXML/musicxml_preserving_exporter.dart';
import 'package:note_vision/features/musicXML/musicxml_score_converter.dart';
import 'package:note_vision/features/musicXML/musicxml_source_reader.dart';

const exporter = MusicXmlExportService();
const converter = MusicXmlScoreConverter();
const reader = MusicXmlSourceReader();

const simpleXml = '''<score-partwise version="3.1">
<part-list><score-part id="P1"><part-name>Piano</part-name></score-part></part-list>
<part id="P1"><measure number="1"><attributes><divisions>2</divisions><time><beats>4</beats><beat-type>4</beat-type></time></attributes>
<note><pitch><step>C</step><octave>4</octave></pitch><duration>2</duration><type>quarter</type></note>
</measure></part></score-partwise>''';

void main() {
  late String fixture;
  late Score imported;
  setUp(() {
    fixture = File(
      'test/musicxml_testfiles/08_polyphonic_preservation.musicxml',
    ).readAsStringSync();
    imported = converter.convert(XmlDocument.parse(fixture));
  });

  test(
    'timeline coordinates voices, chords, grace notes and percussion exactly',
    () {
      final source = imported.musicXmlSource!;
      final events = source.events.where((e) => e.measureIndex == 0).toList();
      expect(events, hasLength(8));
      expect(events.map((e) => e.onset), [
        MusicalTime.zero,
        MusicalTime.zero,
        MusicalTime.zero,
        MusicalTime(1, 3),
        MusicalTime(2, 3),
        MusicalTime.one,
        MusicalTime.one,
        MusicalTime(2),
      ]);
      expect(events.first.isGrace, isTrue);
      expect(events.first.duration, MusicalTime.zero);
      expect(events[2].isChordTone, isTrue);
      expect(events[3].duration, MusicalTime(1, 3));
      expect(events[6].voice, '2');
      expect(events[6].staff, 2);
      // The grace note and the drum note are editable symbols. Each staff
      // of the piano is its own linked part.
      expect([for (final p in imported.parts) p.staff], [1, 2]);
      expect([
        for (final p in imported.parts) p.measures.first.symbols.length,
      ], [6, 2]);
      expect(
        source.bindings
            .where((b) => b.measureIndex == 0)
            .map((b) => b.noteIndex),
        [0, 1, 2, 3, 4, 5, 6, 7],
      );
      expect(source.requiresPreservation, isTrue);
    },
  );

  test(
    'divisions inherited through and beyond a mid-measure change stay exact',
    () {
      final events = imported.musicXmlSource!.events;
      final second = events.where((e) => e.measureIndex == 1).toList();
      expect(second.map((e) => e.duration), [MusicalTime.one, MusicalTime(3)]);
      expect(second[1].onset, MusicalTime.one);
      expect(events.last.duration, MusicalTime(4));
      final rest = imported.parts.first.measures[1].symbols[1] as Rest;
      expect(
        rest.duration,
        6,
        reason: 'Legacy projection must also use the changed divisions',
      );
    },
  );

  test(
    'unchanged import exports the full original XML, including unknown notation',
    () {
      final expected = XmlDocument.parse(fixture).toXmlString();
      expect(exporter.toMusicXml(imported), expected);
      expect(
        exporter.toMusicXml(NotationReviewService.ensureIdentity(imported)),
        expected,
      );
      final reparsed = converter.convert(
        XmlDocument.parse(exporter.toMusicXml(imported)),
      );
      expect(
        reparsed.musicXmlSource!.events.map((e) => e.toJson()),
        imported.musicXmlSource!.events.map((e) => e.toJson()),
      );
    },
  );

  test(
    'project save/reopen keeps source, exact timing and stable edit bindings',
    () async {
      SharedPreferences.setMockInitialValues({});
      final directory = await Directory.systemTemp.createTemp(
        'nv-preservation-',
      );
      addTearDown(() => directory.delete(recursive: true));
      final storage = ProjectStorageService(
        projectsDirOverride: () async => directory,
      );
      final project = Project.create(name: 'Polyphonic Study', score: imported);
      await storage.saveProject(project);
      final reopened = (await storage.loadProject(project.id))!.decodeScore();
      expect(
        reopened.musicXmlSource!.toJson(),
        imported.musicXmlSource!.toJson(),
      );
      expect(exporter.toMusicXml(reopened), imported.musicXmlSource!.xml);
    },
  );

  test(
    'pitch editing patches the bound source note after unsupported earlier notes',
    () {
      // Symbol 3 is the D5 after the grace note and the C5–E5 chord.
      final state = EditorState(
        score: imported,
      ).selectSymbolAt(partIndex: 0, measureIndex: 0, symbolIndex: 3);
      final edited = state.moveSelectedSymbolUp();
      final output = XmlDocument.parse(exporter.toMusicXml(edited.score));
      final first = output.rootElement
          .getElement('part')!
          .findElements('measure')
          .first;
      final notes = first.findElements('note').toList();
      expect(notes[3].getElement('pitch')!.getElement('step')!.innerText, 'E');
      expect(
        notes[3].getElement('lyric')!.getElement('text')!.innerText,
        'Two',
      );
      expect(notes[1].getAttribute('default-x'), '24');
      expect(notes[1].getElement('lyric')!.innerText, 'singleOne');
      expect(
        notes[1]
            .getElement('notations')!
            .findElements('slur')
            .single
            .getAttribute('type'),
        'start',
      );
      expect(first.getElement('backup')!.innerText, '48');
      expect(
        first.getElement('forward')!.getElement('duration')!.innerText,
        '12',
      );
      expect(output.findAllElements('time-modification'), hasLength(4));
      expect(edited.score.musicXmlSource, same(imported.musicXmlSource));
      expect(
        reader.readTimeline(output).map((e) => e.toJson()),
        imported.musicXmlSource!.events.map((e) => e.toJson()),
      );
      expect(
        exporter.toMusicXml(edited.applyUndo().score),
        imported.musicXmlSource!.xml,
      );
      expect(
        exporter.toMusicXml(edited.applyUndo().applyRedo().score),
        output.toXmlString(),
      );
    },
  );

  test(
    'accidental edits preserve display attributes and correct sounding pitch',
    () {
      final edited = EditorState(score: imported)
          .selectSymbolAt(partIndex: 0, measureIndex: 1, symbolIndex: 0)
          .setSelectedNoteAccidental(-1);
      final document = XmlDocument.parse(exporter.toMusicXml(edited.score));
      final note = document
          .findAllElements('measure')
          .toList()[1]
          .findElements('note')
          .first;
      expect(note.getElement('pitch')!.getElement('alter')!.innerText, '-1');
      expect(note.getElement('accidental')!.innerText, 'flat');
      expect(note.getElement('accidental')!.getAttribute('parentheses'), 'yes');
      expect(note.getElement('duration')!.innerText, '12');
    },
  );

  test(
    'metadata edits preserve rights, arranger, instrument and page defaults',
    () {
      final document = XmlDocument.parse(
        exporter.toMusicXml(
          imported.copyWith(title: 'Revised', composer: 'New Composer'),
        ),
      );
      expect(
        document.findAllElements('work-title').single.innerText,
        'Revised',
      );
      expect(document.findAllElements('work-number').single.innerText, 'NV-08');
      final creators = document.findAllElements('creator');
      expect(
        creators
            .firstWhere((e) => e.getAttribute('type') == 'composer')
            .innerText,
        'New Composer',
      );
      expect(
        creators
            .firstWhere((e) => e.getAttribute('type') == 'arranger')
            .innerText,
        'Retained Arranger',
      );
      expect(
        document.findAllElements('rights').single.innerText,
        'Original test fixture',
      );
      expect(
        document.findAllElements('instrument-name').single.innerText,
        'Grand Piano',
      );
      expect(document.findAllElements('millimeters').single.innerText, '7');
    },
  );

  test(
    'unsafe structural edits never silently regenerate a simplified score',
    () {
      final initial = EditorState(score: imported);
      final added = initial.appendMeasureAtEnd();
      expect(
        () => exporter.toMusicXml(added.score),
        throwsA(isA<MusicXmlPreservationException>()),
      );
      final saved = Project.create(
        name: 'Changed',
        score: added.score,
      ).decodeScore();
      expect(saved.musicXmlSource!.xml, imported.musicXmlSource!.xml);
      expect(
        exporter.toMusicXml(added.applyUndo().score),
        imported.musicXmlSource!.xml,
      );
    },
  );

  test(
    'unsafe rhythmic edits retain the project source and fail export explicitly',
    () {
      final note = imported.getSymbolAt(0, 0, 2) as Note;
      final data = note.toJson()
        ..['type'] = 'quarter'
        ..['duration'] = 2;
      final edited = imported.replaceSymbolAt(0, 0, 2, Note.fromJson(data));
      expect(
        () => exporter.toMusicXml(edited),
        throwsA(isA<MusicXmlPreservationException>()),
      );
      expect(
        Score.fromJson(
          jsonDecode(jsonEncode(edited.toJson())),
        ).musicXmlSource!.xml,
        imported.musicXmlSource!.xml,
      );
    },
  );

  test(
    'simple imported scores retain existing structural and rhythm export support',
    () {
      final score = converter.convert(XmlDocument.parse(simpleXml));
      expect(score.musicXmlSource!.requiresPreservation, isFalse);
      final selected = EditorState(
        score: score,
      ).selectSymbolAt(partIndex: 0, measureIndex: 0, symbolIndex: 0);
      final rest = selected.convertSelectedNoteToRest();
      final xml = XmlDocument.parse(
        exporter.toMusicXml(rest.appendMeasureAtEnd().score),
      );
      expect(xml.findAllElements('measure'), hasLength(2));
      expect(xml.findAllElements('rest'), hasLength(1));
    },
  );

  test(
    'timewise source addressing retains hidden notes and supports pitch changes',
    () {
      final xml =
          '''<score-timewise version="4.0"><part-list><score-part id="P1"><part-name>P</part-name></score-part></part-list>
    <measure number="1"><part id="P1"><attributes><divisions>3</divisions></attributes>
      <note><grace/><pitch><step>A</step><octave>4</octave></pitch><type>eighth</type></note>
      <note><pitch><step>C</step><octave>4</octave></pitch><duration>1</duration><type>eighth</type></note>
    </part></measure><measure number="2"><part id="P1">
      <note><rest/><duration>3</duration><type>quarter</type></note>
    </part></measure></score-timewise>''';
      final score = converter.convert(XmlDocument.parse(xml));
      // Symbol 0 is the grace note, 1 the C4.
      final edited = EditorState(score: score)
          .selectSymbolAt(partIndex: 0, measureIndex: 0, symbolIndex: 1)
          .moveSelectedSymbolUp();
      final output = XmlDocument.parse(exporter.toMusicXml(edited.score));
      expect(output.rootElement.name.local, 'score-timewise');
      expect(output.findAllElements('grace'), hasLength(1));
      expect(
        output.findAllElements('pitch').last.getElement('step')!.innerText,
        'D',
      );
      expect(score.musicXmlSource!.events[1].duration, MusicalTime(1, 3));
      expect(score.musicXmlSource!.events.last.duration, MusicalTime.one);
    },
  );

  test(
    'fractional divisions and durations are accepted without losing exact time',
    () {
      final xml = simpleXml
          .replaceAll('<divisions>2</divisions>', '<divisions>1.5</divisions>')
          .replaceAll('<duration>2</duration>', '<duration>.5</duration>');
      final score = converter.convert(XmlDocument.parse(xml));
      expect(score.musicXmlSource!.events.single.duration, MusicalTime(1, 3));
      expect(score.musicXmlSource!.requiresPreservation, isTrue);
      expect(exporter.toMusicXml(score), XmlDocument.parse(xml).toXmlString());
    },
  );

  test(
    'invalid source cursor and division values are rejected with useful errors',
    () {
      for (final value in ['0', '-2', 'NaN']) {
        expect(
          () => converter.convert(
            XmlDocument.parse(
              simpleXml.replaceAll(
                '<divisions>2</divisions>',
                '<divisions>$value</divisions>',
              ),
            ),
          ),
          throwsFormatException,
        );
      }
      expect(
        () => converter.convert(
          XmlDocument.parse(
            simpleXml.replaceFirst(
              '<note>',
              '<backup><duration>1</duration></backup><note>',
            ),
          ),
        ),
        throwsFormatException,
      );
    },
  );

  test(
    'legacy score JSON remains readable and unknown source schema fails explicitly',
    () {
      final legacy = imported.notationProjection();
      final score = Score.fromJson(legacy);
      expect(score.musicXmlSource, isNull);
      expect(() => exporter.toMusicXml(score), returnsNormally);
      final json = imported.toJson();
      (json['musicXmlSource'] as Map)['schemaVersion'] = 999;
      expect(() => Score.fromJson(json), throwsFormatException);
    },
  );

  test(
    'microtonal alterations, named voices and final barlines require preservation',
    () {
      for (final xml in [
        simpleXml.replaceFirst('<octave>', '<alter>0.5</alter><octave>'),
        simpleXml.replaceFirst('<type>', '<voice>RH</voice><type>'),
        simpleXml.replaceFirst(
          '</measure>',
          '<barline location="right"><bar-style>light-heavy</bar-style></barline></measure>',
        ),
      ]) {
        final score = converter.convert(XmlDocument.parse(xml));
        expect(score.musicXmlSource!.requiresPreservation, isTrue);
        expect(
          exporter.toMusicXml(score),
          XmlDocument.parse(xml).toXmlString(),
        );
        expect(
          () => exporter.toMusicXml(
            EditorState(score: score).appendMeasureAtEnd().score,
          ),
          throwsA(isA<MusicXmlPreservationException>()),
        );
      }
    },
  );

  test(
    'an explicit natural replaces an unrepresented fractional alteration',
    () {
      final score = converter.convert(
        XmlDocument.parse(
          simpleXml.replaceFirst('<octave>', '<alter>0.5</alter><octave>'),
        ),
      );
      final edited = EditorState(score: score)
          .selectSymbolAt(partIndex: 0, measureIndex: 0, symbolIndex: 0)
          .setSelectedNoteAccidental(0);
      final xml = XmlDocument.parse(exporter.toMusicXml(edited.score));
      expect(xml.findAllElements('alter'), isEmpty);
      expect(xml.findAllElements('accidental').single.innerText, 'natural');
    },
  );

  test(
    'pitch edits cannot silently detach a tie whose other endpoint is unedited',
    () {
      final score = converter.convert(
        XmlDocument.parse(
          simpleXml
              .replaceFirst(
                '<type>quarter</type>',
                '<tie type="start"/><type>quarter</type><notations><tied type="start"/></notations>',
              )
              .replaceFirst(
                '</measure>',
                '<note><pitch><step>C</step><octave>4</octave></pitch>'
                    '<duration>2</duration><tie type="stop"/><type>quarter</type>'
                    '<notations><tied type="stop"/></notations></note></measure>',
              ),
        ),
      );
      final selected = EditorState(
        score: score,
      ).selectSymbolAt(partIndex: 0, measureIndex: 0, symbolIndex: 0);
      expect(
        () => exporter.toMusicXml(selected.moveSelectedSymbolUp().score),
        throwsA(
          isA<MusicXmlPreservationException>().having(
            (e) => e.message,
            'message',
            contains('tied note'),
          ),
        ),
      );
      expect(exporter.toMusicXml(score), score.musicXmlSource!.xml);
    },
  );

  test(
    'retained declarations match UTF-8 export while the original source stays intact',
    () {
      final original =
          '<?xml version="1.0" encoding="UTF-16" standalone="yes"?>$simpleXml';
      final score = converter.convert(XmlDocument.parse(original));
      final output = XmlDocument.parse(exporter.toMusicXml(score));
      final declaration = output.children.whereType<XmlDeclaration>().single;
      expect(declaration.encoding, 'UTF-8');
      expect(declaration.standalone, isTrue);
      expect(score.musicXmlSource!.xml, contains('encoding="UTF-16"'));
    },
  );

  test(
    'movement titles and noncanonical repeats remain retained on structural edits',
    () {
      for (final xml in [
        simpleXml.replaceFirst(
          '<part-list>',
          '<work><work-title>Collection</work-title></work><movement-title>Movement I</movement-title><part-list>',
        ),
        simpleXml.replaceFirst(
          '</measure>',
          '<barline><repeat direction="backward"/></barline></measure>',
        ),
      ]) {
        final score = converter.convert(XmlDocument.parse(xml));
        expect(score.musicXmlSource!.requiresPreservation, isTrue);
        expect(
          () => exporter.toMusicXml(
            EditorState(score: score).appendMeasureAtEnd().score,
          ),
          throwsA(isA<MusicXmlPreservationException>()),
        );
        expect(
          exporter.toMusicXml(score),
          XmlDocument.parse(xml).toXmlString(),
        );
      }
      final repeated = converter.convert(
        XmlDocument.parse(
          simpleXml.replaceFirst(
            '</measure>',
            '<barline><repeat direction="backward"/></barline></measure>',
          ),
        ),
      );
      expect(
        repeated.parts.single.measures.single.rightBarlineType,
        isNotNull,
        reason: 'MusicXML barline location defaults to right',
      );
    },
  );
}
