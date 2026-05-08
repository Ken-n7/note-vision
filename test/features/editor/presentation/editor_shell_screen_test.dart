import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:note_vision/core/models/measure.dart';
import 'package:note_vision/core/models/note.dart';
import 'package:note_vision/core/models/part.dart';
import 'package:note_vision/core/models/rest.dart';
import 'package:note_vision/core/models/score.dart';
import 'package:note_vision/core/services/playback_service.dart';
import 'package:note_vision/core/widgets/score_notation_viewer.dart';
import 'package:note_vision/core/widgets/score_notation/notation_layout.dart';
import 'package:note_vision/core/widgets/score_notation/score_notation_painter.dart';
import 'package:note_vision/features/editor/model/editor_state.dart';
import 'package:note_vision/features/editor/presentation/editor_layout_policy.dart';
import 'package:note_vision/features/editor/presentation/editor_shell_screen.dart';

void main() {
  group('pageStartIndicesForMeasures', () {
    test('does not create a duplicate first page when measure 1 is flagged', () {
      final measures = [
        const Measure(number: 1, symbols: [], startsNewPage: true),
        const Measure(number: 2, symbols: []),
        const Measure(number: 3, symbols: []),
      ];

      expect(pageStartIndicesForMeasures(measures), const [0]);
    });

    test('uses explicit startsNewPage markers when present', () {
      final measures = [
        const Measure(number: 1, symbols: []),
        const Measure(number: 2, symbols: [], startsNewPage: true),
        const Measure(number: 3, symbols: []),
      ];

      expect(pageStartIndicesForMeasures(measures), const [0, 1]);
    });

    test('falls back to fixed page buckets for older scores', () {
      final measures = List.generate(
        21,
        (i) => Measure(number: i + 1, symbols: const []),
      );

      expect(pageStartIndicesForMeasures(measures), const [0, 20]);
    });

    test('uses the provided layout policy for fallback page buckets', () {
      final measures = List.generate(
        7,
        (i) => Measure(number: i + 1, symbols: const []),
      );

      expect(
        pageStartIndicesForMeasures(
          measures,
          layoutPolicy: const EditorLayoutPolicy(
            measuresPerRow: 2,
            rowsPerPage: 2,
          ),
        ),
        const [0, 4],
      );
    });

    test('part-count-derived policy reduces fallback measures per page', () {
      final measures = List.generate(
        9,
        (i) => Measure(number: i + 1, symbols: const []),
      );

      expect(
        pageStartIndicesForMeasures(
          measures,
          layoutPolicy: EditorLayoutPolicy.forPartCount(4),
        ),
        const [0, 4, 8],
      );
    });
  });

  group('pageIndexForMeasure', () {
    test('returns page 0 when page starts are empty', () {
      expect(pageIndexForMeasure(const [], 0), 0);
      expect(pageIndexForMeasure(const [], 12), 0);
    });

    test('uses explicit page starts instead of fixed 9-measure buckets', () {
      expect(pageIndexForMeasure(const [0, 1], 0), 0);
      expect(pageIndexForMeasure(const [0, 1], 1), 1);
      expect(pageIndexForMeasure(const [0, 1], 4), 1);
    });

    test('keeps later playback positions on the most recent page start', () {
      const pageStarts = [0, 5, 8];

      expect(pageIndexForMeasure(pageStarts, 0), 0);
      expect(pageIndexForMeasure(pageStarts, 4), 0);
      expect(pageIndexForMeasure(pageStarts, 5), 1);
      expect(pageIndexForMeasure(pageStarts, 7), 1);
      expect(pageIndexForMeasure(pageStarts, 8), 2);
      expect(pageIndexForMeasure(pageStarts, 12), 2);
    });
  });

  Future<void> pumpEditorShell(
    WidgetTester tester, {
    required Score score,
    Size surfaceSize = const Size(1600, 900),
  }) async {
    tester.view.physicalSize = surfaceSize;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        home: EditorShellScreen(
          args: EditorShellArgs(
            score: score,
            initialState: EditorState(score: score),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  InkWell actionTileForLabel(WidgetTester tester, String label) {
    final finder = find.ancestor(
      of: find.text(label),
      matching: find.byType(InkWell),
    );
    return tester.widget<InkWell>(finder.first);
  }

  Score buildScore({bool withSymbols = true}) {
    return Score(
      id: 'score-1',
      title: 'Test Score',
      composer: 'Composer',
      parts: [
        Part(
          id: 'P1',
          name: 'Part 1',
          measures: [
            Measure(
              number: 1,
              symbols: withSymbols
                  ? const [
                      Note(step: 'C', octave: 4, duration: 1, type: 'quarter'),
                      Rest(duration: 1, type: 'quarter'),
                    ]
                  : const [],
            ),
          ],
        ),
      ],
    );
  }

  testWidgets('renders editor shell sections and action buttons', (
    tester,
  ) async {
    final score = buildScore();

    await pumpEditorShell(tester, score: score);

    expect(find.text('Test Score'), findsOneWidget);
    expect(find.text('Score Editor · Simple Melody'), findsOneWidget);
    expect(find.text('Save'), findsOneWidget);
    expect(find.text('Up'), findsOneWidget);
    expect(find.text('Down'), findsOneWidget);
    expect(find.text('Whole'), findsWidgets);
    expect(find.text('Half'), findsWidgets);
    expect(find.text('Qtr'), findsOneWidget);
    expect(find.text('8th'), findsOneWidget);
    expect(find.text('CLEF'), findsOneWidget);
    expect(find.text('Treble'), findsOneWidget);
    expect(find.text('Bass'), findsOneWidget);
    expect(find.text('Add'), findsOneWidget);
    expect(find.byTooltip('Undo'), findsOneWidget);
    expect(find.byTooltip('Redo'), findsOneWidget);
    expect(find.byTooltip('More'), findsOneWidget);
  });

  testWidgets('uses overflow menu for scan and export actions on narrow screens', (
    tester,
  ) async {
    final score = Score(
      id: 'score-narrow',
      title: 'Moonlight Sonata',
      composer: 'Composer',
      parts: [
        Part(
          id: 'P1',
          name: 'Part 1',
          measures: const [
            Measure(
              number: 1,
              symbols: [
                Note(step: 'C', octave: 4, duration: 1, type: 'quarter'),
              ],
            ),
          ],
        ),
      ],
    );

    await pumpEditorShell(
      tester,
      score: score,
      surfaceSize: const Size(360, 800),
    );

    expect(find.text('Moonlight Sonata'), findsOneWidget);
    expect(find.byTooltip('Scan New Page'), findsNothing);
    expect(find.byTooltip('More'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.tap(find.byTooltip('More'));
    await tester.pumpAndSettle();

    expect(find.text('Scan New Page'), findsOneWidget);
    expect(find.text('Export MusicXML…'), findsOneWidget);
    expect(find.text('Export PDF…'), findsOneWidget);
  });

  testWidgets('keeps measure actions enabled with default measure context', (
    tester,
  ) async {
    final score = buildScore(withSymbols: false);

    await pumpEditorShell(tester, score: score);

    final moveUpButton = actionTileForLabel(tester, 'Up');
    expect(moveUpButton.onTap, isNull);

    final addMeasureButton = actionTileForLabel(tester, 'Add');
    expect(addMeasureButton.onTap, isNotNull);

    await tester.tap(find.text('Add'));
    await tester.pump();

    expect(tester.takeException(), isNull);
  });

  testWidgets('tapping symbols selects, reselects, and deselects', (
    tester,
  ) async {
    final score = buildScore();

    await pumpEditorShell(tester, score: score);

    final moveUpButtonFinder = find.ancestor(
      of: find.text('Up'),
      matching: find.byType(InkWell),
    );
    expect(tester.widget<InkWell>(moveUpButtonFinder.first).onTap, isNull);

    final notationBox = tester.renderObject<RenderBox>(
      find.byType(ScoreNotationViewer),
    );

    await tester.tapAt(
      notationBox.localToGlobal(
        _symbolCenterOffset(score, measureIndex: 0, symbolIndex: 0),
      ),
    );
    await tester.pump();
    expect(find.text('SELECTION'), findsOneWidget);
    expect(find.text('C4'), findsWidgets);
    expect(tester.widget<InkWell>(moveUpButtonFinder.first).onTap, isNotNull);

    await tester.tapAt(
      notationBox.localToGlobal(
        _symbolCenterOffset(score, measureIndex: 0, symbolIndex: 1),
      ),
    );
    await tester.pump();
    expect(find.text('Rest'), findsOneWidget);
    expect(find.text('quarter'), findsOneWidget);

    await tester.tapAt(
      notationBox.localToGlobal(
        _symbolCenterOffset(score, measureIndex: 0, symbolIndex: 1),
      ),
    );
    await tester.pump();
    expect(
      find.text('Measure 1 selected. Tap a note or rest to edit a symbol.'),
      findsOneWidget,
    );
    expect(tester.widget<InkWell>(moveUpButtonFinder.first).onTap, isNull);
    expect(actionTileForLabel(tester, 'Add').onTap, isNotNull);
  });

  testWidgets(
    'drag reorder updates model order and undo restores original order',
    (tester) async {
      final score = Score(
        id: 'score-reorder',
        title: 'Test Score',
        composer: 'Composer',
        parts: [
          Part(
            id: 'P1',
            name: 'Part 1',
            measures: [
              Measure(
                number: 1,
                symbols: const [
                  Note(step: 'C', octave: 4, duration: 1, type: 'quarter'),
                  Note(step: 'E', octave: 4, duration: 1, type: 'quarter'),
                  Rest(duration: 1, type: 'quarter'),
                ],
              ),
            ],
          ),
        ],
      );

      await pumpEditorShell(tester, score: score);

      // Invoke the drag-completed callback directly to avoid InteractiveViewer
      // gesture competition — the viewer's drag logic is tested separately in
      // score_notation_viewer_test.dart.
      final viewer = tester.widget<ScoreNotationViewer>(
        find.byType(ScoreNotationViewer),
      );
      viewer.onDragCompleted!(
        const NotationSymbolReorder(
          fromPartIndex: 0,
          fromMeasureIndex: 0,
          fromSymbolIndex: 0,
          toPartIndex: 0,
          toMeasureIndex: 0,
          toSymbolIndex: 2,
        ),
        Offset.zero,
      );
      await tester.pump();

      // After reorder: C4 moved to index 2, E4 is now at index 0.
      // moveSymbolToDest selects the moved symbol (C4 at index 2).
      expect(find.text('C4'), findsWidgets);

      // Invoke onSymbolTap directly — y-coordinates differ per pitch so tapAt
      // risks missing the hit rect when pitch changes after a reorder.
      final viewer2 = tester.widget<ScoreNotationViewer>(
        find.byType(ScoreNotationViewer),
      );
      viewer2.onSymbolTap!(
        const NotationSymbolTarget(
          partIndex: 0,
          measureIndex: 0,
          symbolIndex: 0,
          center: Offset.zero,
          hitRect: Rect.zero,
        ),
      );
      await tester.pump();
      expect(find.text('E4'), findsOneWidget);

      final undoButton = find.byTooltip('Undo');
      await tester.tap(undoButton);
      await tester.pump();

      // After undo: C4 is back at index 0.
      final viewer3 = tester.widget<ScoreNotationViewer>(
        find.byType(ScoreNotationViewer),
      );
      viewer3.onSymbolTap!(
        const NotationSymbolTarget(
          partIndex: 0,
          measureIndex: 0,
          symbolIndex: 0,
          center: Offset.zero,
          hitRect: Rect.zero,
        ),
      );
      await tester.pump();
      expect(find.text('C4'), findsWidgets);
    },
  );

  testWidgets('landscape keeps controls beside notation without overlap', (
    tester,
  ) async {
    final score = buildScore();
    await pumpEditorShell(tester, score: score);

    final notationRect = tester.getRect(find.byType(ScoreNotationViewer));
    final symbolLabelRect = tester.getRect(find.text('SELECTION'));

    expect(symbolLabelRect.left, greaterThan(notationRect.right));
    expect(tester.takeException(), isNull);
  });

  testWidgets('move to next measure across a page boundary follows the target page', (
    tester,
  ) async {
    final score = Score(
      id: 'score-page-follow-next',
      title: 'Boundary Move',
      composer: 'Composer',
      parts: [
        Part(
          id: 'P1',
          name: 'Part 1',
          measures: List.generate(21, (i) {
            return Measure(
              number: i + 1,
              symbols: [
                Note(
                  step: i == 19 ? 'C' : 'D',
                  octave: 4,
                  duration: 1,
                  type: 'quarter',
                ),
              ],
            );
          }),
        ),
      ],
    );

    await pumpEditorShell(tester, score: score);

    final viewerBefore = tester.widget<ScoreNotationViewer>(
      find.byType(ScoreNotationViewer).last,
    );
    viewerBefore.onSymbolTap!(
      const NotationSymbolTarget(
        partIndex: 0,
        measureIndex: 19,
        symbolIndex: 0,
        center: Offset.zero,
        hitRect: Rect.zero,
      ),
    );
    await tester.pump();

    await tester.tap(find.text('Next'));
    await tester.pumpAndSettle();

    final viewerAfter = tester.widget<ScoreNotationViewer>(
      find.byType(ScoreNotationViewer).last,
    );
    expect(viewerAfter.firstMeasureIndex, 20);
    expect(viewerAfter.selectedMeasureIndex, 0);
  });

  testWidgets('adding a measure after the last visible measure follows the new page', (
    tester,
  ) async {
    final score = Score(
      id: 'score-page-follow-add',
      title: 'Boundary Add',
      composer: 'Composer',
      parts: [
        Part(
          id: 'P1',
          name: 'Part 1',
          measures: List.generate(
            20,
            (i) => Measure(
              number: i + 1,
              symbols: const [
                Note(step: 'C', octave: 4, duration: 1, type: 'quarter'),
              ],
            ),
          ),
        ),
      ],
    );

    await pumpEditorShell(tester, score: score);

    final viewerBefore = tester.widget<ScoreNotationViewer>(
      find.byType(ScoreNotationViewer).last,
    );
    viewerBefore.onSymbolTap!(
      const NotationSymbolTarget(
        partIndex: 0,
        measureIndex: 19,
        symbolIndex: 0,
        center: Offset.zero,
        hitRect: Rect.zero,
      ),
    );
    await tester.pump();

    await tester.tap(find.text('Add'));
    await tester.pumpAndSettle();

    final viewerAfter = tester.widget<ScoreNotationViewer>(
      find.byType(ScoreNotationViewer).last,
    );
    expect(viewerAfter.firstMeasureIndex, 20);
    expect(viewerAfter.pageMeasureCount, 1);
    expect(viewerAfter.selectedMeasureIndex, 0);
  });

  testWidgets('deleting the only measure on the last page returns to the previous page', (
    tester,
  ) async {
    final score = Score(
      id: 'score-page-follow-delete',
      title: 'Boundary Delete',
      composer: 'Composer',
      parts: [
        Part(
          id: 'P1',
          name: 'Part 1',
          measures: List.generate(
            20,
            (i) => Measure(
              number: i + 1,
              symbols: const [
                Note(step: 'C', octave: 4, duration: 1, type: 'quarter'),
              ],
            ),
          ),
        ),
      ],
    );

    await pumpEditorShell(tester, score: score);

    final viewerBefore = tester.widget<ScoreNotationViewer>(
      find.byType(ScoreNotationViewer).last,
    );
    viewerBefore.onSymbolTap!(
      const NotationSymbolTarget(
        partIndex: 0,
        measureIndex: 19,
        symbolIndex: 0,
        center: Offset.zero,
        hitRect: Rect.zero,
      ),
    );
    await tester.pump();

    await tester.tap(find.text('Add'));
    await tester.pumpAndSettle();

    var viewer = tester.widget<ScoreNotationViewer>(
      find.byType(ScoreNotationViewer).last,
    );
    expect(viewer.firstMeasureIndex, 20);

    await tester.tap(find.text('Del'));
    await tester.pumpAndSettle();

    viewer = tester.widget<ScoreNotationViewer>(
      find.byType(ScoreNotationViewer).last,
    );
    expect(viewer.firstMeasureIndex, 0);
    expect(viewer.pageMeasureCount, 20);
  });

  testWidgets('portrait narrow screen renders without overflow', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final score = buildScore();
    await tester.pumpWidget(
      MaterialApp(
        home: EditorShellScreen(
          args: EditorShellArgs(
            score: score,
            initialState: EditorState(score: score),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('Save'), findsOneWidget);
    // Toolbar buttons use 3-char labels in portrait mode
    expect(find.text('PIT'), findsOneWidget);
    expect(find.text('CLE'), findsOneWidget);
  });

  testWidgets(
    'compact selection card shows pitch and duration without overflow',
    (tester) async {
      tester.view.physicalSize = const Size(360, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final score = buildScore();
      await tester.pumpWidget(
        MaterialApp(
          home: EditorShellScreen(
            args: EditorShellArgs(
              score: score,
              initialState: EditorState(score: score),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Select a note via callback to trigger the compact selection card.
      final viewer = tester.widget<ScoreNotationViewer>(
        find.byType(ScoreNotationViewer),
      );
      viewer.onSymbolTap!(
        const NotationSymbolTarget(
          partIndex: 0,
          measureIndex: 0,
          symbolIndex: 0,
          center: Offset.zero,
          hitRect: Rect.zero,
        ),
      );
      await tester.pump();

      expect(tester.takeException(), isNull);
    expect(find.text('C4'), findsWidgets);
      expect(find.text('quarter'), findsOneWidget);
    },
  );

  group('portrait inspector group popup stays open after action tap', () {
    Future<void> pumpPortrait(WidgetTester tester, Score score) async {
      tester.view.physicalSize = const Size(360, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        MaterialApp(
          home: EditorShellScreen(
            args: EditorShellArgs(
              score: score,
              initialState: EditorState(score: score),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    void selectFirstNote(WidgetTester tester) {
      tester
          .widget<ScoreNotationViewer>(find.byType(ScoreNotationViewer))
          .onSymbolTap!(
        const NotationSymbolTarget(
          partIndex: 0,
          measureIndex: 0,
          symbolIndex: 0,
          center: Offset.zero,
          hitRect: Rect.zero,
        ),
      );
    }

    testWidgets('PITCH — Up tap keeps popup open', (tester) async {
      await pumpPortrait(tester, buildScore());
      selectFirstNote(tester);
      await tester.pump();

      await tester.tap(find.text('PIT'));
      await tester.pump();
      expect(find.text('Up'), findsOneWidget);

      await tester.tap(find.text('Up'));
      await tester.pump();
      expect(find.text('Up'), findsOneWidget);
    });

    testWidgets('ACCIDENTAL — sharp tap keeps popup open', (tester) async {
      await pumpPortrait(tester, buildScore());
      selectFirstNote(tester);
      await tester.pump();

      await tester.tap(find.text('ACC'));
      await tester.pump();
      expect(find.text('♯'), findsOneWidget);

      await tester.tap(find.text('♯'));
      await tester.pump();
      expect(find.text('♯'), findsOneWidget);
    });

    testWidgets('DURATION — 8th tap keeps popup open', (tester) async {
      await pumpPortrait(tester, buildScore());
      selectFirstNote(tester);
      await tester.pump();

      await tester.tap(find.text('DUR'));
      await tester.pump();
      expect(find.text('8th'), findsOneWidget);

      await tester.tap(find.text('8th'));
      await tester.pump();
      expect(find.text('8th'), findsOneWidget);
    });

    testWidgets('MEASURE — Add tap keeps popup open', (tester) async {
      await pumpPortrait(tester, buildScore());
      selectFirstNote(tester);
      await tester.pump();

      await tester.tap(find.text('MEA'));
      await tester.pump();
      expect(find.text('Add'), findsOneWidget);

      await tester.tap(find.text('Add'));
      await tester.pump();
      expect(find.text('Add'), findsOneWidget);
    });

    testWidgets('PITCH — re-tapping tab closes popup', (tester) async {
      await pumpPortrait(tester, buildScore());
      selectFirstNote(tester);
      await tester.pump();

      await tester.tap(find.text('PIT'));
      await tester.pump();
      expect(find.text('Up'), findsOneWidget);

      await tester.tap(find.text('PIT'));
      await tester.pump();
      expect(find.text('Up'), findsNothing);
    });
  });

  // ── BGC-91: editor interactions locked during playback ──────────────────

  group('BGC-91 — playback lock', () {
    void emitPlaying() => PlaybackService.instance.emitStateForTesting(
      const PlaybackState(status: PlaybackStatus.playing),
    );

    void emitStopped() => PlaybackService.instance.emitStateForTesting(
      const PlaybackState(status: PlaybackStatus.stopped),
    );

    void emitPosition(int measureIndex) =>
        PlaybackService.instance.emitPositionForTesting(
          PlaybackPosition(
            partIndex: 0,
            measureIndex: measureIndex,
            symbolIndex: 0,
          ),
        );

    void clearPosition() =>
        PlaybackService.instance.emitPositionForTesting(PlaybackPosition.none);

    setUp(() {
      emitStopped();
      clearPosition();
    });
    tearDown(() {
      emitStopped();
      clearPosition();
    });

    Future<void> pumpPortrait(WidgetTester tester, Score score) async {
      tester.view.physicalSize = const Size(360, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        MaterialApp(
          home: EditorShellScreen(
            args: EditorShellArgs(
              score: score,
              initialState: EditorState(score: score),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('landscape: action tiles have callbacks before playback', (
      tester,
    ) async {
      final score = buildScore();
      await pumpEditorShell(tester, score: score);

      final viewer = tester.widget<ScoreNotationViewer>(
        find.byType(ScoreNotationViewer),
      );
      viewer.onSymbolTap!(
        const NotationSymbolTarget(
          partIndex: 0,
          measureIndex: 0,
          symbolIndex: 0,
          center: Offset.zero,
          hitRect: Rect.zero,
        ),
      );
      await tester.pump();

      expect(actionTileForLabel(tester, 'Up').onTap, isNotNull);
      expect(actionTileForLabel(tester, 'Down').onTap, isNotNull);
    });

    testWidgets('landscape: action tiles are nulled while playing', (
      tester,
    ) async {
      final score = buildScore();
      await pumpEditorShell(tester, score: score);

      final viewer = tester.widget<ScoreNotationViewer>(
        find.byType(ScoreNotationViewer),
      );
      viewer.onSymbolTap!(
        const NotationSymbolTarget(
          partIndex: 0,
          measureIndex: 0,
          symbolIndex: 0,
          center: Offset.zero,
          hitRect: Rect.zero,
        ),
      );
      await tester.pump();

      emitPlaying();
      await tester.pump();

      expect(actionTileForLabel(tester, 'Up').onTap, isNull);
      expect(actionTileForLabel(tester, 'Down').onTap, isNull);
      expect(actionTileForLabel(tester, 'Add').onTap, isNull);
    });

    testWidgets('landscape: interactions restored when playback stops', (
      tester,
    ) async {
      final score = buildScore();
      await pumpEditorShell(tester, score: score);

      final viewer = tester.widget<ScoreNotationViewer>(
        find.byType(ScoreNotationViewer),
      );
      viewer.onSymbolTap!(
        const NotationSymbolTarget(
          partIndex: 0,
          measureIndex: 0,
          symbolIndex: 0,
          center: Offset.zero,
          hitRect: Rect.zero,
        ),
      );
      await tester.pump();

      emitPlaying();
      await tester.pump();
      expect(actionTileForLabel(tester, 'Up').onTap, isNull);

      emitStopped();
      await tester.pump();
      expect(actionTileForLabel(tester, 'Up').onTap, isNotNull);
    });

    testWidgets('landscape: undo button disabled while playing', (
      tester,
    ) async {
      final score = buildScore();
      await pumpEditorShell(tester, score: score);

      // Select note then tap Down to create an undo entry.
      final viewer = tester.widget<ScoreNotationViewer>(
        find.byType(ScoreNotationViewer),
      );
      viewer.onSymbolTap!(
        const NotationSymbolTarget(
          partIndex: 0,
          measureIndex: 0,
          symbolIndex: 0,
          center: Offset.zero,
          hitRect: Rect.zero,
        ),
      );
      await tester.pump();
      actionTileForLabel(tester, 'Down').onTap!();
      await tester.pump();

      final undoFinder = find.ancestor(
        of: find.byIcon(Icons.undo_rounded),
        matching: find.byType(IconButton),
      );
      expect(tester.widget<IconButton>(undoFinder).onPressed, isNotNull);

      emitPlaying();
      await tester.pumpAndSettle();

      expect(tester.widget<IconButton>(undoFinder).onPressed, isNull);
    });

    testWidgets(
      'landscape: ScoreNotationViewer callbacks nulled while playing',
      (tester) async {
        final score = buildScore();
        await pumpEditorShell(tester, score: score);

        expect(
          tester
              .widget<ScoreNotationViewer>(find.byType(ScoreNotationViewer))
              .onSymbolTap,
          isNotNull,
        );
        expect(
          tester
              .widget<ScoreNotationViewer>(find.byType(ScoreNotationViewer))
              .onDragStarted,
          isNotNull,
        );

        emitPlaying();
        await tester.pumpAndSettle();

        final viewer = tester.widget<ScoreNotationViewer>(
          find.byType(ScoreNotationViewer),
        );
        expect(viewer.onSymbolTap, isNull);
        expect(viewer.onDragStarted, isNull);
      },
    );

    testWidgets('portrait: tab taps suppressed while playing', (tester) async {
      await pumpPortrait(tester, buildScore());

      emitPlaying();
      await tester.pump();

      // Tapping a tab while disabled should not open the popup.
      await tester.tap(find.text('PIT'));
      await tester.pump();
      expect(find.text('Up'), findsNothing);
    });

    testWidgets('portrait: open popup hidden when playback starts', (
      tester,
    ) async {
      await pumpPortrait(tester, buildScore());

      // Open the PITCH popup.
      await tester.tap(find.text('PIT'));
      await tester.pump();
      expect(find.text('Up'), findsOneWidget);

      // Start playback — popup should be suppressed.
      emitPlaying();
      await tester.pumpAndSettle();
      expect(find.text('Up'), findsNothing);
    });

    testWidgets('portrait: tabs re-enable after playback stops', (
      tester,
    ) async {
      await pumpPortrait(tester, buildScore());

      emitPlaying();
      await tester.pump();

      // Confirm tab is suppressed.
      await tester.tap(find.text('PIT'));
      await tester.pump();
      expect(find.text('Up'), findsNothing);

      // Stop playback — tab should work again.
      emitStopped();
      await tester.pump();
      await tester.tap(find.text('PIT'));
      await tester.pump();
      expect(find.text('Up'), findsOneWidget);
    });

    testWidgets('playback position follows the page containing the active measure', (
      tester,
    ) async {
      final score = Score(
        id: 'score-playback-page-follow',
        title: 'Playback Follow',
        composer: 'Composer',
        parts: [
          Part(
            id: 'P1',
            name: 'Part 1',
            measures: List.generate(
              21,
              (i) => Measure(
                number: i + 1,
                symbols: const [
                  Note(step: 'C', octave: 4, duration: 1, type: 'quarter'),
                ],
              ),
            ),
          ),
        ],
      );

      await pumpEditorShell(tester, score: score);

      emitPosition(20);
      await tester.pumpAndSettle();

      final viewer = tester.widget<ScoreNotationViewer>(
        find.byType(ScoreNotationViewer).last,
      );
      expect(viewer.firstMeasureIndex, 20);
      expect(viewer.playbackMeasureIndex, 0);
    });

    testWidgets('new playback positions pull the view back from manual page browsing', (
      tester,
    ) async {
      final score = Score(
        id: 'score-playback-recenter',
        title: 'Playback Recenter',
        composer: 'Composer',
        parts: [
          Part(
            id: 'P1',
            name: 'Part 1',
            measures: List.generate(
              21,
              (i) => Measure(
                number: i + 1,
                symbols: const [
                  Note(step: 'C', octave: 4, duration: 1, type: 'quarter'),
                ],
              ),
            ),
          ),
        ],
      );

      await pumpEditorShell(tester, score: score);

      emitPosition(20);
      await tester.pumpAndSettle();

      await tester.tap(find.text('1').last);
      await tester.pumpAndSettle();

      var viewer = tester.widget<ScoreNotationViewer>(
        find.byType(ScoreNotationViewer).last,
      );
      expect(viewer.firstMeasureIndex, 0);

      emitPosition(20);
      await tester.pumpAndSettle();

      viewer = tester.widget<ScoreNotationViewer>(
        find.byType(ScoreNotationViewer).last,
      );
      expect(viewer.firstMeasureIndex, 20);
    });
  });

  // ── existing tests continue ──────────────────────────────────────────────

  testWidgets('header edit count text stays within bounds after edits', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final score = buildScore();
    await tester.pumpWidget(
      MaterialApp(
        home: EditorShellScreen(
          args: EditorShellArgs(
            score: score,
            initialState: EditorState(score: score),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Select a symbol then insert a note via the inspector button to
    // trigger the edit count display in the header subtitle Row.
    final viewer = tester.widget<ScoreNotationViewer>(
      find.byType(ScoreNotationViewer),
    );
    viewer.onSymbolTap!(
      const NotationSymbolTarget(
        partIndex: 0,
        measureIndex: 0,
        symbolIndex: 0,
        center: Offset.zero,
        hitRect: Rect.zero,
      ),
    );
    await tester.pump();

    // Open the DURATION group popup first, then change duration
    await tester.tap(find.text('DUR'), warnIfMissed: false);
    await tester.pump();
    await tester.tap(find.text('Whole').first, warnIfMissed: false);
    await tester.pump();

    expect(tester.takeException(), isNull);
    expect(find.text('Score Editor · Simple Melody'), findsOneWidget);
  });
}

Offset _symbolCenterOffset(
  Score score, {
  required int measureIndex,
  required int symbolIndex,
}) {
  const policy = EditorLayoutPolicy.standard;
  final minMeasureWidth = policy.minMeasureWidth;
  const rowHeight = 140.0;
  const padding = EdgeInsets.symmetric(horizontal: 16.0, vertical: 28.0);

  final measures = score.parts.first.measures;
  final layout = const NotationLayoutCalculator().calculate(
    measures: measures,
    measuresPerRow: policy.measuresPerRow,
    minMeasureWidth: minMeasureWidth,
    rowHeight: rowHeight,
    padding: padding,
  );

  final target =
      ScoreNotationPainter.buildSymbolTargets(
        parts: [measures],
        measuresPerRow: layout.measuresPerRow,
        minMeasureWidth: minMeasureWidth,
        rowHeight: rowHeight,
        padding: padding,
        rowPrefixWidth: layout.rowPrefixWidth,
      ).firstWhere(
        (entry) =>
            entry.measureIndex == measureIndex &&
            entry.symbolIndex == symbolIndex,
      );

  return target.center;
}
