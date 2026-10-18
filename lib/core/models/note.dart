import 'score_review.dart';
import 'score_symbol.dart';

class Note extends ScoreSymbol {
  final String step; // C, D, E, F, G, A, B
  final int octave; // usually 0-9
  final int? alter; // -1 = flat, 1 = sharp, etc.
  final int duration; // effective divisions, including augmentation dots
  final String type; // whole, half, quarter, eighth, etc.
  final int? voice; // optional
  final int? staff; // optional
  final bool beamed; // true when this eighth note belongs to a beamed group
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
    this.beamed = false,
    this.dots = 0,
    this.isChordTone = false,
    this.confidence,
    this.reviewId,
    this.source,
  });

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
