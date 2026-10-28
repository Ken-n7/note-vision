import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:note_vision/core/models/measure.dart';
import 'package:note_vision/core/models/note.dart';
import 'package:note_vision/core/models/part.dart';
import 'package:note_vision/core/models/rest.dart';
import 'package:note_vision/core/models/time_signature.dart';
import 'package:note_vision/core/services/playback_service.dart';
import 'package:note_vision/core/widgets/score_notation_viewer.dart';
import 'package:note_vision/core/widgets/score_notation/score_notation_painter.dart';
import 'package:note_vision/features/editor/presentation/widgets/editor_tool_dock.dart';
import 'package:note_vision/features/editor/presentation/widgets/symbol_palette.dart';

import '../../../support/editor_controls_harness.dart';

void main() {
  setUpAll(loadControlsFonts);

  Future<void> mode(WidgetTester tester, String value) async {
    await tester.tap(find.byKey(ValueKey('editor-mode-$value')));
    await tester.pumpAndSettle();
  }

  ScoreNotationViewer viewer(WidgetTester tester) => tester
      .widget<ScoreNotationViewer>(find.byType(ScoreNotationViewer).first);

  testWidgets(
    'note entry starts ready, preserves duration for rests, and undoes',
    (tester) async {
      final score = controlsScore().copyWith(
        parts: [
          const Part(
            id: 'p1',
            name: 'Upper staff',
            measures: [
              Measure(
                number: 1,
                timeSignature: TimeSignature(beats: 4, beatType: 4),
                symbols: [],
              ),
            ],
          ),
        ],
      );
      await pumpControls(
        tester,
        score: score,
        selectedSymbol: null,
        size: const Size(390, 844),
      );
      await mode(tester, 'insert');
      expect(
        tester.widget<SymbolPalette>(find.byType(SymbolPalette)).selectedType,
        PaletteSymbolType.quarterNote,
      );
      expect(viewer(tester).insertMode, isTrue);
      viewer(tester).onInsertTap!(
        const NotationInsertTarget(
          measureIndex: 0,
          insertIndex: 0,
          indicatorX: 100,
          step: 'G',
          octave: 4,
        ),
      );
      await tester.pumpAndSettle();
      expect(
        (shownControlsScore(tester).getSymbolAt(0, 0, 0) as Note).pitch,
        'G4',
      );

      await tester.tap(find.text('Rests'));
      await tester.pumpAndSettle();
      expect(
        tester.widget<SymbolPalette>(find.byType(SymbolPalette)).selectedType,
        PaletteSymbolType.quarterRest,
      );
      final quarter = find.descendant(
        of: find.byType(SymbolPalette),
        matching: find.text('Quarter'),
      );
      await tester.ensureVisible(quarter);
      await tester.tap(quarter);
      await tester.pumpAndSettle();
      expect(
        viewer(tester).insertMode,
        isTrue,
        reason: 'Choosing an active value must not end note entry',
      );
      viewer(tester).onInsertTap!(
        const NotationInsertTarget(
          measureIndex: 0,
          insertIndex: 1,
          indicatorX: 140,
          step: 'G',
          octave: 4,
        ),
      );
      await tester.pumpAndSettle();
      expect(shownControlsScore(tester).getSymbolAt(0, 0, 1), isA<Rest>());
      await mode(tester, 'edit');
      expect(viewer(tester).insertMode, isFalse);
      expect(find.byType(SymbolPalette), findsNothing);
      await tester.tap(find.byTooltip('Undo'));
      await tester.pumpAndSettle();
      expect(
        shownControlsScore(tester).parts.single.measures.single.symbols,
        hasLength(1),
      );
    },
  );

  testWidgets(
    'next symbol crosses an empty measure and a page without editing',
    (tester) async {
      final score = controlsScore().copyWith(
        parts: [
          Part(
            id: 'p1',
            name: 'Upper staff',
            measures: [
              const Measure(
                number: 1,
                symbols: [
                  Note(step: 'C', octave: 4, duration: 2, type: 'quarter'),
                ],
              ),
              const Measure(number: 2, symbols: []),
              const Measure(
                number: 3,
                startsNewPage: true,
                symbols: [Rest(duration: 2, type: 'quarter')],
              ),
            ],
          ),
        ],
      );
      await pumpControls(tester, score: score);
      expect(
        viewer(tester).selectedSymbolIndex,
        0,
        reason: 'Assigning review IDs preserves the initial selection',
      );
      expect(
        tester
            .widget<IconButton>(
              find.byWidgetPredicate(
                (widget) =>
                    widget is IconButton && widget.tooltip == 'Previous symbol',
              ),
            )
            .onPressed,
        isNull,
      );
      await tester.tap(find.byTooltip('Next symbol'));
      await tester.pumpAndSettle();
      expect(viewer(tester).firstMeasureIndex, 2);
      expect(viewer(tester).selectedMeasureIndex, 0);
      expect(find.text('Rest'), findsOneWidget);
      expect(find.text('Unsaved'), findsNothing);
      expect(
        tester
            .widget<IconButton>(
              find.byWidgetPredicate(
                (widget) => widget is IconButton && widget.tooltip == 'Undo',
              ),
            )
            .onPressed,
        isNull,
      );
      expect(
        tester
            .widget<IconButton>(
              find.byWidgetPredicate(
                (widget) =>
                    widget is IconButton && widget.tooltip == 'Next symbol',
              ),
            )
            .onPressed,
        isNull,
      );
      await tester.tap(find.byTooltip('Previous symbol'));
      await tester.pumpAndSettle();
      expect(viewer(tester).firstMeasureIndex, 0);
      expect(find.text('C4'), findsOneWidget);
    },
  );

  testWidgets('delete is directly reachable and undo restores the symbol', (
    tester,
  ) async {
    await pumpControls(tester, size: const Size(390, 844));
    final delete = find.byTooltip('Delete symbol');
    expect(
      tester
          .getRect(delete)
          .overlaps(tester.getRect(find.byType(EditorToolDock))),
      isTrue,
    );
    await tester.tap(delete);
    await tester.pumpAndSettle();
    expect(
      (shownControlsScore(tester).getSymbolAt(0, 0, 0) as Note).pitch,
      'E4',
    );
    await tester.tap(find.byTooltip('Undo'));
    await tester.pumpAndSettle();
    expect(
      (shownControlsScore(tester).getSymbolAt(0, 0, 0) as Note).pitch,
      'C4',
    );
  });

  testWidgets(
    'keyboard pitch edits, undo, navigation and insertion share editor state',
    (tester) async {
      await pumpControls(tester);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
      await tester.pumpAndSettle();
      expect(
        (shownControlsScore(tester).getSymbolAt(0, 0, 0) as Note).pitch,
        'D4',
      );
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyZ);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pumpAndSettle();
      expect(
        (shownControlsScore(tester).getSymbolAt(0, 0, 0) as Note).pitch,
        'C4',
      );
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pumpAndSettle();
      expect(viewer(tester).selectedSymbolIndex, 1);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyN);
      await tester.pumpAndSettle();
      expect(viewer(tester).insertMode, isTrue);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(viewer(tester).insertMode, isFalse);
      expect(viewer(tester).selectedSymbolIndex, isNull);
    },
  );

  testWidgets(
    'keyboard edits are locked during playback and resume when paused',
    (tester) async {
      final (playback, _) = await pumpControls(tester);
      playback.emit(PlaybackStatus.playing);
      await tester.pumpAndSettle();
      for (final key in [
        LogicalKeyboardKey.arrowUp,
        LogicalKeyboardKey.delete,
        LogicalKeyboardKey.keyN,
      ]) {
        await tester.sendKeyEvent(key);
      }
      await tester.pumpAndSettle();
      expect(
        (shownControlsScore(tester).getSymbolAt(0, 0, 0) as Note).pitch,
        'C4',
      );
      expect(find.byType(SymbolPalette), findsNothing);
      playback.emit(PlaybackStatus.paused);
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
      await tester.pumpAndSettle();
      expect(
        (shownControlsScore(tester).getSymbolAt(0, 0, 0) as Note).pitch,
        'D4',
      );
    },
  );

  testWidgets('help and metadata entry never receive score editing shortcuts', (
    tester,
  ) async {
    await pumpControls(tester);
    await tester.tap(find.byTooltip('Editor guide'));
    await tester.pumpAndSettle();
    expect(find.text('Make the score your own'), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.delete);
    await tester.pumpAndSettle();
    expect(
      shownControlsScore(tester).parts.first.measures.first.symbols,
      hasLength(3),
    );
    await tester.tap(find.byTooltip('Close help'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Evening Study for Two Hands'));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(TextField).first);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyN);
    await tester.sendKeyEvent(LogicalKeyboardKey.delete);
    await tester.pump();
    expect(find.byType(SymbolPalette), findsNothing);
    expect(
      shownControlsScore(tester).parts.first.measures.first.symbols,
      hasLength(3),
    );
    expect(viewer(tester).selectedSymbolIndex, 0);
  });
}
