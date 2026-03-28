import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:note_vision/core/models/measure.dart';
import 'package:note_vision/core/models/part.dart';
import 'package:note_vision/core/models/score.dart';
import 'package:note_vision/features/detection/domain/detection_result.dart';
import 'package:note_vision/features/detection/domain/symbol_detector.dart';
import 'package:note_vision/features/editor/presentation/editor_shell_screen.dart';
import 'package:note_vision/features/mapping/domain/mapping_result.dart';
import 'package:note_vision/features/mapping/domain/score_mapper_service.dart';
import 'package:note_vision/features/preprocessing/domain/image_preprocessor.dart';
import 'package:note_vision/features/preprocessing/domain/preprocessed_result.dart';
import 'package:note_vision/features/scan/presentation/scan_screen.dart';
import 'package:note_vision/features/scan/presentation/scan_viewmodel.dart';
import 'package:provider/provider.dart';

class _FakeImagePreprocessor implements ImagePreprocessor {
  @override
  Future<PreprocessedResult> preprocess(Uint8List bytes) async {
    return PreprocessedResult(
      bytes: bytes,
      width: 8,
      height: 8,
      scale: 1,
      padX: 0,
      padY: 0,
    );
  }
}

class _FakeSymbolDetector implements SymbolDetector {
  @override
  Future<DetectionResult> detect(PreprocessedResult input) async {
    return const DetectionResult(imageId: 'scan-test');
  }
}

class _FakeScoreMapperService extends ScoreMapperService {
  const _FakeScoreMapperService();

  @override
  MappingResult map(DetectionResult detection) {
    return const MappingResult(
      score: Score(
        id: 'mapped-score',
        title: 'Mapped Score',
        composer: 'Mapper',
        parts: [
          Part(
            id: 'P1',
            name: 'Part 1',
            measures: [Measure(number: 1, symbols: [])],
          ),
        ],
      ),
    );
  }
}

void main() {
  testWidgets('continue opens editor shell route from scan screen', (tester) async {
    final vm = ScanViewModel(
      _FakeImagePreprocessor(),
      _FakeSymbolDetector(),
      mapper: const _FakeScoreMapperService(),
    );

    await tester.pumpWidget(
      ChangeNotifierProvider<ScanViewModel>.value(
        value: vm,
        child: MaterialApp(
          onGenerateRoute: (settings) {
            if (settings.name == EditorShellScreen.routeName) {
              return MaterialPageRoute<void>(
                builder: (_) => const Scaffold(body: Text('Editor Opened')),
              );
            }
            return MaterialPageRoute<void>(
              builder: (_) => ScanScreen(
                imageBytes: Uint8List.fromList(const [1, 2, 3]),
              ),
            );
          },
        ),
      ),
    );

    await tester.pump();
    await tester.pump();
    await tester.pumpAndSettle();

    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();

    expect(find.text('Editor Opened'), findsOneWidget);
  });
}
