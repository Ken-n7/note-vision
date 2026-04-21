import 'package:note_vision/features/detection/domain/detected_staff.dart';
import 'package:note_vision/features/detection/domain/detected_symbol.dart';
import 'package:note_vision/features/detection/domain/detection_result.dart';
import 'mapping_types.dart';

class StaffAssigner {
  const StaffAssigner();

  List<StaffOwnedSymbol> assign(
    DetectionResult detection, {
    required List<String> warnings,
  }) {
    final staffs = detection.staffs;
    if (staffs.isEmpty) return const [];

    return detection.symbols
        .map((symbol) {
          final bestStaff = _findBestStaff(symbol, staffs);
          return StaffOwnedSymbol(symbol: symbol, staff: bestStaff);
        })
        .toList(growable: false);
  }

  DetectedStaff _findBestStaff(
    DetectedSymbol symbol,
    List<DetectedStaff> staffs,
  ) {
    final centerY = _centerY(symbol);

    for (final staff in staffs) {
      if (centerY >= staff.topY && centerY <= staff.bottomY) return staff;
    }

    return staffs.reduce((best, candidate) {
      final bestDist = (_midpoint(best) - centerY).abs();
      final candidateDist = (_midpoint(candidate) - centerY).abs();
      return candidateDist < bestDist ? candidate : best;
    });
  }

  static double _midpoint(DetectedStaff staff) =>
      (staff.topY + staff.bottomY) / 2;

  static double _centerY(DetectedSymbol symbol) =>
      symbol.y + ((symbol.height ?? 0) / 2);
}
