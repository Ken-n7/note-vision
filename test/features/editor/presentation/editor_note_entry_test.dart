import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:note_vision/core/models/note.dart';
import 'package:note_vision/core/services/playback_service.dart';
import 'package:note_vision/core/widgets/score_notation_viewer.dart';
import 'package:note_vision/core/widgets/score_notation/score_notation_painter.dart';

import '../../../support/editor_controls_harness.dart';

ScoreNotationViewer viewer(WidgetTester tester) =>
    tester.widget<ScoreNotationViewer>(find.byType(ScoreNotationViewer).first);

List<String> pitches(WidgetTester tester) => [
  for (final n in shownControlsScore(
    tester,
  ).parts.first.measures.first.symbols.whereType<Note>())
    '${n.isChordTone ? '+' : ''}${n.pitch}',
];

void tapPitch(WidgetTester tester, String step, int octave, {int measure = 0}) {
  viewer(tester).onInsertTap!(
    NotationInsertTarget(
      partIndex: 0,
      measureIndex: measure,
      insertIndex: 1,
      indicatorX: 100,
      step: step,
      octave: octave,
    ),
  );
}

void main() {
  setUpAll(loadControlsFonts);

  testWidgets(
    'Ctrl+Shift+letter inserts time without replacing the next note',
    (tester) async {
      await pumpControls(tester);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyN);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyD);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pumpAndSettle();
      expect(pitches(tester), ['C4', 'D4', 'E4']);
      expect(
        shownControlsScore(tester).parts.first.measures.first.symbols,
        hasLength(4),
      );
      await tester.sendKeyEvent(LogicalKeyboardKey.keyF);
      await tester.pumpAndSettle();
      expect(pitches(tester), ['C4', 'D4', 'F4']);
      await tester.tap(find.byTooltip('Undo'));
      await tester.pumpAndSettle();
      expect(pitches(tester), ['C4', 'D4', 'E4']);
    },
  );

  testWidgets(
    'Chord adds tapped pitches above and below a selected note; undo restores it',
    (tester) async {
      await pumpControls(tester, size: const Size(390, 844));
      await tester.sendKeyEvent(LogicalKeyboardKey.keyN);
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilterChip, 'Chord'));
      await tester.pumpAndSettle();
      tapPitch(tester, 'G', 4);
      await tester.pumpAndSettle();
      tapPitch(tester, 'A', 3);
      await tester.pumpAndSettle();
      expect(pitches(tester), ['C4', '+G4', '+A3', 'E4']);
      // A different bar cannot silently become part of the selected chord.
      tapPitch(tester, 'F', 4, measure: 1);
      await tester.pumpAndSettle();
      expect(pitches(tester), ['C4', '+G4', '+A3', 'E4']);
      await captureControls(tester, 'note-entry-chord-phone');
      await tester.tap(find.byTooltip('Undo'));
      await tester.pumpAndSettle();
      expect(pitches(tester), ['C4', '+G4', 'E4']);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('Insert chip extends a full bar for typed and tapped input', (
    tester,
  ) async {
    await pumpControls(tester, size: const Size(390, 844));
    await tester.sendKeyEvent(LogicalKeyboardKey.keyN);
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilterChip, 'Insert'));
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.keyD);
    await tester.pumpAndSettle();
    expect(pitches(tester), ['C4', 'D4', 'E4']);
    tapPitch(tester, 'F', 4);
    await tester.pumpAndSettle();
    expect(pitches(tester), ['C4', 'F4', 'D4', 'E4']);
    expect(
      shownControlsScore(tester).parts.first.measures.first.symbols,
      hasLength(5),
    );
    await captureControls(tester, 'note-entry-insert-phone');
  });

  testWidgets('playback disables touch input modes and keyboard insertion', (
    tester,
  ) async {
    final (playback, _) = await pumpControls(tester);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyN);
    await tester.pumpAndSettle();
    playback.emit(PlaybackStatus.playing);
    await tester.pumpAndSettle();
    for (final name in ['Chord', 'Insert']) {
      expect(
        tester
            .widget<FilterChip>(find.widgetWithText(FilterChip, name))
            .onSelected,
        isNull,
      );
    }
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyD);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pumpAndSettle();
    expect(pitches(tester), ['C4', 'E4']);
  });

  for (final (name, size, scale) in [
    ('large-text', const Size(390, 844), 1.8),
    ('landscape', const Size(844, 390), 1.0),
    ('tablet', const Size(1024, 1366), 1.0),
  ]) {
    testWidgets('note entry modes fit $name', (tester) async {
      await pumpControls(tester, size: size, textScale: scale);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyN);
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.widgetWithText(FilterChip, 'Chord'));
      await tester.tap(find.widgetWithText(FilterChip, 'Chord'));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<FilterChip>(find.widgetWithText(FilterChip, 'Chord'))
            .selected,
        isTrue,
      );
      await captureControls(tester, 'note-entry-$name');
      expect(tester.takeException(), isNull);
    });
  }
}
