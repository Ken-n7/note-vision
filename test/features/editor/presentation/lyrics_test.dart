import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:note_vision/core/models/note.dart';
import 'package:note_vision/core/services/playback_service.dart';
import 'package:note_vision/features/editor/presentation/widgets/lyrics_sheet.dart';
import '../../../support/editor_controls_harness.dart';

const field = ValueKey('lyrics-text');
Future<void> openLyrics(WidgetTester tester) async {
  await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
  await tester.sendKeyEvent(LogicalKeyboardKey.keyL);
  await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
  await tester.pumpAndSettle();
  expect(find.byType(LyricsSheet), findsOneWidget);
}

void main() {
  setUpAll(loadControlsFonts);
  for (final (name, size, scale) in [
    ('phone', const Size(390, 844), 1.0),
    ('small-large-text', const Size(320, 568), 2.0),
    ('landscape', const Size(844, 390), 1.0),
    ('tablet', const Size(1024, 768), 1.0),
  ]) {
    testWidgets('lyrics panel fits $name and a visible keyboard', (
      tester,
    ) async {
      await pumpControls(tester, size: size, textScale: scale);
      await openLyrics(tester);
      await captureControls(tester, 'lyrics-$name');
      expect(tester.takeException(), isNull);
      tester.view.viewInsets = const FakeViewPadding(bottom: 180);
      addTearDown(tester.view.resetViewInsets);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(
        find.byKey(const ValueKey('lyrics-apply')).hitTestable(),
        findsOneWidget,
      );
    });
  }

  testWidgets('word entry applies all lyrics in one undo step', (tester) async {
    await pumpControls(tester);
    final original = shownControlsScore(tester);
    await openLyrics(tester);
    await tester.enterText(find.byKey(field), 'Hap-');
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(field), 'py');
    await tester.tap(find.byKey(const ValueKey('lyrics-apply')));
    await tester.pumpAndSettle();
    final score = shownControlsScore(tester);
    final first = score.parts.first.measures.first.symbols
        .whereType<Note>()
        .toList();
    expect(first[0].lyrics.single.text, 'Hap');
    expect(first[0].lyrics.single.syllabic, Syllabic.begin);
    expect(first[1].lyrics.single.text, 'py');
    expect(first[1].lyrics.single.syllabic, Syllabic.end);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyZ);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pumpAndSettle();
    expect(
      shownControlsScore(tester).parts.first.toJson(),
      original.parts.first.toJson(),
    );
  });

  testWidgets('extensions and pasted syllables advance across bars', (
    tester,
  ) async {
    await pumpControls(tester);
    await openLyrics(tester);
    await tester.enterText(find.byKey(field), 'Sing__');
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('lyrics-apply')));
    await tester.pumpAndSettle();
    final lyrics = shownControlsScore(tester).parts.first.measures
        .expand((m) => m.symbols)
        .whereType<Note>()
        .expand((n) => n.lyrics)
        .toList();
    expect(lyrics.map((l) => l.extend), [
      LyricExtend.start,
      LyricExtend.continueLine,
      LyricExtend.stop,
    ]);
    await openLyrics(tester);
    await tester.enterText(find.byKey(field), 'Mer-ry dawn');
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('lyrics-apply')));
    await tester.pumpAndSettle();
    final words = shownControlsScore(tester).parts.first.measures
        .expand((m) => m.symbols)
        .whereType<Note>()
        .expand((n) => n.lyrics)
        .toList();
    expect(words.take(3).map((l) => (l.text, l.syllabic)), [
      ('Mer', Syllabic.begin),
      ('ry', Syllabic.end),
      ('dawn', Syllabic.single),
    ]);
  });

  testWidgets(
    'applying without changes creates no history or score replacement',
    (tester) async {
      await pumpControls(tester);
      final original = shownControlsScore(tester);
      await openLyrics(tester);
      await tester.tap(find.byKey(const ValueKey('lyrics-apply')));
      await tester.pumpAndSettle();
      expect(shownControlsScore(tester), same(original));
    },
  );

  testWidgets('cancel and dismissal leave no lyric edits', (tester) async {
    await pumpControls(tester);
    final original = shownControlsScore(tester);
    await openLyrics(tester);
    await tester.enterText(find.byKey(field), 'discard-');
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(shownControlsScore(tester), same(original));
  });

  testWidgets('switching verses keeps the pending syllable', (tester) async {
    await pumpControls(tester);
    await openLyrics(tester);
    await tester.enterText(find.byKey(field), 'One');
    await tester.enterText(find.byKey(const ValueKey('lyrics-verse')), '2');
    await tester.enterText(find.byKey(field), 'Two');
    await tester.tap(find.byKey(const ValueKey('lyrics-apply')));
    await tester.pumpAndSettle();
    final first =
        shownControlsScore(tester).parts.first.measures.first.symbols.first
            as Note;
    expect(first.lyrics.map((l) => (l.verse, l.text)), [
      ('1', 'One'),
      ('2', 'Two'),
    ]);
  });

  testWidgets('playback starting while lyrics are open prevents apply', (
    tester,
  ) async {
    final (playback, _) = await pumpControls(tester);
    final original = shownControlsScore(tester);
    await openLyrics(tester);
    await tester.enterText(find.byKey(field), 'blocked');
    playback.emit(PlaybackStatus.playing);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('lyrics-apply')));
    await tester.pumpAndSettle();
    expect(shownControlsScore(tester), same(original));
  });
}
