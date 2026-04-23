import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:note_vision/core/models/measure.dart';
import 'package:note_vision/core/models/note.dart';
import 'package:note_vision/core/models/part.dart';
import 'package:note_vision/core/models/rest.dart';
import 'package:note_vision/core/models/score.dart';
import 'package:note_vision/core/widgets/score_notation_viewer.dart';
import 'package:note_vision/core/widgets/score_notation/notation_layout.dart';
import 'package:note_vision/core/widgets/score_notation/score_notation_painter.dart';
import 'package:note_vision/features/editor/model/editor_state.dart';
import 'package:note_vision/features/editor/presentation/editor_shell_screen.dart';

void main() {
  Future<void> pumpEditorShell(
    WidgetTester tester, {
    required Score score,
  }) async {
    tester.view.physicalSize = const Size(1600, 900);
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

  testWidgets('renders editor shell sections and action buttons', (tester) async {
    final score = buildScore();

    await pumpEditorShell(tester, score: score);

    expect(find.text('Test Score'), findsOneWidget);
    expect(find.text('Save'), findsOneWidget);
    expect(find.text('Up'), findsOneWidget);
    expect(find.text('Down'), findsOneWidget);
    expect(find.text('Whole'), findsWidgets);
    expect(find.text('Half'), findsWidgets);
    expect(find.text('Qtr'), findsOneWidget);
    expect(find.text('8th'), findsOneWidget);
    expect(find.text('Add'), findsOneWidget);
    expect(find.byTooltip('Undo'), findsOneWidget);
    expect(find.byTooltip('Redo'), findsOneWidget);
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

  testWidgets('tapping symbols selects, reselects, and deselects', (tester) async {
    final score = buildScore();

    await pumpEditorShell(tester, score: score);

    final moveUpButtonFinder = find.ancestor(
      of: find.text('Up'),
      matching: find.byType(InkWell),
    );
    expect(tester.widget<InkWell>(moveUpButtonFinder.first).onTap, isNull);

    final notationBox = tester.renderObject<RenderBox>(find.byType(ScoreNotationViewer));

    await tester.tapAt(
      notationBox.localToGlobal(_symbolCenterOffset(score, measureIndex: 0, symbolIndex: 0)),
    );
    await tester.pump();
    expect(find.text('SELECTION'), findsOneWidget);
    expect(find.text('C4'), findsOneWidget);
    expect(tester.widget<InkWell>(moveUpButtonFinder.first).onTap, isNotNull);

    await tester.tapAt(
      notationBox.localToGlobal(_symbolCenterOffset(score, measureIndex: 0, symbolIndex: 1)),
    );
    await tester.pump();
    expect(find.text('Rest'), findsOneWidget);
    expect(find.text('quarter'), findsOneWidget);

    await tester.tapAt(
      notationBox.localToGlobal(_symbolCenterOffset(score, measureIndex: 0, symbolIndex: 1)),
    );
    await tester.pump();
    expect(find.text('Tap a note or rest to select it'), findsOneWidget);
    expect(tester.widget<InkWell>(moveUpButtonFinder.first).onTap, isNull);
  });

  testWidgets('drag reorder updates model order and undo restores original order', (
    tester,
  ) async {
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
    final viewer = tester.widget<ScoreNotationViewer>(find.byType(ScoreNotationViewer));
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
    expect(find.text('C4'), findsOneWidget);

    // Invoke onSymbolTap directly — y-coordinates differ per pitch so tapAt
    // risks missing the hit rect when pitch changes after a reorder.
    final viewer2 = tester.widget<ScoreNotationViewer>(find.byType(ScoreNotationViewer));
    viewer2.onSymbolTap!(const NotationSymbolTarget(
      partIndex: 0,
      measureIndex: 0,
      symbolIndex: 0,
      center: Offset.zero,
      hitRect: Rect.zero,
    ));
    await tester.pump();
    expect(find.text('E4'), findsOneWidget);

    final undoButton = find.byTooltip('Undo');
    await tester.tap(undoButton);
    await tester.pump();

    // After undo: C4 is back at index 0.
    final viewer3 = tester.widget<ScoreNotationViewer>(find.byType(ScoreNotationViewer));
    viewer3.onSymbolTap!(const NotationSymbolTarget(
      partIndex: 0,
      measureIndex: 0,
      symbolIndex: 0,
      center: Offset.zero,
      hitRect: Rect.zero,
    ));
    await tester.pump();
    expect(find.text('C4'), findsOneWidget);
  });

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

  testWidgets('portrait narrow screen renders without overflow', (tester) async {
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
  });

  testWidgets('compact selection card shows pitch and duration without overflow', (
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

    // Select a note via callback to trigger the compact selection card.
    final viewer = tester.widget<ScoreNotationViewer>(find.byType(ScoreNotationViewer));
    viewer.onSymbolTap!(const NotationSymbolTarget(
      partIndex: 0,
      measureIndex: 0,
      symbolIndex: 0,
      center: Offset.zero,
      hitRect: Rect.zero,
    ));
    await tester.pump();

    expect(tester.takeException(), isNull);
    expect(find.text('C4'), findsOneWidget);
    expect(find.text('quarter'), findsOneWidget);
  });

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
      tester.widget<ScoreNotationViewer>(
        find.byType(ScoreNotationViewer),
      ).onSymbolTap!(const NotationSymbolTarget(
        partIndex: 0,
        measureIndex: 0,
        symbolIndex: 0,
        center: Offset.zero,
        hitRect: Rect.zero,
      ));
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
    final viewer = tester.widget<ScoreNotationViewer>(find.byType(ScoreNotationViewer));
    viewer.onSymbolTap!(const NotationSymbolTarget(
      partIndex: 0,
      measureIndex: 0,
      symbolIndex: 0,
      center: Offset.zero,
      hitRect: Rect.zero,
    ));
    await tester.pump();

    // Open the DURATION group popup first, then change duration
    await tester.tap(find.text('DUR'), warnIfMissed: false);
    await tester.pump();
    await tester.tap(find.text('Whole').first, warnIfMissed: false);
    await tester.pump();

    expect(tester.takeException(), isNull);
    expect(find.text('Score Editor'), findsOneWidget);
  });
}

Offset _symbolCenterOffset(
  Score score, {
  required int measureIndex,
  required int symbolIndex,
}) {
  const measuresPerRow = 3;
  const minMeasureWidth = 214.0;
  const rowHeight = 140.0;
  const padding = EdgeInsets.symmetric(horizontal: 16.0, vertical: 28.0);

  final measures = score.parts.first.measures;
  final layout = const NotationLayoutCalculator().calculate(
    measures: measures,
    measuresPerRow: measuresPerRow,
    minMeasureWidth: minMeasureWidth,
    rowHeight: rowHeight,
    padding: padding,
  );

  final target = ScoreNotationPainter.buildSymbolTargets(
    parts: [measures],
    measuresPerRow: layout.measuresPerRow,
    minMeasureWidth: minMeasureWidth,
    rowHeight: rowHeight,
    padding: padding,
    rowPrefixWidth: layout.rowPrefixWidth,
  ).firstWhere(
    (entry) => entry.measureIndex == measureIndex && entry.symbolIndex == symbolIndex,
  );

  return target.center;
}
