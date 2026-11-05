import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:note_vision/core/models/score.dart';
import 'package:note_vision/features/detection/data/tflite_symbol_detector.dart';
import 'package:note_vision/features/detection/domain/detected_staff.dart';
import 'package:note_vision/features/detection/domain/detection_result.dart';
import 'package:note_vision/features/mapping/domain/mapping_result.dart';
import 'package:note_vision/features/mapping/domain/score_mapper_service.dart';
import 'package:note_vision/features/preprocessing/domain/image_preprocessor.dart';
import 'package:note_vision/features/preprocessing/domain/preprocessed_result.dart';
import 'package:note_vision/features/preprocessing/domain/staff_line_detector.dart';
import 'package:note_vision/features/scan/presentation/scan_viewmodel.dart';

PreprocessedResult _input(int id) => PreprocessedResult(
  bytes: Uint8List.fromList([id]),
  width: 1,
  height: 1,
  scale: 1,
  padX: 0,
  padY: 0,
);

class _Preprocessor implements ImagePreprocessor {
  _Preprocessor(this.process);
  final Future<PreprocessedResult> Function(Uint8List) process;
  @override
  Future<PreprocessedResult> preprocess(Uint8List bytes) => process(bytes);
}

class _Staves implements StaffLineDetector {
  @override
  List<DetectedStaff> detect(Uint8List bytes) => [];
}

/// Models the native detector's lifetime without loading a platform library.
class _Detector extends TfliteSymbolDetector {
  _Detector({this.deferred = false});
  final bool deferred;
  final calls = <int>[];
  final _starts = <int, Completer<void>>{};
  final _pending = <int, Completer<DetectionResult>>{};
  int disposals = 0;

  Future<void> started(int id) =>
      _starts.putIfAbsent(id, Completer<void>.new).future;

  @override
  Future<DetectionResult> detect(
    PreprocessedResult input,
    List<DetectedStaff> staves,
  ) {
    final id = input.bytes.single;
    calls.add(id);
    final pending = _pending[id] = Completer<DetectionResult>();
    _starts.putIfAbsent(id, Completer<void>.new).complete();
    if (!deferred) pending.complete(DetectionResult(imageId: 'scan-$id'));
    return pending.future;
  }

  void complete(int id) =>
      _pending[id]!.complete(DetectionResult(imageId: 'scan-$id'));
  void fail(int id) =>
      _pending[id]!.completeError(StateError('detector failed'));

  @override
  void dispose() => disposals++;
}

class _Mapper extends ScoreMapperService {
  int calls = 0;
  @override
  MappingResult map(DetectionResult detection) {
    calls++;
    return MappingResult(
      score: Score(id: detection.imageId!, title: '', composer: '', parts: []),
    );
  }
}

void main() {
  test('leaving during preparation never starts the native detector', () async {
    final prepared = Completer<PreprocessedResult>();
    final detector = _Detector();
    final vm = ScanViewModel(
      _Preprocessor((_) => prepared.future),
      _Staves(),
      detector,
    );
    final scan = vm.run(Uint8List(0));
    vm.dispose();
    prepared.complete(_input(1));
    await scan;
    expect(detector.calls, isEmpty);
    expect(detector.disposals, 1);
    expect(vm.result, isNull);
  });

  test('reset discards a late preparation error', () async {
    final prepared = Completer<PreprocessedResult>();
    final vm = ScanViewModel(
      _Preprocessor((_) => prepared.future),
      _Staves(),
      _Detector(),
    );
    addTearDown(vm.dispose);
    final states = <ScanState>[];
    vm.addListener(() => states.add(vm.state));
    final scan = vm.run(Uint8List(0));
    vm.reset();
    prepared.completeError(StateError('old photo failed'));
    await scan;
    expect(vm.state, ScanState.idle);
    expect(vm.errorMessage, isNull);
    expect(states, [ScanState.preprocessing, ScanState.idle]);
  });

  test('an older prepared photo cannot replace the newer scan', () async {
    final older = Completer<PreprocessedResult>();
    final detector = _Detector();
    final mapper = _Mapper();
    final vm = ScanViewModel(
      _Preprocessor(
        (bytes) async => bytes.single == 1 ? older.future : _input(2),
      ),
      _Staves(),
      detector,
      mapper: mapper,
    );
    addTearDown(vm.dispose);
    final first = vm.run(Uint8List.fromList([1]));
    await vm.run(Uint8List.fromList([2]));
    older.complete(_input(1));
    await first;
    expect(detector.calls, [2]);
    expect(mapper.calls, 1);
    expect(vm.result?.detection.imageId, 'scan-2');
    expect(vm.mappingResult?.score.id, 'scan-2');
  });

  test('a replacement scan waits for the active native detection', () async {
    final detector = _Detector(deferred: true);
    final mapper = _Mapper();
    final vm = ScanViewModel(
      _Preprocessor((bytes) async => _input(bytes.single)),
      _Staves(),
      detector,
      mapper: mapper,
    );
    addTearDown(vm.dispose);
    final first = vm.run(Uint8List.fromList([1]));
    await detector.started(1);
    final second = vm.run(Uint8List.fromList([2]));
    await Future<void>.delayed(Duration.zero);
    final concurrentCalls = [...detector.calls];
    detector.complete(1);
    await first;
    await detector.started(2);
    detector.complete(2);
    await second;
    expect(concurrentCalls, [1]);
    expect(mapper.calls, 1);
    expect(vm.result?.detection.imageId, 'scan-2');
  });

  for (final fails in [false, true]) {
    test(
      'leaving during detection frees the model after completion ($fails)',
      () async {
        final detector = _Detector(deferred: true);
        final mapper = _Mapper();
        final vm = ScanViewModel(
          _Preprocessor((_) async => _input(1)),
          _Staves(),
          detector,
          mapper: mapper,
        );
        final scan = vm.run(Uint8List(0));
        await detector.started(1);
        vm.dispose();
        final earlyDisposals = detector.disposals;
        fails ? detector.fail(1) : detector.complete(1);
        await scan;
        expect(earlyDisposals, 0);
        expect(detector.disposals, 1);
        expect(mapper.calls, 0);
        expect(vm.result, isNull);
        expect(vm.errorMessage, isNull);
      },
    );
  }

  test(
    'retry clears previous results even when the next photo fails',
    () async {
      final retry = Completer<PreprocessedResult>();
      var preparations = 0;
      final vm = ScanViewModel(
        _Preprocessor(
          (_) async => ++preparations == 1 ? _input(1) : retry.future,
        ),
        _Staves(),
        _Detector(),
        mapper: _Mapper(),
      );
      addTearDown(vm.dispose);
      await vm.run(Uint8List(0));
      expect(vm.mappingResult?.score.id, 'scan-1');
      final scan = vm.run(Uint8List(0));
      final resultWhilePreparing = vm.result;
      final mappingWhilePreparing = vm.mappingResult;
      retry.completeError(StateError('new photo failed'));
      await scan;
      expect(resultWhilePreparing, isNull);
      expect(mappingWhilePreparing, isNull);
      expect(vm.state, ScanState.error);
      expect(vm.result, isNull);
      expect(vm.mappingResult, isNull);
    },
  );

  test('a disposed scan screen cannot start another scan', () async {
    var preparations = 0;
    final detector = _Detector();
    final vm = ScanViewModel(
      _Preprocessor((_) async {
        preparations++;
        return _input(1);
      }),
      _Staves(),
      detector,
    );
    vm.dispose();
    await vm.run(Uint8List(0));
    expect(preparations, 0);
    expect(detector.calls, isEmpty);
    expect(detector.disposals, 1);
  });
}
