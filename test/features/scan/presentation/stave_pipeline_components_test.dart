import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:note_vision/features/cropping/data/basic_stave_aware_cropper.dart';
import 'package:note_vision/features/cropping/domain/stave_crop.dart';
import 'package:note_vision/features/detection/domain/detected_symbol.dart';
import 'package:note_vision/features/preprocessing/domain/preprocessed_result.dart';
import 'package:note_vision/features/resolution/data/basic_symbol_relation_resolver.dart';
import 'package:note_vision/features/structure/domain/score_structure.dart';

void main() {
  test('toStaveCoordinates remaps symbol coordinates and tags metadata', () {
    const symbol = DetectedSymbol(
      id: 's1',
      type: 'noteheadBlack',
      x: 10,
      y: 20,
      width: 6,
      height: 6,
      confidence: 0.9,
    );

    final crop = StaveCrop(
      imageBytes: Uint8List(0),
      staveIndex: 2,
      instrumentGroup: 'piano',
      offsetX: 100,
      offsetY: 200,
      scale: 1,
      isBracePair: true,
    );

    final remapped = symbol.toStaveCoordinates(crop);

    expect(remapped.x, 110);
    expect(remapped.y, 220);
    expect(remapped.metadata?['staveIndex'], 2);
    expect(remapped.metadata?['instrumentGroup'], 'piano');
    expect(remapped.metadata?['isBracePair'], isTrue);
  });

  test('basic cropper emits one crop per system with offsets', () async {
    final preprocessed = PreprocessedResult(
      bytes: Uint8List.fromList(const [1, 2]),
      width: 1024,
      height: 1024,
      scale: 1,
      padX: 0,
      padY: 0,
    );

    final structure = ScoreStructure(
      systems: const [
        StaveSystem(bounds: Rect.fromLTWH(0, 50, 1024, 180)),
        StaveSystem(bounds: Rect.fromLTWH(0, 280, 1024, 180)),
      ],
      groups: const [
        InstrumentGroup(bounds: Rect.fromLTWH(0, 0, 1024, 260), type: 'piano'),
      ],
    );

    final crops = await const BasicStaveAwareCropper().crop(preprocessed, structure);

    expect(crops.length, 2);
    expect(crops.first.offsetY, 50);
    expect(crops.first.instrumentGroup, 'piano');
    expect(crops.last.instrumentGroup, isNull);
  });

  test('resolver returns note entries for note symbols', () async {
    const resolver = BasicSymbolRelationResolver();
    const symbols = [
      DetectedSymbol(id: 'n1', type: 'noteheadBlack', x: 10, y: 20, width: 6, height: 6),
      DetectedSymbol(id: 'r1', type: 'restQuarter', x: 10, y: 80, width: 6, height: 6),
    ];

    const structure = ScoreStructure(staveLines: [20, 30, 40, 50, 60]);

    final resolved = await resolver.resolve(symbols, structure);

    expect(resolved.symbols.length, 2);
    expect(resolved.notes.length, 1);
    expect(resolved.notes.single.pitch, isNotEmpty);
  });
}
