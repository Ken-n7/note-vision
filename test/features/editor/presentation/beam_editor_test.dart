import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:note_vision/core/models/beam_grouping.dart';
import 'package:note_vision/core/models/clef.dart';
import 'package:note_vision/core/models/measure.dart';
import 'package:note_vision/core/models/note.dart';
import 'package:note_vision/core/models/part.dart';
import 'package:note_vision/core/models/rest.dart';
import 'package:note_vision/core/models/score.dart';
import 'package:note_vision/core/models/score_symbol.dart';
import 'package:note_vision/core/models/time_signature.dart';
import 'package:note_vision/core/services/playback_service.dart';
import 'package:note_vision/core/widgets/score_notation_viewer.dart';
import 'package:note_vision/features/editor/presentation/widgets/beam_editor_sheet.dart';

import '../../../support/editor_controls_harness.dart';

Score beamScore({List<ScoreSymbol>? symbols}) => Score(
  id: 'beam-editor',
  title: 'Beam Study',
  composer: '',
  parts: [
    Part(
      id: 'P1',
      name: 'Staff',
      measures: [
        Measure(
          number: 1,
          clef: const Clef(sign: 'G', line: 2),
          timeSignature: const TimeSignature(beats: 4, beatType: 4),
          symbols:
              symbols ??
              [
                for (var i = 0; i < 8; i++)
                  Note(
                    step: ['C', 'D', 'E', 'F'][i % 4],
                    octave: 4,
                    duration: 1,
                    type: 'eighth',
                  ),
              ],
        ),
      ],
    ),
  ],
);

Future<void> openBeams(WidgetTester tester, {bool portrait = true}) async {
  if (portrait) {
    await tester.tap(find.byTooltip('Duration tools'));
    await tester.pumpAndSettle();
  } else {
    await tester.ensureVisible(find.text('Beams'));
  }
  await tester.tap(find.text('Beams'));
  await tester.pumpAndSettle();
  expect(find.byType(BeamEditorSheet), findsOneWidget);
}

Future<void> tapAction(WidgetTester tester, String label) async {
  await tester.ensureVisible(find.text(label));
  await tester.tap(find.text(label));
  await tester.pumpAndSettle();
}

List<ScoreSymbol> previewSymbols(WidgetTester tester) => tester
    .widget<ScoreNotationViewer>(find.byKey(const ValueKey('beam-preview')))
    .score!
    .parts
    .single
    .measures
    .single
    .symbols;

void main() {
  setUpAll(loadControlsFonts);

  for (final (name, size, scale) in [
    ('phone', const Size(390, 844), 1.0),
    ('small-phone', const Size(320, 568), 1.0),
    ('large-text', const Size(320, 568), 2.0),
    ('landscape', const Size(844, 390), 1.0),
    ('tablet', const Size(1024, 768), 2.0),
  ]) {
    testWidgets('beam sheet fits $name and supports a beat-group preview', (
      tester,
    ) async {
      await pumpControls(
        tester,
        score: beamScore(),
        size: size,
        textScale: scale,
      );
      await openBeams(tester, portrait: size.width < size.height);
      expect(tester.takeException(), isNull);
      await captureControls(tester, 'beams-$name');
      await tapAction(tester, 'Group by beat');
      expect(tester.takeException(), isNull);
      expect(BeamGrouping.groups(previewSymbols(tester)), [
        [0, 1],
        [2, 3],
        [4, 5],
        [6, 7],
      ]);
      expect(
        BeamGrouping.groups(
          shownControlsScore(tester).parts.single.measures.single.symbols,
        ),
        isEmpty,
      );
      await captureControls(tester, 'beams-$name-preview');
    });
  }

  testWidgets('a custom range applies once, then undo and redo restore it', (
    tester,
  ) async {
    await pumpControls(tester, score: beamScore(), size: const Size(390, 844));
    await openBeams(tester);
    await tester.tap(find.byKey(const ValueKey('beam-note-3')));
    await tester.pumpAndSettle();
    await tapAction(tester, 'Beam together');
    expect(BeamGrouping.groups(previewSymbols(tester)), [
      [0, 1, 2, 3],
    ]);
    final join = tester.widget<OutlinedButton>(
      find.ancestor(
        of: find.text('Beam together'),
        matching: find.byWidgetPredicate((widget) => widget is OutlinedButton),
      ),
    );
    expect(join.onPressed, isNull);
    expect(find.textContaining('without a rest'), findsNothing);
    await tapAction(tester, 'Apply');
    expect(find.byType(BeamEditorSheet), findsNothing);
    expect(
      BeamGrouping.groups(
        shownControlsScore(tester).parts.single.measures.single.symbols,
      ),
      [
        [0, 1, 2, 3],
      ],
    );
    await tester.tap(find.byTooltip('Undo'));
    await tester.pumpAndSettle();
    expect(
      BeamGrouping.groups(
        shownControlsScore(tester).parts.single.measures.single.symbols,
      ),
      isEmpty,
    );
    await tester.tap(find.byTooltip('Redo'));
    await tester.pumpAndSettle();
    expect(
      BeamGrouping.groups(
        shownControlsScore(tester).parts.single.measures.single.symbols,
      ),
      [
        [0, 1, 2, 3],
      ],
    );
  });

  testWidgets('cancel discards preview and reset disables apply', (
    tester,
  ) async {
    await pumpControls(tester, score: beamScore(), size: const Size(390, 844));
    final original = shownControlsScore(tester).toJson();
    await openBeams(tester);
    await tapAction(tester, 'Group by beat');
    await tapAction(tester, 'Reset');
    expect(BeamGrouping.groups(previewSymbols(tester)), isEmpty);
    final apply = tester.widget<FilledButton>(
      find.ancestor(
        of: find.text('Apply'),
        matching: find.byWidgetPredicate((widget) => widget is FilledButton),
      ),
    );
    expect(apply.onPressed, isNull);
    await tapAction(tester, 'Group by beat');
    await tester.tap(find.byTooltip('Cancel beam editing'));
    await tester.pumpAndSettle();
    expect(shownControlsScore(tester).toJson(), original);
  });

  testWidgets('a rest inside a chosen range prevents joining', (tester) async {
    final note = const Note(step: 'C', octave: 4, duration: 1, type: 'eighth');
    await pumpControls(
      tester,
      score: beamScore(
        symbols: [
          note,
          const Rest(duration: 1, type: 'eighth'),
          note,
        ],
      ),
      size: const Size(390, 844),
    );
    await openBeams(tester);
    await tester.tap(find.byKey(const ValueKey('beam-note-2')));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Beam together'));
    final join = tester.widget<OutlinedButton>(
      find.ancestor(
        of: find.text('Beam together'),
        matching: find.byWidgetPredicate((widget) => widget is OutlinedButton),
      ),
    );
    expect(join.onPressed, isNull);
    expect(find.textContaining('without a rest'), findsOneWidget);
  });

  testWidgets('beam editing is disabled during playback', (tester) async {
    final (playback, _) = await pumpControls(tester, score: beamScore());
    expect(controlsAction(tester, 'Beams').onTap, isNotNull);
    playback.emit(PlaybackStatus.playing);
    await tester.pumpAndSettle();
    expect(controlsAction(tester, 'Beams').onTap, isNull);
  });

  testWidgets('screen readers can choose the range endpoints', (tester) async {
    final semantics = tester.ensureSemantics();
    try {
      await pumpControls(
        tester,
        score: beamScore(),
        size: const Size(390, 844),
      );
      await openBeams(tester);
      final note = tester.getSemantics(
        find.bySemanticsLabel('Note 4, F4, eighth'),
      );
      expect(note.getSemanticsData().hasAction(ui.SemanticsAction.tap), isTrue);
      note.owner!.performAction(note.id, ui.SemanticsAction.tap);
      await tester.pumpAndSettle();
      final viewer = tester.widget<ScoreNotationViewer>(
        find.byKey(const ValueKey('beam-preview')),
      );
      expect(viewer.selectedSymbolIndices, {0, 1, 2, 3});
      await tapAction(tester, 'Beam together');
      expect(BeamGrouping.groups(previewSymbols(tester)), [
        [0, 1, 2, 3],
      ]);
    } finally {
      semantics.dispose();
    }
  });

  testWidgets(
    'break and separate controls preserve distinct neighbouring groups',
    (tester) async {
      final symbols = BeamGrouping.join(
        beamScore().parts.single.measures.single.symbols,
        0,
        3,
      );
      await pumpControls(
        tester,
        score: beamScore(symbols: symbols),
        size: const Size(390, 844),
      );
      await openBeams(tester);
      await tester.ensureVisible(find.byKey(const ValueKey('beam-note-2')));
      await tester.tap(find.byKey(const ValueKey('beam-note-2')));
      await tester.pumpAndSettle();
      await tapAction(tester, 'Break before');
      expect(BeamGrouping.groups(previewSymbols(tester)), [
        [0, 1],
        [2, 3],
      ]);
      await tapAction(tester, 'Separate notes');
      expect(BeamGrouping.groups(previewSymbols(tester)), [
        [0, 1],
      ]);
      await tapAction(tester, 'Apply');
      expect(
        BeamGrouping.groups(
          shownControlsScore(tester).parts.single.measures.single.symbols,
        ),
        [
          [0, 1],
        ],
      );
    },
  );
}
