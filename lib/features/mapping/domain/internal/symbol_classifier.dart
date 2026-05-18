class SymbolClassifier {
  const SymbolClassifier._();

  static bool isSupportedClef(String type) =>
      type == 'clefG' || type == 'clefF';

  static bool isSupportedRest(String type) =>
      type == 'restQuarter' ||
      type == 'restHalf' ||
      type == 'restWhole' ||
      type == 'rest8th' ||
      type == 'rest16th';

  static bool isAugmentationDot(String type) => type == 'augmentationDot';

  static bool isRepeatDot(String type) => type == 'repeatDot';

  static bool isSupportedFlag(String type) =>
      type == 'flag8thUp' || type == 'flag8thDown';

  static bool isNotehead(String type) =>
      type == 'noteheadBlackInSpace' ||
      type == 'noteheadBlackOnLine' ||
      type == 'noteheadHalfInSpace' ||
      type == 'noteheadHalfOnLine' ||
      type == 'noteheadWholeInSpace' ||
      type == 'noteheadWholeOnLine' ||
      type == 'noteheadDoubleWholeInSpace' ||
      type == 'noteheadDoubleWholeOnLine';

  /// Returns true for whole and double-whole noteheads — symbols that never
  /// have a stem, so a missing-stem warning is suppressed for them.
  static bool isWholeNotehead(String type) =>
      type == 'noteheadWholeInSpace' ||
      type == 'noteheadWholeOnLine' ||
      type == 'noteheadDoubleWholeInSpace' ||
      type == 'noteheadDoubleWholeOnLine';

  static bool isTimeSignatureSymbol(String type) =>
      type == 'timeSigCommon' ||
      type == 'timeSigCutCommon' ||
      timeSigDigit(type) != null;

  static bool isKeySignatureAccidental(String type) =>
      type == 'accidentalFlat' ||
      type == 'accidentalSharp' ||
      type == 'accidentalNatural';

  static bool isAnyAccidental(String type) =>
      type == 'accidentalFlat' ||
      type == 'accidentalSharp' ||
      type == 'accidentalNatural' ||
      type == 'accidentalDoubleFlat' ||
      type == 'accidentalDoubleSharp';

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
        'timeSig0': '0', 'timeSig1': '1', 'timeSig2': '2',
        'timeSig3': '3', 'timeSig4': '4', 'timeSig5': '5',
        'timeSig6': '6', 'timeSig7': '7', 'timeSig8': '8',
        'timeSig9': '9',
      }[type];

  static int durationFor(String type) => switch (type) {
        'breve' => 16,
        'whole' => 8,
        'half' => 4,
        'quarter' => 2,
        'eighth' => 1,
        'sixteenth' => 1,
        _ => 1,
      };

  static double beatValueFor(String type) => switch (type) {
        'breve' => 8,
        'whole' => 4,
        'half' => 2,
        'quarter' => 1,
        'eighth' => 0.5,
        'sixteenth' => 0.25,
        _ => 1,
      };
}
