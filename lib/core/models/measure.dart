import 'score_review.dart';
import 'barline_type.dart';
import 'clef.dart';
import 'key_signature.dart';
import 'navigation_mark.dart';
import 'note.dart';
import 'rest.dart';
import 'score_symbol.dart';
import 'time_signature.dart';

class Measure {
  final int number;
  final String? reviewId;
  final SourceRegion? source;
  final Clef? clef;
  final TimeSignature? timeSignature;
  final KeySignature? keySignature;
  final List<ScoreSymbol> symbols;
  final bool startsNewPage;
  final bool startsNewSystem;
  final BarlineType? leftBarlineType;
  final BarlineType? rightBarlineType;

  /// The numbers of a first/second ending that starts at this bar.
  final List<int> endingStart;

  /// How an ending that ends at this bar closes.
  final EndingEnd? endingEnd;

  /// Segno, coda, Fine, To Coda, D.C. and D.S. at this bar.
  final List<NavigationMark> navigation;

  const Measure({
    required this.number,
    this.reviewId,
    this.source,
    this.clef,
    this.timeSignature,
    this.keySignature,
    required this.symbols,
    this.startsNewPage = false,
    this.startsNewSystem = false,
    this.leftBarlineType,
    this.rightBarlineType,
    this.endingStart = const [],
    this.endingEnd,
    this.navigation = const [],
  });

  static const Object _keep = Object();

  /// This bar with the given fields changed and every other field kept, so
  /// that adding a field to [Measure] cannot be lost by a copy.
  Measure copyWith({
    int? number,
    Object? reviewId = _keep,
    Object? source = _keep,
    Object? clef = _keep,
    Object? timeSignature = _keep,
    Object? keySignature = _keep,
    List<ScoreSymbol>? symbols,
    bool? startsNewPage,
    bool? startsNewSystem,
    Object? leftBarlineType = _keep,
    Object? rightBarlineType = _keep,
    List<int>? endingStart,
    Object? endingEnd = _keep,
    List<NavigationMark>? navigation,
  }) => Measure(
    number: number ?? this.number,
    reviewId: identical(reviewId, _keep) ? this.reviewId : reviewId as String?,
    source: identical(source, _keep) ? this.source : source as SourceRegion?,
    clef: identical(clef, _keep) ? this.clef : clef as Clef?,
    timeSignature: identical(timeSignature, _keep)
        ? this.timeSignature
        : timeSignature as TimeSignature?,
    keySignature: identical(keySignature, _keep)
        ? this.keySignature
        : keySignature as KeySignature?,
    symbols: symbols ?? this.symbols,
    startsNewPage: startsNewPage ?? this.startsNewPage,
    startsNewSystem: startsNewSystem ?? this.startsNewSystem,
    leftBarlineType: identical(leftBarlineType, _keep)
        ? this.leftBarlineType
        : leftBarlineType as BarlineType?,
    rightBarlineType: identical(rightBarlineType, _keep)
        ? this.rightBarlineType
        : rightBarlineType as BarlineType?,
    endingStart: endingStart ?? this.endingStart,
    endingEnd: identical(endingEnd, _keep)
        ? this.endingEnd
        : endingEnd as EndingEnd?,
    navigation: navigation ?? this.navigation,
  );

  Map<String, dynamic> toJson() => {
    'number': number,
    if (reviewId != null) 'reviewId': reviewId,
    if (source != null) 'source': source!.toJson(),
    if (clef != null) 'clef': clef!.toJson(),
    if (timeSignature != null) 'timeSignature': timeSignature!.toJson(),
    if (keySignature != null) 'keySignature': keySignature!.toJson(),
    'symbols': symbols.map((s) => s.toJson()).toList(),
    if (startsNewPage) 'startsNewPage': true,
    if (startsNewSystem) 'startsNewSystem': true,
    if (leftBarlineType != null) 'leftBarlineType': leftBarlineType!.jsonValue,
    if (rightBarlineType != null)
      'rightBarlineType': rightBarlineType!.jsonValue,
    if (endingStart.isNotEmpty) 'endingStart': endingStart,
    if (endingEnd != null) 'endingEnd': endingEnd!.name,
    if (navigation.isNotEmpty)
      'navigation': [for (final n in navigation) n.name],
  };

  factory Measure.fromJson(Map<String, dynamic> json) => Measure(
    number: json['number'] as int,
    reviewId: json['reviewId'] as String?,
    source: json['source'] == null
        ? null
        : SourceRegion.fromJson(
            Map<String, dynamic>.from(json['source'] as Map),
          ),
    clef: json['clef'] != null
        ? Clef.fromJson(json['clef'] as Map<String, dynamic>)
        : null,
    timeSignature: json['timeSignature'] != null
        ? TimeSignature.fromJson(json['timeSignature'] as Map<String, dynamic>)
        : null,
    keySignature: json['keySignature'] != null
        ? KeySignature.fromJson(json['keySignature'] as Map<String, dynamic>)
        : null,
    symbols: (json['symbols'] as List<dynamic>)
        .map((s) => _symbolFromJson(s as Map<String, dynamic>))
        .toList(),
    startsNewPage: json['startsNewPage'] as bool? ?? false,
    startsNewSystem: json['startsNewSystem'] as bool? ?? false,
    leftBarlineType: json['leftBarlineType'] != null
        ? BarlineType.fromJsonValue(json['leftBarlineType'] as String)
        : null,
    rightBarlineType: json['rightBarlineType'] != null
        ? BarlineType.fromJsonValue(json['rightBarlineType'] as String)
        : null,
    endingStart: [
      for (final n in json['endingStart'] as List? ?? const []) n as int,
    ],
    endingEnd: json['endingEnd'] == null
        ? null
        : EndingEnd.values.byName(json['endingEnd'] as String),
    navigation: NavigationMark.listFromJson(json['navigation']),
  );

  static ScoreSymbol _symbolFromJson(Map<String, dynamic> json) {
    return switch (json['symbolType'] as String) {
      'note' => Note.fromJson(json),
      'rest' => Rest.fromJson(json),
      'clef' => Clef.fromJson(json),
      'keySignature' => KeySignature.fromJson(json),
      'timeSignature' => TimeSignature.fromJson(json),
      final t => throw FormatException('Unknown symbolType: $t'),
    };
  }

  /// This measure with a new key signature and symbols, keeping its number,
  /// clef, meter, layout breaks, barlines and scan evidence.
  Measure withContent({
    required KeySignature? keySignature,
    required List<ScoreSymbol> symbols,
  }) => copyWith(keySignature: keySignature, symbols: symbols);

  List<Note> get notes => symbols.whereType<Note>().toList();

  List<Rest> get rests => symbols.whereType<Rest>().toList();

  int get symbolCount => symbols.length;

  @override
  String toString() {
    final buffer = StringBuffer();
    buffer.writeln('  Measure $number:');
    if (clef != null) buffer.writeln('    $clef');
    if (timeSignature != null) buffer.writeln('    $timeSignature');
    if (keySignature != null) buffer.writeln('    $keySignature');
    if (leftBarlineType != null) {
      buffer.writeln('    leftBarlineType: $leftBarlineType');
    }
    if (rightBarlineType != null) {
      buffer.writeln('    rightBarlineType: $rightBarlineType');
    }
    for (final symbol in symbols) {
      buffer.writeln('    $symbol');
    }
    return buffer.toString();
  }
}
