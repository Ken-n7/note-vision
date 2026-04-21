import 'package:flutter/widgets.dart';

class ResponsiveLayout {
  const ResponsiveLayout._();

  static bool isTablet(double width) => width >= 700;

  static double horizontalPadding(double width) {
    if (width >= 1200) return 40;
    if (width >= 900) return 32;
    if (width >= 700) return 24;
    return 16;
  }

  static int gridColumns({
    required double width,
    required Orientation orientation,
  }) {
    if (width >= 1200) return 5;
    if (width >= 900) return 4;
    if (width >= 700) return orientation == Orientation.landscape ? 4 : 3;
    return orientation == Orientation.landscape ? 3 : 2;
  }
}
