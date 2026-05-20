enum MusicSymbol {
  // Index order must exactly match the DeepScores YOLO dataset class list.
  accidentalDoubleFlat,        // 0
  accidentalDoubleSharp,       // 1
  accidentalFlat,              // 2
  accidentalFlatSmall,         // 3
  accidentalNatural,           // 4
  accidentalNaturalSmall,      // 5
  accidentalSharp,             // 6
  accidentalSharpSmall,        // 7
  arpeggiato,                  // 8
  articAccentAbove,            // 9
  articAccentBelow,            // 10
  articMarcatoAbove,           // 11
  articMarcatoBelow,           // 12
  articStaccatissimoAbove,     // 13
  articStaccatissimoBelow,     // 14
  articStaccatoAbove,          // 15
  articStaccatoBelow,          // 16
  articTenutoAbove,            // 17
  articTenutoBelow,            // 18
  augmentationDot,             // 19
  beam,                        // 20
  brace,                       // 21
  caesura,                     // 22
  clef15,                      // 23
  clef8,                       // 24
  clefCAlto,                   // 25
  clefCTenor,                  // 26
  clefF,                       // 27
  clefG,                       // 28
  clefUnpitchedPercussion,     // 29
  coda,                        // 30
  dynamicCrescendoHairpin,     // 31
  dynamicDiminuendoHairpin,    // 32
  dynamicF,                    // 33
  dynamicM,                    // 34
  dynamicP,                    // 35
  dynamicR,                    // 36
  dynamicS,                    // 37
  dynamicZ,                    // 38
  fermataAbove,                // 39
  fermataBelow,                // 40
  fingering0,                  // 41
  fingering1,                  // 42
  fingering2,                  // 43
  fingering3,                  // 44
  fingering4,                  // 45
  fingering5,                  // 46
  flag128thDown,               // 47
  flag128thUp,                 // 48
  flag16thDown,                // 49
  flag16thUp,                  // 50
  flag32ndDown,                // 51
  flag32ndUp,                  // 52
  flag64thDown,                // 53
  flag64thUp,                  // 54
  flag8thDown,                 // 55
  flag8thDownSmall,            // 56
  flag8thUp,                   // 57
  flag8thUpSmall,              // 58
  graceNoteAcciaccaturaStemDown, // 59
  graceNoteAcciaccaturaStemUp,   // 60
  graceNoteAppoggiaturaStemDown, // 61
  graceNoteAppoggiaturaStemUp,   // 62
  keyFlat,                     // 63
  keyNatural,                  // 64
  keySharp,                    // 65
  keyboardPedalPed,            // 66
  keyboardPedalUp,             // 67
  ledgerLine,                  // 68
  noteheadBlackInSpace,        // 69
  noteheadBlackInSpaceSmall,   // 70
  noteheadBlackOnLine,         // 71
  noteheadBlackOnLineSmall,    // 72
  noteheadDoubleWholeInSpace,  // 73
  noteheadDoubleWholeInSpaceSmall, // 74
  noteheadDoubleWholeOnLine,   // 75
  noteheadDoubleWholeOnLineSmall,  // 76
  noteheadHalfInSpace,         // 77
  noteheadHalfInSpaceSmall,    // 78
  noteheadHalfOnLine,          // 79
  noteheadHalfOnLineSmall,     // 80
  noteheadWholeInSpace,        // 81
  noteheadWholeInSpaceSmall,   // 82
  noteheadWholeOnLine,         // 83
  noteheadWholeOnLineSmall,    // 84
  ornamentMordent,             // 85
  ornamentTrill,               // 86
  ornamentTurn,                // 87
  ornamentTurnInverted,        // 88
  ottavaBracket,               // 89
  repeatDot,                   // 90
  rest128th,                   // 91
  rest16th,                    // 92
  rest32nd,                    // 93
  rest64th,                    // 94
  rest8th,                     // 95
  restDoubleWhole,             // 96
  restHBar,                    // 97
  restHNr,                     // 98
  restHalf,                    // 99
  restQuarter,                 // 100
  restWhole,                   // 101
  segno,                       // 102
  slur,                        // 103
  staff,                       // 104
  stem,                        // 105
  stringsDownBow,              // 106
  stringsUpBow,                // 107
  tie,                         // 108
  timeSig0,                    // 109
  timeSig1,                    // 110
  timeSig2,                    // 111
  timeSig3,                    // 112
  timeSig4,                    // 113
  timeSig5,                    // 114
  timeSig6,                    // 115
  timeSig7,                    // 116
  timeSig8,                    // 117
  timeSig9,                    // 118
  timeSigCommon,               // 119
  timeSigCutCommon,            // 120
  tremolo1,                    // 121
  tremolo2,                    // 122
  tremolo3,                    // 123
  tremolo4,                    // 124
  tremolo5,                    // 125
  tuplet1,                     // 126
  tuplet2,                     // 127
  tuplet3,                     // 128
  tuplet4,                     // 129
  tuplet5,                     // 130
  tuplet6,                     // 131
  tuplet7,                     // 132
  tuplet8,                     // 133
  tuplet9,                     // 134
  tupletBracket;               // 135

  static MusicSymbol fromString(String name) {
    return MusicSymbol.values.firstWhere(
      (e) => e.name == name,
      orElse: () => throw ArgumentError('Unknown symbol: $name'),
    );
  }

  bool get isNote => [
        noteheadBlackInSpace,
        noteheadBlackOnLine,
        noteheadHalfInSpace,
        noteheadHalfOnLine,
        noteheadWholeInSpace,
        noteheadWholeOnLine,
        noteheadDoubleWholeInSpace,
        noteheadDoubleWholeOnLine,
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
      ].contains(this);

  bool get isClef => [clefF, clefG].contains(this);

  bool get isTimeSignature => [
        timeSig0, timeSig1, timeSig2, timeSig3, timeSig4,
        timeSig5, timeSig6, timeSig7, timeSig8, timeSig9,
        timeSigCommon, timeSigCutCommon,
      ].contains(this);

  bool get isAccidental => [
        accidentalFlat,
        accidentalSharp,
        accidentalNatural,
        accidentalDoubleFlat,
        accidentalDoubleSharp,
      ].contains(this);
}
