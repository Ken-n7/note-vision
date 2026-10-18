import 'score_review.dart';
import 'dart:math' as math;

import 'barline_type.dart';
import 'clef.dart';
import 'measure.dart';
import 'part.dart';
import 'score_symbol.dart';
import 'time_signature.dart';

class Score {
  static const Object _keep = Object();

  final String id;
  final String title;
  final String composer;
  final List<Part> parts;
  final List<ScoreSourcePage> sourcePages;
  final List<ScoreReviewEntry> reviewHistory;

  const Score({
    required this.id,
    required this.title,
    required this.composer,
    required this.parts,
    this.sourcePages = const [],
    this.reviewHistory = const [],
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'composer': composer,
    'parts': parts.map((p) => p.toJson()).toList(),
    if (sourcePages.isNotEmpty)
      'sourcePages': sourcePages.map((p) => p.toJson()).toList(),
    if (reviewHistory.isNotEmpty)
      'reviewHistory': reviewHistory.map((e) => e.toJson()).toList(),
  };

  factory Score.fromJson(Map<String, dynamic> json) => Score(
    id: json['id'] as String,
    title: json['title'] as String,
    composer: (json['composer'] as String?) ?? '',
    sourcePages: (json['sourcePages'] as List? ?? [])
        .map(
          (p) => ScoreSourcePage.fromJson(Map<String, dynamic>.from(p as Map)),
        )
        .toList(),
    reviewHistory: (json['reviewHistory'] as List? ?? [])
        .map(
          (e) => ScoreReviewEntry.fromJson(Map<String, dynamic>.from(e as Map)),
        )
        .toList(),
    parts: (json['parts'] as List<dynamic>)
        .map((p) => Part.fromJson(p as Map<String, dynamic>))
        .toList(),
  );

  Score copyWith({
    String? title,
    String? composer,
    List<Part>? parts,
    List<ScoreSourcePage>? sourcePages,
    List<ScoreReviewEntry>? reviewHistory,
  }) => Score(
    id: id,
    title: title ?? this.title,
    composer: composer ?? this.composer,
    parts: parts ?? this.parts,
    sourcePages: sourcePages ?? this.sourcePages,
    reviewHistory: reviewHistory ?? this.reviewHistory,
  );

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

  /// Sets the time signature of measure [measureIndex] in every part: a
  /// time signature applies to all staves alike. It holds until the next
  /// measure that sets one.
  Score setTimeSignatureAt(int measureIndex, TimeSignature timeSignature) {
    var next = this;
    for (var p = 0; p < parts.length; p++) {
      final measure = next._measureAt(p, measureIndex);
      if (measure == null || measure.timeSignature == timeSignature) continue;
      next = next._replaceMeasure(
        p,
        measureIndex,
        next._copyMeasure(measure, timeSignature: timeSignature),
      );
    }
    return next;
  }

  Score setMeasureClef(int partIndex, int measureIndex, Clef? clef) {
    final measure = _measureAt(partIndex, measureIndex);
    if (measure == null) return this;
    if (measure.clef == clef) return this;

    return _replaceMeasure(
      partIndex,
      measureIndex,
      _copyMeasure(measure, clef: clef),
    );
  }

  /// Appends the measures of [other] to this score, matching parts by index.
  /// Parts in [other] beyond this score's part count are ignored. Parts in
  /// this score without a counterpart in [other] are left unchanged.
  /// The newly appended measures are renumbered to continue from the last
  /// measure of each existing part.
  Score appendScore(Score other) {
    if (other.parts.isEmpty) return this;
    final count = math.min(parts.length, other.parts.length);
    final updatedParts = <Part>[];
    for (int i = 0; i < parts.length; i++) {
      final cp = parts[i];
      if (i >= count) {
        updatedParts.add(cp);
        continue;
      }
      final sp = other.parts[i];
      final existingCount = cp.measures.length;
      updatedParts.add(
        Part(
          id: cp.id,
          name: cp.name,
          measures: [
            ...cp.measures,
            for (int j = 0; j < sp.measures.length; j++)
              _copyMeasure(
                sp.measures[j],
                number: existingCount + j + 1,
                startsNewPage: j == 0, // each scanned page starts a new page
              ),
          ],
        ),
      );
    }
    return copyWith(
      parts: updatedParts,
      sourcePages: [
        ...sourcePages,
        ...other.sourcePages.where(
          (p) => !sourcePages.any((own) => own.id == p.id),
        ),
      ],
    );
  }

  /// Inserts a new empty measure immediately after [measureIndex] in every
  /// part, then renumbers all measures in each part by their list position
  /// (1-indexed). Clef/key/time are left null on the new measure — the active
  /// clef flows forward from the preceding measure during reconstruction and
  /// export, so no explicit carry-over is needed.
  Score insertMeasureAfterInAllParts(int measureIndex) {
    if (parts.isEmpty) return this;

    final updatedParts = List<Part>.from(parts);
    for (int pi = 0; pi < updatedParts.length; pi++) {
      final part = updatedParts[pi];
      final measures = List<Measure>.from(part.measures);
      final insertAt = (measureIndex + 1).clamp(0, measures.length);
      measures.insert(
        insertAt,
        Measure(number: insertAt + 1, symbols: const []),
      );

      updatedParts[pi] = Part(
        id: part.id,
        name: part.name,
        measures: _renumberMeasures(measures),
      );
    }

    return copyWith(parts: updatedParts);
  }

  /// Removes the measure at [measureIndex] from every part and renumbers.
  /// The caller is responsible for ensuring more than one measure exists.
  /// A part too short to have that measure (imported parts can differ in
  /// length) is left as it is.
  Score deleteMeasureFromAllParts(int measureIndex) {
    if (parts.isEmpty) return this;

    final updatedParts = List<Part>.from(parts);
    for (int pi = 0; pi < updatedParts.length; pi++) {
      final part = updatedParts[pi];
      if (measureIndex < 0 || measureIndex >= part.measures.length) continue;
      final measures = List<Measure>.from(part.measures)
        ..removeAt(measureIndex);

      updatedParts[pi] = Part(
        id: part.id,
        name: part.name,
        measures: _renumberMeasures(measures),
      );
    }

    return copyWith(parts: updatedParts);
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
    final measure = _measureAt(partIndex, measureIndex);
    if (measure == null) return this;

    return _replaceMeasure(
      partIndex,
      measureIndex,
      _copyMeasure(measure, symbols: symbols),
    );
  }

  Score _replaceMeasure(
    int partIndex,
    int measureIndex,
    Measure updatedMeasure,
  ) {
    final updatedParts = List<Part>.from(parts);
    final part = updatedParts[partIndex];
    final updatedMeasures = List<Measure>.from(part.measures);
    updatedMeasures[measureIndex] = updatedMeasure;

    updatedParts[partIndex] = Part(
      id: part.id,
      name: part.name,
      measures: updatedMeasures,
    );

    return copyWith(parts: updatedParts);
  }

  List<Measure> _renumberMeasures(List<Measure> measures) {
    return [
      for (int i = 0; i < measures.length; i++)
        _copyMeasure(measures[i], number: i + 1),
    ];
  }

  Measure _copyMeasure(
    Measure measure, {
    int? number,
    Object? clef = _keep,
    Object? timeSignature = _keep,
    List<ScoreSymbol>? symbols,
    bool? startsNewPage,
    bool? startsNewSystem,
    Object? leftBarlineType = _keep,
    Object? rightBarlineType = _keep,
  }) {
    return Measure(
      number: number ?? measure.number,
      reviewId: measure.reviewId,
      source: measure.source,
      clef: identical(clef, _keep) ? measure.clef : clef as Clef?,
      timeSignature: identical(timeSignature, _keep)
          ? measure.timeSignature
          : timeSignature as TimeSignature?,
      keySignature: measure.keySignature,
      symbols: symbols ?? measure.symbols,
      startsNewPage: startsNewPage ?? measure.startsNewPage,
      startsNewSystem: startsNewSystem ?? measure.startsNewSystem,
      leftBarlineType: identical(leftBarlineType, _keep)
          ? measure.leftBarlineType
          : leftBarlineType as BarlineType?,
      rightBarlineType: identical(rightBarlineType, _keep)
          ? measure.rightBarlineType
          : rightBarlineType as BarlineType?,
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
