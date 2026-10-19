import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:note_vision/core/models/part.dart';
import 'package:note_vision/core/services/playback_service.dart';
import 'package:note_vision/core/widgets/score_notation_viewer.dart';

import '../../../support/editor_controls_harness.dart';

Future<void> openClearDialog(WidgetTester tester) async {
  await tester.tap(find.byTooltip('More'));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Clear all symbols…'));
  await tester.pumpAndSettle();
}

void main() {
  setUpAll(loadControlsFonts);

  testWidgets('clear confirms scope, supports cancel, undo, redo and save', (
    tester,
  ) async {
    final original = controlsScore();
    final score = original.copyWith(
      parts: [
        original.parts.first,
        Part(
          id: 'p2',
          name: 'Lower staff',
          measures: original.parts.first.measures,
        ),
      ],
    );
    final (_, storage) = await pumpControls(
      tester,
      score: score,
      existingProject: true,
    );
    final before = shownControlsScore(tester).toJson();
    await openClearDialog(tester);
    expect(
      find.textContaining('Remove all 24 notes and rests'),
      findsOneWidget,
    );
    expect(find.textContaining('every page and staff'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(shownControlsScore(tester).toJson(), before);
    expect(find.text('Unsaved'), findsNothing);

    await openClearDialog(tester);
    await tester.tap(find.text('Clear all symbols'));
    await tester.pumpAndSettle();
    expect(
      shownControlsScore(
        tester,
      ).parts.every((p) => p.measures.every((m) => m.symbols.isEmpty)),
      isTrue,
    );
    expect(find.text('Unsaved'), findsOneWidget);
    expect(find.text('All notes and rests cleared'), findsOneWidget);
    expect(find.text('Score Editor'), findsOneWidget);
    expect(
      tester
          .widget<ScoreNotationViewer>(find.byType(ScoreNotationViewer))
          .selectedSymbolIndex,
      isNull,
    );
    await tester.tap(find.text('Undo'));
    await tester.pumpAndSettle();
    expect(shownControlsScore(tester).toJson(), before);
    expect(find.text('Unsaved'), findsNothing);
    await tester.tap(find.byTooltip('Redo'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(
      storage.saved.single.decodeScore().parts.every(
        (p) => p.measures.every((m) => m.symbols.isEmpty),
      ),
      isTrue,
    );
    expect(find.text('Unsaved'), findsNothing);
    await tester.tap(find.byTooltip('Undo'));
    await tester.pumpAndSettle();
    expect(shownControlsScore(tester).toJson(), before);
    expect(find.text('Unsaved'), findsOneWidget);
  });

  testWidgets('clear is disabled during playback and resets paused transport', (
    tester,
  ) async {
    final (playback, _) = await pumpControls(tester);
    playback.emit(PlaybackStatus.playing);
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('More'));
    await tester.pumpAndSettle();
    final item = find.ancestor(
      of: find.text('Clear all symbols…'),
      matching: find.byWidgetPredicate((w) => w is PopupMenuItem),
    );
    expect(tester.widget<PopupMenuItem>(item).enabled, isFalse);
    await tester.tapAt(const Offset(10, 700));
    await tester.pumpAndSettle();
    playback.emit(PlaybackStatus.paused);
    playback.emitPosition(
      const PlaybackPosition(partIndex: 0, measureIndex: 2, symbolIndex: 1),
    );
    await tester.pumpAndSettle();
    await openClearDialog(tester);
    await tester.tap(find.text('Clear all symbols'));
    await tester.pumpAndSettle();
    expect(playback.status, PlaybackStatus.stopped);
    expect(find.byTooltip('Resume'), findsNothing);
    await tester.tap(find.byTooltip('More'));
    await tester.pumpAndSettle();
    expect(tester.widget<PopupMenuItem>(item).enabled, isFalse);
  });

  testWidgets('a later edit removes the clear Undo banner', (tester) async {
    await pumpControls(tester);
    await openClearDialog(tester);
    await tester.tap(find.text('Clear all symbols'));
    await tester.pumpAndSettle();
    expect(find.text('All notes and rests cleared'), findsOneWidget);
    await tester.ensureVisible(find.text('Add'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Add'));
    await tester.pumpAndSettle();
    expect(find.text('All notes and rests cleared'), findsNothing);
    expect(shownControlsScore(tester).parts.first.measures, hasLength(5));
    await tester.tap(find.byTooltip('Undo'));
    await tester.pumpAndSettle();
    expect(shownControlsScore(tester).parts.first.measures, hasLength(4));
    expect(
      shownControlsScore(
        tester,
      ).parts.first.measures.every((m) => m.symbols.isEmpty),
      isTrue,
    );
    await tester.tap(find.byTooltip('Undo'));
    await tester.pumpAndSettle();
    expect(
      shownControlsScore(tester).parts.first.measures.first.symbols,
      hasLength(3),
    );
  });

  testWidgets('confirmation rejects a score changed while the dialog is open', (
    tester,
  ) async {
    await pumpControls(tester);
    final before = shownControlsScore(tester).toJson();
    await openClearDialog(tester);
    // Simulate an asynchronous score update while confirmation is open.
    controlsAction(tester, 'Up').onTap!();
    await tester.pump();
    await tester.tap(find.text('Clear all symbols'));
    await tester.pumpAndSettle();
    expect(
      find.text('The score changed. Choose Clear all symbols again.'),
      findsOneWidget,
    );
    expect(
      shownControlsScore(tester).parts.first.measures.first.symbols,
      hasLength(3),
    );
    await tester.tap(find.byTooltip('Undo'));
    await tester.pumpAndSettle();
    expect(shownControlsScore(tester).toJson(), before);
  });

  for (final (name, size, scale) in [
    ('phone', const Size(390, 844), 1.0),
    ('small-phone-large-text', const Size(320, 568), 2.0),
    ('tablet', const Size(1024, 768), 1.0),
  ]) {
    testWidgets('clear menu and confirmation fit $name; dismissal is safe', (
      tester,
    ) async {
      await pumpControls(tester, size: size, textScale: scale);
      final before = shownControlsScore(tester).toJson();
      await tester.tap(find.byTooltip('More'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await captureControls(tester, 'clear-$name-menu');
      await tester.ensureVisible(find.text('Clear all symbols…'));
      await tester.tap(find.text('Clear all symbols…'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await captureControls(tester, 'clear-$name-dialog');
      expect(find.text('Clear all symbols?'), findsOneWidget);
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsNothing);
      expect(shownControlsScore(tester).toJson(), before);
      expect(find.text('Unsaved'), findsNothing);
    });
  }
}
