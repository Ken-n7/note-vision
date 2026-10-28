/// What a [Spanner] draws.
enum SpannerKind { tie, slur }

/// A tie or slur from one note to a later one, by their review IDs (stable
/// through edits, undo and saving). A spanner whose notes are gone is
/// ignored, and works again if undo brings them back.
class Spanner {
  const Spanner(this.kind, this.from, this.to);

  final SpannerKind kind;
  final String from, to;

  Map<String, dynamic> toJson() => {'kind': kind.name, 'from': from, 'to': to};

  factory Spanner.fromJson(Map<String, dynamic> json) => Spanner(
    SpannerKind.values.byName(json['kind'] as String),
    json['from'] as String,
    json['to'] as String,
  );

  @override
  bool operator ==(Object other) =>
      other is Spanner &&
      other.kind == kind &&
      other.from == from &&
      other.to == to;

  @override
  int get hashCode => Object.hash(kind, from, to);

  @override
  String toString() => 'Spanner(${kind.name}: $from → $to)';
}
