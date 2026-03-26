import 'package:flutter/material.dart';

class StaveSystem {
  final Rect bounds;
  final List<double> staveLines;

  const StaveSystem({required this.bounds, this.staveLines = const []});
}

class InstrumentGroup {
  final Rect bounds;
  final String type;

  const InstrumentGroup({required this.bounds, required this.type});
}

class ScoreStructure {
  final List<StaveSystem> systems;
  final List<InstrumentGroup> groups;
  final List<double> staveLines;

  const ScoreStructure({
    this.systems = const [],
    this.groups = const [],
    this.staveLines = const [],
  });

  bool get isEmpty => systems.isEmpty && groups.isEmpty && staveLines.isEmpty;
}
