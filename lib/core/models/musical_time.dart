/// Exact time in quarter notes. Integer ratios keep tuplets and source
/// divisions exact without rounding them to the legacy two-division grid.
class MusicalTime implements Comparable<MusicalTime> {
  const MusicalTime._(this.numerator, this.denominator);

  factory MusicalTime(int numerator, [int denominator = 1]) {
    return MusicalTime._ratio(BigInt.from(numerator), BigInt.from(denominator));
  }

  factory MusicalTime._ratio(BigInt numerator, BigInt denominator) {
    if (denominator == BigInt.zero) {
      throw ArgumentError('Time denominator cannot be zero');
    }
    if (denominator.isNegative) {
      numerator = -numerator;
      denominator = -denominator;
    }
    final divisor = numerator.gcd(denominator);
    numerator ~/= divisor;
    denominator ~/= divisor;
    // Remain exact in project JSON on both Dart VM and JavaScript targets.
    final limit = BigInt.from(9007199254740991);
    if (numerator.abs() > limit || denominator > limit) {
      throw const FormatException('Musical time exceeds supported precision');
    }
    return MusicalTime._(numerator.toInt(), denominator.toInt());
  }

  static const zero = MusicalTime._(0, 1);
  static const one = MusicalTime._(1, 1);
  final int numerator, denominator;

  /// MusicXML divisions use XML decimals, including fractional divisions.
  factory MusicalTime.decimal(String value) {
    final text = value.trim();
    if (!RegExp(r'^[+-]?(?:\d+(?:\.\d*)?|\.\d+)$').hasMatch(text)) {
      throw FormatException('Invalid musical time: $value');
    }
    final sign = text.startsWith('-') ? -1 : 1;
    final parts = text.replaceFirst(RegExp(r'^[+-]'), '').split('.');
    final fraction = parts.length > 1 ? parts[1] : '';
    if (fraction.length > 9 || parts.first.length + fraction.length > 15) {
      throw FormatException('Musical time exceeds supported precision: $value');
    }
    var scale = 1;
    for (var i = 0; i < fraction.length; i++) {
      scale *= 10;
    }
    return MusicalTime(
      sign * int.parse('${parts.first.isEmpty ? '0' : parts.first}$fraction'),
      scale,
    );
  }

  factory MusicalTime.fromJson(Map<String, dynamic> json) =>
      MusicalTime(json['numerator'] as int, json['denominator'] as int);

  Map<String, dynamic> toJson() => {
    'numerator': numerator,
    'denominator': denominator,
  };
  MusicalTime operator +(MusicalTime other) => MusicalTime._ratio(
    BigInt.from(numerator) * BigInt.from(other.denominator) +
        BigInt.from(other.numerator) * BigInt.from(denominator),
    BigInt.from(denominator) * BigInt.from(other.denominator),
  );
  MusicalTime operator -(MusicalTime other) => MusicalTime._ratio(
    BigInt.from(numerator) * BigInt.from(other.denominator) -
        BigInt.from(other.numerator) * BigInt.from(denominator),
    BigInt.from(denominator) * BigInt.from(other.denominator),
  );
  MusicalTime operator /(MusicalTime other) => MusicalTime._ratio(
    BigInt.from(numerator) * BigInt.from(other.denominator),
    BigInt.from(denominator) * BigInt.from(other.numerator),
  );
  MusicalTime operator *(MusicalTime other) => MusicalTime._ratio(
    BigInt.from(numerator) * BigInt.from(other.numerator),
    BigInt.from(denominator) * BigInt.from(other.denominator),
  );
  double get asDouble => numerator / denominator;
  bool get isNegative => numerator < 0;
  bool get isZero => numerator == 0;

  @override
  int compareTo(MusicalTime other) =>
      (BigInt.from(numerator) * BigInt.from(other.denominator)).compareTo(
        BigInt.from(other.numerator) * BigInt.from(denominator),
      );
  @override
  bool operator ==(Object other) =>
      other is MusicalTime &&
      numerator == other.numerator &&
      denominator == other.denominator;
  @override
  int get hashCode => Object.hash(numerator, denominator);
  @override
  String toString() =>
      denominator == 1 ? '$numerator' : '$numerator/$denominator';
}
