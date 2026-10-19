import 'score_review.dart';
import 'score_symbol.dart';
import 'note_beam.dart';

export 'note_beam.dart';

class Note extends ScoreSymbol {
  final String step; // C, D, E, F, G, A, B
  final int octave; // usually 0-9
  final int? alter; // -1 = flat, 1 = sharp, etc.
  final int duration; // effective divisions, including augmentation dots
  final String type; // whole, half, quarter, eighth, etc.
  final int? voice; // optional
  final int? staff; // optional
  final bool _legacyBeamed;

  /// Numbered beam boundaries and hooks. Older scores use the boolean flag.
  final Map<int, BeamValue> beams;
  bool get beamed => _legacyBeamed || beams.containsKey(1);
  final int dots; // number of augmentation dots
  final bool isChordTone; // true when this note starts with the preceding note

  /// The detector's confidence for a scanned note; null when the note was
  /// typed, imported or edited, so an edited note no longer counts as unsure.
  final double? confidence;
  final String? reviewId;
  final SourceRegion? source;

  const Note({
    required this.step,
    required this.octave,
    this.alter,
    required this.duration,
    required this.type,
    this.voice,
    this.staff,
    bool beamed = false,
    this.beams = const {},
    this.dots = 0,
    this.isChordTone = false,
    this.confidence,
    this.reviewId,
    this.source,
  }) : _legacyBeamed = beamed;

  @override
  Map<String, dynamic> toJson() => {
    'symbolType': 'note',
    'step': step,
    'octave': octave,
    if (alter != null) 'alter': alter,
    'duration': duration,
    'type': type,
    if (voice != null) 'voice': voice,
    if (staff != null) 'staff': staff,
    if (beamed) 'beamed': true,
    if (beams.isNotEmpty)
      'beams': {
        for (final entry in beams.entries) '${entry.key}': entry.value.xmlValue,
      },
    if (dots > 0) 'dots': dots,
    if (isChordTone) 'isChordTone': true,
    if (confidence != null) 'confidence': confidence,
    if (reviewId != null) 'reviewId': reviewId,
    if (source != null) 'source': source!.toJson(),
  };

  factory Note.fromJson(Map<String, dynamic> json) => Note(
    step: json['step'] as String,
    octave: json['octave'] as int,
    alter: json['alter'] as int?,
    duration: json['duration'] as int,
    type: json['type'] as String,
    voice: json['voice'] as int?,
    staff: json['staff'] as int?,
    beamed: json['beamed'] as bool? ?? false,
    beams: _readBeams(json['beams']),
    dots: json['dots'] as int? ?? 0,
    isChordTone: json['isChordTone'] as bool? ?? false,
    confidence: (json['confidence'] as num?)?.toDouble(),
    reviewId: json['reviewId'] as String?,
    source: json['source'] == null
        ? null
        : SourceRegion.fromJson(
            Map<String, dynamic>.from(json['source'] as Map),
          ),
  );

  static Map<int, BeamValue> _readBeams(dynamic json) {
    if (json is! Map) return const {};
    final result = <int, BeamValue>{};
    for (final entry in json.entries) {
      final level = int.tryParse('${entry.key}');
      final value = BeamValue.parse('${entry.value}');
      if (level != null && level >= 1 && level <= 8 && value != null) {
        result[level] = value;
      }
    }
    return Map.unmodifiable(result);
  }

  Note withBeams(Map<int, BeamValue> values) => Note(
    step: step,
    octave: octave,
    alter: alter,
    duration: duration,
    type: type,
    voice: voice,
    staff: staff,
    beams: Map.unmodifiable(values),
    dots: dots,
    isChordTone: isChordTone,
    confidence: confidence,
    reviewId: reviewId,
    source: source,
  );

  String get pitch {
    final accidental = switch (alter) {
      -2 => 'bb',
      -1 => 'b',
      1 => '#',
      2 => 'x',
      _ => '',
    };
    return '$step$accidental$octave';
  }

  @override
  String toString() =>
      'Note(pitch: $pitch, duration: $duration, type: $type'
      '${voice != null ? ', voice: $voice' : ''}'
      '${staff != null ? ', staff: $staff' : ''}'
      '${beamed ? ', beamed: true' : ''}'
      '${dots > 0 ? ', dots: $dots' : ''}'
      '${isChordTone ? ', isChordTone: true' : ''}'
      ')';
}
