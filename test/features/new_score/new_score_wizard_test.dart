import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:note_vision/core/models/score.dart';
import 'package:note_vision/core/models/time_signature.dart';
import 'package:note_vision/core/theme/app_theme.dart';
import 'package:note_vision/features/new_score/new_score_wizard.dart';

import '../../support/editor_controls_harness.dart' show loadControlsFonts;

/// Opens the wizard from a button and returns what it pops.
Future<Score? Function()> pumpWizard(
  WidgetTester tester, {
  Size size = const Size(390, 844),
  double textScale = 1,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  Score? result;
  final theme = AppTheme.dark();
  await tester.pumpWidget(
    RepaintBoundary(
      key: _boundary,
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: theme.copyWith(
          textTheme: theme.textTheme.apply(fontFamily: 'NotoSans'),
        ),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(textScale)),
          child: child!,
        ),
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () async => result = await Navigator.push<Score>(
              context,
              MaterialPageRoute(builder: (_) => const NewScoreWizard()),
            ),
            child: const Text('open'),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
  return () => result;
}

final _boundary = GlobalKey();

Future<void> capture(WidgetTester tester, String name) async {
  final dir = Platform.environment['NV_EDITOR_SCREENSHOTS'];
  if (dir == null) return;
  await tester.runAsync(() async {
    final boundary =
        _boundary.currentContext!.findRenderObject() as RenderRepaintBoundary;
    final image = await boundary.toImage(pixelRatio: 1);
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();
    await Directory(dir).create(recursive: true);
    await File(
      '$dir/new-score-$name.png',
    ).writeAsBytes(data!.buffer.asUint8List());
  });
}

Future<void> tapVisible(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

Future<void> pickInstrument(WidgetTester tester, String name) async {
  await tester.scrollUntilVisible(
    find.text(name),
    100,
    scrollable: find.descendant(
      of: find.byType(BottomSheet),
      matching: find.byType(Scrollable),
    ),
  );
  await tester.tap(find.text(name));
  await tester.pumpAndSettle();
}

void main() {
  setUpAll(loadControlsFonts);

  testWidgets('choose SATB, 3/4 with a pickup and a tempo, then create', (
    tester,
  ) async {
    final result = await pumpWizard(tester);
    await capture(tester, 'instruments');
    await tapVisible(tester, find.widgetWithText(ChoiceChip, 'SATB'));
    // Your staves are listed first.
    await tester.drag(find.byType(ListView), const Offset(0, 2000));
    await tester.pumpAndSettle();
    expect(find.text('Tenor'), findsOneWidget);
    expect(find.text('Treble clef 8vb'), findsOneWidget);
    await tester.tap(find.text('Next'));
    await tester.pumpAndSettle();

    await tester.enterText(find.widgetWithText(TextField, 'Title'), 'Hymn');
    await tapVisible(tester, find.widgetWithText(ChoiceChip, '3/4'));
    await tapVisible(tester, find.widgetWithText(ChoiceChip, '1 quarter'));
    await tapVisible(tester, find.text('Write a metronome mark'));
    await capture(tester, 'details');
    await tester.ensureVisible(find.text('Create score'));
    await tester.tap(find.text('Create score'));
    await tester.pumpAndSettle();

    final score = result()!;
    expect(score.title, 'Hymn');
    expect(score.parts.map((p) => p.name), [
      'Soprano',
      'Alto',
      'Tenor',
      'Bass',
    ]);
    final first = score.parts.first.measures.first;
    expect(first.implicit, isTrue);
    expect(first.timeSignature, const TimeSignature(beats: 3, beatType: 4));
    expect(first.annotations.single.perMinute, 120);
    expect(score.parts.first.measures, hasLength(33));
  });

  testWidgets('instruments can be added, moved and removed; none blocks Next', (
    tester,
  ) async {
    await pumpWizard(tester);
    await tester.tap(find.byTooltip('Remove Piano'));
    await tester.pumpAndSettle();
    expect(
      tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
      isNull,
    );
    await tester.tap(find.text('Add instrument'));
    await tester.pumpAndSettle();
    await pickInstrument(tester, 'Cello');
    await tester.tap(find.text('Add instrument'));
    await tester.pumpAndSettle();
    await pickInstrument(tester, 'Flute');
    await tester.tap(find.byTooltip('Move Flute up'));
    await tester.pumpAndSettle();
    final names = tester
        .widgetList<ListTile>(find.byType(ListTile))
        .map((t) => (t.title as Text).data);
    expect(names, ['Flute', 'Cello']);
  });

  for (final (name, size, scale) in [
    ('phone', const Size(390, 844), 1.0),
    ('small-phone-large-text', const Size(320, 568), 2.0),
    ('landscape', const Size(844, 390), 1.0),
  ]) {
    testWidgets('Classical orchestra can be created on $name', (tester) async {
      final result = await pumpWizard(tester, size: size, textScale: scale);
      await tester.scrollUntilVisible(
        find.widgetWithText(ChoiceChip, 'Classical orchestra'),
        400,
        scrollable: find.byType(Scrollable).first,
      );
      await tapVisible(
        tester,
        find.widgetWithText(ChoiceChip, 'Classical orchestra'),
      );
      // Find the first instrument before moving down to the horns; lazy
      // list layout can correct its offset when the template adds staves.
      await tester.scrollUntilVisible(
        find.text('Flutes'),
        -200,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.scrollUntilVisible(
        find.text('Two treble staves'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text('Horns in F'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await capture(tester, 'classical-$name');
      await tester.tap(find.text('Next'));
      await tester.pumpAndSettle();
      await tapVisible(tester, find.text('Create score'));
      expect(result()!.parts, hasLength(13));
      expect(result()!.parts[5].squareBracket, isTrue);
      expect(result()!.parts[5].measures.first.clef?.sign, 'G');
      expect(tester.takeException(), isNull);
    });
  }

  for (final (name, size, scale) in [
    ('small-phone-large-text', const Size(320, 568), 2.0),
    ('landscape', const Size(844, 390), 1.0),
  ]) {
    testWidgets('both steps fit a $name', (tester) async {
      await pumpWizard(tester, size: size, textScale: scale);
      expect(tester.takeException(), isNull);
      await capture(tester, '$name-1');
      await tester.tap(find.text('Next'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await capture(tester, '$name-2');
    });
  }
}
