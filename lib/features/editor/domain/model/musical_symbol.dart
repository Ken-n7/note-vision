enum MusicalSymbol {
  wholeNote,
  halfNote,
  quarterNote,
  eighthNote,
  wholeRest,
  halfRest,
  quarterRest;

  String get label {
    switch (this) {
      case MusicalSymbol.wholeNote:
        return 'Whole';
      case MusicalSymbol.halfNote:
        return 'Half';
      case MusicalSymbol.quarterNote:
        return 'Quarter';
      case MusicalSymbol.eighthNote:
        return 'Eighth';
      case MusicalSymbol.wholeRest:
        return 'W Rest';
      case MusicalSymbol.halfRest:
        return 'H Rest';
      case MusicalSymbol.quarterRest:
        return 'Q Rest';
    }
  }

  bool get isRest => index >= 4; // wholeRest and below
}