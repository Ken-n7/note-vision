enum MusicSymbol {
  accidentalDoubleFlat,
  accidentalDoubleSharp,
  accidentalFlat,
  accidentalNatural,
  accidentalSharp,
  augmentationDot,
  beam,
  brace,
  combStaff,
  combTimeSignature,
  fClef,
  flag128thDown,
  flag128thUp,
  flag16thDown,
  flag16thUp,
  flag32ndDown,
  flag32ndUp,
  flag64thDown,
  flag64thUp,
  flag8thDown,
  flag8thUp,
  gClef,
  keyFlat,
  keyNatural,
  keySharp,
  legerLine,
  noteheadBlack,
  noteheadDoubleWhole,
  noteheadHalf,
  noteheadWhole,
  repeatDot,
  rest128th,
  rest16th,
  rest32nd,
  rest64th,
  rest8th,
  restDoubleWhole,
  restHBar,
  restHNr,
  restHalf,
  restLonga,
  restQuarter,
  restWhole,
  staffLine,
  stem,
  timeSig0,
  timeSig1,
  timeSig2,
  timeSig3,
  timeSig4,
  timeSig5,
  timeSig6,
  timeSig7,
  timeSig8,
  timeSig9,
  timeSigCommon,
  timeSigCutCommon;

  static MusicSymbol fromString(String name) {
    return MusicSymbol.values.firstWhere(
      (e) => e.name == name,
      orElse: () => throw ArgumentError('Unknown symbol: $name'),
    );
  }

  // helper to group symbols for UI color coding later
  bool get isNote => [
        noteheadBlack,
        noteheadHalf,
        noteheadWhole,
        noteheadDoubleWhole,
      ].contains(this);

  bool get isRest => [
        restQuarter,
        restHalf,
        restWhole,
        rest8th,
        rest16th,
        rest32nd,
        rest64th,
        rest128th,
        restDoubleWhole,
        restHBar,
        restHNr,
        restLonga,
      ].contains(this);

  bool get isClef => [fClef, gClef].contains(this);

  bool get isTimeSignature => [
        timeSig0, timeSig1, timeSig2, timeSig3, timeSig4,
        timeSig5, timeSig6, timeSig7, timeSig8, timeSig9,
        timeSigCommon, timeSigCutCommon, combTimeSignature,
      ].contains(this);

  bool get isAccidental => [
        accidentalFlat,
        accidentalSharp,
        accidentalNatural,
        accidentalDoubleFlat,
        accidentalDoubleSharp,
      ].contains(this);
}