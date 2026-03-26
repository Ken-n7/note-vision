import 'package:note_vision/features/detection/domain/detected_symbol.dart';

class ResolvedNote {
  final DetectedSymbol symbol;
  final String pitch;

  const ResolvedNote({required this.symbol, required this.pitch});
}

class ResolvedScore {
  final List<ResolvedNote> notes;
  final List<List<DetectedSymbol>> groups;
  final List<DetectedSymbol> symbols;

  const ResolvedScore({
    this.notes = const [],
    this.groups = const [],
    this.symbols = const [],
  });
}
