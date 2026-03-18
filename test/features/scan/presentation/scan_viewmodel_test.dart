import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:note_vision/features/detection/domain/detection_result.dart';
import 'package:note_vision/features/detection/domain/detected_barline.dart';
import 'package:note_vision/features/detection/domain/detected_staff.dart';
import 'package:note_vision/features/detection/domain/detected_symbol.dart';
import 'package:note_vision/features/detection/domain/symbol_detector.dart';
import 'package:note_vision/features/preprocessing/domain/image_preprocessor.dart';
import 'package:note_vision/features/preprocessing/domain/preprocessed_result.dart';
import 'package:note_vision/features/scan/presentation/scan_viewmodel.dart';

class _FakeImagePreprocessor implements ImagePreprocessor {
  _FakeImagePreprocessor(this.result);

  final PreprocessedResult result;

  @override
  Future<PreprocessedResult> preprocess(Uint8List bytes) async => result;
}

class _FakeSymbolDetector implements SymbolDetector {
  _FakeSymbolDetector(this.result);

  final DetectionResult result;

  @override
  Future<DetectionResult> detect(PreprocessedResult input) async => result;
}

class _ThrowingImagePreprocessor implements ImagePreprocessor {
  @override
  Future<PreprocessedResult> preprocess(Uint8List bytes) {
    throw StateError('preprocessing failed');
  }
}

void main() {
  group('ScanViewModel', () {
    test('stores a full detection result after a successful run', () async {
      final preprocessed = PreprocessedResult(
        bytes: Uint8List.fromList(const [1, 2, 3]),
        width: 416,
        height: 416,
        scale: 1,
        padX: 0,
        padY: 0,
      );
      const detection = DetectionResult(
        imageId: 'scan-1',
        staffs: [
          DetectedStaff(
            id: 'staff-1',
            topY: 50,
            bottomY: 90,
            lineYs: [50, 60, 70, 80, 90],
          ),
        ],
        barlines: [DetectedBarline(x: 128, staffId: 'staff-1')],
        symbols: [
          DetectedSymbol(
            id: 'symbol-1',
            type: 'noteheadBlack',
            x: 140,
            y: 68,
            width: 11,
            height: 9,
            confidence: 0.93,
          ),
        ],
      );

      final viewModel = ScanViewModel(
        _FakeImagePreprocessor(preprocessed),
        _FakeSymbolDetector(detection),
      );

      final states = <ScanState>[];
      viewModel.addListener(() => states.add(viewModel.state));

      await viewModel.run(Uint8List.fromList(const [9, 8, 7]));

      expect(states, [ScanState.preprocessing, ScanState.detecting, ScanState.done]);
      expect(viewModel.state, ScanState.done);
      expect(viewModel.errorMessage, isNull);
      expect(viewModel.result, isNotNull);
      expect(viewModel.result!.detection, detection);
      expect(viewModel.result!.symbols.single.type, 'noteheadBlack');
      expect(viewModel.result!.detection.staffs.single.id, 'staff-1');
      expect(viewModel.result!.detection.barlines.single.x, 128);
    });

    test('moves to error state when preprocessing throws', () async {
      final viewModel = ScanViewModel(
        _ThrowingImagePreprocessor(),
        _FakeSymbolDetector(const DetectionResult()),
      );

      await viewModel.run(Uint8List.fromList(const [0]));

      expect(viewModel.state, ScanState.error);
      expect(viewModel.result, isNull);
      expect(viewModel.errorMessage, contains('preprocessing failed'));
    });

    test('reset clears result and error state', () async {
      final viewModel = ScanViewModel(
        _FakeImagePreprocessor(
          PreprocessedResult(
            bytes: Uint8List.fromList(const [1]),
            width: 1,
            height: 1,
            scale: 1,
            padX: 0,
            padY: 0,
          ),
        ),
        _FakeSymbolDetector(
          const DetectionResult(
            symbols: [DetectedSymbol(id: 'symbol-reset', type: 'stem', x: 1, y: 2)],
          ),
        ),
      );

      await viewModel.run(Uint8List.fromList(const [1]));
      viewModel.reset();

      expect(viewModel.state, ScanState.idle);
      expect(viewModel.result, isNull);
      expect(viewModel.errorMessage, isNull);
    });
  });
}