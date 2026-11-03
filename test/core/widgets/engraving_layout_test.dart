import 'package:flutter_test/flutter_test.dart';
import 'package:note_vision/core/models/measure.dart';
import 'package:note_vision/core/models/musical_time.dart';
import 'package:note_vision/core/models/note.dart';
import 'package:note_vision/core/models/part.dart';
import 'package:note_vision/core/models/rest.dart';
import 'package:note_vision/core/models/score.dart';
import 'package:note_vision/core/widgets/score_notation/engraving_layout.dart';
import 'package:note_vision/core/widgets/score_notation/score_notation_metrics.dart';
import 'package:note_vision/features/pdf/pdf_score_renderer.dart';
import 'package:note_vision/core/widgets/score_notation/annotation_layout.dart';
import 'package:note_vision/features/editor/presentation/editor_layout_policy.dart';
import 'package:note_vision/features/musicXML/musicxml_score_converter.dart';
import 'package:xml/xml.dart';
import '../../support/engraving_fixture.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'annotation positions keep rational beats without decimal conversion',
    () {
      final m = Measure(
        number: 1,
        symbols: [engravingNote('C')],
        annotations: [
          ScoreAnnotation(
            kind: AnnotationKind.staffText,
            text: 'triplet beat',
            offset: MusicalTime(1, 3),
          ),
        ],
      );
      final parts = [
        [m],
      ];
      final b = EngravingLayout(parts).bars.single.place(width: 400);
      final text = AnnotationLayout.build(
        parts: parts,
        part: 0,
        measure: 0,
        visible: m,
        startX: 0,
        width: 400,
        staffTop: 100,
        staffBottom: 148,
        inset: 16,
        placement: b,
      ).single;
      expect(text.x, b.timeX(MusicalTime(1, 3)));
    },
  );
  test('manual page breaks still allow automatic overflow pages', () {
    final score = engravingFixture();
    final dense = score.parts.single.measures[1];
    final measures = [
      for (var i = 0; i < 18; i++)
        dense.copyWith(number: i + 1, startsNewPage: i == 7),
    ];
    final long = score.copyWith(
      parts: [Part(id: 'P1', name: 'Voice', measures: measures)],
    );
    final policy = EditorLayoutPolicy.forScore(long);
    final starts = pageStartIndicesForMeasures(measures, layoutPolicy: policy);
    expect(starts, contains(7));
    final pages = const PdfScoreRenderer().debugPageLayoutForTesting(long);
    expect(pages.map((p) => p.firstMeasureIndex), starts);
    expect(pages.every((p) => p.measureCount <= policy.measuresPerPage), true);
    expect(pages.fold(0, (n, p) => n + p.measureCount), 18);
  });
  test('ledger lines follow the staff grid above and below it', () {
    expect(ScoreNotationMetrics.ledgerYs(54), isEmpty);
    expect(ScoreNotationMetrics.ledgerYs(60), [60.0]);
    expect(ScoreNotationMetrics.ledgerYs(78), [60.0, 72.0]);
    expect(ScoreNotationMetrics.ledgerYs(-24), [-12.0, -24.0]);
  });
  test('editor and PDF include final bars of a longer lower staff', () {
    final score = Score(
      id: 'longer',
      title: '',
      composer: '',
      parts: [
        const Part(
          id: 'P1',
          name: 'Short',
          measures: [Measure(number: 1, symbols: [])],
        ),
        Part(
          id: 'P2',
          name: 'Long',
          measures: [
            for (var i = 0; i < 25; i++)
              Measure(number: i + 1, symbols: [engravingNote('C')]),
          ],
        ),
      ],
    );
    final reference = layoutMeasuresForScore(score);
    final policy = EditorLayoutPolicy.forScore(score);
    final starts = pageStartIndicesForMeasures(reference, layoutPolicy: policy);
    final pdf = const PdfScoreRenderer().debugPageLayoutForTesting(score);
    expect(reference.length, 25);
    expect(pdf.map((p) => p.firstMeasureIndex), starts);
    expect(pdf.fold(0, (n, p) => n + p.measureCount), 25);
  });
  BarEngraving bar(List<Note> notes) => EngravingLayout([
    [Measure(number: 1, symbols: notes)],
  ]).bars.single;
  test('duration springs give longer notes more space, with exact onsets', () {
    final b = bar([
      engravingNote('C', type: 'half'),
      engravingNote('D'),
      engravingNote('E', type: 'eighth'),
      engravingNote('F', type: 'eighth'),
    ]);
    final placed = b.place(width: 500);
    final xs = [for (var i = 0; i < 4; i++) placed.symbolX(0, i)];
    expect(xs[1] - xs[0], greaterThan(xs[2] - xs[1]));
    expect(xs[2] - xs[1], greaterThan(xs[3] - xs[2]));
    expect(b.staff.single.keys.map((k) => k.$1), [
      MusicalTime.zero,
      MusicalTime(2),
      MusicalTime(3),
      MusicalTime(7, 2),
    ]);
  });
  test('grace notes stay compact immediately before aligned main notes', () {
    final b = bar([
      engravingNote('C'),
      engravingNote('D', grace: Grace.appoggiatura, type: 'eighth'),
      engravingNote('E', grace: Grace.appoggiatura, type: 'eighth'),
      engravingNote('F'),
    ]);
    final placed = b.place(width: 500);
    final xs = [for (var i = 0; i < 4; i++) placed.symbolX(0, i)];
    expect(xs[2] - xs[1], lessThan(24));
    expect(xs[3] - xs[2], lessThan(24));
    expect(xs[1] - xs[0], greaterThan(70));
    expect(b.staff.single.keys[3].$1, MusicalTime.one);
  });
  test(
    'all staves share time positions even with different rhythm densities',
    () {
      final parts = [
        [
          Measure(
            number: 1,
            symbols: [
              engravingNote('C', type: 'half'),
              engravingNote('G', type: 'half'),
            ],
          ),
        ],
        [
          Measure(
            number: 1,
            symbols: [
              for (final step in ['C', 'D', 'E', 'F']) engravingNote(step),
            ],
          ),
        ],
      ];
      final placed = EngravingLayout(parts).bars.single.place(width: 400);
      expect(placed.symbolX(0, 0), placed.symbolX(1, 0));
      expect(placed.symbolX(0, 1), placed.symbolX(1, 2));
    },
  );
  test('source forward gaps and sub-960th onsets remain distinct', () {
    final score = const MusicXmlScoreConverter().convert(
      XmlDocument.parse('''
      <score-partwise><part-list><score-part id="P1"><part-name>Voice</part-name></score-part></part-list>
      <part id="P1"><measure number="1"><attributes><divisions>2000</divisions></attributes>
      <forward><duration>1</duration></forward>
      <note><pitch><step>C</step><octave>4</octave></pitch><duration>1</duration><type>quarter</type></note>
      <note><pitch><step>D</step><octave>4</octave></pitch><duration>1998</duration><type>quarter</type></note>
      </measure></part></score-partwise>'''),
    );
    final b = EngravingLayout.forScore(score).bars.single;
    expect(b.staff.single.keys.map((k) => k.$1), [
      MusicalTime(1, 2000),
      MusicalTime(1, 1000),
    ]);
    final placed = b.place(width: 400);
    expect(
      placed.symbolX(0, 1) - placed.symbolX(0, 0),
      greaterThanOrEqualTo(20),
    );
    expect(placed.symbolX(0, 0), greaterThan(placed.timeX(MusicalTime.zero)));
  });
  test(
    'chord seconds alternate heads, accidentals stack, voices stay distinct',
    () {
      final b = EngravingLayout.forScore(engravingFixture()).bars.last;
      final placed = b.place(width: b.minimumWidth + 40), s = b.staff.single;
      expect(s.headOffsets.take(4), [0, 12, 0, 12]);
      final accidentals = [
        for (var i = 0; i < 4; i++)
          placed.symbolX(0, i) + s.accidentalOffsets[i]!,
      ];
      expect(accidentals.toSet(), hasLength(4));
      expect(
        placed.symbolX(0, 6) - placed.symbolX(0, 0),
        greaterThanOrEqualTo(18),
      );
      expect(placed.stemX(0, 0), placed.stemX(0, 1));
      expect(s.stemStarts[0], 0);
      expect(s.stemEnds[0], closeTo(-58.8, 1e-8));
    },
  );
  test('long lyrics and annotations reserve ink space inside the bar', () {
    final b = EngravingLayout.forScore(engravingFixture()).bars[2];
    final placed = b.place(width: b.minimumWidth + 20);
    final symbols = b.measures.single!.symbols;
    double? previousRight;
    for (final (i, s) in symbols.indexed) {
      if (s is! Note || s.lyrics.isEmpty) continue;
      final half = EngravingLayout.textWidth(s.lyrics.single.text) / 2;
      final left = placed.symbolX(0, i) - half,
          right = placed.symbolX(0, i) + half;
      expect(left, greaterThanOrEqualTo(0));
      expect(right, lessThanOrEqualTo(placed.width));
      if (previousRight != null) expect(left, greaterThan(previousRight));
      previousRight = right;
    }
  });
  test('same-kind simultaneous text stacks in separate reserved lanes', () {
    final score = engravingFixture();
    final parts = [score.parts.single.measures];
    final m = parts.single[2];
    final drawing = AnnotationLayout.build(
      parts: parts,
      part: 0,
      measure: 2,
      visible: m,
      startX: 0,
      width: 500,
      staffTop: 100,
      staffBottom: 148,
      inset: 16,
    );
    expect(drawing[0].x, drawing[1].x);
    expect((drawing[0].y - drawing[1].y).abs(), 20);
    expect(AnnotationLayout.aboveHeight(parts), 60);
    expect(drawing.every((t) => t.y <= 60), true);
  });
  test(
    'dense bars adapt row count; PDF-sized pages keep all minimum ink space',
    () {
      final score = engravingFixture(),
          policy = EditorLayoutPolicy.forScore(engravingFixture());
      expect(policy.measuresPerRow, lessThan(4));
      expect(
        policy.minMeasureWidth,
        greaterThanOrEqualTo(EngravingLayout.forScore(score).minimumBarWidth),
      );
    },
  );
  test('shorter ensemble staves leave missing bars empty without crashing', () {
    final engraving = EngravingLayout([
      [
        Measure(number: 1, symbols: [engravingNote('C')]),
        Measure(number: 2, symbols: [engravingNote('D')]),
      ],
      [
        Measure(number: 1, symbols: [engravingNote('G')]),
      ],
    ]);
    expect(engraving.bars, hasLength(2));
    expect(engraving.bars.last.staff[1].symbols, isEmpty);
    expect(
      engraving.bars.last.place(width: 200).symbolX(0, 0),
      greaterThan(16),
    );
  });
  test(
    'bar rests stay centered and extreme notes reserve vertical clearance',
    () {
      final b = EngravingLayout([
        [
          Measure(
            number: 1,
            symbols: const [
              Rest(duration: 8, type: 'whole', measureRest: true),
            ],
          ),
        ],
      ]).bars.single;
      expect(b.place(width: 320).symbolX(0, 0), 160);
      final score = Score(
        id: 'extreme',
        title: '',
        composer: '',
        parts: [
          Part(
            id: 'P1',
            name: '',
            measures: [
              Measure(
                number: 1,
                symbols: [
                  engravingNote('C', octave: 7, voice: 1),
                  engravingNote('C', octave: 2, voice: 2),
                ],
              ),
            ],
          ),
        ],
      );
      final c = EngravingLayout.forScore(score).clearance;
      expect(c.$1, greaterThan(50));
      expect(c.$2, greaterThan(50));
      expect(EditorLayoutPolicy.forScore(score).rowHeight, greaterThan(240));
    },
  );
}
