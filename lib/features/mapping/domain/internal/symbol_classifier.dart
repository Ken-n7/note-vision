class SymbolClassifier {
  const SymbolClassifier._();

  static bool isSupportedClef(String type) =>
      type == 'gClef' || type == 'clefG' || type == 'fClef';

  static bool isSupportedRest(String type) =>
      type == 'restQuarter' ||
      type == 'restHalf' ||
      type == 'restWhole' ||
      type == 'rest8th' ||
      type == 'rest16th';

  static bool isSupportedFlag(String type) =>
      type == 'flag8thUp' || type == 'flag8thDown';

  static bool isNotehead(String type) =>
      type == 'noteheadWhole' ||
      type == 'noteheadHalf' ||
      type == 'noteheadBlack';

  static bool isTimeSignatureSymbol(String type) =>
      type == 'timeSigCommon' ||
      type == 'timeSigCutCommon' ||
      timeSigDigit(type) != null ||
      type == 'combTimeSignature';

  static bool isKeySignatureAccidental(String type) =>
      type == 'accidentalFlat' ||
      type == 'accidentalSharp' ||
      type == 'accidentalNatural';

  /// Matches any accidental that can appear on an individual note (including
  /// double variants). These may also appear in the key-signature zone.
  static bool isAnyAccidental(String type) =>
      type == 'accidentalFlat' ||
      type == 'accidentalSharp' ||
      type == 'accidentalNatural' ||
      type == 'accidentalDoubleFlat' ||
      type == 'accidentalDoubleSharp';

  /// Maps an accidental type to its MusicXML `alter` value, or null if
  /// the type is not a recognised accidental.
  static int? alterFor(String type) => switch (type) {
    'accidentalSharp' => 1,
    'accidentalFlat' => -1,
    'accidentalNatural' => 0,
    'accidentalDoubleSharp' => 2,
    'accidentalDoubleFlat' => -2,
    _ => null,
  };

  static bool isSignatureSymbol(String type) =>
      isSupportedClef(type) ||
      isTimeSignatureSymbol(type) ||
      isKeySignatureAccidental(type);

  static String? timeSigDigit(String type) => const {
    'timeSig0': '0',
    'timeSig1': '1',
    'timeSig2': '2',
    'timeSig3': '3',
    'timeSig4': '4',
    'timeSig5': '5',
    'timeSig6': '6',
    'timeSig7': '7',
    'timeSig8': '8',
    'timeSig9': '9',
  }[type];

  static int durationFor(String type) => switch (type) {
    'whole' => 4,
    'half' => 2,
    'quarter' => 1,
    'eighth' => 1,
    'sixteenth' => 1,
    _ => 1,
  };
}
