import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:note_vision/core/models/measure.dart';
import 'package:note_vision/core/services/playback_service.dart';
import 'package:note_vision/features/editor/presentation/widgets/annotations_sheet.dart';
import '../../../support/editor_controls_harness.dart';

Future<void> open(WidgetTester tester, LogicalKeyboardKey key) async {
  await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
  await tester.sendKeyDownEvent(LogicalKeyboardKey.altLeft);
  await tester.sendKeyEvent(key);
  await tester.sendKeyUpEvent(LogicalKeyboardKey.altLeft);
  await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
  await tester.pumpAndSettle();
  expect(find.byType(AnnotationsSheet), findsOneWidget);
}

void main() {
  setUpAll(loadControlsFonts);
  for (final (name, size, scale) in [
    ('phone', const Size(390, 844), 1.0),
    ('large-text', const Size(320, 568), 2.0),
    ('landscape', const Size(844, 390), 1.0),
    ('tablet', const Size(1024, 768), 1.0),
  ]) {
    testWidgets('annotations panel fits $name and keyboard', (tester) async {
      await pumpControls(tester, size: size, textScale: scale);
      await open(tester, LogicalKeyboardKey.keyT);
      await captureControls(tester, 'annotations-$name');
      expect(tester.takeException(), isNull);
      tester.view.viewInsets = const FakeViewPadding(bottom: 180);
      addTearDown(tester.view.resetViewInsets);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(
        find.byKey(const ValueKey('annotations-apply')).hitTestable(),
        findsOneWidget,
      );
    });
  }
  testWidgets('tempo applies in one edit, shows relative speed and undoes', (
    tester,
  ) async {
    await pumpControls(tester);
    await open(tester, LogicalKeyboardKey.keyT);
    await tester.enterText(
      find.byKey(const ValueKey('annotation-text')),
      'Andante',
    );
    await tester.ensureVisible(find.byKey(const ValueKey('annotation-bpm')));
    await tester.enterText(find.byKey(const ValueKey('annotation-bpm')), '80');
    await tester.tap(find.byKey(const ValueKey('annotations-apply')));
    await tester.pumpAndSettle();
    final a = shownControlsScore(
      tester,
    ).parts.first.measures.first.annotations.single;
    expect((a.kind, a.text, a.tempo), (AnnotationKind.tempo, 'Andante', 80));
    expect(find.text('100%'), findsOneWidget);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyZ);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pumpAndSettle();
    expect(
      shownControlsScore(tester).parts.first.measures.first.annotations,
      isEmpty,
    );
  });
  testWidgets(
    'chord validates before apply and cancel leaves score unchanged',
    (tester) async {
      await pumpControls(tester);
      final original = shownControlsScore(tester);
      await open(tester, LogicalKeyboardKey.keyK);
      await tester.enterText(
        find.byKey(const ValueKey('annotation-text')),
        'nonsense',
      );
      await tester.tap(find.byKey(const ValueKey('annotations-apply')));
      await tester.pumpAndSettle();
      expect(find.byType(AnnotationsSheet), findsOneWidget);
      await tester.enterText(
        find.byKey(const ValueKey('annotation-text')),
        'Bbmaj7/F',
      );
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(shownControlsScore(tester), same(original));
      await open(tester, LogicalKeyboardKey.keyK);
      await tester.enterText(
        find.byKey(const ValueKey('annotation-text')),
        'Bbmaj7/F',
      );
      await tester.tap(find.byKey(const ValueKey('annotations-apply')));
      await tester.pumpAndSettle();
      expect(
        shownControlsScore(
          tester,
        ).parts.first.measures.first.annotations.single.chord!.label,
        'Bbmaj7/F',
      );
    },
  );
  testWidgets('playback beginning while panel is open prevents apply', (
    tester,
  ) async {
    final (playback, _) = await pumpControls(tester);
    final original = shownControlsScore(tester);
    await open(tester, LogicalKeyboardKey.keyT);
    playback.emit(PlaybackStatus.playing);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('annotations-apply')));
    await tester.pumpAndSettle();
    expect(shownControlsScore(tester), same(original));
  });
  testWidgets(
    'tempo shortcut edits the existing beat and unchanged apply is a no-op',
    (tester) async {
      await pumpControls(tester);
      await open(tester, LogicalKeyboardKey.keyT);
      await tester.tap(find.byKey(const ValueKey('annotations-apply')));
      await tester.pumpAndSettle();
      final original = shownControlsScore(tester);
      await open(tester, LogicalKeyboardKey.keyT);
      await tester.tap(find.byKey(const ValueKey('annotations-apply')));
      await tester.pumpAndSettle();
      expect(shownControlsScore(tester), same(original));
      expect(
        shownControlsScore(tester).parts.first.measures.first.annotations,
        hasLength(1),
      );
    },
  );
  testWidgets('removing another marking keeps a pending text edit', (
    tester,
  ) async {
    await pumpControls(tester);
    await open(tester, LogicalKeyboardKey.keyT);
    await tester.tap(find.text('Add Staff text'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const ValueKey('annotation-text')));
    await tester.enterText(
      find.byKey(const ValueKey('annotation-text')),
      'dolce',
    );
    await tester.tap(find.byKey(const ValueKey('annotations-apply')));
    await tester.pumpAndSettle();
    await open(tester, LogicalKeyboardKey.keyT);
    await tester.tap(find.byKey(const ValueKey('annotation-item-1')));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const ValueKey('annotation-text')));
    await tester.enterText(
      find.byKey(const ValueKey('annotation-text')),
      'cantabile',
    );
    final remove = find.descendant(
      of: find.byKey(const ValueKey('annotation-item-0')),
      matching: find.byTooltip('Remove marking'),
    );
    await tester.ensureVisible(remove);
    await tester.tap(remove);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('annotations-apply')));
    await tester.pumpAndSettle();
    expect(
      shownControlsScore(
        tester,
      ).parts.first.measures.first.annotations.single.text,
      'cantabile',
    );
  });
}
