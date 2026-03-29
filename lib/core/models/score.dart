import 'measure.dart';
import 'part.dart';
import 'score_symbol.dart';

class Score {
  final String id;
  final String title;
  final String composer;
  final List<Part> parts;

  const Score({
    required this.id,
    required this.title,
    required this.composer,
    required this.parts,
  });

  int get partCount => parts.length;

  int get totalMeasures =>
      parts.fold(0, (sum, part) => sum + part.measures.length);

  ScoreSymbol? getSymbolAt(int partIndex, int measureIndex, int symbolIndex) {
    final measure = _measureAt(partIndex, measureIndex);
    if (measure == null) return null;
    if (symbolIndex < 0 || symbolIndex >= measure.symbols.length) return null;
    return measure.symbols[symbolIndex];
  }

  Score replaceSymbolAt(
    int partIndex,
    int measureIndex,
    int symbolIndex,
    ScoreSymbol newSymbol,
  ) {
    final measure = _measureAt(partIndex, measureIndex);
    if (measure == null) return this;
    if (symbolIndex < 0 || symbolIndex >= measure.symbols.length) return this;

    final symbols = List<ScoreSymbol>.from(measure.symbols);
    symbols[symbolIndex] = newSymbol;
    return _replaceMeasureSymbols(partIndex, measureIndex, symbols);
  }

  Score deleteSymbolAt(int partIndex, int measureIndex, int symbolIndex) {
    final measure = _measureAt(partIndex, measureIndex);
    if (measure == null) return this;
    if (symbolIndex < 0 || symbolIndex >= measure.symbols.length) return this;

    final symbols = List<ScoreSymbol>.from(measure.symbols)
      ..removeAt(symbolIndex);
    return _replaceMeasureSymbols(partIndex, measureIndex, symbols);
  }

  Score insertSymbolAt(
    int partIndex,
    int measureIndex,
    int symbolIndex,
    ScoreSymbol symbol,
  ) {
    final measure = _measureAt(partIndex, measureIndex);
    if (measure == null) return this;
    if (symbolIndex < 0 || symbolIndex > measure.symbols.length) return this;

    final symbols = List<ScoreSymbol>.from(measure.symbols)
      ..insert(symbolIndex, symbol);
    return _replaceMeasureSymbols(partIndex, measureIndex, symbols);
  }

  Score reorderSymbol(
    int partIndex,
    int measureIndex,
    int fromIndex,
    int toIndex,
  ) {
    final measure = _measureAt(partIndex, measureIndex);
    if (measure == null) return this;
    if (fromIndex < 0 || fromIndex >= measure.symbols.length) return this;
    if (toIndex < 0 || toIndex >= measure.symbols.length) return this;
    if (fromIndex == toIndex) return this;

    final symbols = List<ScoreSymbol>.from(measure.symbols);
    final moved = symbols.removeAt(fromIndex);
    symbols.insert(toIndex, moved);
    return _replaceMeasureSymbols(partIndex, measureIndex, symbols);
  }

  Measure? _measureAt(int partIndex, int measureIndex) {
    if (partIndex < 0 || partIndex >= parts.length) return null;
    final part = parts[partIndex];
    if (measureIndex < 0 || measureIndex >= part.measures.length) return null;
    return part.measures[measureIndex];
  }

  Score _replaceMeasureSymbols(
    int partIndex,
    int measureIndex,
    List<ScoreSymbol> symbols,
  ) {
    final updatedParts = List<Part>.from(parts);
    final part = updatedParts[partIndex];
    final updatedMeasures = List<Measure>.from(part.measures);
    final measure = updatedMeasures[measureIndex];

    updatedMeasures[measureIndex] = Measure(
      number: measure.number,
      clef: measure.clef,
      timeSignature: measure.timeSignature,
      keySignature: measure.keySignature,
      symbols: symbols,
    );

    updatedParts[partIndex] = Part(
      id: part.id,
      name: part.name,
      measures: updatedMeasures,
    );

    return Score(
      id: id,
      title: title,
      composer: composer,
      parts: updatedParts,
    );
  }

  @override
  String toString() {
    final buffer = StringBuffer();
    buffer.writeln('Score(');
    buffer.writeln('  id: $id');
    buffer.writeln('  title: $title');
    buffer.writeln('  composer: $composer');
    buffer.writeln('  parts: ${parts.length}');
    buffer.writeln('  totalMeasures: $totalMeasures');
    buffer.writeln(')');
    for (final part in parts) {
      buffer.write(part);
    }
    return buffer.toString();
  }
}
