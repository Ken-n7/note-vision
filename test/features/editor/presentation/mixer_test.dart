import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:note_vision/core/models/part_playback.dart';
import 'package:note_vision/core/services/playback_service.dart';
import 'package:note_vision/features/editor/presentation/widgets/mixer_sheet.dart';
import 'package:note_vision/features/new_score/new_score.dart';
import '../../../support/editor_controls_harness.dart';
import '../../../support/playback_mix_fixture.dart';

Future<void> open(WidgetTester tester) async {
  await tester.tap(find.byTooltip('More'));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Mixer…'));
  await tester.pumpAndSettle();
  expect(find.byType(MixerSheet), findsOneWidget);
}

void main() {
  setUpAll(loadControlsFonts);
  testWidgets(
    'orchestral kit and mix are shared while mute stays per percussion part',
    (tester) async {
      final full = buildNewScore(
        NewScoreOptions(
          staves: scoreTemplates
              .firstWhere((t) => t.name == 'Symphony orchestra')
              .staves,
          bars: 1,
        ),
      );
      final score = full.copyWith(
        parts: full.parts.where((p) => p.singleLine).toList(),
      );
      await pumpControls(tester, score: score, selectedSymbol: null);
      await open(tester);
      expect(find.text('Orchestral kit'), findsOneWidget);
      tester
          .widget<Slider>(find.byKey(const ValueKey('mixer-volume')))
          .onChanged!(50);
      await tester.pump();
      await tester.ensureVisible(find.byKey(const ValueKey('mixer-mute')));
      await tester.tap(find.byKey(const ValueKey('mixer-mute')));
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('mixer-apply')));
      await tester.pumpAndSettle();
      final after = shownControlsScore(tester);
      expect(after.parts.map((p) => p.playback.volume), [50, 50, 50]);
      expect(after.parts.map((p) => p.playback.mute), [true, false, false]);
      await tester.tap(find.byTooltip('Undo'));
      await tester.pumpAndSettle();
      expect(shownControlsScore(tester).parts.map((p) => p.playback.volume), [
        100,
        100,
        100,
      ]);
      expect(shownControlsScore(tester).parts.map((p) => p.playback.mute), [
        false,
        false,
        false,
      ]);
    },
  );
  testWidgets('F10 opens the mixer and sound selection keeps notation', (
    tester,
  ) async {
    final (playback, _) = await pumpControls(tester);
    final before = shownControlsScore(tester);
    await tester.sendKeyEvent(LogicalKeyboardKey.f10);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('mixer-sound')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Bright piano').last);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('mixer-apply')));
    await tester.pumpAndSettle();
    final after = shownControlsScore(tester);
    expect(after.parts.first.playback.program, 1);
    expect(after.parts.first.measures, before.parts.first.measures);
    playback.emit(PlaybackStatus.playing);
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.f10);
    await tester.pumpAndSettle();
    expect(find.byType(MixerSheet), findsNothing);
  });
  for (final (name, size, scale) in [
    ('phone', const Size(390, 844), 1.0),
    ('large-text', const Size(320, 568), 2.0),
    ('landscape', const Size(844, 390), 1.0),
    ('tablet', const Size(1024, 768), 1.0),
  ]) {
    testWidgets('mixer fits $name', (tester) async {
      await pumpControls(
        tester,
        size: size,
        textScale: scale,
        score: ensemble(linked: true),
      );
      await open(tester);
      await captureControls(tester, 'mixer-$name');
      expect(tester.takeException(), isNull);
      expect(find.byKey(const ValueKey('mixer-strip-1')), findsNothing);
      expect(
        find.byKey(const ValueKey('mixer-apply')).hitTestable(),
        findsOneWidget,
      );
      await tester.ensureVisible(find.byKey(const ValueKey('mixer-solo')));
      await tester.tap(find.byKey(const ValueKey('mixer-solo')));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
  }
  testWidgets('apply saves both strips as one edit and undo restores mix', (
    tester,
  ) async {
    await pumpControls(tester, score: ensemble());
    await open(tester);
    tester
        .widget<Slider>(find.byKey(const ValueKey('mixer-volume')))
        .onChanged!(50);
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('mixer-strip-1')));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const ValueKey('mixer-mute')));
    await tester.tap(find.byKey(const ValueKey('mixer-mute')));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('mixer-apply')));
    await tester.pumpAndSettle();
    var score = shownControlsScore(tester);
    expect(score.parts.first.playback.volume, 50);
    expect(score.parts.last.playback.mute, true);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyZ);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pumpAndSettle();
    score = shownControlsScore(tester);
    expect(
      score.parts.map((p) => p.playback),
      everyElement(const PartPlayback()),
    );
  });
  testWidgets('cancel and unchanged apply leave score untouched', (
    tester,
  ) async {
    await pumpControls(tester);
    final original = shownControlsScore(tester);
    await open(tester);
    tester
        .widget<Slider>(find.byKey(const ValueKey('mixer-volume')))
        .onChanged!(20);
    await tester.pump();
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(shownControlsScore(tester), same(original));
    await open(tester);
    await tester.tap(find.byKey(const ValueKey('mixer-apply')));
    await tester.pumpAndSettle();
    expect(shownControlsScore(tester), same(original));
  });
  testWidgets('playback starting while mixer open prevents apply', (
    tester,
  ) async {
    final (playback, _) = await pumpControls(tester);
    final original = shownControlsScore(tester);
    await open(tester);
    tester
        .widget<Slider>(find.byKey(const ValueKey('mixer-volume')))
        .onChanged!(20);
    await tester.pump();
    playback.emit(PlaybackStatus.playing);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('mixer-apply')));
    await tester.pumpAndSettle();
    expect(shownControlsScore(tester), same(original));
  });
}
