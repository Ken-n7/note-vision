import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:note_vision/core/services/notation_review_service.dart';
import 'package:note_vision/core/services/playback_service.dart';
import 'package:note_vision/features/editor/presentation/widgets/review_bar_editor.dart';
import 'package:note_vision/features/editor/presentation/widgets/scan_key_correction_sheet.dart';
import '../../../support/editor_controls_harness.dart';
import 'guided_review_test.dart' show openReview, tap;

Future<void> openSheet(WidgetTester tester) async {
  await tap(tester, find.text('Correct key across rows…'));
  expect(find.byType(ScanKeyCorrectionSheet), findsOneWidget);
}

void main() {
  setUpAll(() async {
    // Use the shipped typography for both ordinary and screenshot runs.
    // Ahem's wide glyphs change the lazy list's scroll extents at 1.8x text.
    for (final name in ['NotoSans', 'NotoMusic']) {
      await (FontLoader(
        name,
      )..addFont(rootBundle.load('assets/fonts/$name-Regular.ttf'))).load();
    }
    await (FontLoader(
      'MaterialIcons',
    )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
  });

  testWidgets(
    'cancel and preview do not edit; explicit rows apply together and Undo restores',
    (tester) async {
      final (_, storage) = await openReview(
        tester,
        size: const Size(1024, 768),
      );
      final base = tester
          .widget<ReviewBarEditor>(find.byType(ReviewBarEditor))
          .score;
      await openSheet(tester);
      await tap(tester, find.byTooltip('Cancel key correction'));
      expect(
        tester.widget<ReviewBarEditor>(find.byType(ReviewBarEditor)).score,
        same(base),
      );
      await openSheet(tester);
      await tap(tester, find.byType(DropdownButtonFormField<int>).last);
      await tap(tester, find.text('3 sharps ♯').last);
      await tap(tester, find.text('Select all rows'));
      await tap(tester, find.text('Preview key correction'));
      expect(find.text('2 rows will change to 3 sharps ♯'), findsOneWidget);
      expect(
        tester.widget<ReviewBarEditor>(find.byType(ReviewBarEditor)).score,
        same(base),
      );
      await tap(tester, find.text('Current key'));
      await tap(tester, find.text('Proposed key'));
      await captureControls(tester, 'key-correction-preview');
      await tap(tester, find.text('Apply key correction'));
      await tap(tester, find.text('Save & close'));
      final corrected = storage.saved.last.decodeScore();
      expect(
        corrected.parts.map((p) => p.measures.first.keySignature?.fifths),
        [3, 3],
      );
      expect(
        corrected.reviewHistory.where(
          (e) => e.change?.startsWith('Correct key on') ?? false,
        ),
        hasLength(1),
      );
      final restored = NotationReviewService.restore(
        corrected,
        corrected.reviewHistory.last,
      )!;
      expect(
        restored.parts.map((p) => p.toJson()),
        base.parts.map((p) => p.toJson()),
      );
      await tap(tester, find.byTooltip('Undo'));
      await tap(tester, find.text('Save'));
      expect(
        storage.saved.last.decodeScore().parts.map((p) => p.toJson()),
        base.parts.map((p) => p.toJson()),
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'only current row is selected by default and empty selection disables preview',
    (tester) async {
      final (_, storage) = await openReview(
        tester,
        size: const Size(1024, 768),
      );
      final base = tester
          .widget<ReviewBarEditor>(find.byType(ReviewBarEditor))
          .score;
      await openSheet(tester);
      final rows = tester
          .widgetList<CheckboxListTile>(find.byType(CheckboxListTile))
          .toList();
      expect(rows.map((r) => r.value), [true, false]);
      await tap(tester, find.text('Clear selection'));
      expect(
        tester
            .widget<FilledButton>(
              find.widgetWithText(FilledButton, 'Preview key correction'),
            )
            .onPressed,
        isNull,
      );
      await tap(tester, find.text('Row 1').last);
      await tap(tester, find.text('Preview key correction'));
      await tap(tester, find.text('Change selection'));
      await tap(tester, find.text('Preview key correction'));
      await tap(tester, find.text('Apply key correction'));
      await tap(tester, find.text('Save & close'));
      expect(
        storage.saved.last.decodeScore().parts[1].toJson(),
        base.parts[1].toJson(),
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'playback starting during preview prevents applying the correction',
    (tester) async {
      final (playback, _) = await openReview(
        tester,
        size: const Size(1024, 768),
      );
      final base = tester
          .widget<ReviewBarEditor>(find.byType(ReviewBarEditor))
          .score;
      await openSheet(tester);
      await tap(tester, find.text('Preview key correction'));
      playback.emit(PlaybackStatus.playing);
      await tester.pumpAndSettle();
      await tap(tester, find.text('Apply key correction'));
      expect(
        tester
            .widget<ReviewBarEditor>(find.byType(ReviewBarEditor))
            .score
            .toJson(),
        base.toJson(),
      );
      playback.emit(PlaybackStatus.stopped);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    },
  );

  for (final (name, size, scale) in [
    ('small', const Size(320, 568), 1.0),
    ('large-text', const Size(390, 844), 1.8),
    ('landscape', const Size(844, 390), 1.0),
  ]) {
    testWidgets('row selection and preview fit $name', (tester) async {
      await openReview(tester, size: size, scale: scale);
      await openSheet(tester);
      await tester.scrollUntilVisible(
        find.text('Select all rows'),
        120,
        scrollable: find
            .descendant(
              of: find.byType(ScanKeyCorrectionSheet),
              matching: find.byType(Scrollable),
            )
            .first,
      );
      await tap(tester, find.text('Select all rows'));
      await tap(tester, find.text('Preview key correction'));
      await tester.scrollUntilVisible(
        find.text('Proposed key'),
        180,
        scrollable: find
            .descendant(
              of: find.byType(ScanKeyCorrectionSheet),
              matching: find.byType(Scrollable),
            )
            .first,
      );
      await tap(tester, find.text('Proposed key'));
      await captureControls(tester, 'key-correction-$name');
      expect(tester.takeException(), isNull);
      await tap(tester, find.byTooltip('Cancel key correction'));
    });
  }
}
