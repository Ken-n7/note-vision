// Trace the dense photo's written sharps through actual app reconstruction.
// flutter test --no-pub tool/key_signature_trace_test.dart
// Optionally replay frozen raw inference through the production decoder:
// NV_KEY_WORK=<root with full/dense.png and raw/dense.bin>
// NV_KEY_REPORT=<output.json> flutter test --no-pub tool/key_signature_trace_test.dart
// NV_KEY_LABELS=<B9 24-class YOLO labels for this page> also checks annotations.
// This is a known-photo diagnostic, not an unseen-model accuracy benchmark.
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:note_vision/features/detection/data/tflite_symbol_detector.dart';
import 'package:note_vision/features/detection/domain/detected_symbol.dart';
import 'package:note_vision/features/detection/domain/detection_result.dart';
import 'package:note_vision/features/mapping/domain/detection_to_score_mapper_service.dart';
import 'package:note_vision/features/mapping/domain/internal/signature_inferrer.dart';
import 'package:note_vision/features/preprocessing/data/horizontal_projection_staff_detector.dart';

void main() {
  test('trace written sharp glyphs without changing detector policy', () {
    const fixtures = 'test/fixtures/barlines';
    final labels =
        jsonDecode(File('$fixtures/key_sharp_centers.json').readAsStringSync())
            as Map<String, dynamic>;
    final rows = (labels['rows'] as List).map((row) {
      return (row as List).map((p) {
        return Offset((p[0] as num).toDouble(), (p[1] as num).toDouble());
      }).toList();
    }).toList();
    final centers = rows.expand((r) => r).toList();
    final size = labels['imageSize'] as List;
    final width = (size[0] as num).toDouble();
    final height = (size[1] as num).toDouble();

    // Exclusive nearest-label matching prevents a loose box being counted
    // against both close upper sharps on row nine. These tolerances are only
    // diagnostic correspondence rules, never production detection cutoffs.
    int labelAt(Offset point) {
      var best = -1, distance = double.infinity;
      for (var i = 0; i < centers.length; i++) {
        final delta = point - centers[i];
        if (delta.dx.abs() > 11 || delta.dy.abs() > 14) continue;
        final d = delta.distanceSquared;
        if (d < distance) {
          best = i;
          distance = d;
        }
      }
      return best;
    }

    Float32List? raw;
    final work = Platform.environment['NV_KEY_WORK'];
    final DetectionResult detection;
    if (work == null) {
      detection = DetectionResult.fromJson(
        jsonDecode(File('$fixtures/dense.detection.json').readAsStringSync()),
      );
    } else {
      final bytes = File('$work/full/dense.png').readAsBytesSync();
      final image = img.decodePng(bytes)!;
      expect([image.width, image.height], size);
      raw = File(
        '$work/raw/dense.bin',
      ).readAsBytesSync().buffer.asFloat32List();
      expect(raw.length, 28 * 18900);
      detection = TfliteSymbolDetector().detectFromOutput(
        image,
        const HorizontalProjectionStaffDetector().detect(bytes),
        raw,
      );
    }
    final before = jsonEncode(detection.toJson());
    const mapper = DetectionToScoreMapperService();
    final pipeline = mapper.mapWithPipeline(detection);
    final score = pipeline.result.score;
    const signatures = SignatureInferrer();
    final leading = [
      for (final staff in detection.staffs)
        signatures.collectLeadingSignatureSymbols(
          pipeline.measures.firstWhere((m) => m.staff.id == staff.id).symbols,
        ),
    ];
    expect(leading, hasLength(rows.length));

    final perGlyph = <Map<String, Object?>>[];
    final annotationPath = Platform.environment['NV_KEY_LABELS'];
    final annotationMatches = List.filled(centers.length, 0);
    var annotatedSharps = 0;
    if (annotationPath != null) {
      for (final line in File(annotationPath).readAsLinesSync()) {
        if (line.trim().isEmpty) continue;
        final fields = line
            .trim()
            .split(RegExp(r'\s+'))
            .map(double.parse)
            .toList();
        expect(fields, hasLength(5));
        if (fields[0] != 10) continue;
        annotatedSharps++;
        final label = labelAt(Offset(fields[1] * width, fields[2] * height));
        if (label >= 0) annotationMatches[label]++;
      }
      expect(
        annotationMatches,
        everyElement(1),
        reason: 'Each written key sharp must already have a sharp annotation',
      );
    }
    for (var i = 0; i < centers.length; i++) {
      final retained = detection.symbols
          .where(
            (s) => s.boundingBox != null && labelAt(s.boundingBox!.center) == i,
          )
          .toList();
      final leadingSharps = leading[i ~/ 3]
          .where(
            (s) =>
                s.symbol.type == 'accidentalSharp' &&
                s.symbol.boundingBox != null &&
                labelAt(s.symbol.boundingBox!.center) == i,
          )
          .map((s) => s.symbol.id)
          .toList();
      Map<String, Object?>? candidate;
      if (raw != null) {
        var bestSharp = -1, strongest = -1;
        var sharpScore = -1.0, strongestScore = -1.0;
        var winningClass = -1, passingSharpAnchors = 0;
        for (var a = 0; a < 18900; a++) {
          final w = raw[2 * 18900 + a] * width;
          final h = raw[3 * 18900 + a] * height;
          if (w < 10 ||
              w > 45 ||
              h < 15 ||
              h > 65 ||
              labelAt(Offset(raw[a] * width, raw[18900 + a] * height)) != i) {
            continue;
          }
          // Frozen B9 v2 A contract: 4 box rows, 24 scores, class 10=sharp.
          final sharp = raw[14 * 18900 + a];
          var winner = 0, confidence = 0.0;
          for (var c = 0; c < 24; c++) {
            final value = raw[(4 + c) * 18900 + a];
            if (value > confidence) {
              winner = c;
              confidence = value;
            }
          }
          if (sharp > sharpScore) {
            sharpScore = sharp;
            bestSharp = a;
          }
          if (confidence > strongestScore) {
            strongestScore = confidence;
            strongest = a;
            winningClass = winner;
          }
          if (winner == 10 &&
              confidence >=
                  TfliteSymbolDetector.confidenceThresholdForName(
                    'accidentalSharp',
                  )) {
            passingSharpAnchors++;
          }
        }
        candidate = {
          'bestSharpAnchor': bestSharp,
          'bestSharpScore': bestSharp < 0 ? null : sharpScore,
          'strongestAnchor': strongest,
          'strongestClass': winningClass,
          'strongestScore': strongest < 0 ? null : strongestScore,
          'passingSharpAnchors': passingSharpAnchors,
        };
      }
      perGlyph.add({
        'row': i ~/ 3 + 1,
        'glyph': i % 3 + 1,
        'center': [centers[i].dx, centers[i].dy],
        'retained': retained
            .map(
              (s) => {'id': s.id, 'type': s.type, 'confidence': s.confidence},
            )
            .toList(),
        'leadingSharpIds': leadingSharps,
        'rawCandidate': ?candidate,
      });
    }

    // Counterfactual only: substitute all 27 manually labelled sharp glyphs.
    // Do not feed these additions back to the detector or write any fixture.
    bool isLabelledGlyph(DetectedSymbol s) =>
        {'accidentalSharp', 'accidentalNatural', 'timeSig4'}.contains(s.type) &&
        s.boundingBox != null &&
        labelAt(s.boundingBox!.center) >= 0;
    final oracle = DetectionResult.fromJson({
      ...detection.toJson(),
      'symbols': [
        for (final s in detection.symbols)
          if (!isLabelledGlyph(s)) s.toJson(),
        for (var i = 0; i < centers.length; i++)
          DetectedSymbol(
            id: 'labelled-sharp-$i',
            type: 'accidentalSharp',
            x: centers[i].dx - 10,
            y: centers[i].dy - 15,
            width: 20,
            height: 30,
          ).toJson(),
      ],
    });
    final corrected = mapper.map(oracle).score;
    expect(
      corrected.parts.map((p) => p.measures.first.keySignature?.fifths),
      List.filled(9, 3),
    );
    expect(
      [
        for (final p in corrected.parts)
          for (final m in p.measures) m.symbols.map((s) => s.toJson()).toList(),
      ],
      [
        for (final p in score.parts)
          for (final m in p.measures) m.symbols.map((s) => s.toJson()).toList(),
      ],
    );
    expect(jsonEncode(detection.toJson()), before);
    final report = {
      'input': work ?? '$fixtures/dense.detection.json',
      'scope':
          'Known-photo glyph diagnostic; no full transcription or model benchmark',
      'writtenSharpsPerRow': rows.map((r) => r.length).toList(),
      'leadingSharpsPerRow': leading
          .map((r) => r.where((s) => s.symbol.type == 'accidentalSharp').length)
          .toList(),
      'mappedFifths': score.parts
          .map((p) => p.measures.first.keySignature?.fifths)
          .toList(),
      'labelledDetectionFifths': corrected.parts
          .map((p) => p.measures.first.keySignature?.fifths)
          .toList(),
      'notesAndRestsPreserved': true,
      if (annotationPath != null)
        'annotations': {
          'path': annotationPath,
          'totalSharpLabels': annotatedSharps,
          'matchesPerKeyGlyph': annotationMatches,
        },
      'glyphs': perGlyph,
    };
    final output = const JsonEncoder.withIndent('  ').convert(report);
    final destination = Platform.environment['NV_KEY_REPORT'];
    if (destination != null) File(destination).writeAsStringSync(output);
    // ignore: avoid_print
    print(output);
  });
}
