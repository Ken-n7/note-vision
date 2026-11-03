enum BarlineType {
  repeatStart,
  repeatEnd,
  doubleBar,
  finalBar;

  String get jsonValue => switch (this) {
        BarlineType.repeatStart => 'repeatStart',
        BarlineType.repeatEnd => 'repeatEnd',
        BarlineType.doubleBar => 'double',
        BarlineType.finalBar => 'final',
      };

  static BarlineType fromJsonValue(String value) => switch (value) {
        'repeatStart' => BarlineType.repeatStart,
        'repeatEnd' => BarlineType.repeatEnd,
        'double' => BarlineType.doubleBar,
        'final' => BarlineType.finalBar,
        _ => throw FormatException('Unknown BarlineType: $value'),
      };
}
