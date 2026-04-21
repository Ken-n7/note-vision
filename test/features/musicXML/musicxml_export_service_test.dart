import 'package:flutter_test/flutter_test.dart';
import 'package:note_vision/core/models/clef.dart';
import 'package:note_vision/core/models/key_signature.dart';
import 'package:note_vision/core/models/measure.dart';
import 'package:note_vision/core/models/note.dart';
import 'package:note_vision/core/models/part.dart';
import 'package:note_vision/core/models/rest.dart';
import 'package:note_vision/core/models/score.dart';
import 'package:note_vision/core/models/time_signature.dart';
import 'package:note_vision/features/musicXML/musicxml_export_service.dart';

void main() {
  const service = MusicXmlExportService();

  // ---------------------------------------------------------------------------
  // Helpers
  // ---------------------------------------------------------------------------

  Score minimalScore({
    String title = 'Test Score',
    String composer = 'Test Composer',
    List<Part>? parts,
  }) {
    return Score(
      id: 'test-id',
      title: title,
      composer: composer,
      parts:
          parts ??
          [
            Part(
              id: 'P1',
              name: 'Piano',
              measures: [
                Measure(
                  number: 1,
                  clef: const Clef(sign: 'G', line: 2),
                  timeSignature: const TimeSignature(beats: 4, beatType: 4),
                  keySignature: const KeySignature(fifths: 0),
                  symbols: const [
                    Note(step: 'C', octave: 4, duration: 2, type: 'quarter'),
                  ],
                ),
              ],
            ),
          ],
    );
  }

  // ---------------------------------------------------------------------------
  // XML header
  // ---------------------------------------------------------------------------

  group('XML header', () {
    test('output starts with XML declaration', () {
      final xml = service.toMusicXml(minimalScore());
      expect(xml, startsWith('<?xml version="1.0" encoding="UTF-8"?>'));
    });

    test('output includes MusicXML 3.1 DOCTYPE', () {
      final xml = service.toMusicXml(minimalScore());
      expect(xml, contains('<!DOCTYPE score-partwise'));
      expect(xml, contains('MusicXML 3.1 Partwise'));
    });

    test('root element is score-partwise with version 3.1', () {
      final xml = service.toMusicXml(minimalScore());
      expect(xml, contains('<score-partwise version="3.1">'));
    });
  });

  // ---------------------------------------------------------------------------
  // Work and identification
  // ---------------------------------------------------------------------------

  group('work and identification', () {
    test('work-title contains score title', () {
      final xml = service.toMusicXml(minimalScore(title: 'Sonata No. 1'));
      expect(xml, contains('<work-title>Sonata No. 1</work-title>'));
    });

    test('creator element contains composer name', () {
      final xml = service.toMusicXml(minimalScore(composer: 'J.S. Bach'));
      expect(xml, contains('<creator type="composer">J.S. Bach</creator>'));
    });

    test('encoding element contains software name', () {
      final xml = service.toMusicXml(minimalScore());
      expect(xml, contains('<software>Note Vision</software>'));
    });

    test('encoding-date is present and formatted as YYYY-MM-DD', () {
      final xml = service.toMusicXml(minimalScore());
      final datePattern = RegExp(
        r'<encoding-date>\d{4}-\d{2}-\d{2}</encoding-date>',
      );
      expect(datePattern.hasMatch(xml), isTrue);
    });
  });

  // ---------------------------------------------------------------------------
  // Part list
  // ---------------------------------------------------------------------------

  group('part list', () {
    test('score-part element uses part id', () {
      final xml = service.toMusicXml(minimalScore());
      expect(xml, contains('<score-part id="P1">'));
    });

    test('part-name element contains part name', () {
      final xml = service.toMusicXml(minimalScore());
      expect(xml, contains('<part-name>Piano</part-name>'));
    });

    test('multiple parts all appear in part-list', () {
      final score = Score(
        id: 'id',
        title: 'T',
        composer: 'C',
        parts: [
          Part(
            id: 'P1',
            name: 'Violin',
            measures: [Measure(number: 1, symbols: const [])],
          ),
          Part(
            id: 'P2',
            name: 'Cello',
            measures: [Measure(number: 1, symbols: const [])],
          ),
        ],
      );
      final xml = service.toMusicXml(score);
      expect(xml, contains('<score-part id="P1">'));
      expect(xml, contains('<score-part id="P2">'));
      expect(xml, contains('<part-name>Violin</part-name>'));
      expect(xml, contains('<part-name>Cello</part-name>'));
    });
  });

  // ---------------------------------------------------------------------------
  // Measure attributes
  // ---------------------------------------------------------------------------

  group('measure attributes', () {
    test('first measure always has divisions element', () {
      final xml = service.toMusicXml(minimalScore());
      expect(xml, contains('<divisions>2</divisions>'));
    });

    test('treble clef emits sign G on line 2', () {
      final xml = service.toMusicXml(minimalScore());
      expect(xml, contains('<sign>G</sign>'));
      expect(xml, contains('<line>2</line>'));
    });

    test('bass clef emits sign F on line 4', () {
      final score = Score(
        id: 'id',
        title: 'T',
        composer: 'C',
        parts: [
          Part(
            id: 'P1',
            name: 'P',
            measures: [
              Measure(
                number: 1,
                clef: const Clef(sign: 'F', line: 4),
                symbols: const [],
              ),
            ],
          ),
        ],
      );
      final xml = service.toMusicXml(score);
      expect(xml, contains('<sign>F</sign>'));
      expect(xml, contains('<line>4</line>'));
    });

    test('time signature emits beats and beat-type', () {
      final xml = service.toMusicXml(minimalScore());
      expect(xml, contains('<beats>4</beats>'));
      expect(xml, contains('<beat-type>4</beat-type>'));
    });

    test('key signature emits fifths value', () {
      final xml = service.toMusicXml(minimalScore());
      expect(xml, contains('<fifths>0</fifths>'));
    });

    test('sharp key signature (G major = 1 sharp)', () {
      final score = Score(
        id: 'id',
        title: 'T',
        composer: 'C',
        parts: [
          Part(
            id: 'P1',
            name: 'P',
            measures: [
              Measure(
                number: 1,
                keySignature: const KeySignature(fifths: 1),
                symbols: const [],
              ),
            ],
          ),
        ],
      );
      final xml = service.toMusicXml(score);
      expect(xml, contains('<fifths>1</fifths>'));
    });

    test('flat key signature (F major = -1 flat)', () {
      final score = Score(
        id: 'id',
        title: 'T',
        composer: 'C',
        parts: [
          Part(
            id: 'P1',
            name: 'P',
            measures: [
              Measure(
                number: 1,
                keySignature: const KeySignature(fifths: -1),
                symbols: const [],
              ),
            ],
          ),
        ],
      );
      final xml = service.toMusicXml(score);
      expect(xml, contains('<fifths>-1</fifths>'));
    });

    test('subsequent measure without signatures has no attributes block', () {
      final score = Score(
        id: 'id',
        title: 'T',
        composer: 'C',
        parts: [
          Part(
            id: 'P1',
            name: 'P',
            measures: [
              Measure(
                number: 1,
                clef: const Clef(sign: 'G', line: 2),
                timeSignature: const TimeSignature(beats: 4, beatType: 4),
                keySignature: const KeySignature(fifths: 0),
                symbols: const [],
              ),
              Measure(number: 2, symbols: const []),
            ],
          ),
        ],
      );
      final xml = service.toMusicXml(score);
      // attributes block should appear exactly once
      expect('<attributes>'.allMatches(xml).length, 1);
    });

    test(
      'subsequent measure with new time signature gets an attributes block',
      () {
        final score = Score(
          id: 'id',
          title: 'T',
          composer: 'C',
          parts: [
            Part(
              id: 'P1',
              name: 'P',
              measures: [
                Measure(
                  number: 1,
                  clef: const Clef(sign: 'G', line: 2),
                  timeSignature: const TimeSignature(beats: 4, beatType: 4),
                  keySignature: const KeySignature(fifths: 0),
                  symbols: const [],
                ),
                Measure(
                  number: 2,
                  timeSignature: const TimeSignature(beats: 3, beatType: 4),
                  symbols: const [],
                ),
              ],
            ),
          ],
        );
        final xml = service.toMusicXml(score);
        expect(xml, contains('<beats>3</beats>'));
      },
    );
  });

  // ---------------------------------------------------------------------------
  // Note output
  // ---------------------------------------------------------------------------

  group('note output', () {
    test('basic note has pitch, duration, and type elements', () {
      final xml = service.toMusicXml(minimalScore());
      expect(xml, contains('<step>C</step>'));
      expect(xml, contains('<octave>4</octave>'));
      expect(xml, contains('<duration>2</duration>'));
      expect(xml, contains('<type>quarter</type>'));
    });

    test('alter element emitted for sharp note', () {
      final score = Score(
        id: 'id',
        title: 'T',
        composer: 'C',
        parts: [
          Part(
            id: 'P1',
            name: 'P',
            measures: [
              Measure(
                number: 1,
                symbols: const [
                  Note(
                    step: 'F',
                    octave: 4,
                    alter: 1,
                    duration: 2,
                    type: 'quarter',
                  ),
                ],
              ),
            ],
          ),
        ],
      );
      final xml = service.toMusicXml(score);
      expect(xml, contains('<alter>1</alter>'));
    });

    test('alter element emitted for flat note', () {
      final score = Score(
        id: 'id',
        title: 'T',
        composer: 'C',
        parts: [
          Part(
            id: 'P1',
            name: 'P',
            measures: [
              Measure(
                number: 1,
                symbols: const [
                  Note(
                    step: 'B',
                    octave: 4,
                    alter: -1,
                    duration: 2,
                    type: 'quarter',
                  ),
                ],
              ),
            ],
          ),
        ],
      );
      final xml = service.toMusicXml(score);
      expect(xml, contains('<alter>-1</alter>'));
    });

    test('alter element omitted when alter is 0', () {
      final score = Score(
        id: 'id',
        title: 'T',
        composer: 'C',
        parts: [
          Part(
            id: 'P1',
            name: 'P',
            measures: [
              Measure(
                number: 1,
                symbols: const [
                  Note(
                    step: 'C',
                    octave: 4,
                    alter: 0,
                    duration: 2,
                    type: 'quarter',
                  ),
                ],
              ),
            ],
          ),
        ],
      );
      final xml = service.toMusicXml(score);
      expect(xml, isNot(contains('<alter>')));
    });

    test('alter element omitted when alter is null', () {
      final xml = service.toMusicXml(minimalScore());
      expect(xml, isNot(contains('<alter>')));
    });

    test('voice element emitted when present', () {
      final score = Score(
        id: 'id',
        title: 'T',
        composer: 'C',
        parts: [
          Part(
            id: 'P1',
            name: 'P',
            measures: [
              Measure(
                number: 1,
                symbols: const [
                  Note(
                    step: 'C',
                    octave: 4,
                    duration: 2,
                    type: 'quarter',
                    voice: 1,
                  ),
                ],
              ),
            ],
          ),
        ],
      );
      final xml = service.toMusicXml(score);
      expect(xml, contains('<voice>1</voice>'));
    });

    test('staff element emitted when present', () {
      final score = Score(
        id: 'id',
        title: 'T',
        composer: 'C',
        parts: [
          Part(
            id: 'P1',
            name: 'P',
            measures: [
              Measure(
                number: 1,
                symbols: const [
                  Note(
                    step: 'C',
                    octave: 4,
                    duration: 2,
                    type: 'quarter',
                    staff: 1,
                  ),
                ],
              ),
            ],
          ),
        ],
      );
      final xml = service.toMusicXml(score);
      expect(xml, contains('<staff>1</staff>'));
    });

    test('voice and staff omitted when null', () {
      final xml = service.toMusicXml(minimalScore());
      expect(xml, isNot(contains('<voice>')));
      expect(xml, isNot(contains('<staff>')));
    });
  });

  // ---------------------------------------------------------------------------
  // Rest output
  // ---------------------------------------------------------------------------

  group('rest output', () {
    test('rest emits rest element, duration, and type', () {
      final score = Score(
        id: 'id',
        title: 'T',
        composer: 'C',
        parts: [
          Part(
            id: 'P1',
            name: 'P',
            measures: [
              Measure(
                number: 1,
                symbols: const [Rest(duration: 2, type: 'quarter')],
              ),
            ],
          ),
        ],
      );
      final xml = service.toMusicXml(score);
      expect(xml, contains('<rest/>'));
      expect(xml, contains('<duration>2</duration>'));
      expect(xml, contains('<type>quarter</type>'));
    });

    test('rest voice and staff emitted when present', () {
      final score = Score(
        id: 'id',
        title: 'T',
        composer: 'C',
        parts: [
          Part(
            id: 'P1',
            name: 'P',
            measures: [
              Measure(
                number: 1,
                symbols: const [
                  Rest(duration: 2, type: 'quarter', voice: 2, staff: 1),
                ],
              ),
            ],
          ),
        ],
      );
      final xml = service.toMusicXml(score);
      expect(xml, contains('<voice>2</voice>'));
      expect(xml, contains('<staff>1</staff>'));
    });

    test('whole rest has duration 8', () {
      final score = Score(
        id: 'id',
        title: 'T',
        composer: 'C',
        parts: [
          Part(
            id: 'P1',
            name: 'P',
            measures: [
              Measure(
                number: 1,
                symbols: const [Rest(duration: 8, type: 'whole')],
              ),
            ],
          ),
        ],
      );
      final xml = service.toMusicXml(score);
      expect(xml, contains('<duration>8</duration>'));
      expect(xml, contains('<type>whole</type>'));
    });
  });

  // ---------------------------------------------------------------------------
  // Duration values
  // ---------------------------------------------------------------------------

  group('duration values match DurationSpec constants', () {
    for (final entry in const [
      ('whole', 8),
      ('half', 4),
      ('quarter', 2),
      ('eighth', 1),
    ]) {
      final (type, divisions) = entry;
      test('$type note has duration $divisions', () {
        final score = Score(
          id: 'id',
          title: 'T',
          composer: 'C',
          parts: [
            Part(
              id: 'P1',
              name: 'P',
              measures: [
                Measure(
                  number: 1,
                  symbols: [
                    Note(step: 'C', octave: 4, duration: divisions, type: type),
                  ],
                ),
              ],
            ),
          ],
        );
        final xml = service.toMusicXml(score);
        expect(xml, contains('<duration>$divisions</duration>'));
        expect(xml, contains('<type>$type</type>'));
      });
    }
  });

  // ---------------------------------------------------------------------------
  // Multiple parts and measures
  // ---------------------------------------------------------------------------

  group('multiple parts', () {
    test('each part gets its own part element with correct id', () {
      final score = Score(
        id: 'id',
        title: 'T',
        composer: 'C',
        parts: [
          Part(
            id: 'P1',
            name: 'Violin',
            measures: [Measure(number: 1, symbols: const [])],
          ),
          Part(
            id: 'P2',
            name: 'Cello',
            measures: [Measure(number: 1, symbols: const [])],
          ),
        ],
      );
      final xml = service.toMusicXml(score);
      expect(xml, contains('<part id="P1">'));
      expect(xml, contains('<part id="P2">'));
    });
  });

  group('multiple measures', () {
    test('measure numbers appear in order', () {
      final score = Score(
        id: 'id',
        title: 'T',
        composer: 'C',
        parts: [
          Part(
            id: 'P1',
            name: 'P',
            measures: [
              Measure(number: 1, symbols: const []),
              Measure(number: 2, symbols: const []),
              Measure(number: 3, symbols: const []),
            ],
          ),
        ],
      );
      final xml = service.toMusicXml(score);
      final m1 = xml.indexOf('measure number="1"');
      final m2 = xml.indexOf('measure number="2"');
      final m3 = xml.indexOf('measure number="3"');
      expect(m1, lessThan(m2));
      expect(m2, lessThan(m3));
    });
  });

  // ---------------------------------------------------------------------------
  // Edge cases
  // ---------------------------------------------------------------------------

  group('edge cases', () {
    test('empty parts list produces valid xml without crashing', () {
      final score = Score(id: 'id', title: 'T', composer: 'C', parts: const []);
      expect(() => service.toMusicXml(score), returnsNormally);
    });

    test('empty title still produces work-title element', () {
      final score = Score(id: 'id', title: '', composer: 'C', parts: const []);
      final xml = service.toMusicXml(score);
      expect(xml, contains('<work-title>'));
    });

    test('empty symbols list in measure produces valid output', () {
      final score = Score(
        id: 'id',
        title: 'T',
        composer: 'C',
        parts: [
          Part(
            id: 'P1',
            name: 'P',
            measures: [Measure(number: 1, symbols: const [])],
          ),
        ],
      );
      expect(() => service.toMusicXml(score), returnsNormally);
    });
  });

  // ---------------------------------------------------------------------------
  // Safe file name helper (tested indirectly via toMusicXml — pure logic)
  // ---------------------------------------------------------------------------

  group('safe file name logic (via title round-trip)', () {
    // The _safeFileName method is private, but we verify the title content
    // is preserved correctly in work-title (the title is passed through as-is
    // to XML; only the file name is sanitised on export).
    test('title with spaces and slashes is preserved in work-title', () {
      final xml = service.toMusicXml(
        minimalScore(title: 'Sonata / No. 1 in C'),
      );
      expect(xml, contains('<work-title>Sonata / No. 1 in C</work-title>'));
    });
  });
}
