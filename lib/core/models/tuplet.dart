/// A tuplet: [actual] notes in the time of [normal] (a triplet is 3:2).
/// [start] and [stop] mark the first and last symbol of its bracket.
class Tuplet {
  const Tuplet(this.actual, this.normal, {this.start = false, this.stop = false});

  final int actual, normal;
  final bool start, stop;

  /// How much the tuplet shortens a written value.
  double get factor => normal / actual;

  Tuplet copyWith({bool? start, bool? stop}) =>
      Tuplet(actual, normal, start: start ?? this.start, stop: stop ?? this.stop);

  Map<String, dynamic> toJson() => {
    'actual': actual,
    'normal': normal,
    if (start) 'start': true,
    if (stop) 'stop': true,
  };

  static Tuplet? fromJson(Object? json) => json is Map
      ? Tuplet(
          json['actual'] as int,
          json['normal'] as int,
          start: json['start'] as bool? ?? false,
          stop: json['stop'] as bool? ?? false,
        )
      : null;

  @override
  bool operator ==(Object other) =>
      other is Tuplet &&
      other.actual == actual &&
      other.normal == normal &&
      other.start == start &&
      other.stop == stop;

  @override
  int get hashCode => Object.hash(actual, normal, start, stop);

  @override
  String toString() =>
      'Tuplet($actual:$normal${start ? ' start' : ''}${stop ? ' stop' : ''})';
}
