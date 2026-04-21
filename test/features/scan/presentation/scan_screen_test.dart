import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:note_vision/core/models/measure.dart';
import 'package:note_vision/core/models/part.dart';
import 'package:note_vision/core/models/score.dart';
import 'package:note_vision/features/detection/domain/detected_staff.dart';
import 'package:note_vision/features/detection/domain/detection_result.dart';
import 'package:note_vision/features/detection/domain/detected_symbol.dart';
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

class _FakeStaffLineDetector implements StaffLineDetector {
  @override
  List<DetectedStaff> detect(Uint8List pngBytes) => const [];
}

class _FakeSymbolDetector implements SymbolDetector {
  @override
  Future<DetectionResult> detect(
    PreprocessedResult input,
    List<DetectedStaff> staves,
  ) async {
    return const DetectionResult(
      imageId: 'scan-test',
      symbols: [
        DetectedSymbol(id: 's1', type: 'noteheadFilled', x: 1, y: 1),
      ],
    );
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
  final validImageBytes = Uint8List.fromList(const <int>[
    0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A,
    0x00, 0x00, 0x00, 0x0D, 0x49, 0x48, 0x44, 0x52,
    0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01,
    0x08, 0x06, 0x00, 0x00, 0x00, 0x1F, 0x15, 0xC4,
    0x89, 0x00, 0x00, 0x00, 0x0D, 0x49, 0x44, 0x41,
    0x54, 0x78, 0x9C, 0x63, 0xF8, 0xCF, 0xC0, 0x00,
    0x00, 0x03, 0x01, 0x01, 0x00, 0x18, 0xDD, 0x8D,
    0x18, 0x00, 0x00, 0x00, 0x00, 0x49, 0x45, 0x4E,
    0x44, 0xAE, 0x42, 0x60, 0x82,
  ]);

  testWidgets('continue opens editor shell route from scan screen', (tester) async {
    final vm = ScanViewModel(
      _FakeImagePreprocessor(),
      _FakeStaffLineDetector(),
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
                imageBytes: validImageBytes,
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
