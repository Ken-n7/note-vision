import 'score_review.dart';
import 'dart:math' as math;

import 'clef.dart';
import 'measure.dart';
import 'note.dart';
import 'part.dart';
import 'spanner.dart';
import 'rest.dart';
import 'score_symbol.dart';
import 'time_signature.dart';
import 'musicxml_source.dart';

export 'spanner.dart';

enum ScorePlaybackLayout { sequentialStaves, simultaneousParts }

class Score {
  static const Object _keep = Object();

  final String id;
  final String title;
  final String composer;
  final List<Part> parts;
  final List<ScoreSourcePage> sourcePages;
  final List<ScoreReviewEntry> reviewHistory;
  final MusicXmlSource? musicXmlSource;
  final ScorePlaybackLayout? _playbackLayout;
  ScorePlaybackLayout get playbackLayout =>
      _playbackLayout ??
      (musicXmlSource == null
          ? ScorePlaybackLayout.sequentialStaves
          : ScorePlaybackLayout.simultaneousParts);

  const Score({
    required this.id,
    required this.title,
    required this.composer,
    required this.parts,
    this.sourcePages = const [],
    this.reviewHistory = const [],
    this.musicXmlSource,
    ScorePlaybackLayout? playbackLayout,
    this.spanners = const [],
  }) : _playbackLayout = playbackLayout;

  /// Ties and slurs between notes.
  final List<Spanner> spanners;

  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'composer': composer,
    'parts': parts.map((p) => p.toJson()).toList(),
    if (sourcePages.isNotEmpty)
      'sourcePages': sourcePages.map((p) => p.toJson()).toList(),
    if (reviewHistory.isNotEmpty)
      'reviewHistory': reviewHistory.map((e) => e.toJson()).toList(),
    if (musicXmlSource != null) 'musicXmlSource': musicXmlSource!.toJson(),
    if (_playbackLayout != null || musicXmlSource != null)
      'playbackLayout': playbackLayout.name,
    if (spanners.isNotEmpty)
      'spanners': spanners.map((s) => s.toJson()).toList(),
  };

  factory Score.fromJson(Map<String, dynamic> json) => Score(
    id: json['id'] as String,
    title: json['title'] as String,
    composer: (json['composer'] as String?) ?? '',
    playbackLayout: json['playbackLayout'] == null
        ? null
        : ScorePlaybackLayout.values.firstWhere(
            (v) => v.name == json['playbackLayout'],
            orElse: () =>
                throw const FormatException('Unknown score playback layout'),
          ),
    musicXmlSource: json['musicXmlSource'] == null
        ? null
        : MusicXmlSource.fromJson(
            Map<String, dynamic>.from(json['musicXmlSource'] as Map),
          ),
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
    spanners: (json['spanners'] as List? ?? [])
        .map((s) => Spanner.fromJson(Map<String, dynamic>.from(s as Map)))
        .toList(),
  );

  Score copyWith({
    String? title,
    String? composer,
    List<Part>? parts,
    List<ScoreSourcePage>? sourcePages,
    List<ScoreReviewEntry>? reviewHistory,
    MusicXmlSource? musicXmlSource,
    ScorePlaybackLayout? playbackLayout,
    List<Spanner>? spanners,
  }) => Score(
    id: id,
    title: title ?? this.title,
    composer: composer ?? this.composer,
    parts: parts ?? this.parts,
    sourcePages: sourcePages ?? this.sourcePages,
    reviewHistory: reviewHistory ?? this.reviewHistory,
    musicXmlSource: musicXmlSource ?? this.musicXmlSource,
    playbackLayout: playbackLayout ?? _playbackLayout,
    spanners: spanners ?? this.spanners,
  );

  /// The editable projection excludes retained source and review decisions.
  /// It is the baseline against which preservation-aware export compares edits.
  Map<String, dynamic> notationProjection() => {
    'id': id,
    'title': title,
    'composer': composer,
    'parts': parts.map((p) => p.toJson()).toList(),
    if (spanners.isNotEmpty)
      'spanners': spanners.map((s) => s.toJson()).toList(),
  };

  int get partCount => parts.length;

  int get totalMeasures =>
      parts.fold(0, (sum, part) => sum + part.measures.length);

  /// Clears musical content while keeping the score's structure and evidence.
  /// Structural symbols stored inside a measure are preserved too.
  Score clearAllMusicSymbols() {
    var changed = false;
    final updatedParts = <Part>[];
    for (final part in parts) {
      var partChanged = false;
      final measures = <Measure>[];
      for (final measure in part.measures) {
        final symbols = measure.symbols
            .where((s) => s is! Note && s is! Rest)
            .toList();
        if (symbols.length == measure.symbols.length) {
          measures.add(measure);
        } else {
          partChanged = true;
          measures.add(_copyMeasure(measure, symbols: symbols));
        }
      }
      changed |= partChanged;
      updatedParts.add(
        partChanged
            ? Part(
                id: part.id,
                name: part.name,
                staff: part.staff,
                playback: part.playback,
                measures: measures,
              )
            : part,
      );
    }
    return changed ? copyWith(parts: updatedParts) : this;
  }

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
      updatedParts.add(
        Part(
          id: cp.id,
          name: cp.name,
          staff: cp.staff,
          playback: cp.playback,
          measures: [
            ...cp.measures,
            for (int j = 0; j < sp.measures.length; j++)
              _copyMeasure(
                sp.measures[j],
                number: (cp.measures.lastOrNull?.number ?? 0) + j + 1,
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
        staff: part.staff,
        playback: part.playback,
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
        staff: part.staff,
        playback: part.playback,
        measures: _renumberMeasures(measures),
      );
    }

    return copyWith(parts: updatedParts);
  }

  /// Leaves the bar at [measureIndex] out of the bar count (a pickup) in
  /// every part, or counts it again, renumbering the bars.
  Score setMeasureImplicit(int measureIndex, bool implicit) => copyWith(
    parts: [
      for (final part in parts)
        Part(
          id: part.id,
          name: part.name,
          staff: part.staff,
          playback: part.playback,
          measures: _renumberMeasures([
            for (final (i, m) in part.measures.indexed)
              i == measureIndex ? m.copyWith(implicit: implicit) : m,
          ]),
        ),
    ],
  );

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
      staff: part.staff,
      playback: part.playback,
      measures: updatedMeasures,
    );

    return copyWith(parts: updatedParts);
  }

  /// Numbers bars from 1 in order; a pickup (implicit bar) is not counted
  /// and takes the number before it (0 at the start), as MuseScore numbers.
  List<Measure> _renumberMeasures(List<Measure> measures) {
    var n = 0;
    return [
      for (final m in measures) _copyMeasure(m, number: m.implicit ? n : ++n),
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
    var copy = measure.copyWith(
      number: number,
      symbols: symbols,
      startsNewPage: startsNewPage,
      startsNewSystem: startsNewSystem,
    );
    if (!identical(clef, _keep)) copy = copy.copyWith(clef: clef);
    if (!identical(timeSignature, _keep)) {
      copy = copy.copyWith(timeSignature: timeSignature);
    }
    if (!identical(leftBarlineType, _keep)) {
      copy = copy.copyWith(leftBarlineType: leftBarlineType);
    }
    if (!identical(rightBarlineType, _keep)) {
      copy = copy.copyWith(rightBarlineType: rightBarlineType);
    }
    return copy;
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
