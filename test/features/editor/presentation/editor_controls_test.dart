import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:note_vision/core/models/note.dart';
import 'package:note_vision/core/models/part.dart';
import 'package:note_vision/core/services/playback_service.dart';
import 'package:note_vision/core/widgets/score_notation_viewer.dart';
import 'package:note_vision/features/editor/presentation/widgets/symbol_palette.dart';

import '../../../support/editor_controls_harness.dart';

void main() {
  setUpAll(loadControlsFonts);

  for (final (name, size, scale) in [
    ('phone', const Size(390, 844), 1.0),
    ('small-phone', const Size(320, 568), 1.0),
    ('small-phone-large-text', const Size(320, 568), 2.0),
    ('landscape-phone', const Size(844, 390), 1.0),
    ('tablet', const Size(1024, 768), 1.0),
    ('tablet-large-text', const Size(1024, 768), 2.0),
  ]) {
    testWidgets('editor controls fit $name', (tester) async {
      await pumpControls(tester, size: size, textScale: scale);
      final layoutError = tester.takeException();
      await captureControls(tester, name);
      expect(layoutError, isNull);
      if (size.width < size.height) {
        await tester.tap(find.byTooltip('Duration tools'));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        final popup = tester.getRect(find.text('DURATION'));
        expect(popup.top, greaterThanOrEqualTo(0));
        await captureControls(tester, '$name-duration');
      }
    });
  }

  testWidgets('pitch controls are disabled for a rest', (tester) async {
    await pumpControls(tester, selectedSymbol: 2);
    expect(controlsAction(tester, 'Up').onTap, isNull);
    expect(controlsAction(tester, 'Down').onTap, isNull);
  });

  testWidgets('screen readers can activate tool tabs and insertion choices', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    try {
      await pumpControls(
        tester,
        size: const Size(390, 844),
        selectedSymbol: null,
      );
      final tab = tester.getSemantics(find.bySemanticsLabel('Pitch tools'));
      expect(tab.getSemanticsData().hasAction(ui.SemanticsAction.tap), isTrue);
      tab.owner!.performAction(tab.id, ui.SemanticsAction.tap);
      await tester.pumpAndSettle();
      expect(find.text('PITCH'), findsOneWidget);

      final note = tester.getSemantics(find.bySemanticsLabel('Quarter note'));
      expect(note.getSemanticsData().hasAction(ui.SemanticsAction.tap), isTrue);
      note.owner!.performAction(note.id, ui.SemanticsAction.tap);
      await tester.pumpAndSettle();
      expect(
        tester.widget<SymbolPalette>(find.byType(SymbolPalette)).selectedType,
        PaletteSymbolType.quarterNote,
      );
    } finally {
      semantics.dispose();
    }
  });

  testWidgets('insertion tools reveal the palette and lock during playback', (
    tester,
  ) async {
    final (playback, _) = await pumpControls(tester);
    expect(find.byType(SymbolPalette), findsNothing);
    await tester.tap(find.text('Insert'));
    await tester.pumpAndSettle();
    expect(find.byType(SymbolPalette), findsOneWidget);
    await tester.tap(find.text('Done'));
    await tester.pumpAndSettle();
    expect(find.byType(SymbolPalette), findsNothing);
    playback.emit(PlaybackStatus.playing);
    await tester.pumpAndSettle();
    final insert = tester.widget<TextButton>(
      find.ancestor(of: find.text('Insert'), matching: find.byType(TextButton)),
    );
    expect(insert.onPressed, isNull);
  });

  testWidgets('seeking while paused cues the correct staff without playing', (
    tester,
  ) async {
    final original = controlsScore();
    final score = original.copyWith(
      parts: [
        Part(
          id: 'p1',
          name: 'Upper staff',
          measures: original.parts.first.measures.take(2).toList(),
        ),
        Part(
          id: 'p2',
          name: 'Lower staff',
          measures: original.parts.first.measures,
        ),
      ],
    );
    final (playback, _) = await pumpControls(tester, score: score);
    playback.emit(PlaybackStatus.paused);
    await tester.pumpAndSettle();
    final slider = tester.widget<Slider>(
      find.byKey(const ValueKey('playback-scrubber')),
    );
    expect(slider.max, 5);
    slider.onChangeEnd!(4);
    await tester.pumpAndSettle();
    expect(playback.soughtPart, 1);
    expect(playback.soughtMeasure, 2);
    expect(playback.status, PlaybackStatus.paused);
    expect(find.byTooltip('Resume'), findsOneWidget);
  });

  testWidgets('duration controls disable choices that cannot fit the measure', (
    tester,
  ) async {
    await pumpControls(tester);
    expect(controlsAction(tester, 'Half').onTap, isNull);
    expect(controlsAction(tester, '8th').onTap, isNotNull);
    expect(controlsAction(tester, 'Dot').onTap, isNull);
  });

  testWidgets('playback controls follow the editor playback service', (
    tester,
  ) async {
    final (playback, _) = await pumpControls(tester);
    playback.emit(PlaybackStatus.playing);
    await tester.pumpAndSettle();
    expect(find.byTooltip('Pause'), findsOneWidget);
    await tester.tap(find.byTooltip('Pause'));
    await tester.pumpAndSettle();
    expect(playback.status, PlaybackStatus.paused);
  });

  testWidgets('empty measure taps update the context for editing tools', (
    tester,
  ) async {
    await pumpControls(tester);
    final viewer = tester.widget<ScoreNotationViewer>(
      find.byType(ScoreNotationViewer),
    );
    expect(viewer.onMeasureTap, isNotNull);
    viewer.onMeasureTap!(
      const NotationMeasureTarget(partIndex: 0, measureIndex: 2),
    );
    await tester.pumpAndSettle();
    final updated = tester.widget<ScoreNotationViewer>(
      find.byType(ScoreNotationViewer),
    );
    expect(updated.selectedMeasureIndex, 2);
    expect(updated.selectedSymbolIndex, isNull);
  });

  testWidgets('undo after saving marks the changed score unsaved', (
    tester,
  ) async {
    await pumpControls(tester, existingProject: true);
    await tester.tap(find.text('Up'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(find.text('Unsaved'), findsNothing);
    await tester.tap(find.byTooltip('Undo'));
    await tester.pumpAndSettle();
    expect(
      (shownControlsScore(tester).getSymbolAt(0, 0, 0) as Note).pitch,
      'C4',
    );
    expect(find.text('Unsaved'), findsOneWidget);
  });

  testWidgets('edits made during a save remain visibly unsaved', (
    tester,
  ) async {
    final storage = ControlsStorage()..pending = Completer<void>();
    await pumpControls(tester, existingProject: true, storage: storage);
    await tester.tap(find.text('Up'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save'));
    await tester.pump();
    expect(find.text('Saving…'), findsOneWidget);
    expect(
      tester
          .widget<FilledButton>(
            find.ancestor(
              of: find.text('Saving…'),
              matching: find.byWidgetPredicate(
                (widget) => widget is FilledButton,
              ),
            ),
          )
          .onPressed,
      isNull,
    );
    await tester.tap(find.text('Up'));
    await tester.pump();
    storage.pending!.complete();
    await tester.pumpAndSettle();
    expect(
      (storage.saved.single.decodeScore().getSymbolAt(0, 0, 0) as Note).pitch,
      'D4',
    );
    expect(
      (shownControlsScore(tester).getSymbolAt(0, 0, 0) as Note).pitch,
      'E4',
    );
    expect(find.text('Unsaved'), findsOneWidget);
  });
}
