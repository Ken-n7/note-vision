import 'package:flutter_test/flutter_test.dart';
import 'package:note_vision/core/models/measure.dart';
import 'package:note_vision/core/models/note.dart';
import 'package:note_vision/core/models/part.dart';
import 'package:note_vision/core/models/score.dart';
import 'package:note_vision/core/widgets/score_notation/lyric_layout.dart';
import 'package:note_vision/features/editor/presentation/editor_layout_policy.dart';
import 'package:note_vision/features/pdf/pdf_score_renderer.dart';

Note note(List<Lyric> lyrics, {int voice = 1}) => Note(
  step: 'C',
  octave: 4,
  duration: 2,
  type: 'quarter',
  voice: voice,
  lyrics: lyrics,
);
LyricDrawing draw(List<LyricAnchor> notes, int system) => LyricLayout.build(
  notes: notes,
  system: system,
  staffTop: 28,
  staffBottom: 76,
  left: 100,
  right: 700,
  textWidth: (text) => text.length * 6.0,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('syllables center on notes with separate verse lines and a hyphen', () {
    final result = draw([
      LyricAnchor(
        note([
          const Lyric(text: 'Hap', syllabic: Syllabic.begin),
          const Lyric(text: 'Good', verse: '2'),
        ]),
        0,
        200,
      ),
      LyricAnchor(
        note([const Lyric(text: 'py', syllabic: Syllabic.end)]),
        0,
        260,
      ),
    ], 0);
    expect(result.texts.map((t) => (t.text, t.x, t.y)), [
      ('Hap', 191.0, 122.0),
      ('py', 254.0, 122.0),
      ('Good', 188.0, 140.0),
    ]);
    expect(result.lines, hasLength(1));
    expect(result.lines.single.y, 118);
  });

  test('hyphens and melismas split across systems and page boundaries', () {
    final notes = [
      LyricAnchor(
        note([const Lyric(text: 'hold', extend: LyricExtend.start)]),
        -1,
        650,
      ),
      LyricAnchor(note([]), 0, 200),
      LyricAnchor(
        note([const Lyric(text: '', extend: LyricExtend.stop)]),
        1,
        250,
      ),
      LyricAnchor(
        note([const Lyric(text: 'a', syllabic: Syllabic.begin)]),
        1,
        400,
      ),
      LyricAnchor(
        note([const Lyric(text: 'men', syllabic: Syllabic.end)]),
        2,
        200,
      ),
    ];
    final page = draw(notes, 0);
    expect(page.texts, isEmpty);
    expect((page.lines.single.x1, page.lines.single.x2), (100, 700));
    final next = draw(notes, 1);
    expect(next.lines, hasLength(2));
    expect(next.lines.first.x2, 258);
  });

  test(
    'different voices never share connectors; hidden lyrics do not draw',
    () {
      final result = draw([
        LyricAnchor(
          note([const Lyric(text: 'a', syllabic: Syllabic.begin)]),
          0,
          200,
        ),
        LyricAnchor(note([const Lyric(text: 'other')], voice: 2), 0, 250),
        LyricAnchor(note([const Lyric(text: 'hidden', hidden: true)]), 0, 300),
      ], 0);
      expect(result.lines, isEmpty);
      expect(result.texts.map((t) => t.text), ['a', 'other']);
    },
  );

  test('many verses reserve matching editor and PDF pagination', () async {
    final score = Score(
      id: 'verses',
      title: 'Verses',
      composer: '',
      parts: [
        Part(
          id: 'P1',
          name: 'Voice',
          measures: [
            for (var i = 0; i < 21; i++)
              Measure(
                number: i + 1,
                symbols: [
                  note([
                    for (var verse = 1; verse <= 8; verse++)
                      Lyric(text: 'Verse $verse', verse: '$verse'),
                  ]),
                ],
              ),
          ],
        ),
      ],
    );
    final policy = EditorLayoutPolicy.forScore(score);
    expect(policy.rowHeight, 266);
    expect(policy.rowsPerPage, 3);
    final pdf = const PdfScoreRenderer();
    final pages = pdf.debugPageLayoutForTesting(score);
    expect(pages.first.rowsPerPage, policy.rowsPerPage);
    expect(
      pages.map((p) => p.firstMeasureIndex),
      pageStartIndicesForMeasures(
        score.parts.first.measures,
        layoutPolicy: policy,
      ),
    );
    expect((await pdf.render(score)).length, greaterThan(1000));
  });
}
