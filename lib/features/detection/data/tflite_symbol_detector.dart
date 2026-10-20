import 'dart:typed_data';

import 'package:flutter/foundation.dart' show listEquals;
import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;
import 'package:tflite_flutter/tflite_flutter.dart';

import '../../preprocessing/data/barline_finder.dart';
import '../../preprocessing/data/staff_line_tracer.dart';
import '../../preprocessing/domain/preprocessed_result.dart';
import '../domain/detected_staff.dart';
import '../domain/detected_symbol.dart';
import '../domain/detection_result.dart';
import '../domain/music_symbol.dart';
import '../domain/symbol_detector.dart';

class TfliteSymbolDetector implements SymbolDetector {
  static const String _modelPath = 'assets/models/best.tflite';
  static const String _modelVersion = 'B9 v2 A';

  /// Model output class index → (pipeline symbol, note value).
  /// Order must match the training data.yaml `names` list.
  /// Whole-note symbols (notehead + stem + flag in one box) are mapped onto
  /// the existing notehead vocabulary; the note value rides along in
  /// metadata['noteType'] since there are no separate stem/flag detections.
  static const List<(MusicSymbol, String?)> _classes = [
    (MusicSymbol.clefF, null), // Fclef
    (MusicSymbol.clefG, null), // Gclef
    (MusicSymbol.noteheadBlackInSpace, 'eighth'), // eighthnote
    (MusicSymbol.noteheadHalfInSpace, 'half'), // halfnote
    (MusicSymbol.restHalf, null), // halfrest
    (MusicSymbol.noteheadBlackInSpace, 'quarter'), // quarternote
    (MusicSymbol.noteheadBlackInSpace, 'sixteenth'), // sixteenthnote
    (MusicSymbol.noteheadWholeInSpace, 'whole'), // wholenote
    (MusicSymbol.restWhole, null), // wholerest
    (MusicSymbol.beam, null), // beam
    (MusicSymbol.accidentalSharp, null), // sharp
    (MusicSymbol.accidentalFlat, null), // flat
    (MusicSymbol.accidentalNatural, null), // natural
    (MusicSymbol.restQuarter, null), // quarterrest
    (MusicSymbol.rest8th, null), // eighthrest
    (MusicSymbol.rest16th, null), // sixteenthrest
    (MusicSymbol.timeSig2, null), // timeSig2
    (MusicSymbol.timeSig3, null), // timeSig3
    (MusicSymbol.timeSig4, null), // timeSig4
    (MusicSymbol.timeSig6, null), // timeSig6
    (MusicSymbol.timeSig8, null), // timeSig8
    (MusicSymbol.timeSigCommon, null), // timeSigCommon
    (MusicSymbol.timeSigCutCommon, null), // timeSigCutCommon
    (MusicSymbol.augmentationDot, null), // augmentationDot
  ];

  // Retain the existing cutoffs for B9 v2. New per-class cutoffs must be
  // calibrated on validation pages with the app's postprocessing.
  static const double _defaultThreshold = 0.40;
  static const Map<MusicSymbol, double> _confidenceThresholds = {
    MusicSymbol.restHalf: 0.30,
    MusicSymbol.restWhole: 0.30,
  };

  static const double _iouThreshold = 0.35;
  static const int _inputSize = 960;
  static const int _anchors = 18900;
  static const int _outputRows = 28; // 4 box + 24 classes

  // Two stacked beams of a sixteenth group overlap far more than two
  // detections of different symbols do, so beams get a looser NMS.
  static const double _beamIouThreshold = 0.7;

  Interpreter? _interpreter;

  Future<void> init() async {
    if (_interpreter != null) return;
    final options = InterpreterOptions()..threads = 4;
    final interpreter = await Interpreter.fromAsset(
      _modelPath,
      options: options,
    );
    try {
      final inputs = interpreter.getInputTensors();
      final outputs = interpreter.getOutputTensors();
      if (inputs.length != 1 || outputs.length != 1) {
        throw StateError('$_modelVersion requires one input and one output.');
      }
      final input = inputs.single;
      final output = outputs.single;
      if (!listEquals(input.shape, const [1, 3, _inputSize, _inputSize]) ||
          !listEquals(output.shape, const [1, _outputRows, _anchors]) ||
          input.type != TensorType.float32 ||
          output.type != TensorType.float32) {
        throw StateError(
          'Incompatible symbol model: ${input.shape} ${input.type} -> '
          '${output.shape} ${output.type}. Expected FP32 '
          '[1, 3, $_inputSize, $_inputSize] -> [1, $_outputRows, $_anchors].',
        );
      }
      debugPrint(
        'Symbol model: $_modelVersion | ${input.shape} -> ${output.shape} FP32',
      );
      _interpreter = interpreter;
    } catch (_) {
      interpreter.close();
      rethrow;
    }
  }

  void dispose() {
    _interpreter?.close();
    _interpreter = null;
  }

  @override
  Future<DetectionResult> detect(
    PreprocessedResult input,
    List<DetectedStaff> staves,
  ) async {
    if (_interpreter == null) await init();

    final img.Image? fullImage = img.decodeImage(input.bytes);
    if (fullImage == null) {
      throw Exception(
        'Could not decode preprocessed image. The scan input may be corrupted.',
      );
    }

    // Stretch to 960×960 — the training images were stretched (Roboflow
    // "Resize: Stretch"), so letterboxing would skew the input distribution.
    final resized = img.copyResize(
      fullImage,
      width: _inputSize,
      height: _inputSize,
      interpolation: img.Interpolation.linear,
    );

    final nmsMusical = _nms(
      _parseOutput(
        _runInference(resized),
        image: fullImage,
        scaleX: fullImage.width / _inputSize,
        scaleY: fullImage.height / _inputSize,
      ),
    );

    // The model has no staff class. Each clef first looks for the real lines
    // it sits on, which follow a sloped or hand-ruled staff; failing that it
    // gets a level staff sized from the clef. The projector's staves only
    // fill in where there is no clef: on handwriting it often groups the
    // wrong rows.
    final tracedStaves = _tracedStaves(nmsMusical, fullImage);
    final clefStaves = _addClefStaves(nmsMusical, tracedStaves);
    final middleX = fullImage.width / 2;
    final projectedStaves = [
      for (final staff in staves)
        if (!clefStaves.any(
          (c) => c.containsY((staff.topY + staff.bottomY) / 2, x: middleX),
        ))
          staff,
    ];
    final afterClefStaves = [...clefStaves, ...projectedStaves]
      ..sort((a, b) => a.topY.compareTo(b.topY));
    final allStaves = _addClusterStaves(nmsMusical, afterClefStaves);
    final symbols = _filterOutsideStaves(nmsMusical, allStaves);

    debugPrint(
      '[TfliteSymbolDetector] ${fullImage.width}×${fullImage.height} → '
      '$_inputSize×$_inputSize | '
      '${allStaves.length} stave(s) '
      '(${tracedStaves.length} traced, '
      '${clefStaves.length - tracedStaves.length} clef-synthesized, '
      '${projectedStaves.length} projected, '
      '${allStaves.length - afterClefStaves.length} cluster-synthesized) | '
      '${symbols.length} musical symbol(s)',
    );

    return DetectionResult(
      symbols: symbols,
      staffs: allStaves,
      barlines: const BarlineFinder().find(fullImage, allStaves, symbols),
    );
  }

  /// Runs the model and returns its raw output, row-major `[28][18900]`:
  /// rows 0–3 = cx, cy, w, h (normalized 0–1), rows 4–27 = class scores.
  Float32List _runInference(img.Image resized) {
    final input = _imageToTensor(resized);
    final output = Uint8List(_outputRows * _anchors * 4);
    _interpreter!.run(input.buffer.asUint8List(), output);
    return output.buffer.asFloat32List();
  }

  /// Builds the channels-first `[1, 3, 960, 960]` float input the LiteRT
  /// export expects, pixels normalized to [0.0, 1.0].
  Float32List _imageToTensor(img.Image resized) {
    const plane = _inputSize * _inputSize;
    final data = Float32List(3 * plane);
    int i = 0;
    for (int y = 0; y < _inputSize; y++) {
      for (int x = 0; x < _inputSize; x++) {
        final pixel = resized.getPixel(x, y);
        data[i] = pixel.r / 255.0;
        data[plane + i] = pixel.g / 255.0;
        data[2 * plane + i] = pixel.b / 255.0;
        i++;
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

  // Proportions of written clefs, measured on the group's pages (a staff is
  // 4 spaces tall). They differ from engraved clefs, which are 7 and 3 spaces.
  //
  // G clef — 1.48 staves tall and centred on the staff, so the top staff line
  // sits ~0.96 spaces below the clef top.
  static const _gClefHeightInSpaces = 4 * StaffLineTracer.gClefHeightInStaves;
  static const _gClefSpacesAboveTopLine = _gClefHeightInSpaces / 2 - 2;

  // F clef — 0.85 staves tall, its middle 0.2 spaces below the staff's, so
  // the top staff line sits ~0.5 spaces above the clef top.
  static const _fClefHeightInSpaces = 4 * StaffLineTracer.fClefHeightInStaves;
  static const _fClefSpacesAboveTopLine =
      _fClefHeightInSpaces / 2 -
      StaffLineTracer.fClefMiddleBelowStaffMiddle -
      2;

  /// A staff for each clef that sits on five traceable lines.
  List<DetectedStaff> _tracedStaves(
    List<DetectedSymbol> symbols,
    img.Image image,
  ) {
    final clefs = symbols
        .where((s) => _clefSymbols.contains(s.musicSymbol))
        .toList();
    if (clefs.isEmpty) return const [];

    const tracer = StaffLineTracer();
    return tracer.stavesAtClefs(tracer.candidates(image), [
      for (final clef in clefs)
        if (clef.boundingBox case final box?)
          (isGClef: clef.musicSymbol == MusicSymbol.clefG, box: box),
    ]);
  }

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
        (s) => s.containsY(clefCenterY, x: box.center.dx),
      );
      if (covered) continue;

      final List<double> lineYs;

      if (clef.musicSymbol == MusicSymbol.clefG) {
        final lineSpacing =
            (box.height / _gClefHeightInSpaces).clamp(8.0, double.infinity);
        final topLineY = box.top + _gClefSpacesAboveTopLine * lineSpacing;
        lineYs = List.generate(5, (i) => topLineY + i * lineSpacing);
      } else {
        final lineSpacing =
            (box.height / _fClefHeightInSpaces).clamp(8.0, double.infinity);
        final topLineY = box.top + _fClefSpacesAboveTopLine * lineSpacing;
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

  /// Spaces beyond a staff's outer lines within which a symbol is kept.
  static const _keepSpaces = 2.5;

  List<DetectedSymbol> _filterOutsideStaves(
    List<DetectedSymbol> symbols,
    List<DetectedStaff> staves,
  ) {
    if (staves.isEmpty) return symbols;
    return symbols.where((s) {
      final box = s.boundingBox;
      if (box == null) return true;
      return staves.any((staff) {
        if (staff.lineYs.length < 2) {
          return staff.containsY(box.center.dy, x: box.center.dx);
        }
        // Up to two ledger lines above or below still belongs to the staff.
        final space =
            (staff.lineYs.last - staff.lineYs.first) / (staff.lineYs.length - 1);
        final level = box.center.dy - staff.offsetAt(box.center.dx);
        return level >= staff.lineYs.first - _keepSpaces * space &&
            level <= staff.lineYs.last + _keepSpaces * space;
      });
    }).toList();
  }

  /// Converts raw model output into [DetectedSymbol]s in original-image
  /// pixel space. Note boxes are shrunk to their notehead so pitch is read
  /// from the head, not the middle of the stem.
  List<DetectedSymbol> _parseOutput(
    Float32List raw, {
    required img.Image image,
    required double scaleX,
    required double scaleY,
  }) {
    final decoded = <(int, double, Rect)>[];

    for (int a = 0; a < _anchors; a++) {
      int classIndex = 0;
      double confidence = 0;
      for (int c = 0; c < _classes.length; c++) {
        final score = raw[(4 + c) * _anchors + a];
        if (score > confidence) {
          confidence = score;
          classIndex = c;
        }
      }

      if (confidence < confidenceThresholdFor(_classes[classIndex].$1)) continue;

      final cx = raw[a] * _inputSize * scaleX;
      final cy = raw[_anchors + a] * _inputSize * scaleY;
      final w = raw[2 * _anchors + a] * _inputSize * scaleX;
      final h = raw[3 * _anchors + a] * _inputSize * scaleY;
      if (w <= 0 || h <= 0) continue;

      decoded.add((
        classIndex,
        confidence,
        Rect.fromCenter(center: Offset(cx, cy), width: w, height: h),
      ));
    }

    // Beams only tell beamed notes apart; they are used up here and not
    // passed on to the mapper.
    final beams = _nms(
      [
        for (final (classIndex, confidence, box) in decoded)
          if (_classes[classIndex].$1 == MusicSymbol.beam)
            DetectedSymbol.fromMusicSymbol(
              id: 'beam',
              symbol: MusicSymbol.beam,
              boundingBox: box,
              confidence: confidence,
            ),
      ],
      iouThreshold: _beamIouThreshold,
    ).map((beam) => beam.boundingBox!).toList();

    final detections = <DetectedSymbol>[];

    for (var (classIndex, confidence, box) in decoded) {
      var (symbol, noteType) = _classes[classIndex];
      if (symbol == MusicSymbol.beam) continue;
      var beamed = false;
      if (noteType == 'quarter') {
        noteType = beamedNoteType(box, beams);
        beamed = noteType != 'quarter';
      }

      final fullBox = box;
      if (noteType != null && noteType != 'whole') {
        box = noteheadRect(image, box);
      }

      detections.add(
        DetectedSymbol.fromMusicSymbol(
          id: 'symbol-${detections.length}',
          symbol: symbol,
          boundingBox: box,
          confidence: confidence,
          metadata: noteType == null
              ? null
              : {
                  'noteType': noteType,
                  // The editor draws beamed notes with beams, not flags.
                  if (beamed) 'beamed': true,
                  // The scan result screen shows what the model boxed.
                  if (box != fullBox)
                    DetectedSymbol.fullBoxKey: [
                      fullBox.left,
                      fullBox.top,
                      fullBox.right,
                      fullBox.bottom,
                    ],
                },
        ),
      );
    }

    return detections;
  }

  /// How far past a note box's top and bottom a beam may sit and still count,
  /// as a fraction of the box height. Stems are often drawn short of the beam.
  static const double _beamReachRatio = 0.1;

  /// The model labels a beamed note as a quarter note (head + stem) plus
  /// separate beam boxes: one beam on the note makes it an eighth, two or
  /// more a sixteenth.
  // ponytail: box-overlap count, 94% right on MUSCIMA++ ground-truth boxes;
  // misses stems drawn well short of the beam. Match beams to the stem tip
  // if beamed rhythms come out wrong.
  @visibleForTesting
  static String beamedNoteType(Rect note, List<Rect> beams) {
    final reach = note.height * _beamReachRatio;
    final zone = Rect.fromLTRB(
      note.left,
      note.top - reach,
      note.right,
      note.bottom + reach,
    );
    return switch (beams.where(zone.overlaps).length) {
      0 => 'quarter',
      1 => 'eighth',
      _ => 'sixteenth',
    };
  }

  /// Fraction of a stemmed note's box height taken as the notehead band.
  static const double _noteheadBandRatio = 0.3;

  /// Height of the returned notehead box as a fraction of the note box. A
  /// stemmed note spans ~4 line spacings and a printed head is ~0.65 of one,
  /// which is what the staff-synthesis fallbacks assume.
  static const double _noteheadBoxRatio = 0.16;

  /// Returns the notehead of a stemmed note box, centred in whichever end
  /// band (top or bottom) has more ink. The head is a filled/ringed blob,
  /// the other end is only a thin stem tip plus flag.
  // ponytail: ink-density guess, ~95% right on the test set; misses some
  // wide flagged notes. Train a separate notehead class if pitch errors matter.
  @visibleForTesting
  static Rect noteheadRect(img.Image image, Rect box) {
    final band = box.height * _noteheadBandRatio;
    final top = Rect.fromLTRB(box.left, box.top, box.right, box.top + band);
    final bottom = Rect.fromLTRB(
      box.left,
      box.bottom - band,
      box.right,
      box.bottom,
    );
    final head =
        _meanLuminance(image, top) < _meanLuminance(image, bottom) ? top : bottom;
    return Rect.fromCenter(
      center: head.center,
      width: box.width,
      height: box.height * _noteheadBoxRatio,
    );
  }

  static double _meanLuminance(img.Image image, Rect r) {
    final x0 = r.left.floor().clamp(0, image.width - 1);
    final x1 = r.right.ceil().clamp(x0 + 1, image.width);
    final y0 = r.top.floor().clamp(0, image.height - 1);
    final y1 = r.bottom.ceil().clamp(y0 + 1, image.height);
    double sum = 0;
    for (int y = y0; y < y1; y++) {
      for (int x = x0; x < x1; x++) {
        sum += image.getPixel(x, y).luminance;
      }
    }
    return sum / ((x1 - x0) * (y1 - y0));
  }

  List<DetectedSymbol> _nms(
    List<DetectedSymbol> detections, {
    double iouThreshold = _iouThreshold,
  }) {
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

        if (_iou(detectionBox, keptBox) > iouThreshold) {
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
