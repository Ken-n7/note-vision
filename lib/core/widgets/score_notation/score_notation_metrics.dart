abstract final class ScoreNotationMetrics {
  static const musicFontFamily = 'NotoMusic';
  static const musicFontAsset = 'assets/fonts/NotoMusic-Regular.ttf';
  static const textFontFamily = 'NotoSans';
  static const textFontAsset = 'assets/fonts/NotoSans-Regular.ttf';
  static const textBoldFontAsset = 'assets/fonts/NotoSans-Bold.ttf';

  static const trebleClefGlyph = '\u{1D11E}';
  static const sharpGlyph = '\u266F';
  static const flatGlyph = '\u266D';
  static const naturalGlyph = '\u266E';
  static const doubleSharpGlyph = '\u{1D12A}';
  static const doubleFlatGlyph = '\u{1D12B}';

  static const staffLineSpacing = 12.0;
  static const staffLineCount = 5;
  static const middleStaffLineIndex = 2.0;
  static const tapTargetSize = 24.0;

  static const staffLineStrokeWidth = 1.1;
  static const barlineStrokeWidth = 1.2;
  static const systemConnectorStrokeWidth = 1.8;

  static const rowSignatureStartX = 42.0;
  static const measureNumberFontSize = 11.0;
  static const measureNumberOffsetX = 8.0;
  static const measureNumberOffsetY = -22.0;
  static const measureInnerPadding = 16.0;

  static const noteheadRotation = -0.35;
  static const noteheadWholeWidth = 14.0;
  static const noteheadWholeHeight = 9.8;
  static const noteheadDefaultWidth = 12.5;
  static const noteheadDefaultHeight = 8.8;
  static const openNoteStrokeWidth = 1.2;
  static const breveSideLineOffsetFactor = 0.9;
  static const breveSideLineHalfHeight = 10.0;

  static const accidentalFontSize = 16.0;
  static const accidentalGap = 3.0;
  static const pdfAccidentalXOffset = 18.0;
  static const pdfAccidentalYOffset = 6.0;

  static const stemLengthStaffSpaces = 3.4;
  static const stemXOffset = 6.0;
  static const stemStrokeWidth = 1.3;
  static const flagStrokeWidth = 1.2;
  static const beamThickness = 4.0;

  static const dotRadius = 2.1;
  static const dotSpacing = 6.0;
  static const dotYOffset = -2.0;

  static const wholeRestLineIndex = 3.0;
  static const wholeRestCenterYOffset = 4.3;
  static const halfRestLineIndex = 2.0;
  static const halfRestCenterYOffset = -3.0;
  static const restRectWidth = 16.0;
  static const restRectHeight = 4.8;
  static const restDotXOffset = 12.0;
  static const quarterRestLineIndex = 1.35;
  static const quarterRestCenterYOffset = 8.0;
  static const quarterRestDotXOffset = 10.0;
  static const quarterRestDotYOffset = 8.0;

  static const cClefSpineWidth = 3.5;
  static const cClefBracketStrokeWidth = 2.0;
  static const cClefVerticalStrokeWidth = 1.5;
  static const cClefCenterStrokeWidth = 1.2;
  static const bassClefStrokeWidth = 1.6;
  static const bassClefDotRadius = 2.5;
  static const trebleClefXOffset = 10.0;
  static const trebleClefGLineIndexFromTop = 3.0;
  static const trebleClefEditorGlyphAnchorFromTop = 38.0;
  static const trebleClefPdfBaselineFromGLine = -4.0;
  static const trebleClefFontSize = 42.0;

  static const keySignatureFontSize = 20.0;
  static const keySignatureSpacing = 10.0;
  static const keySignatureYOffset = 12.0;
  static const timeSignatureFontSize = 22.0;
  static const timeSignatureBottomOffsetSpaces = 2.0;

  static double staffHeightFor(double lineSpacing) {
    return lineSpacing * (staffLineCount - 1);
  }

  static double stemLengthFor(double lineSpacing) {
    return lineSpacing * stemLengthStaffSpaces;
  }

  static double trebleClefTopForStaff({
    required double staffTop,
    required double lineSpacing,
  }) {
    final scale = lineSpacing / staffLineSpacing;
    final gLineY = staffTop + lineSpacing * trebleClefGLineIndexFromTop;
    return gLineY - trebleClefEditorGlyphAnchorFromTop * scale;
  }

  static double trebleClefPdfBaselineForStaff({
    required double staffTop,
    required double lineSpacing,
  }) {
    final scale = lineSpacing / staffLineSpacing;
    final gLineY = staffTop - lineSpacing * trebleClefGLineIndexFromTop;
    return gLineY + trebleClefPdfBaselineFromGLine * scale;
  }
}
