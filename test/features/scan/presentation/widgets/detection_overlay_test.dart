import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:note_vision/features/detection/domain/detected_staff.dart';
import 'package:note_vision/features/detection/domain/detected_symbol.dart';
import 'package:note_vision/features/detection/domain/music_symbol.dart';
import 'package:note_vision/features/scan/presentation/widgets/detection_overlay.dart';

DetectedSymbol _symbol(
  MusicSymbol symbol, {
  Rect box = const Rect.fromLTWH(10, 40, 12, 8),
  Map<String, Object?>? metadata,
}) => DetectedSymbol.fromMusicSymbol(
      id: 's',
      symbol: symbol,
      boundingBox: box,
      metadata: metadata,
    );

void main() {
  group('overlayLabel', () {
    test('notes show their length as a number', () {
      for (final (type, label) in [
        ('whole', '1'),
        ('half', '2'),
        ('quarter', '4'),
        ('eighth', '8'),
        ('sixteenth', '16'),
      ]) {
        final note = _symbol(
          MusicSymbol.noteheadBlackInSpace,
          metadata: {'noteType': type},
        );
        expect(overlayLabel(note), label);
      }
    });

    test('rests, clefs, accidentals and time signatures are named', () {
      expect(overlayLabel(_symbol(MusicSymbol.rest8th)), '8');
      expect(overlayLabel(_symbol(MusicSymbol.clefF)), 'F');
      expect(overlayLabel(_symbol(MusicSymbol.accidentalNatural)), 'nat');
      expect(overlayLabel(_symbol(MusicSymbol.timeSigCutCommon)), 'cut');
    });

    test('a dot needs no text', () {
      expect(overlayLabel(_symbol(MusicSymbol.augmentationDot)), isEmpty);
      expect(
        SymbolKind.of(_symbol(MusicSymbol.augmentationDot)),
        SymbolKind.dot,
      );
    });
  });

  group('overlayBox', () {
    test('a note is outlined by the box the model drew, not its head', () {
      final note = _symbol(
        MusicSymbol.noteheadBlackInSpace,
        metadata: {
          'noteType': 'quarter',
          DetectedSymbol.fullBoxKey: [8.0, 2.0, 24.0, 50.0],
        },
      );
      expect(overlayBox(note), const Rect.fromLTRB(8, 2, 24, 50));
      expect(note.boundingBox, const Rect.fromLTWH(10, 40, 12, 8));
    });

    test('other symbols use their own box, also after a JSON round trip', () {
      final rest = _symbol(MusicSymbol.restHalf);
      expect(overlayBox(rest), rest.boundingBox);

      final note = DetectedSymbol.fromJson(
        _symbol(
          MusicSymbol.noteheadHalfInSpace,
          metadata: {
            'noteType': 'half',
            DetectedSymbol.fullBoxKey: [8, 2, 24, 50],
          },
        ).toJson().cast<String, dynamic>(),
      );
      expect(overlayBox(note), const Rect.fromLTRB(8, 2, 24, 50));
    });
  });

  testWidgets('overlay and legend draw without errors', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Column(
            children: [
              SizedBox(
                width: 300,
                height: 400,
                child: DetectionOverlay(
                  imageWidth: 904,
                  imageHeight: 1200,
                  staffs: const [
                    DetectedStaff(
                      id: 'traced-staff-0',
                      topY: 90,
                      bottomY: 150,
                      lineYs: [100, 110, 120, 130, 140],
                      offsetXs: [100, 800],
                      offsetYs: [0, -30],
                    ),
                  ],
                  symbols: [
                    _symbol(MusicSymbol.clefG, box: const Rect.fromLTWH(20, 70, 40, 100)),
                    _symbol(
                      MusicSymbol.noteheadBlackInSpace,
                      box: const Rect.fromLTWH(200, 128, 14, 10),
                      metadata: {
                        'noteType': 'eighth',
                        DetectedSymbol.fullBoxKey: [198.0, 80.0, 222.0, 140.0],
                      },
                    ),
                    _symbol(MusicSymbol.augmentationDot, box: const Rect.fromLTWH(0, 0, 6, 6)),
                  ],
                ),
              ),
              const DetectionLegend(),
            ],
          ),
        ),
      ),
    );

    expect(tester.takeException(), isNull);
    expect(find.text('Note'), findsOneWidget);
    expect(find.text('Staff'), findsOneWidget);
  });
}
