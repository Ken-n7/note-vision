import 'dart:typed_data';

import '../../detection/domain/detected_staff.dart';

/// Analyses a full-resolution grayscale-as-RGB PNG and returns one
/// [DetectedStaff] per stave found in the image.
///
/// Each [DetectedStaff] carries:
///   • [topY] / [bottomY]  — pixel extent of the stave (first-line top,
///                            last-line bottom) in the original image.
///   • [lineYs]            — five Y-centre positions of the staff lines
///                            (first → fifth), in the original image.
abstract class StaffLineDetector {
  List<DetectedStaff> detect(Uint8List pngBytes);
}
