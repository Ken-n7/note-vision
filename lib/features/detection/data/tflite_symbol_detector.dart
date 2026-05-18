import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;
import 'package:tflite_flutter/tflite_flutter.dart';

import '../../preprocessing/domain/preprocessed_result.dart';
import '../domain/detected_staff.dart';
import '../domain/detected_symbol.dart';
import '../domain/detection_result.dart';
import '../domain/music_symbol.dart';
import '../domain/symbol_detector.dart';

class TfliteSymbolDetector implements SymbolDetector {
  static const String _modelPath = 'assets/models/deepscores_int8.tflite';

  static const double _defaultThreshold = 0.75;
  static const Map<MusicSymbol, double> _confidenceThresholds = {
    MusicSymbol.accidentalFlat: 0.65,
    MusicSymbol.accidentalSharp: 0.65,
    MusicSymbol.accidentalNatural: 0.60,
    MusicSymbol.accidentalDoubleFlat: 0.60,
    MusicSymbol.accidentalDoubleSharp: 0.60,
    MusicSymbol.augmentationDot: 0.55,
    MusicSymbol.flag8thDown: 0.65,
    MusicSymbol.flag8thUp: 0.65,
    MusicSymbol.flag16thDown: 0.65,
    MusicSymbol.flag16thUp: 0.65,
    MusicSymbol.flag32ndDown: 0.65,
    MusicSymbol.flag32ndUp: 0.65,
    MusicSymbol.flag64thDown: 0.65,
    MusicSymbol.flag64thUp: 0.65,
    MusicSymbol.flag128thDown: 0.65,
    MusicSymbol.flag128thUp: 0.65,
    MusicSymbol.ledgerLine: 0.60,
    MusicSymbol.repeatDot: 0.60,
  };

  static const double _iouThreshold = 0.35;
  static const int _inputSize = 640;

  Interpreter? _interpreter;

  Future<void> init() async {
    final options = InterpreterOptions()..threads = 4;
    _interpreter = await Interpreter.fromAsset(_modelPath, options: options);

    final inputTensor = _interpreter!.getInputTensor(0);
    final outputTensor = _interpreter!.getOutputTensor(0);
    debugPrint('Input shape: ${inputTensor.shape}');
    debugPrint('Input type: ${inputTensor.type}');
    debugPrint('Output shape: ${outputTensor.shape}');
    debugPrint('Output type: ${outputTensor.type}');
  }

  void dispose() {
    _interpreter?.close();
  }

  @override
  Future<DetectionResult> detect(
    PreprocessedResult input,
    List<DetectedStaff> staves,
  ) async {
    if (_interpreter == null) await init();

    final img.Image fullImage = img.decodeImage(input.bytes)!;

    // Letterbox the image to 640×640: scale uniformly so the long edge fits,
    // then pad the short edge with gray (114) — matching standard Ultralytics
    // YOLOv8 training preprocessing. This avoids the aspect-ratio distortion
    // that stretch-to-square causes for small symbols like noteheads and flags.
    final lb = _letterbox(fullImage);

    final raw = _runInference(lb.image);
    final allDetections = _parseOutput(
      raw,
      scale: lb.scale,
      padLeft: lb.padLeft,
      padTop: lb.padTop,
    );

    // Partition detections by role before NMS to avoid cross-class suppression.
    // staff → staff geometry bboxes; everything else → musical symbols.
    final staffDetections = allDetections
        .where((s) => s.musicSymbol == MusicSymbol.staff)
        .toList();
    final musicalDetections = allDetections
        .where((s) => s.musicSymbol != MusicSymbol.staff)
        .toList();

    final mergedStaves = _mergeStaves(_nms(staffDetections), staves);
    final nmsMusical = _nms(musicalDetections);
    final afterClefStaves = _addClefStaves(nmsMusical, mergedStaves);
    final allStaves = _addClusterStaves(nmsMusical, afterClefStaves);
    final symbols = _filterOutsideStaves(nmsMusical, allStaves);

    debugPrint(
      '[TfliteSymbolDetector] ${fullImage.width}×${fullImage.height} → '
      '$_inputSize×$_inputSize | '
      '${staffDetections.length} staff → ${allStaves.length} stave(s) '
      '(${mergedStaves.length} detected, '
      '${afterClefStaves.length - mergedStaves.length} clef-synthesized, '
      '${allStaves.length - afterClefStaves.length} cluster-synthesized) | '
      '${symbols.length} musical symbol(s)',
    );

    return DetectionResult(symbols: symbols, staffs: allStaves);
  }

  /// Builds the final staff list by preferring model-detected [staff]
  /// bboxes and supplementing with [projectorStaves] from
  /// [HorizontalProjectionStaffDetector] wherever the model missed a staff.
  List<DetectedStaff> _mergeStaves(
    List<DetectedSymbol> staffSymbols,
    List<DetectedStaff> projectorStaves,
  ) {
    // Convert each staff bbox into a DetectedStaff. Assume the bbox spans
    // exactly from the top staff line to the bottom staff line, giving 4 equal
    // gaps between 5 lines.
    final modelStaves = <DetectedStaff>[];
    for (int i = 0; i < staffSymbols.length; i++) {
      final box = staffSymbols[i].boundingBox;
      if (box == null) continue;
      final spacing = box.height / 4;
      modelStaves.add(
        DetectedStaff(
          id: 'model-staff-$i',
          topY: box.top,
          bottomY: box.bottom,
          lineYs: List.generate(5, (l) => box.top + l * spacing),
        ),
      );
    }

    // Add projector staves whose midpoint isn't already covered by a model staff.
    final supplementary = <DetectedStaff>[];
    for (final proj in projectorStaves) {
      final midY = (proj.topY + proj.bottomY) / 2;
      final covered = modelStaves.any(
        (ms) => midY >= ms.topY && midY <= ms.bottomY,
      );
      if (!covered) supplementary.add(proj);
    }

    if (modelStaves.isEmpty && supplementary.isEmpty) {
      debugPrint(
        '[TfliteSymbolDetector] No staves from model or projector — '
        'mapper will attempt SyntheticStaffBuilder.',
      );
    } else {
      debugPrint(
        '[TfliteSymbolDetector] Staves: ${modelStaves.length} model, '
        '${supplementary.length} projector supplement.',
      );
    }

    final merged = [...modelStaves, ...supplementary]
      ..sort((a, b) => a.topY.compareTo(b.topY));
    return merged;
  }

  List<List<double>> _runInference(img.Image tile) {
    final inputData = _imageToTensor(tile);

    // Wrap in nested list so tflite_flutter maps it to [1, 640, 640, 3].
    final input = [
      List.generate(
        _inputSize,
        (y) => List.generate(
          _inputSize,
          (x) {
            final base = (y * _inputSize + x) * 3;
            return [inputData[base], inputData[base + 1], inputData[base + 2]];
          },
        ),
      ),
    ];

    final output = List.generate(
      300,
      (_) => List.filled(6, 0.0),
    ).reshape([1, 300, 6]);

    _interpreter!.run(input, output);

    return output[0] as List<List<double>>;
  }

  /// Builds the input tensor from a 640×640 RGB image.
  ///
  /// The Ultralytics INT8 TFLite export keeps float32 I/O (internal ops are
  /// quantized but the tensor interface remains float32). Pixels are normalized
  /// to [0.0, 1.0].
  Float32List _imageToTensor(img.Image tile) {
    final data = Float32List(_inputSize * _inputSize * 3);
    int idx = 0;
    for (int y = 0; y < _inputSize; y++) {
      for (int x = 0; x < _inputSize; x++) {
        final pixel = tile.getPixel(x, y);
        data[idx++] = pixel.r.toInt() / 255.0;
        data[idx++] = pixel.g.toInt() / 255.0;
        data[idx++] = pixel.b.toInt() / 255.0;
      }
    }
    return data;
  }

  static double confidenceThresholdFor(MusicSymbol? symbol) {
    if (symbol == null) {
      return _defaultThreshold;
    }
    return _confidenceThresholds[symbol] ?? _defaultThreshold;
  }

  static double confidenceThresholdForName(String symbolName) {
    for (final symbol in MusicSymbol.values) {
      if (symbol.name == symbolName) {
        return confidenceThresholdFor(symbol);
      }
    }
    return _defaultThreshold;
  }

  static const _clefSymbols = {
    MusicSymbol.clefG,
    MusicSymbol.clefF,
  };

  // Standard music engraving proportions (in inter-line spaces):
  //
  // G clef — tall glyph, extends ~2 spaces above line 5 (top staff line)
  // and ~1 space below line 1 (bottom staff line). Total bbox height ≈ 7
  // inter-line spaces. The top staff line is ~2 spaces below the clef top.
  static const _gClefHeightInSpaces = 7.0;
  static const _gClefSpacesAboveTopLine = 2.0;

  // F clef — compact glyph, roughly 3 inter-line spaces tall. The curl sits
  // near line 4 (second from top), which is ~0.5 spaces below the clef top.
  static const _fClefHeightInSpaces = 3.0;
  static const _fClefSpacesAboveLine4 = 0.5; // line 4 = index 1 from top

  /// Tier-3 staff recovery: any detected clef whose center Y falls outside
  /// every already-known staff is unambiguous evidence of a missed staff.
  /// Staff geometry is derived from the clef bbox using known engraving
  /// proportions per clef type — one clef is sufficient, no spacing check
  /// required.
  List<DetectedStaff> _addClefStaves(
    List<DetectedSymbol> symbols,
    List<DetectedStaff> detectedStaves,
  ) {
    final clefs = symbols
        .where((s) => _clefSymbols.contains(s.musicSymbol))
        .toList();

    if (clefs.isEmpty) return detectedStaves;

    final synthesized = <DetectedStaff>[];
    int synthIndex = detectedStaves.length;

    for (final clef in clefs) {
      final box = clef.boundingBox;
      if (box == null) continue;

      final clefCenterY = box.center.dy;

      final covered = detectedStaves.any(
        (s) => clefCenterY >= s.topY && clefCenterY <= s.bottomY,
      );
      if (covered) continue;

      final List<double> lineYs;

      if (clef.musicSymbol == MusicSymbol.clefG) {
        // lineSpacing derived from the known 7-space total height of the G clef.
        final lineSpacing =
            (box.height / _gClefHeightInSpaces).clamp(8.0, double.infinity);
        // Top staff line (line 5) sits ~2 spaces below the top of the bbox.
        final topLineY = box.top + _gClefSpacesAboveTopLine * lineSpacing;
        lineYs = List.generate(5, (i) => topLineY + i * lineSpacing);
      } else {
        // clefF: lineSpacing from the 3-space total height.
        final lineSpacing =
            (box.height / _fClefHeightInSpaces).clamp(8.0, double.infinity);
        // Line 4 (index 1 from top) sits ~0.5 spaces below the bbox top.
        final line4Y = box.top + _fClefSpacesAboveLine4 * lineSpacing;
        final topLineY = line4Y - lineSpacing; // line 5 = one space above line 4
        lineYs = List.generate(5, (i) => topLineY + i * lineSpacing);
      }

      synthesized.add(DetectedStaff(
        id: 'clef-staff-$synthIndex',
        topY: lineYs.first - (lineYs[1] - lineYs[0]),
        bottomY: lineYs.last + (lineYs[1] - lineYs[0]),
        lineYs: lineYs,
      ));
      synthIndex++;
    }

    if (synthesized.isNotEmpty) {
      debugPrint(
        '[TfliteSymbolDetector] +${synthesized.length} clef-synthesized staff(ves).',
      );
    }

    return ([...detectedStaves, ...synthesized]
      ..sort((a, b) => a.topY.compareTo(b.topY)));
  }

  static const _noteheadSymbols = {
    MusicSymbol.noteheadBlackInSpace,
    MusicSymbol.noteheadBlackOnLine,
    MusicSymbol.noteheadHalfInSpace,
    MusicSymbol.noteheadHalfOnLine,
    MusicSymbol.noteheadWholeInSpace,
    MusicSymbol.noteheadWholeOnLine,
    MusicSymbol.noteheadDoubleWholeInSpace,
    MusicSymbol.noteheadDoubleWholeOnLine,
  };

  // Standard music engraving proportion: notehead height / inter-line spacing.
  // Used by both clef and cluster synthesis to derive proportionally correct
  // staff geometry rather than relying on symbol spread.
  static const _noteheadHeightRatio = 0.65;

  /// Third-tier staff recovery: cluster noteheads by vertical proximity, then
  /// synthesize a [DetectedStaff] for any cluster that (a) isn't already
  /// covered by a detected staff and (b) sits at a multiple of the expected
  /// inter-staff spacing from a neighbouring detected staff.
  ///
  /// The spacing check confirms that the cluster is at a plausible staff
  /// position rather than stray symbols between staves. When only one staff
  /// has been detected the spacing is estimated from that staff's height;
  /// when none exist this method is a no-op (the mapper's [SyntheticStaffBuilder]
  /// handles the fully-blind case).
  List<DetectedStaff> _addClusterStaves(
    List<DetectedSymbol> symbols,
    List<DetectedStaff> detectedStaves,
  ) {
    if (detectedStaves.isEmpty) return detectedStaves;

    // Derive line spacing from median notehead height across the whole image.
    // This is more reliable than per-cluster spread because a melody may only
    // span 2–3 lines, making spread / 4 a systematic underestimate.
    final noteheadHeights = symbols
        .where((s) => _noteheadSymbols.contains(s.musicSymbol))
        .map((s) => s.boundingBox?.height ?? 0.0)
        .where((h) => h > 0)
        .toList()
      ..sort();

    final double lineSpacing;
    if (noteheadHeights.isNotEmpty) {
      final medianHeight = noteheadHeights[noteheadHeights.length ~/ 2];
      lineSpacing = (medianHeight / _noteheadHeightRatio).clamp(8.0, double.infinity);
    } else {
      lineSpacing = 20.0;
    }

    // Collect notehead center-Y values — the most stable geometry signal.
    final centerYs = symbols
        .where((s) => _noteheadSymbols.contains(s.musicSymbol))
        .map((s) {
          final box = s.boundingBox;
          return box != null ? box.center.dy : s.y + ((s.height ?? 0) / 2);
        })
        .toList()
      ..sort();

    if (centerYs.isEmpty) return detectedStaves;

    final sortedStaves = [...detectedStaves]
      ..sort((a, b) => a.topY.compareTo(b.topY));

    // Compute expected inter-staff spacing from detected staves.
    // With ≥2 staves use the median center-to-center gap; with exactly 1
    // stave use 1.5× its height as a rough estimate.
    final double expectedSpacing;
    if (sortedStaves.length >= 2) {
      final gaps = <double>[];
      for (int i = 1; i < sortedStaves.length; i++) {
        final cA = (sortedStaves[i - 1].topY + sortedStaves[i - 1].bottomY) / 2;
        final cB = (sortedStaves[i].topY + sortedStaves[i].bottomY) / 2;
        gaps.add(cB - cA);
      }
      gaps.sort();
      expectedSpacing = gaps[gaps.length ~/ 2];
    } else {
      final h = sortedStaves[0].bottomY - sortedStaves[0].topY;
      expectedSpacing = h * 1.5;
    }

    // Cluster noteheads by Y-gap. Use 60 % of expectedSpacing as the gap
    // threshold so noteheads from adjacent staves never merge into one cluster.
    final gapThreshold = (expectedSpacing * 0.6).clamp(40.0, 120.0);
    final clusters = <List<double>>[];
    var current = [centerYs.first];
    for (int i = 1; i < centerYs.length; i++) {
      if (centerYs[i] - current.last > gapThreshold) {
        clusters.add(current);
        current = [centerYs[i]];
      } else {
        current.add(centerYs[i]);
      }
    }
    clusters.add(current);

    final synthesized = <DetectedStaff>[];
    int synthIndex = detectedStaves.length;
    const spacingTolerance = 0.30; // allow ±30 % of expectedSpacing

    for (final cluster in clusters) {
      if (cluster.length < 3) continue;

      final clusterMedianY = cluster[cluster.length ~/ 2];

      // Skip if the cluster is already inside a detected staff.
      final covered = sortedStaves.any(
        (s) => clusterMedianY >= s.topY && clusterMedianY <= s.bottomY,
      );
      if (covered) continue;

      // Confirm the cluster sits at a whole-number multiple of expectedSpacing
      // from any detected staff. This rejects isolated stray symbols.
      final aligned = sortedStaves.any((s) {
        final staffCenter = (s.topY + s.bottomY) / 2;
        final distance = (clusterMedianY - staffCenter).abs();
        final n = (distance / expectedSpacing).round();
        if (n == 0) return false;
        return (distance - expectedSpacing * n).abs() <= expectedSpacing * spacingTolerance;
      });
      if (!aligned) continue;

      // Anchor 5 lines around the cluster median Y (treated as middle staff line).
      final lineYs = List.generate(5, (i) => clusterMedianY + (i - 2) * lineSpacing);

      synthesized.add(DetectedStaff(
        id: 'cluster-staff-$synthIndex',
        topY: lineYs.first - lineSpacing,
        bottomY: lineYs.last + lineSpacing,
        lineYs: lineYs,
      ));
      synthIndex++;
    }

    if (synthesized.isNotEmpty) {
      debugPrint(
        '[TfliteSymbolDetector] +${synthesized.length} cluster-synthesized staff(ves) '
        '(expectedSpacing=${expectedSpacing.toStringAsFixed(1)}px).',
      );
    }

    return ([...detectedStaves, ...synthesized]
      ..sort((a, b) => a.topY.compareTo(b.topY)));
  }

  List<DetectedSymbol> _filterOutsideStaves(
    List<DetectedSymbol> symbols,
    List<DetectedStaff> staves,
  ) {
    if (staves.isEmpty) return symbols;
    return symbols.where((s) {
      final box = s.boundingBox;
      if (box == null) return true;
      final centerY = box.center.dy;
      return staves.any((staff) => centerY >= staff.topY && centerY <= staff.bottomY);
    }).toList();
  }

  /// Scales [src] to fit within [_inputSize]×[_inputSize] preserving aspect
  /// ratio, then pads the shorter dimension with gray (114) on both sides —
  /// the standard Ultralytics YOLOv8 letterbox used during training.
  ({img.Image image, double scale, int padLeft, int padTop}) _letterbox(
    img.Image src,
  ) {
    final scale = src.width >= src.height
        ? _inputSize / src.width
        : _inputSize / src.height;

    final scaledW = (src.width * scale).round();
    final scaledH = (src.height * scale).round();
    final padLeft = (_inputSize - scaledW) ~/ 2;
    final padTop = (_inputSize - scaledH) ~/ 2;

    final resized = img.copyResize(
      src,
      width: scaledW,
      height: scaledH,
      interpolation: img.Interpolation.linear,
    );

    final canvas = img.Image(
      width: _inputSize,
      height: _inputSize,
      numChannels: 3,
    );

    // Fill with gray (114, 114, 114) — standard YOLO padding value.
    for (int y = 0; y < _inputSize; y++) {
      for (int x = 0; x < _inputSize; x++) {
        canvas.setPixelRgb(x, y, 114, 114, 114);
      }
    }

    // Stamp the resized image into the centre of the canvas.
    for (int y = 0; y < scaledH; y++) {
      for (int x = 0; x < scaledW; x++) {
        canvas.setPixel(x + padLeft, y + padTop, resized.getPixel(x, y));
      }
    }

    return (image: canvas, scale: scale, padLeft: padLeft, padTop: padTop);
  }

  /// Converts raw model output rows into [DetectedSymbol]s in original-image
  /// pixel space. Undoes the letterbox transform using [scale], [padLeft],
  /// and [padTop] so all coordinates are in the pre-letterbox image space.
  List<DetectedSymbol> _parseOutput(
    List<List<double>> rawOutput, {
    required double scale,
    required int padLeft,
    required int padTop,
  }) {
    final detections = <DetectedSymbol>[];
    int counter = 0;

    for (final detection in rawOutput) {
      final classIndex = detection[5].toInt();
      if (classIndex < 0 || classIndex >= MusicSymbol.values.length) continue;

      final symbol = MusicSymbol.values[classIndex];
      final confidence = detection[4];
      if (confidence < confidenceThresholdFor(symbol)) continue;

      // Ultralytics YOLO TFLite NMS output: normalized 0–1 coords relative to
      // the 640×640 letterboxed input. Undo padding then undo the uniform scale
      // to recover coordinates in the original full-resolution image space.
      final x1 = (detection[0] * _inputSize - padLeft) / scale;
      final y1 = (detection[1] * _inputSize - padTop) / scale;
      final x2 = (detection[2] * _inputSize - padLeft) / scale;
      final y2 = (detection[3] * _inputSize - padTop) / scale;

      if (x2 <= x1 || y2 <= y1) continue;

      detections.add(
        DetectedSymbol.fromMusicSymbol(
          id: 'symbol-$counter',
          symbol: symbol,
          boundingBox: Rect.fromLTRB(x1, y1, x2, y2),
          confidence: confidence,
        ),
      );
      counter++;
    }

    return detections;
  }

  List<DetectedSymbol> _nms(List<DetectedSymbol> detections) {
    if (detections.isEmpty) return detections;

    detections.sort((a, b) => (b.confidence ?? 0).compareTo(a.confidence ?? 0));

    final kept = <DetectedSymbol>[];

    for (final detection in detections) {
      final detectionBox = detection.boundingBox;
      if (detectionBox == null) {
        kept.add(detection);
        continue;
      }

      bool suppressed = false;
      for (final keptDetection in kept) {
        final keptBox = keptDetection.boundingBox;
        if (keptBox == null) continue;

        if (_iou(detectionBox, keptBox) > _iouThreshold) {
          suppressed = true;
          break;
        }
      }
      if (!suppressed) kept.add(detection);
    }

    return kept;
  }

  double _iou(Rect a, Rect b) {
    final intersection = a.intersect(b);
    if (intersection.isEmpty) return 0.0;
    final intersectionArea = intersection.width * intersection.height;
    final unionArea =
        (a.width * a.height) + (b.width * b.height) - intersectionArea;
    return intersectionArea / unionArea;
  }
}
