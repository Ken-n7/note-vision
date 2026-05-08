enum BarlineType {
  repeatStart,
  repeatEnd;

  String get jsonValue => switch (this) {
        BarlineType.repeatStart => 'repeatStart',
        BarlineType.repeatEnd => 'repeatEnd',
      };

  static BarlineType fromJsonValue(String value) => switch (value) {
        'repeatStart' => BarlineType.repeatStart,
        'repeatEnd' => BarlineType.repeatEnd,
        _ => throw FormatException('Unknown BarlineType: $value'),
      };
}
