import 'score_review.dart';
import 'score_symbol.dart';
import 'articulation.dart';
import 'tuplet.dart';

class Rest extends ScoreSymbol {
  final int duration; // effective divisions, including augmentation dots
  final String type; // whole, half, quarter, eighth, etc.
  final int? voice;
  final int? staff;
  final int dots;

  /// The detector's confidence for a scanned rest; null otherwise.
  final double? confidence;
  final String? reviewId;
  final SourceRegion? source;

  const Rest({
    required this.duration,
    required this.type,
    this.voice,
    this.staff,
    this.dots = 0,
    this.confidence,
    this.reviewId,
    this.source,
    this.tuplet,
    this.marks = const [],
  });

  /// The tuplet this rest belongs to, if any.
  final Tuplet? tuplet;

  /// Articulations, ornaments and fermatas on this rest.
  final List<Articulation> marks;

  static const Object _keep = Object();

  /// This rest with the given fields changed and every other field kept.
  Rest copyWith({
    int? duration,
    String? type,
    Object? voice = _keep,
    Object? staff = _keep,
    int? dots,
    Object? confidence = _keep,
    Object? reviewId = _keep,
    Object? source = _keep,
    Object? tuplet = _keep,
    List<Articulation>? marks,
  }) => Rest(
    duration: duration ?? this.duration,
    type: type ?? this.type,
    voice: identical(voice, _keep) ? this.voice : voice as int?,
    staff: identical(staff, _keep) ? this.staff : staff as int?,
    dots: dots ?? this.dots,
    confidence: identical(confidence, _keep)
        ? this.confidence
        : confidence as double?,
    reviewId: identical(reviewId, _keep) ? this.reviewId : reviewId as String?,
    source: identical(source, _keep) ? this.source : source as SourceRegion?,
    tuplet: identical(tuplet, _keep) ? this.tuplet : tuplet as Tuplet?,
    marks: marks ?? this.marks,
  );

  @override
  Map<String, dynamic> toJson() => {
    'symbolType': 'rest',
    'duration': duration,
    'type': type,
    if (voice != null) 'voice': voice,
    if (staff != null) 'staff': staff,
    if (dots > 0) 'dots': dots,
    if (confidence != null) 'confidence': confidence,
    if (reviewId != null) 'reviewId': reviewId,
    if (source != null) 'source': source!.toJson(),
    if (tuplet != null) 'tuplet': tuplet!.toJson(),
    if (marks.isNotEmpty) 'marks': [for (final m in marks) m.name],
  };

  factory Rest.fromJson(Map<String, dynamic> json) => Rest(
    tuplet: Tuplet.fromJson(json['tuplet']),
    marks: Articulation.listFromJson(json['marks']),
    duration: json['duration'] as int,
    type: json['type'] as String,
    voice: json['voice'] as int?,
    staff: json['staff'] as int?,
    dots: json['dots'] as int? ?? 0,
    confidence: (json['confidence'] as num?)?.toDouble(),
    reviewId: json['reviewId'] as String?,
    source: json['source'] == null
        ? null
        : SourceRegion.fromJson(
            Map<String, dynamic>.from(json['source'] as Map),
          ),
  );

  @override
  String toString() =>
      'Rest(duration: $duration, type: $type'
      '${voice != null ? ', voice: $voice' : ''}'
      '${staff != null ? ', staff: $staff' : ''}'
      '${dots > 0 ? ', dots: $dots' : ''}'
      ')';
}
