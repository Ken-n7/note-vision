// Diagnostic replay of real sheet photos. No changes to model weights/cutoffs.
// NV_BAR_PICKED=1 consumes already picker-prepared JPEGs without re-encoding.
// Android's Bitmap resize (filter=false) + JPEG-82 differs from the optional
// Dart linear-resize approximation below. Use native-prepared images for a
// replay of the phone's preparation; model runtime outputs may still differ.
// Committed barline fixtures preserve the prepared inputs.
// NV_BAR_PHOTOS=<jpg directory> NV_BAR_WORK=<work> NV_BAR_PHASE=inputs
//   flutter test tool/barline_trace_test.dart
// Then run note-vision-data/scripts/run_raw.py assets/models/best.tflite <work>.
// NV_BAR_WORK=<work> NV_BAR_PHASE=eval flutter test tool/barline_trace_test.dart
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:note_vision/core/models/note.dart';
import 'package:note_vision/core/models/rest.dart';
import 'package:note_vision/features/detection/data/tflite_symbol_detector.dart';
import 'package:note_vision/features/mapping/domain/detection_to_score_mapper_service.dart';
import 'package:note_vision/features/preprocessing/data/basic_image_preprocessor.dart';
import 'package:note_vision/features/preprocessing/data/horizontal_projection_staff_detector.dart';

void main() {
  test('trace photo bar boundaries', timeout: Timeout.none, () async {
    final work = Platform.environment['NV_BAR_WORK'];
    if (work == null) return;
    if (Platform.environment['NV_BAR_PHASE'] == 'inputs') {
      final photos = Directory(Platform.environment['NV_BAR_PHOTOS']!);
      Directory('$work/inputs').createSync(recursive: true);
      Directory('$work/full').createSync(recursive: true);
      for (final file in photos.listSync().whereType<File>()) {
        final name = file.uri.pathSegments.last.split('.').first;
        final image = img.bakeOrientation(
          img.decodeImage(file.readAsBytesSync())!,
        );
        final scale = math.min(1, 1200 / math.max(image.width, image.height));
        final picked = Platform.environment['NV_BAR_PICKED'] == '1'
            ? file.readAsBytesSync()
            : img.encodeJpg(
                img.copyResize(
                  image,
                  width: (image.width * scale).round(),
                  height: (image.height * scale).round(),
                  interpolation: img.Interpolation.linear,
                ),
                quality: 82,
              );
        final pre = await BasicImagePreprocessor().preprocess(picked);
        File('$work/full/$name.png').writeAsBytesSync(pre.bytes);
        final full = img.decodeImage(pre.bytes)!;
        File('$work/inputs/$name.png').writeAsBytesSync(
          img.encodePng(img.grayscale(TfliteSymbolDetector.modelInput(full))),
        );
      }
      return;
    }
    final output = '$work/${Platform.environment['NV_BAR_RESULT'] ?? 'before'}';
    Directory(output).createSync(recursive: true);
    final results = <Map<String, Object?>>[];
    for (final file in Directory('$work/full').listSync().whereType<File>()) {
      final name = file.uri.pathSegments.last.split('.').first;
      final full = img.decodeImage(file.readAsBytesSync())!;
      final projected = const HorizontalProjectionStaffDetector().detect(
        file.readAsBytesSync(),
      );
      final raw = File(
        '$work/raw/$name.bin',
      ).readAsBytesSync().buffer.asFloat32List();
      final detection = TfliteSymbolDetector().detectFromOutput(
        full,
        projected,
        raw,
      );
      final pipeline = const DetectionToScoreMapperService().mapWithPipeline(
        detection,
      );
      File(
        '$output/$name.detection.json',
      ).writeAsStringSync(jsonEncode(detection.toJson()));
      File(
        '$output/$name.score.json',
      ).writeAsStringSync(jsonEncode(pipeline.result.score.toJson()));
      final rows = [
        for (final (p, staff) in detection.staffs.indexed)
          {
            'staff': p + 1,
            'id': staff.id,
            'barlines': detection.barlines
                .where((b) => b.staffId == staff.id)
                .map((b) => b.x)
                .toList(),
            'notes': pipeline.result.score.parts[p].measures
                .map((m) => m.symbols.whereType<Note>().length)
                .toList(),
            'rests': pipeline.result.score.parts[p].measures
                .map((m) => m.symbols.whereType<Rest>().length)
                .toList(),
            'heads': [
              for (final a in pipeline.assignments.where(
                (a) =>
                    a.staff.id == staff.id &&
                    a.symbol.musicSymbol?.isNote == true,
              ))
                {
                  'id': a.symbol.id,
                  'x': a.symbolCenterX,
                  'box': a.symbol.metadata?['fullBox'],
                  'type': a.symbol.metadata?['noteType'],
                },
            ],
          },
      ];
      results.add({
        'photo': name,
        'rows': rows,
        'warnings': pipeline.result.warnings,
      });
      // ignore: avoid_print
      print(
        '$name: ${rows.map((r) => 'row ${r['staff']}: ${r['barlines']} -> ${r['notes']}').join('; ')}',
      );
    }
    File(
      '$output/report.json',
    ).writeAsStringSync(const JsonEncoder.withIndent('  ').convert(results));
  });
}
