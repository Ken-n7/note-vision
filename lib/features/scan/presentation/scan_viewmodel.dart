import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:note_vision/features/preprocessing/domain/image_preprocessor.dart';
import 'package:note_vision/features/detection/domain/symbol_detector.dart';
import 'package:note_vision/features/mapping/domain/mapping_result.dart';
import 'package:note_vision/features/mapping/domain/score_mapper_service.dart';
import 'package:note_vision/features/cropping/data/basic_stave_aware_cropper.dart';
import 'package:note_vision/features/cropping/domain/stave_aware_cropper.dart';
import 'package:note_vision/features/detection/domain/detection_result.dart';
import 'package:note_vision/features/detection/domain/detected_symbol.dart';
import 'package:note_vision/features/resolution/data/basic_symbol_relation_resolver.dart';
import 'package:note_vision/features/resolution/domain/symbol_relation_resolver.dart';
import 'package:note_vision/features/scan/domain/scan_result.dart';
import 'package:note_vision/features/structure/data/tflite_structure_detector.dart';
import 'package:note_vision/features/structure/domain/structure_detector.dart';

enum ScanState {
  idle,
  preprocessing,
  detectingStructure,
  cropping,
  detecting,
  resolving,
  done,
  error,
}

class ScanViewModel extends ChangeNotifier {
  final ImagePreprocessor _preprocessor;
  final StructureDetector _structureDetector;
  final StaveAwareCropper _cropper;
  final SymbolDetector _detector;
  final SymbolRelationResolver _relationResolver;
  final ScoreMapperService? _mapper;

  ScanViewModel(
    this._preprocessor,
    this._detector, {
    StructureDetector? structureDetector,
    StaveAwareCropper? cropper,
    SymbolRelationResolver? relationResolver,
    ScoreMapperService? mapper,
  })  : _structureDetector = structureDetector ?? TfliteStructureDetector(),
        _cropper = cropper ?? const BasicStaveAwareCropper(),
        _relationResolver = relationResolver ?? const BasicSymbolRelationResolver(),
        _mapper = mapper;

  ScanState state = ScanState.idle;
  ScanResult? result;
  MappingResult? mappingResult;
  String? errorMessage;

  Future<void> run(Uint8List bytes) async {
    // Step 1 — preprocessing
    state = ScanState.preprocessing;
    errorMessage = null;
    notifyListeners();

    try {
      final structureInput = await _preprocessor.preprocess(
        bytes,
        targetSize: 1024,
      );

      state = ScanState.detectingStructure;
      notifyListeners();

      final structure = await _structureDetector.detect(structureInput);

      state = ScanState.cropping;
      notifyListeners();

      final crops = await _cropper.crop(structureInput, structure);

      // Step 2 — detection
      state = ScanState.detecting;
      notifyListeners();

      final allSymbols = <DetectedSymbol>[];
      for (final crop in crops) {
        final preprocessedCrop = await _preprocessor.preprocess(
          crop.imageBytes,
          targetSize: 416,
        );
        final cropDetection = await _detector.detect(preprocessedCrop);
        allSymbols.addAll(
          cropDetection.symbols.map((symbol) => symbol.toStaveCoordinates(crop)),
        );
      }

      state = ScanState.resolving;
      notifyListeners();

      final resolvedScore = await _relationResolver.resolve(allSymbols, structure);
      final detection = DetectionResult(symbols: resolvedScore.symbols);

      result = ScanResult(
        preprocessed: structureInput,
        detection: detection,
        structure: structure,
        resolvedScore: resolvedScore,
      );
      mappingResult = _mapper?.map(detection);
      state = ScanState.done;
    } catch (e) {
      errorMessage = e.toString();
      state = ScanState.error;
    }

    notifyListeners();
  }

  void reset() {
    result = null;
    mappingResult = null;
    state = ScanState.idle;
    errorMessage = null;
    notifyListeners();
  }
}
