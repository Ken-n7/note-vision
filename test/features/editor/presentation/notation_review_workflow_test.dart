import 'package:shared_preferences/shared_preferences.dart';
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:note_vision/core/models/clef.dart';
import 'package:note_vision/core/models/measure.dart';
import 'package:note_vision/core/models/note.dart';
import 'package:note_vision/core/models/part.dart';
import 'package:note_vision/core/models/score.dart';
import 'package:note_vision/core/models/score_review.dart';
import 'package:note_vision/core/models/time_signature.dart';
import 'package:note_vision/core/services/playback_service.dart';
import 'package:note_vision/core/theme/app_theme.dart';
import 'package:note_vision/core/widgets/score_notation_viewer.dart';
import 'package:note_vision/features/editor/model/editor_state.dart';
import 'package:note_vision/features/editor/presentation/editor_shell_screen.dart';
import 'package:note_vision/features/editor/presentation/widgets/notation_review_panel.dart';
import 'package:note_vision/features/editor/presentation/widgets/scan_comparison_view.dart';

class _ReviewPlayback implements PlaybackService {
  final states = StreamController<PlaybackState>.broadcast();
  final positions = StreamController<PlaybackPosition>.broadcast();
  PlaybackStatus _status = PlaybackStatus.stopped;
  Score? playedScore;
  int? first, last, part;

  @override
  Stream<PlaybackState> get stateStream => states.stream;
  @override
  Stream<PlaybackPosition> get positionStream => positions.stream;
  @override
  PlaybackStatus get status => _status;
  @override
  int get tempo => 120;
  @override
  PlaybackPosition get position => PlaybackPosition.none;
  @override
  Future<void> init() async {}
  @override
  Future<void> play(
    Score score, {
    int fromMeasureIndex = 0,
    int fromPartIndex = 0,
    int? throughMeasureIndex,
  }) async {
    playedScore = score;
    first = fromMeasureIndex;
    part = fromPartIndex;
    last = throughMeasureIndex;
    _status = PlaybackStatus.playing;
    states.add(PlaybackState(status: _status));
  }

  @override
  void stop() {
    _status = PlaybackStatus.stopped;
    if (!states.isClosed) states.add(PlaybackState(status: _status));
  }

  @override
  Future<void> dispose() async {
    await states.close();
    await positions.close();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Score _score({bool withScan = false}) {
  final image = img.Image(width: 600, height: 200);
  img.fill(image, color: img.ColorRgb8(250, 248, 241));
  for (var line = 0; line < 5; line++) {
    img.drawLine(
      image,
      x1: 20,
      y1: 65 + line * 15,
      x2: 580,
      y2: 65 + line * 15,
      color: img.ColorRgb8(60, 55, 50),
    );
  }
  for (var n = 0; n < 2; n++) {
    img.fillCircle(
      image,
      x: 100 + n * 140,
      y: 110 - n * 15,
      radius: 8,
      color: img.ColorRgb8(40, 35, 30),
    );
    img.drawLine(
      image,
      x1: 107 + n * 140,
      y1: 110 - n * 15,
      x2: 107 + n * 140,
      y2: 60 - n * 15,
      thickness: 2,
      color: img.ColorRgb8(40, 35, 30),
    );
  }
  return Score(
    id: 'review-demo',
    title: 'Evening Study',
    composer: '',
    sourcePages: withScan
        ? [
            ScoreSourcePage(
              id: 'scan',
              imageBase64: base64Encode(img.encodePng(image)),
            ),
          ]
        : [],
    parts: [
      Part(
        id: 'p1',
        name: 'Upper staff',
        measures: [
          for (var m = 0; m < 7; m++)
            Measure(
              number: m + 1,
              clef: m == 0 ? const Clef(sign: 'G', line: 2) : null,
              timeSignature: m == 0
                  ? const TimeSignature(beats: 4, beatType: 4)
                  : null,
              // Bars 2 and 5 hold their last note twice, as a doubled
              // detection would (same place on the page).
              symbols: [
                for (var n = 0; n < (m == 1 || m == 4 ? 5 : 4); n++)
                  Note(
                    step: ['C', 'D', 'E', 'G', 'G'][n],
                    octave: 4,
                    duration: 2,
                    type: 'quarter',
                    source: withScan
                        ? SourceRegion(
                            pageId: 'scan',
                            x: (90 + (n < 4 ? n : 3) * 140) / 600,
                            y: .2,
                            width: .04,
                            height: .4,
                          )
                        : null,
                  ),
              ],
            ),
        ],
      ),
    ],
  );
}

final _boundaryKey = GlobalKey();

Future<_ReviewPlayback> _pump(
  WidgetTester tester, {
  Size size = const Size(390, 844),
  double textScale = 1,
  bool withScan = false,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  final playback = _ReviewPlayback();
  addTearDown(() async {
    await tester.pumpWidget(const SizedBox.shrink());
    await playback.dispose();
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });
  final score = _score(withScan: withScan);
  await tester.pumpWidget(
    RepaintBoundary(
      key: _boundaryKey,
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: AppTheme.dark().copyWith(
          textTheme: AppTheme.dark().textTheme.apply(fontFamily: 'NotoSans'),
        ),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(textScale)),
          child: child!,
        ),
        home: EditorShellScreen(
          args: EditorShellArgs(
            score: score,
            initialState: EditorState(score: score),
          ),
          playbackService: playback,
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  await tester.tap(find.byTooltip('Review & Correct'));
  await tester.pumpAndSettle();
  return playback;
}

Future<void> _tap(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

Future<void> _capture(WidgetTester tester, String name) async {
  final directory = Platform.environment['NV_REVIEW_SCREENSHOTS'];
  if (directory == null) return;
  await tester.runAsync(() async {
    final boundary =
        _boundaryKey.currentContext!.findRenderObject()
            as RenderRepaintBoundary;
    final image = await boundary.toImage(pixelRatio: 1);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();
    await Directory(directory).create(recursive: true);
    await File(
      '$directory/$name.png',
    ).writeAsBytes(bytes!.buffer.asUint8List());
  });
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));
  setUpAll(() async {
    if (Platform.environment['NV_REVIEW_SCREENSHOTS'] != null) {
      await (FontLoader(
        'MaterialIcons',
      )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
      for (final font in ['NotoSans', 'NotoMusic']) {
        await (FontLoader(
          font,
        )..addFont(rootBundle.load('assets/fonts/$font-Regular.ttf'))).load();
      }
    }
  });

  for (final (name, size, scale) in [
    ('phone', const Size(390, 844), 1.0),
    ('small-phone', const Size(320, 568), 1.0),
    ('large-text', const Size(390, 844), 1.8),
    ('landscape-phone', const Size(844, 390), 1.0),
    ('tablet', const Size(1024, 768), 1.0),
  ]) {
    testWidgets('review remains usable on $name', (tester) async {
      await _pump(tester, size: size, textScale: scale);
      expect(find.byType(NotationReviewPanel), findsOneWidget);
      expect(tester.takeException(), isNull);
      await _capture(tester, name);
      await _tap(tester, find.text('Preview change'));
      expect(tester.takeException(), isNull);
      final preview = tester.widget<ScoreNotationViewer>(
        find.byType(ScoreNotationViewer).first,
      );
      // The doubled note is gone from bar 2.
      expect(preview.score!.parts.first.measures[1].symbols, hasLength(4));
      await _capture(tester, '$name-preview');
      await _tap(tester, find.text('Apply change'));
      expect(
        find.text('1 remaining · 1 applied · 0 kept original'),
        findsOneWidget,
      );
      await _tap(tester, find.byTooltip('Undo'));
      expect(
        find.text('2 remaining · 0 applied · 0 kept original'),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets(
    'kept decisions can be reopened from history after closing review',
    (tester) async {
      await _pump(tester);
      await _tap(tester, find.text('Keep original'));
      expect(
        find.text('1 remaining · 0 applied · 1 kept original'),
        findsOneWidget,
      );
      await _tap(tester, find.text('Done'));
      expect(find.byType(NotationReviewPanel), findsNothing);
      await _tap(tester, find.byTooltip('Review & Correct'));
      await _tap(tester, find.text('History'));
      await _tap(tester, find.text('Review again'));
      expect(
        find.text('2 remaining · 0 applied · 0 kept original'),
        findsOneWidget,
      );
    },
  );

  testWidgets(
    'batch previews selected changes and applies them in one undo step',
    (tester) async {
      await _pump(tester, size: const Size(1024, 768));
      await _tap(tester, find.text('Batch'));
      final checkboxes = find.byType(CheckboxListTile);
      await _tap(tester, checkboxes.at(0));
      await _tap(tester, checkboxes.at(1));
      await _tap(tester, find.text('Preview selected (2)'));
      expect(find.text('Changes 2 measures across 1 staff.'), findsOneWidget);
      await _capture(tester, 'batch-preview');
      await _tap(tester, find.text('Apply selected (2)'));
      expect(
        find.text('0 remaining · 2 applied · 0 kept original'),
        findsOneWidget,
      );
      await _tap(tester, find.byTooltip('Undo'));
      expect(
        find.text('2 remaining · 0 applied · 0 kept original'),
        findsOneWidget,
      );
    },
  );

  testWidgets(
    'original scan is available during review and playback uses the proposed passage',
    (tester) async {
      final playback = await _pump(tester, withScan: true);
      await tester.ensureVisible(find.text('Compare original scan'));
      await tester.tap(find.text('Compare original scan'));
      await tester.pump();
      await tester.runAsync(() async {
        await Future<void>.delayed(const Duration(milliseconds: 80));
      });
      await tester.pumpAndSettle();
      expect(find.byType(ScanComparisonView), findsOneWidget);
      expect(tester.takeException(), isNull);
      await _capture(tester, 'scan-comparison');
      await _tap(tester, find.text('Preview change'));
      await _tap(tester, find.text('Listen to proposed'));
      expect(
        playback.playedScore!.parts.first.measures[1].symbols,
        hasLength(4),
      );
      expect(playback.first, 0);
      expect(playback.last, 2);
      expect(playback.part, 0);
      final apply = tester.widget<FilledButton>(
        find.widgetWithText(FilledButton, 'Apply change'),
      );
      expect(apply.onPressed, isNull);
      await _tap(tester, find.text('Stop listening'));
      expect(
        tester
            .widget<FilledButton>(
              find.widgetWithText(FilledButton, 'Apply change'),
            )
            .onPressed,
        isNotNull,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('review panel resizes without covering the score', (
    tester,
  ) async {
    await _pump(tester);
    final panel = find.byType(NotationReviewPanel);
    final before = tester.getSize(panel).height;
    await tester.drag(
      find.bySemanticsLabel('Resize review panel'),
      const Offset(0, -90),
    );
    await tester.pumpAndSettle();
    expect(tester.getSize(panel).height, greaterThan(before));
    final canvas = tester.getRect(find.byType(ScoreNotationViewer).first);
    expect(canvas.height, greaterThan(0));
    expect(tester.takeException(), isNull);
  });
}
