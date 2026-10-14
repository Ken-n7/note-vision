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

    return detection.symbols.map((symbol) {
      final bestStaff = _findBestStaff(symbol, staffs);
      return StaffOwnedSymbol(symbol: symbol, staff: bestStaff);
    }).toList(growable: false);
  }

  DetectedStaff _findBestStaff(
    DetectedSymbol symbol,
    List<DetectedStaff> staffs,
  ) {
    final centerY = _centerY(symbol);
    final centerX = symbol.x + ((symbol.width ?? 0) / 2);

    for (final staff in staffs) {
      if (staff.containsY(centerY, x: centerX)) return staff;
    }

    // A sloped staff is not where its level lines say; measure to where it
    // actually runs under the symbol.
    double distance(DetectedStaff staff) =>
        ((staff.topY + staff.bottomY) / 2 + staff.offsetAt(centerX) - centerY)
            .abs();
    return staffs.reduce(
      (best, candidate) => distance(candidate) < distance(best) ? candidate : best,
    );
  }

  static double _centerY(DetectedSymbol symbol) =>
      symbol.y + ((symbol.height ?? 0) / 2);
}