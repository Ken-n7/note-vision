import 'dart:ui' show Rect;

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:note_vision/features/detection/domain/detected_staff.dart';
import 'package:note_vision/features/detection/domain/detected_symbol.dart';
import 'package:note_vision/features/detection/domain/music_symbol.dart';
import 'package:note_vision/features/preprocessing/data/barline_finder.dart';

const _lines = [100.0, 112.0, 124.0, 136.0, 148.0];

/// A grey page with one staff (lines 12 px apart) and dark vertical strokes
/// at [strokes]: (x, top, bottom).
img.Image _page(List<(int, int, int)> strokes) {
  final image = img.Image(width: 600, height: 260, numChannels: 3);
  img.fill(image, color: img.ColorRgb8(200, 200, 200));
  for (final y in _lines) {
    for (var x = 20; x < 580; x++) {
      image.setPixelRgb(x, y.toInt(), 30, 30, 30);
    }
  }
  for (final (x, top, bottom) in strokes) {
    for (var y = top; y <= bottom; y++) {
      image.setPixelRgb(x, y, 30, 30, 30);
      image.setPixelRgb(x + 1, y, 30, 30, 30);
    }
  }
  return image;
}

DetectedSymbol _quarter(double x, {Rect? fullBox}) =>
    DetectedSymbol.fromMusicSymbol(
      id: 'n$x',
      symbol: MusicSymbol.noteheadBlackInSpace,
      boundingBox: Rect.fromLTWH(x, 130, 12, 9),
      metadata: {
        'noteType': 'quarter',
        if (fullBox != null)
          DetectedSymbol.fullBoxKey: [
            fullBox.left,
            fullBox.top,
            fullBox.right,
            fullBox.bottom,
          ],
      },
    );

void main() {
  const staff = DetectedStaff(
    id: 'staff-0',
    topY: 88,
    bottomY: 160,
    lineYs: _lines,
  );
  const finder = BarlineFinder();

  test('finds a barline between notes and ignores a stem in its note box', () {
    final image = _page([
      (300, 100, 148), // barline: exactly the staff's height
      (162, 90, 140), // stem of the note at x=150, inside its box
    ]);
    final symbols = [
      _quarter(100),
      _quarter(150, fullBox: const Rect.fromLTRB(148, 88, 166, 142)),
      _quarter(400),
    ];

    final barlines = finder.find(image, const [staff], symbols);

    expect(barlines, hasLength(1));
    expect(barlines.single.x, closeTo(300.5, 1.5));
    expect(barlines.single.staffId, 'staff-0');
  });

  test('a stroke that carries on past the staff is not a barline', () {
    final image = _page([(300, 70, 178)]);
    final barlines = finder.find(
      image,
      const [staff],
      [_quarter(100), _quarter(400)],
    );
    expect(barlines, isEmpty);
  });

  test('the lines at the start and end of a staff split nothing off', () {
    final image = _page([(30, 100, 148), (300, 100, 148), (570, 100, 148)]);
    final barlines = finder.find(
      image,
      const [staff],
      [_quarter(100), _quarter(400)],
    );
    expect(barlines.map((b) => b.x.round()), [301]);
  });
}
