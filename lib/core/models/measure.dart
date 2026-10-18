import 'score_review.dart';
import 'barline_type.dart';
import 'clef.dart';
import 'key_signature.dart';
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
  });

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
