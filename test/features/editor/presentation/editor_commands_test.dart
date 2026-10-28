import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:note_vision/core/models/note.dart';
import 'package:note_vision/core/models/rest.dart';
import 'package:note_vision/core/services/playback_service.dart';
import 'package:note_vision/features/editor/presentation/widgets/editor_command_palette.dart';
import 'package:note_vision/features/editor/presentation/widgets/symbol_palette.dart';

import '../../../support/editor_controls_harness.dart';

void main() {
  setUpAll(loadControlsFonts);

  Future<void> modified(WidgetTester tester, LogicalKeyboardKey key) async {
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(key);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pumpAndSettle();
  }

  Future<void> search(WidgetTester tester, String query) async {
    await tester.tap(find.byTooltip('Score commands (Ctrl/Cmd+K)'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('editor-command-search')),
      query,
    );
    await tester.pumpAndSettle();
  }

  Note selectedNote(WidgetTester tester) =>
      shownControlsScore(tester).getSymbolAt(0, 0, 0) as Note;

  testWidgets('search runs octave edits and undo restores the saved score', (
    tester,
  ) async {
    await pumpControls(tester);
    await search(tester, 'raise octave');
    expect(find.text('Raise octave'), findsOneWidget);
    expect(find.text('Lower octave'), findsNothing);
    await tester.tap(find.byKey(const ValueKey('command-octaveUp')));
    await tester.pumpAndSettle();
    expect(find.byType(EditorCommandPalette), findsNothing);
    expect(selectedNote(tester).pitch, 'C5');
    await tester.tap(find.byTooltip('Undo'));
    await tester.pumpAndSettle();
    expect(selectedNote(tester).pitch, 'C4');
    expect(find.text('Unsaved'), findsNothing);
  });

  testWidgets('search keyboard navigation edits only after submitting', (
    tester,
  ) async {
    await pumpControls(tester);
    await modified(tester, LogicalKeyboardKey.keyK);
    expect(find.byType(EditorCommandPalette), findsOneWidget);
    await tester.enterText(
      find.byKey(const ValueKey('editor-command-search')),
      'octave',
    );
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pumpAndSettle();
    expect(selectedNote(tester).pitch, 'C4');
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await tester.pumpAndSettle();
    expect(selectedNote(tester).pitch, 'C3');
  });

  testWidgets('search explains missing selection and empty results', (
    tester,
  ) async {
    await pumpControls(tester, selectedSymbol: null);
    await search(tester, 'raise octave');
    expect(find.text('Pitch · Select a note or rest'), findsOneWidget);
    final row = tester.widget<InkWell>(
      find.byKey(const ValueKey('command-octaveUp')),
    );
    expect(row.onTap, isNull);
    await tester.enterText(
      find.byKey(const ValueKey('editor-command-search')),
      'nothing-will-match-this',
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('No matching commands'), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.byType(EditorCommandPalette), findsNothing);
    expect(selectedNote(tester).pitch, 'C4');
  });

  testWidgets('playback starting during search prevents stale edits', (
    tester,
  ) async {
    final (playback, _) = await pumpControls(tester);
    await search(tester, 'raise octave');
    playback.emit(PlaybackStatus.playing);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('command-octaveUp')));
    await tester.pumpAndSettle();
    expect(selectedNote(tester).pitch, 'C4');
    await search(tester, 'raise octave');
    expect(
      find.text('Pitch · Pause playback to edit the score'),
      findsOneWidget,
    );
    expect(
      tester
          .widget<InkWell>(find.byKey(const ValueKey('command-octaveUp')))
          .onTap,
      isNull,
    );
  });

  testWidgets(
    'octave and duration keys share command history; entry values do not edit',
    (tester) async {
      await pumpControls(tester);
      await modified(tester, LogicalKeyboardKey.arrowUp);
      expect(selectedNote(tester).pitch, 'C5');
      await tester.sendKeyEvent(LogicalKeyboardKey.digit4);
      await tester.pumpAndSettle();
      expect(selectedNote(tester).type, 'eighth');
      await tester.sendKeyEvent(LogicalKeyboardKey.period);
      await tester.pumpAndSettle();
      expect(selectedNote(tester).dots, 1);
      await modified(tester, LogicalKeyboardKey.keyZ);
      expect(selectedNote(tester).dots, 0);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyN);
      await tester.sendKeyEvent(LogicalKeyboardKey.digit6);
      await tester.pumpAndSettle();
      expect(
        tester.widget<SymbolPalette>(find.byType(SymbolPalette)).selectedType,
        PaletteSymbolType.halfNote,
      );
      expect(selectedNote(tester).type, 'eighth');
    },
  );

  testWidgets('conversion is reachable on a phone and can be undone', (
    tester,
  ) async {
    await pumpControls(tester, size: const Size(390, 844));
    await tester.ensureVisible(find.text('To rest'));
    await tester.tap(find.text('To rest'));
    await tester.pumpAndSettle();
    expect(shownControlsScore(tester).getSymbolAt(0, 0, 0), isA<Rest>());
    await tester.ensureVisible(find.text('To C4 note'));
    await tester.tap(find.text('To C4 note'));
    await tester.pumpAndSettle();
    expect(selectedNote(tester).pitch, 'C4');
    await tester.tap(find.byTooltip('Undo'));
    await tester.pumpAndSettle();
    expect(shownControlsScore(tester).getSymbolAt(0, 0, 0), isA<Rest>());
  });

  testWidgets('search retains the query when a keyboard reduces its height', (
    tester,
  ) async {
    await pumpControls(tester, size: const Size(844, 390));
    await search(tester, 'raise octave');
    tester.view.viewInsets = const FakeViewPadding(bottom: 180);
    addTearDown(tester.view.resetViewInsets);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    final field = tester.widget<TextField>(
      find.byKey(const ValueKey('editor-command-search')),
    );
    expect(field.controller!.text, 'raise octave');
    expect(find.text('Lower octave'), findsNothing);
    expect(
      tester
          .getSize(find.byKey(const ValueKey('editor-command-results')))
          .height,
      greaterThan(60),
    );
  });

  for (final (name, size, textScale) in [
    ('phone', const Size(390, 844), 1.0),
    ('large-text', const Size(320, 640), 2.0),
    ('landscape', const Size(844, 390), 1.0),
    ('tablet', const Size(1200, 800), 1.0),
  ]) {
    testWidgets('commands fit $name with keyboard visible', (tester) async {
      await pumpControls(tester, size: size, textScale: textScale);
      tester.view.viewInsets = const FakeViewPadding(bottom: 180);
      addTearDown(tester.view.resetViewInsets);
      await search(tester, 'octave');
      expect(tester.takeException(), isNull);
      expect(find.text('Raise octave'), findsOneWidget);
      await captureControls(tester, 'commands-$name');
    });
  }
}
