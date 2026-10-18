import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:note_vision/core/models/clef.dart';
import 'package:note_vision/core/models/measure.dart';
import 'package:note_vision/core/models/note.dart';
import 'package:note_vision/core/models/part.dart';
import 'package:note_vision/core/models/project.dart';
import 'package:note_vision/core/models/rest.dart';
import 'package:note_vision/core/models/score.dart';
import 'package:note_vision/core/models/time_signature.dart';
import 'package:note_vision/core/services/notation_review_service.dart';
import 'package:note_vision/core/services/playback_service.dart';
import 'package:note_vision/core/services/project_storage_service.dart';
import 'package:note_vision/core/theme/app_theme.dart';
import 'package:note_vision/core/widgets/score_notation_viewer.dart';
import 'package:note_vision/features/editor/domain/editor_actions.dart';
import 'package:note_vision/features/editor/model/editor_state.dart';
import 'package:note_vision/features/editor/presentation/editor_shell_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

class ControlsPlayback implements PlaybackService {
  final _states = StreamController<PlaybackState>.broadcast();
  final _positions = StreamController<PlaybackPosition>.broadcast();
  PlaybackStatus _status = PlaybackStatus.stopped;
  int _tempo = 120;
  PlaybackPosition _position = PlaybackPosition.none;
  int? soughtMeasure, soughtPart;
  @override
  Stream<PlaybackState> get stateStream => _states.stream;
  @override
  Stream<PlaybackPosition> get positionStream => _positions.stream;
  @override
  PlaybackStatus get status => _status;
  @override
  int get tempo => _tempo;
  @override
  PlaybackPosition get position => _position;
  @override
  Future<void> init() async {}
  void emit(PlaybackStatus status) {
    _status = status;
    _states.add(PlaybackState(status: status));
  }

  void emitPosition(PlaybackPosition position) {
    _position = position;
    _positions.add(position);
  }

  @override
  Future<void> play(
    Score score, {
    int fromMeasureIndex = 0,
    int fromPartIndex = 0,
    int? throughMeasureIndex,
  }) async {
    soughtMeasure = fromMeasureIndex;
    soughtPart = fromPartIndex;
    emit(PlaybackStatus.playing);
  }

  @override
  void stop() {
    if (!_states.isClosed) emit(PlaybackStatus.stopped);
  }

  @override
  void pause() => emit(PlaybackStatus.paused);
  @override
  void resume({Score? score}) => emit(PlaybackStatus.playing);
  @override
  Future<void> seek(
    Score score, {
    int fromMeasureIndex = 0,
    int fromPartIndex = 0,
  }) async {
    soughtMeasure = fromMeasureIndex;
    soughtPart = fromPartIndex;
    emitPosition(
      PlaybackPosition(
        partIndex: fromPartIndex,
        measureIndex: fromMeasureIndex,
        symbolIndex: 0,
      ),
    );
  }

  @override
  void setTempo(int bpm) {
    _tempo = bpm;
  }

  @override
  Future<void> dispose() async {
    await _states.close();
    await _positions.close();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class ControlsStorage extends ProjectStorageService {
  final saved = <Project>[];
  Completer<void>? pending;
  @override
  Future<void> saveProject(Project project) async {
    saved.add(project);
    await pending?.future;
  }
}

Score controlsScore() => NotationReviewService.ensureIdentity(
  Score(
    id: 'controls',
    title: 'Evening Study for Two Hands',
    composer: 'Note Vision',
    parts: [
      Part(
        id: 'p1',
        name: 'Upper staff',
        measures: [
          for (var m = 0; m < 4; m++)
            Measure(
              number: m + 1,
              clef: m == 0 ? const Clef(sign: 'G', line: 2) : null,
              timeSignature: m == 0
                  ? const TimeSignature(beats: 4, beatType: 4)
                  : null,
              symbols: const [
                Note(step: 'C', octave: 4, duration: 2, type: 'quarter'),
                Note(step: 'E', octave: 4, duration: 2, type: 'quarter'),
                Rest(duration: 4, type: 'half'),
              ],
            ),
        ],
      ),
    ],
  ),
);

final controlsBoundaryKey = GlobalKey();

Future<(ControlsPlayback, ControlsStorage)> pumpControls(
  WidgetTester tester, {
  Size size = const Size(1200, 800),
  double textScale = 1,
  int? selectedSymbol = 0,
  bool existingProject = false,
  ControlsStorage? storage,
  Score? score,
}) async {
  SharedPreferences.setMockInitialValues({});
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  final playback = ControlsPlayback();
  storage ??= ControlsStorage();
  score ??= controlsScore();
  var state = EditorState(score: score);
  if (selectedSymbol != null) {
    state = state.selectSymbolAt(
      partIndex: 0,
      measureIndex: 0,
      symbolIndex: selectedSymbol,
    );
  }
  addTearDown(() async {
    await tester.pumpWidget(const SizedBox.shrink());
    await playback.dispose();
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });
  final theme = AppTheme.dark();
  await tester.pumpWidget(
    RepaintBoundary(
      key: controlsBoundaryKey,
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
        home: EditorShellScreen(
          args: EditorShellArgs(
            score: score,
            initialState: state,
            existingProject: existingProject
                ? Project.create(name: 'Evening Study', score: score)
                : null,
          ),
          playbackService: playback,
          projectStorageService: storage,
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return (playback, storage);
}

InkWell controlsAction(WidgetTester tester, String label) =>
    tester.widget<InkWell>(
      find.ancestor(of: find.text(label), matching: find.byType(InkWell)).first,
    );

Score shownControlsScore(WidgetTester tester) => tester
    .widget<ScoreNotationViewer>(find.byType(ScoreNotationViewer).first)
    .score!;

Future<void> loadControlsFonts() async {
  if (Platform.environment['NV_EDITOR_SCREENSHOTS'] == null) return;
  await (FontLoader(
    'MaterialIcons',
  )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
  for (final name in ['NotoSans', 'NotoMusic']) {
    await (FontLoader(
      name,
    )..addFont(rootBundle.load('assets/fonts/$name-Regular.ttf'))).load();
  }
}

Future<void> captureControls(WidgetTester tester, String name) async {
  final directory = Platform.environment['NV_EDITOR_SCREENSHOTS'];
  if (directory == null) return;
  await tester.runAsync(() async {
    final boundary =
        controlsBoundaryKey.currentContext!.findRenderObject()
            as RenderRepaintBoundary;
    final image = await boundary.toImage(pixelRatio: 1);
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();
    await Directory(directory).create(recursive: true);
    await File('$directory/$name.png').writeAsBytes(data!.buffer.asUint8List());
  });
}
