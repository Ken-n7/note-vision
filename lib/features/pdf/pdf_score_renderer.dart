import '../editor/presentation/editor_layout_policy.dart';
import '../../core/widgets/score_notation/engraving_layout.dart';
import '../../core/widgets/score_notation/score_display_projection.dart';
import 'dart:math' as math;

import 'package:flutter/services.dart';
import 'package:note_vision/core/models/beam_grouping.dart';
import 'package:note_vision/core/models/clef.dart';
import 'package:note_vision/core/models/key_signature.dart';
import 'package:note_vision/core/models/measure.dart';
import 'package:note_vision/core/models/note.dart';
import 'package:note_vision/core/models/rest.dart';
import 'package:note_vision/core/models/score.dart';
import 'package:note_vision/core/models/score_symbol.dart';
import 'package:note_vision/core/models/time_signature.dart';
import 'package:note_vision/core/widgets/score_notation/mark_glyphs.dart';
import 'package:note_vision/core/widgets/score_notation/lyric_layout.dart';
import 'package:note_vision/core/widgets/score_notation/annotation_layout.dart';
import 'package:note_vision/core/widgets/score_notation/score_notation_painter.dart'
    show endingAt, graceScale;
import 'package:note_vision/core/widgets/score_notation/score_notation_metrics.dart';
import 'package:note_vision/core/widgets/score_notation/staff_pitch_mapper.dart';
import 'package:note_vision/core/widgets/score_notation/voice_layout.dart';
import 'package:pdf/pdf.dart';

/// Renders a [Score] as an engraved A4 PDF and returns the raw bytes.
///
/// Uses the same pitch-to-position math as [ScoreNotationPainter] so that
/// the PDF output matches the editor canvas layout.
class PdfScoreRenderer {
  const PdfScoreRenderer({this.compress = true})
    : _policy = null,
      _hiddenMeasures = const {};
  PdfScoreRenderer._configured(Score score, {required this.compress})
    : _policy = EditorLayoutPolicy.forScore(score),
      _hiddenMeasures = ScoreDisplayProjection.forScore(score).hiddenMeasures;
  final EditorLayoutPolicy? _policy;
  final Set<int> _hiddenMeasures;

  /// PDF stream compression. Tests can disable this to inspect generated
  /// content streams without changing production output.
  final bool compress;

  // ── Page & layout constants ──────────────────────────────────────────────
  // These mirror EditorLayoutPolicy.standard so exported pages use the same
  // measure grouping as the editor canvas.
  double get _editorPageW => _policy?.pageWidth ?? 760.0;
  double get _editorPageH => _policy?.pageHeight ?? 1120.0;
  static const double _editorPadX = 16.0;
  static const double _editorPadY = 28.0;
  static const double _editorRowH = 140.0;
  static const double _editorPrefixW = 86.0;
  static const double _editorLineSpacing =
      ScoreNotationMetrics.staffLineSpacing;
  static const double _editorStaffTopOffset = 28.0;
  int get _measuresPerSystem => _policy?.measuresPerRow ?? 4;
  static const int _baseRowsPerPage = 5;
  static const double _editorFirstPageHeaderOffset = 88.0;

  double get _scale {
    final natural = math.min(
      PdfPageFormat.a4.height / _editorPageH,
      PdfPageFormat.a4.width / _editorPageW,
    );
    // Header fonts stay at their printed size when a large ensemble shrinks.
    // Reserve their physical height, including the top notation padding.
    if ((_editorFirstPageHeaderOffset + _editorPadY) * natural >=
        _minimumNotationTop) {
      return natural;
    }
    return math.min(
      natural,
      (PdfPageFormat.a4.height - _minimumNotationTop) /
          (_editorPageH - _editorFirstPageHeaderOffset - _editorPadY),
    );
  }

  double get _pageX0 => (PdfPageFormat.a4.width - _editorPageW * _scale) / 2;
  double get _pageY0 =>
      (PdfPageFormat.a4.height -
          _editorPageH * _scale -
          (_firstPageHeaderOffset - _editorFirstPageHeaderOffset * _scale)) /
      2;
  double get _padX => _editorPadX * _scale;
  double get _padY => _editorPadY * _scale;
  double get _prefixW => _editorPrefixW * _scale;
  double get _mw =>
      ((_editorPageW - _editorPadX * 2 - _editorPrefixW) / _measuresPerSystem) *
      _scale;
  double get _ls => _editorLineSpacing * _scale;
  double get _staffH => ScoreNotationMetrics.staffHeightFor(_ls);
  double get _firstPageHeaderOffset => math.max(
    _editorFirstPageHeaderOffset * _scale,
    _minimumNotationTop - _editorPadY * _scale,
  );

  static const double _titleFontSize = 20.0;
  static const double _composerFontSize = 10.5;
  static const double _headerTopInset = 24.0;
  static const double _headerComposerGap = 8.0;
  static const double _minimumNotationTop =
      _headerTopInset + 2 * _titleFontSize + _headerComposerGap + 8;

  static const PdfColor _ink = PdfColor.fromInt(0xFF111827);

  // ── Public API ────────────────────────────────────────────────────────────

  /// Returns raw PDF bytes for [score].
  Future<Uint8List> render(Score score) => PdfScoreRenderer._configured(
    score,
    compress: compress,
  )._render(ScoreDisplayProjection.forScore(score).score);

  Future<Uint8List> _render(Score score) async {
    final doc = PdfDocument(compress: compress);
    final font = PdfTtfFont(
      doc,
      await rootBundle.load(ScoreNotationMetrics.textFontAsset),
    );
    final fontBold = PdfTtfFont(
      doc,
      await rootBundle.load(ScoreNotationMetrics.textBoldFontAsset),
    );
    final musicFont = PdfTtfFont(
      doc,
      await rootBundle.load(ScoreNotationMetrics.musicFontAsset),
    );

    if (score.parts.isEmpty) {
      final page = PdfPage(doc, pageFormat: PdfPageFormat.a4);
      final g = page.getGraphics();
      _drawScoreHeader(g, score, font, fontBold, PdfPageFormat.a4);
      _text(
        g,
        fontBold,
        14,
        'Empty score',
        _pageX0 + _padX,
        PdfPageFormat.a4.height - _pageY0 - _padY - _firstPageHeaderOffset - 14,
      );
      return doc.save();
    }

    final pages = _paginate(score);

    for (var i = 0; i < pages.length; i++) {
      final pageData = pages[i];
      final page = PdfPage(doc, pageFormat: PdfPageFormat.a4);
      final g = page.getGraphics();
      _paintPage(
        g,
        pageData,
        score,
        font,
        fontBold,
        musicFont,
        PdfPageFormat.a4,
        isFirstPage: i == 0,
      );
    }

    return doc.save();
  }

  List<PdfPageLayoutInfo> debugPageLayoutForTesting(Score score) {
    return PdfScoreRenderer._configured(score, compress: compress)
        ._paginate(ScoreDisplayProjection.forScore(score).score)
        .map(
          (page) => PdfPageLayoutInfo(
            firstMeasureIndex: page.firstMeasureIndex,
            measureCount: page.measureCount,
            measuresPerSystem: page.measuresPerSystem,
            rowsPerPage: page.rowsPerPage,
          ),
        )
        .toList(growable: false);
  }

  List<List<Measure>> debugPageSliceForTesting(Score score, int pageIndex) {
    final pages = PdfScoreRenderer._configured(
      score,
      compress: compress,
    )._paginate(ScoreDisplayProjection.forScore(score).score);
    if (pageIndex < 0 || pageIndex >= pages.length) {
      return const <List<Measure>>[];
    }
    return _sliceScoreForPage(
      ScoreDisplayProjection.forScore(score).score,
      pages[pageIndex],
    );
  }

  PdfHeaderLayoutInfo debugHeaderLayoutForTesting(Score score) {
    final configured = PdfScoreRenderer._configured(score, compress: compress);
    return PdfHeaderLayoutInfo(
      title: _headerTitle(score),
      composer: _headerComposer(score),
      firstPageStaffOffset: configured._firstPageHeaderOffset,
      headerTextBottom:
          configured._pageY0 +
          _headerTopInset +
          _titleFontSize +
          (_headerComposer(score).isEmpty
              ? 0
              : _titleFontSize + _headerComposerGap) +
          3,
      firstNotationTop:
          configured._pageY0 +
          configured._firstPageHeaderOffset +
          _editorPadY * configured._scale,
    );
  }

  double debugPitchYForTesting({
    required String step,
    required int octave,
    required double staffBottom,
    String clefSign = 'G',
    int clefLine = 2,
  }) {
    return _yForPitch(
      step: step,
      octave: octave,
      bottomLineY: staffBottom,
      clefSign: clefSign,
      clefLine: clefLine,
    );
  }

  // ── Pagination ────────────────────────────────────────────────────────────

  List<_PageData> _paginate(Score score) {
    final partCount = score.parts.length;
    final rowsPerPage =
        _policy?.rowsPerPage ??
        _rowsPerPageForPartCount(
          partCount,
          extraHeight:
              (LyricLayout.extraHeight(score.parts.map((p) => p.measures)) +
              AnnotationLayout.extraHeight(
                score.parts.map((p) => p.measures).toList(),
              )),
        );
    final referenceMeasures = layoutMeasuresForScore(score);
    final pageStarts = _pageStartIndices(
      referenceMeasures,
      rowsPerPage: rowsPerPage,
    );
    final result = <_PageData>[];

    for (var i = 0; i < pageStarts.length; i++) {
      final firstMeasureIndex = pageStarts[i];
      final nextMeasureIndex = i + 1 < pageStarts.length
          ? pageStarts[i + 1]
          : referenceMeasures.length;
      result.add(
        _PageData(
          firstMeasureIndex: firstMeasureIndex,
          measureCount: math.max(0, nextMeasureIndex - firstMeasureIndex),
          measuresPerSystem: _measuresPerSystem,
          rowsPerPage: rowsPerPage,
        ),
      );
    }

    if (result.isEmpty) {
      result.add(
        _PageData(
          firstMeasureIndex: 0,
          measureCount: 0,
          measuresPerSystem: _measuresPerSystem,
          rowsPerPage: rowsPerPage,
        ),
      );
    }
    return result;
  }

  int _rowsPerPageForPartCount(int partCount, {double extraHeight = 0}) {
    final normalizedPartCount = math.max(1, partCount);
    final availableHeight =
        _editorPageH - (_editorPadY * 2) - _editorFirstPageHeaderOffset;
    final maxRowsThatFit =
        (availableHeight / (normalizedPartCount * (_editorRowH + extraHeight)))
            .floor();
    return math.max(1, math.min(_baseRowsPerPage, maxRowsThatFit));
  }

  List<int> _pageStartIndices(
    List<Measure> measures, {
    required int rowsPerPage,
  }) {
    return pageStartIndicesForMeasures(
      measures,
      layoutPolicy:
          _policy ??
          EditorLayoutPolicy(
            measuresPerRow: _measuresPerSystem,
            rowsPerPage: rowsPerPage,
          ),
    );
  }

  List<List<Measure>> _sliceScoreForPage(Score score, _PageData page) {
    if (ScoreDisplayProjection.fromDisplayScore(score) != null) {
      return [
        for (final p in score.parts)
          p.measures.sublist(
            page.firstMeasureIndex,
            math.min(
              p.measures.length,
              page.firstMeasureIndex + page.measureCount,
            ),
          ),
      ];
    }
    return score.parts
        .map(
          (part) => _sliceMeasuresWithInheritedMetadata(
            measures: part.measures,
            firstMeasureIndex: page.firstMeasureIndex,
            pageMeasureCount: page.measureCount,
          ),
        )
        .toList(growable: false);
  }

  List<Measure> _sliceMeasuresWithInheritedMetadata({
    required List<Measure> measures,
    required int firstMeasureIndex,
    required int pageMeasureCount,
  }) {
    final start = firstMeasureIndex.clamp(0, measures.length);
    final end = (start + pageMeasureCount).clamp(start, measures.length);

    Clef? activeClef;
    TimeSignature? activeTimeSignature;
    KeySignature? activeKeySignature;

    for (var i = 0; i < start; i++) {
      final measure = measures[i];
      activeClef = measure.clef ?? activeClef;
      activeTimeSignature = measure.timeSignature ?? activeTimeSignature;
      activeKeySignature = measure.keySignature ?? activeKeySignature;
    }

    final slice = <Measure>[];
    for (var i = start; i < end; i++) {
      final measure = measures[i];
      final normalized = measure.copyWith(
        clef: measure.clef ?? activeClef,
        timeSignature: measure.timeSignature ?? activeTimeSignature,
        keySignature: measure.keySignature ?? activeKeySignature,
      );
      slice.add(normalized);
      activeClef = normalized.clef;
      activeTimeSignature = normalized.timeSignature;
      activeKeySignature = normalized.keySignature;
    }

    return slice;
  }

  // ── Page painter ──────────────────────────────────────────────────────────

  void _paintPage(
    PdfGraphics g,
    _PageData page,
    Score score,
    PdfFont font,
    PdfFont fontBold,
    PdfFont musicFont,
    PdfPageFormat fmt, {
    required bool isFirstPage,
  }) {
    final pageH = fmt.height;
    final allParts = EngravingLayout.forScore(score).parts;
    final partCount = score.parts.length;
    final pageParts = _sliceScoreForPage(score, page);
    final engraving = EngravingLayout(
      pageParts,
      score: score,
      firstMeasure: page.firstMeasureIndex,
    );
    final maxMeasures = pageParts.fold(0, (m, p) => math.max(m, p.length));
    final systemCount = maxMeasures == 0
        ? 0
        : (maxMeasures / page.measuresPerSystem).ceil();
    final headerOffset = isFirstPage ? _firstPageHeaderOffset : 0.0;

    if (isFirstPage) {
      _drawScoreHeader(g, score, font, fontBold, fmt);
    }

    final clearance = EngravingLayout.forScore(score).clearance;
    final rowHeight =
        clearance.$1 +
        clearance.$2 +
        _editorRowH +
        (LyricLayout.extraHeight(allParts) +
            AnnotationLayout.extraHeight(allParts));
    final above =
        clearance.$1 +
        LyricLayout.aboveHeight(allParts) +
        AnnotationLayout.aboveHeight(allParts);
    final notePoints = <String, _PdfNotePoint>{};
    for (var s = 0; s < systemCount; s++) {
      final startM = s * page.measuresPerSystem;

      for (var pi = 0; pi < partCount; pi++) {
        final partMeasures = pageParts[pi];
        if (startM >= partMeasures.length) continue;

        var endM = math.min(
          startM + page.measuresPerSystem,
          partMeasures.length,
        );
        while (endM > startM &&
            _hiddenMeasures.contains(page.firstMeasureIndex + endM - 1)) {
          endM--;
        }
        if (endM == startM) continue;
        final rowMeasures = partMeasures.sublist(startM, endM);

        // staffTop = top staff line in PDF coords (y from bottom).
        final editorStaffTop =
            _editorPadY +
            s * partCount * rowHeight +
            pi * rowHeight +
            above +
            _editorStaffTopOffset;
        final staffTop =
            pageH - _pageY0 - editorStaffTop * _scale - headerOffset;

        final joined = pi > 0 && score.parts[pi].joinsPrevious;
        _drawStaffRow(
          g,
          font,
          fontBold,
          musicFont,
          placements: [
            for (var i = startM; i < endM; i++)
              engraving.place(
                i,
                _mw / _scale,
                page.measuresPerSystem,
                _editorPrefixW,
              ),
          ],
          partIndex: pi,
          pageMeasures: partMeasures,
          rowStart: startM,
          rowMeasures: rowMeasures,
          staffTop: staffTop,
          clefSign: _clefSign(rowMeasures),
          clefLine: _clefLine(rowMeasures),
          numberBars: !joined,
          topStaff: pi == 0,
          tabTuning: score.parts[pi].isTab ? score.parts[pi].tabTuning : null,
          singleLine: score.parts[pi].singleLine,
          // The staves of the same instrument above and below, for notes
          // drawn across staves.
          crossStaves: {
            for (final move in [-1, 1])
              if (pi + move >= 0 &&
                  pi + move < partCount &&
                  startM < pageParts[pi + move].length &&
                  (move > 0
                      ? score.parts[pi + move].joinsPrevious
                      : score.parts[pi].joinsPrevious))
                move: (
                  top: staffTop - move * rowHeight * _scale,
                  sign: _clefSign(
                    pageParts[pi + move].sublist(
                      startM,
                      math.min(endM, pageParts[pi + move].length),
                    ),
                  ),
                  line: _clefLine(
                    pageParts[pi + move].sublist(
                      startM,
                      math.min(endM, pageParts[pi + move].length),
                    ),
                  ),
                ),
          },
          notePoints: notePoints,
        );
        for (final (i, m) in rowMeasures.indexed) {
          final annotationTexts = AnnotationLayout.build(
            parts: allParts,
            part: pi,
            measure: page.firstMeasureIndex + startM + i,
            visible: m,
            startX: _editorPadX + _editorPrefixW + i * _mw / _scale,
            width: _mw / _scale,
            staffTop: 0,
            staffBottom: _staffH / _scale,
            inset: ScoreNotationMetrics.laneInset(
              timeInMeasure: ScoreNotationMetrics.timeSignatureInMeasure(
                partMeasures,
                startM + i,
                measureInRow: i,
                rowPrefixWidth: _editorPrefixW,
              ),
            ),
            placement: engraving.place(
              startM + i,
              _mw / _scale,
              page.measuresPerSystem,
              _editorPrefixW,
            ),
            lyricAbove: LyricLayout.aboveHeight(allParts),
          );
          for (final t in annotationTexts) {
            final x = _pageX0 + t.x * _scale, y = staffTop - t.y * _scale;
            _text(
              g,
              font,
              AnnotationLayout.fontSize * _scale,
              t.annotation.label,
              x,
              y,
            );
            if (t.annotation.kind == AnnotationKind.rehearsal) {
              final w =
                  font.stringMetrics(t.annotation.label).width *
                  AnnotationLayout.fontSize *
                  _scale;
              g
                ..setColor(_ink)
                ..setLineWidth(_scale)
                ..drawRect(
                  x - 4 * _scale,
                  y - 4 * _scale,
                  w + 8 * _scale,
                  20 * _scale,
                )
                ..strokePath();
            }
          }
        }
        final lyricDrawing = LyricLayout.build(
          notes: LyricLayout.anchors(
            measures: score.parts[pi].measures,
            pageMeasures: partMeasures,
            firstMeasure: page.firstMeasureIndex,
            perRow: page.measuresPerSystem,
            contentX: _editorPadX + _editorPrefixW,
            measureWidth: _mw / _scale,
            prefixWidth: _editorPrefixW,
            engraving: engraving,
            part: pi,
          ),
          aboveClearance: clearance.$1,
          belowClearance: clearance.$2,
          system: s,
          staffTop: 0,
          staffBottom: ScoreNotationMetrics.staffHeightFor(_editorLineSpacing),
          left: _editorPadX + _editorPrefixW,
          right:
              _editorPadX +
              _editorPrefixW +
              rowMeasures.length * _mw / _scale -
              4,
          textWidth: (text) =>
              font.stringMetrics(text).width * LyricLayout.fontSize,
        );
        for (final t in lyricDrawing.texts) {
          _text(
            g,
            font,
            LyricLayout.fontSize * _scale,
            t.text,
            _pageX0 + t.x * _scale,
            staffTop - t.y * _scale,
          );
        }
        for (final line in lyricDrawing.lines) {
          _line(
            g,
            _pageX0 + line.x1 * _scale,
            staffTop - line.y * _scale,
            _pageX0 + line.x2 * _scale,
            staffTop - line.y * _scale,
            0.8 * _scale,
          );
        }
        if (joined) {
          _drawGrandStaff(
            g,
            upperTop: staffTop + rowHeight * _scale,
            lowerTop: staffTop,
            measures: rowMeasures.length,
            tab: score.parts[pi].isTab,
            squareBracket: score.parts[pi].squareBracket,
          );
        }
      }
    }
    _drawSpanners(g, score.spanners, notePoints);
  }

  /// How far below the bottom line dynamics and hairpins sit.
  double get _dynamicsBelow => 22 * _scale;

  /// [mark] centred at ([x], [y]), as in the editor.
  void _drawDynamic(
    PdfGraphics g,
    PdfFont font,
    String mark,
    double x,
    double y,
  ) {
    final size = 14 * _scale;
    final width = font.stringMetrics(mark).width * size;
    _text(g, font, size, mark, x - width / 2, y - size * 0.35);
  }

  /// The editor's mark shapes, scaled, with y flipped (PDF y points up).
  void _drawMarkShapes(
    PdfGraphics g,
    PdfFont font,
    List<MarkShape> shapes,
    double x,
    double y,
  ) {
    double px(double dx) => x + dx * _scale;
    double py(double dy) => y - dy * _scale;
    g.setColor(_ink);
    for (final shape in shapes) {
      switch (shape) {
        case MarkDot(x: final dx, y: final dy, :final radius):
          g
            ..drawEllipse(px(dx), py(dy), radius * _scale, radius * _scale)
            ..fillPath();
        case MarkLines(:final points, :final width, :final filled):
          g.moveTo(px(points.first.$1), py(points.first.$2));
          for (final (dx, dy) in points.skip(1)) {
            g.lineTo(px(dx), py(dy));
          }
          if (filled) {
            g
              ..closePath()
              ..fillPath();
          } else {
            g
              ..setLineWidth(width * _scale)
              ..strokePath();
          }
        case MarkCurve(
          :final start,
          :final segments,
          :final width,
          :final filled,
        ):
          g.moveTo(px(start.$1), py(start.$2));
          for (final (c1, c2, end) in segments) {
            g.curveTo(
              px(c1.$1),
              py(c1.$2),
              px(c2.$1),
              py(c2.$2),
              px(end.$1),
              py(end.$2),
            );
          }
          if (filled) {
            g
              ..closePath()
              ..fillPath();
          } else {
            g
              ..setLineWidth(width * _scale)
              ..strokePath();
          }
        case MarkText(:final text, x: final dx, y: final dy, :final size):
          final scaled = size * _scale;
          final width = font.stringMetrics(text).width * scaled;
          _text(
            g,
            font,
            scaled,
            text,
            px(dx) - width / 2,
            py(dy) - scaled * 0.35,
          );
      }
    }
  }

  /// Hairpins as in the editor (PDF y points up).
  void _drawHairpin(
    PdfGraphics g,
    bool crescendo,
    _PdfNotePoint? a,
    _PdfNotePoint? b,
  ) {
    final open = 4 * _scale;
    final width = 1.2 * _scale;
    void wedge(double rowTop, double x1, double x2, double from, double to) {
      if (x2 - x1 < 4 * _scale) return;
      final y = rowTop - _staffH - _dynamicsBelow;
      _line(g, x1, y + from, x2, y + to, width);
      _line(g, x1, y - from, x2, y - to, width);
    }

    double startX(_PdfNotePoint p) =>
        p.x - 4 * _scale + (p.dynamic ? 12 * _scale : 0);
    double endX(_PdfNotePoint p) => p.x + 12 * _scale;
    final (narrow, wide) = crescendo ? (0.0, open) : (open, 0.0);
    if (a != null && b != null && a.rowTop == b.rowTop) {
      wedge(a.rowTop, startX(a), endX(b), narrow, wide);
      return;
    }
    final half = open / 2;
    if (a != null) {
      wedge(a.rowTop, startX(a), a.rowEndX - 2 * _scale, narrow, half);
    }
    if (b != null) {
      wedge(b.rowTop, b.rowStartX + 4 * _scale, endX(b), half, wide);
    }
  }

  /// Tuplet numbers and brackets as in the editor (PDF y points up).
  void _drawTuplets(
    PdfGraphics g,
    PdfFont font,
    List<ScoreSymbol> symbols,
    List<double> xs,
    List<double> ys, {
    required bool Function(int) stemUp,
    required Set<int> beamed,
    required double staffTop,
  }) {
    var group = <int>[];
    for (final (i, symbol) in symbols.indexed) {
      final tuplet = switch (symbol) {
        Note(isChordTone: true) => null,
        Note(:final tuplet) || Rest(:final tuplet) => tuplet,
        _ => null,
      };
      if (tuplet == null) continue;
      if (tuplet.start) group = [];
      group.add(i);
      if (!tuplet.stop) continue;
      final x1 = xs[group.first] - 6 * _scale;
      final x2 = xs[group.last] + 6 * _scale;
      var top = staffTop + 4 * _scale;
      for (final k in group) {
        final reach = symbols[k] is Rest
            ? 10 * _scale
            : stemUp(k)
            ? ScoreNotationMetrics.stemLengthFor(_ls)
            : 8 * _scale;
        top = math.max(top, ys[k] + reach);
      }
      top += 6 * _scale;
      final size = 11 * _scale;
      final label = '${tuplet.actual}';
      final width = font.stringMetrics(label).width * size;
      final mid = (x1 + x2) / 2;
      _text(g, font, size, label, mid - width / 2, top - size * 0.35);
      if (!group.every(beamed.contains)) {
        final w = 1 * _scale;
        final gap = width / 2 + 3 * _scale;
        _line(g, x1, top - 5 * _scale, x1, top, w);
        _line(g, x1, top, mid - gap, top, w);
        _line(g, mid + gap, top, x2, top, w);
        _line(g, x2, top, x2, top - 5 * _scale, w);
      }
      group = [];
    }
  }

  /// Ties and slurs as in the editor (PDF y points up): thin crescents on
  /// the side away from the stems, split into halves across rows.
  void _drawSpanners(
    PdfGraphics g,
    List<Spanner> spanners,
    Map<String, _PdfNotePoint> points,
  ) {
    for (final spanner in spanners) {
      final a = points[spanner.from];
      final b = points[spanner.to];
      if (a == null && b == null) continue;
      if (spanner.kind.isHairpin) {
        _drawHairpin(g, spanner.kind == SpannerKind.crescendo, a, b);
        continue;
      }
      final tie = spanner.kind == SpannerKind.tie;
      final dir = (a ?? b)!.stemUp ? -1.0 : 1.0; // -1 draws below the heads
      final lift = (tie ? 5.0 : 9.0) * _scale;
      final inset = (tie ? 5.0 : 0.0) * _scale;
      void arc(double x1, double y1, double x2, double y2) {
        final length = (x2 - x1).abs();
        if (length < 2 * _scale) return;
        final height =
            (tie
                ? (3 + length / _scale * 0.04).clamp(3.0, 7.0)
                : (length / _scale * 0.12).clamp(5.0, 16.0)) *
            _scale *
            1.3;
        final inner = height - 1.6 * _scale;
        double x(double t) => x1 + (x2 - x1) * t;
        double y(double t, double h) => y1 + (y2 - y1) * t + dir * h;
        g
          ..setColor(_ink)
          ..moveTo(x1, y1)
          ..curveTo(x(.25), y(.25, height), x(.75), y(.75, height), x2, y2)
          ..curveTo(x(.75), y(.75, inner), x(.25), y(.25, inner), x1, y1)
          ..closePath()
          ..fillPath();
      }

      if (a != null && b != null && a.rowTop == b.rowTop) {
        arc(a.x + inset, a.y + dir * lift, b.x - inset, b.y + dir * lift);
        continue;
      }
      if (a != null) {
        final y = a.y + dir * lift;
        arc(a.x + inset, y, a.rowEndX - 2 * _scale, y);
      }
      if (b != null) {
        final y = b.y + dir * lift;
        arc(b.rowStartX + 4 * _scale, y, b.x - inset, y);
      }
    }
  }

  /// Braces a joined staff to the one above and runs barlines between them,
  /// as in the editor (PDF y points up).
  void _drawGrandStaff(
    PdfGraphics g, {
    required double upperTop,
    required double lowerTop,
    required int measures,
    bool tab = false,
    bool squareBracket = false,
  }) {
    final rowStartX = _pageX0 + _padX;
    final contentStartX = rowStartX + _prefixW;
    final upperBottom = upperTop - _staffH;
    final lowerBottom = lowerTop - _staffH;
    final width = ScoreNotationMetrics.barlineStrokeWidth * _scale;
    _line(g, rowStartX, upperTop, rowStartX, lowerBottom, width);
    // A TAB staff (Guitar + Tablature) is only joined at the left.
    if (tab) return;
    for (var m = 0; m <= measures; m++) {
      final x = contentStartX + m * _mw;
      _line(g, x, upperBottom, x, lowerTop, width);
    }
    if (squareBracket) {
      final x = rowStartX - 7 * _scale;
      _line(g, x + 5 * _scale, upperTop, x, upperTop, 2 * _scale);
      _line(g, x, upperTop, x, lowerBottom, 2 * _scale);
      _line(g, x, lowerBottom, x + 5 * _scale, lowerBottom, 2 * _scale);
      return;
    }
    final mid = (upperTop + lowerBottom) / 2;
    final x = rowStartX - 4 * _scale;
    final w = 7 * _scale;
    final s = _scale;
    g
      ..setColor(_ink)
      ..moveTo(x, upperTop)
      ..curveTo(
        x - w * 1.4,
        upperTop - 6 * s,
        x + w * 0.2,
        mid + 8 * s,
        x - w,
        mid,
      )
      ..curveTo(
        x + w * 0.2,
        mid - 8 * s,
        x - w * 1.4,
        lowerBottom + 6 * s,
        x,
        lowerBottom,
      )
      ..curveTo(
        x - w * 0.9,
        lowerBottom + 6 * s,
        x - w * 0.4,
        mid - 6 * s,
        x - w - 1.5 * s,
        mid,
      )
      ..curveTo(
        x - w * 0.4,
        mid + 6 * s,
        x - w * 0.9,
        upperTop - 6 * s,
        x,
        upperTop,
      )
      ..closePath()
      ..fillPath();
  }

  void _drawScoreHeader(
    PdfGraphics g,
    Score score,
    PdfFont font,
    PdfFont fontBold,
    PdfPageFormat fmt,
  ) {
    final left = _pageX0 + _padX;
    final right = fmt.width - _pageX0 - _padX;
    final width = right - left;
    final titleBaseline =
        fmt.height - _pageY0 - _headerTopInset - _titleFontSize;
    final composerBaseline =
        titleBaseline - _titleFontSize - _headerComposerGap;

    _drawFittedText(
      g,
      fontBold,
      _titleFontSize,
      _headerTitle(score),
      left,
      width,
      titleBaseline,
      align: _PdfTextAlign.center,
      minSize: 12,
    );

    final composer = _headerComposer(score);
    if (composer.isEmpty) return;

    _drawFittedText(
      g,
      font,
      _composerFontSize,
      composer,
      left,
      width,
      composerBaseline,
      align: _PdfTextAlign.right,
      minSize: 8,
    );
  }

  // ── Staff row ──────────────────────────────────────────────────────────────

  /// [rowMeasures] are [pageMeasures] (one part's measures on the page) from
  /// [rowStart] on.
  void _drawStaffRow(
    PdfGraphics g,
    PdfFont font,
    PdfFont fontBold,
    PdfFont musicFont, {
    required List<Measure> pageMeasures,
    required List<BarPlacement> placements,
    required int partIndex,
    required int rowStart,
    required List<Measure> rowMeasures,
    required double staffTop,
    required String clefSign,
    required int clefLine,
    bool numberBars = true,
    bool topStaff = true,
    bool singleLine = false,
    Map<String, _PdfNotePoint>? notePoints,
    List<int>? tabTuning,
    Map<int, ({double top, String sign, int line})> crossStaves = const {},
  }) {
    // staffTop = y of top staff line (PDF: y from bottom)
    // staffBottom = y of bottom staff line
    final staffBottom = staffTop - _staffH;
    final rowStartX = _pageX0 + _padX;
    final contentStartX = rowStartX + _prefixW;
    final staffEndX = contentStartX + rowMeasures.length * _mw;
    // Where time signatures go: as in the editor (ScoreNotationMetrics).
    final timeInMeasure = [
      for (var mi = 0; mi < rowMeasures.length; mi++)
        ScoreNotationMetrics.timeSignatureInMeasure(
          pageMeasures,
          rowStart + mi,
          measureInRow: mi,
          rowPrefixWidth: _editorPrefixW,
        ),
    ];

    // 5 staff lines, or a tablature staff's line per string in that height.
    final lineCount = singleLine
        ? 1
        : tabTuning?.length ?? ScoreNotationMetrics.staffLineCount;
    for (var i = 0; i < lineCount; i++) {
      final lineY = singleLine
          ? staffTop - _staffH / 2
          : staffTop - i * _staffH / (lineCount - 1);
      _line(
        g,
        rowStartX,
        lineY,
        staffEndX,
        lineY,
        ScoreNotationMetrics.staffLineStrokeWidth * _scale,
      );
    }

    // Opening barline
    _line(
      g,
      contentStartX,
      staffTop - (singleLine ? _ls : 0),
      contentStartX,
      staffBottom + (singleLine ? _ls : 0),
      ScoreNotationMetrics.barlineStrokeWidth * _scale,
    );
    // Closing barline
    _line(
      g,
      staffEndX,
      staffTop - (singleLine ? _ls : 0),
      staffEndX,
      staffBottom + (singleLine ? _ls : 0),
      ScoreNotationMetrics.barlineStrokeWidth * _scale,
    );

    // Clef
    if (clefSign == 'T') {
      // TAB, written down the start of the staff.
      for (final (k, letter) in ['T', 'A', 'B'].indexed) {
        _text(
          g,
          fontBold,
          13 * _scale,
          letter,
          rowStartX + ScoreNotationMetrics.trebleClefXOffset * _scale,
          staffTop - (k + 1) * _staffH / 3 + 2 * _scale,
        );
      }
    } else if (clefSign == 'P') {
      // A percussion clef: two thick bars over the middle of the staff.
      for (final dx in [0.0, 6.0]) {
        g
          ..setColor(_ink)
          ..drawRect(
            rowStartX + (ScoreNotationMetrics.trebleClefXOffset + dx) * _scale,
            staffTop - 3 * _ls,
            3 * _scale,
            2 * _ls,
          )
          ..fillPath();
      }
    } else if (clefSign.toUpperCase() == 'F') {
      _drawBassClef(g, rowStartX + 8 * _scale, staffTop, staffBottom);
    } else if (clefSign.toUpperCase() == 'C') {
      _drawCClef(
        g,
        rowStartX + 6 * _scale,
        staffTop,
        staffBottom,
        clefLine: clefLine,
      );
    } else {
      _drawTrebleClef(
        g,
        musicFont,
        rowStartX + ScoreNotationMetrics.trebleClefXOffset * _scale,
        staffTop,
      );
    }
    // An octave clef's small 8, below (sounding lower) or above.
    if (clefSign.length > 1) {
      final below = clefSign.contains('-');
      _text(
        g,
        fontBold,
        9 * _scale,
        '8',
        rowStartX + (ScoreNotationMetrics.trebleClefXOffset + 7) * _scale,
        below ? staffBottom - 2.6 * _ls : staffTop + 2.2 * _ls,
      );
    }

    // Key signature at the start of every system; the time signature on the
    // page's first system and where it changes.
    var sigX = rowStartX + ScoreNotationMetrics.rowSignatureStartX * _scale;
    if (rowMeasures.isNotEmpty) {
      final first = rowMeasures.first;
      // A percussion staff has no key.
      if (first.keySignature != null && clefSign != 'P' && clefSign != 'T') {
        sigX = _drawKeySignature(
          g,
          musicFont,
          sigX,
          first.keySignature!.fifths,
          staffBottom: staffBottom,
          clefSign: clefSign,
          clefLine: clefLine,
        );
      }
      if (ScoreNotationMetrics.showsTimeSignature(pageMeasures, rowStart) &&
          !timeInMeasure.first) {
        _drawTimeSig(
          g,
          fontBold,
          sigX + 10 * _scale,
          staffTop,
          first.timeSignature!,
        );
      }
    }

    // Measures
    for (var mi = 0; mi < rowMeasures.length; mi++) {
      final measure = rowMeasures[mi];
      final measureStartX = contentStartX + mi * _mw;
      final measureEndX = measureStartX + _mw;

      // Measure barline (except before first)
      if (mi > 0) {
        _line(
          g,
          measureStartX,
          staffTop - (singleLine ? _ls : 0),
          measureStartX,
          staffBottom + (singleLine ? _ls : 0),
          ScoreNotationMetrics.barlineStrokeWidth * _scale,
        );
      }

      if (timeInMeasure[mi]) {
        _drawTimeSig(
          g,
          fontBold,
          measureStartX + ScoreNotationMetrics.timeSignatureInMeasureX * _scale,
          staffTop,
          measure.timeSignature!,
        );
      }

      // Repeat signs, barline styles, endings and navigation, as drawn in
      // the editor (endings and navigation on the top staff only).
      _drawMarkShapes(
        g,
        font,
        barShapes(
          width: _mw / _scale,
          spacing: _ls / _scale,
          left: measure.leftBarlineType,
          right: measure.rightBarlineType,
          ending: endingAt(pageMeasures, rowStart + mi),
          navigation: measure.navigation,
          first: topStaff,
          singleLine: singleLine,
        ),
        measureStartX,
        staffTop,
      );

      // Measure number (once per grand staff, above the upper staff)
      if (numberBars && !measure.implicit) {
        _text(
          g,
          font,
          ScoreNotationMetrics.measureNumberFontSize * _scale,
          '${measure.number}',
          measureStartX + ScoreNotationMetrics.measureNumberOffsetX * _scale,
          staffTop - ScoreNotationMetrics.measureNumberOffsetY * _scale,
        );
      }

      _drawMeasureSymbols(
        g,
        musicFont,
        measure,
        placement: placements[mi],
        partIndex: partIndex,
        laneInset:
            ScoreNotationMetrics.laneInset(timeInMeasure: timeInMeasure[mi]) *
            _scale,
        measureStartX: measureStartX,
        measureEndX: measureEndX,
        staffTop: staffTop,
        staffBottom: staffBottom,
        clefSign: clefSign,
        clefLine: clefLine,
        notePoints: notePoints,
        rowStartX: contentStartX,
        tabTuning: tabTuning,
        singleLine: singleLine,
        crossStaves: crossStaves,
        rowEndX: staffEndX,
        textFont: font,
      );
    }
  }

  // ── Measure symbols ────────────────────────────────────────────────────────

  /// [laneInset] is the gap before the first symbol, already scaled.
  void _drawMeasureSymbols(
    PdfGraphics g,
    PdfFont musicFont,
    Measure measure, {
    required double laneInset,
    required BarPlacement placement,
    required int partIndex,
    required double measureStartX,
    required double measureEndX,
    required double staffTop,
    required double staffBottom,
    required String clefSign,
    int clefLine = 2,
    Map<String, _PdfNotePoint>? notePoints,
    double rowStartX = 0,
    List<int>? tabTuning,
    bool singleLine = false,
    Map<int, ({double top, String sign, int line})> crossStaves = const {},
    double rowEndX = 0,
    PdfFont? textFont,
  }) {
    if (measure.symbols.isEmpty) return;

    final geometry = placement.bar.staff[partIndex];
    final count = measure.symbols.length;
    final layout = VoiceLayout.of(measure.symbols);
    final middleLineY =
        staffTop - _ls * ScoreNotationMetrics.middleStaffLineIndex;

    // Pre-compute x/y positions for all symbols.
    final xs = List<double>.generate(
      count,
      (i) => measureStartX + placement.symbolX(partIndex, i) * _scale,
    );
    final ys = <double>[];
    for (var i = 0; i < count; i++) {
      final sym = measure.symbols[i];
      if (sym is Note) {
        // A cross-staff note sits on the staff it moves to, in its clef.
        final cross = crossStaves[sym.staffMove];
        ys.add(
          _yForPitch(
            step: sym.step,
            octave: sym.octave,
            bottomLineY: cross == null ? staffBottom : cross.top - _staffH,
            clefSign: cross?.sign ?? clefSign,
            clefLine: cross?.line ?? clefLine,
          ),
        );
      } else {
        ys.add(staffTop - _ls * ScoreNotationMetrics.middleStaffLineIndex);
      }
    }

    // Build beam groups: runs of consecutive beamed eighth notes. A
    // tablature staff shows frets without stems or beams.
    final beamGroups = tabTuning != null
        ? const <List<int>>[]
        : _buildBeamGroups(measure.symbols);
    final beamedIndices = <int>{};
    for (final group in beamGroups) {
      if (group.length >= 2) {
        beamedIndices.addAll(group);
      }
    }

    // Draw notes/rests.
    for (var i = 0; i < count; i++) {
      final symbol = measure.symbols[i];
      final x = xs[i];
      final y = ys[i];

      // On a tablature staff a note is its fret number on its string.
      if (symbol is Note && tabTuning != null) {
        final string = (symbol.string ?? 1).clamp(1, tabTuning.length);
        final sy = staffTop - (string - 1) * _staffH / (tabTuning.length - 1);
        if (symbol.reviewId case final id? when notePoints != null) {
          notePoints[id] = _PdfNotePoint(
            x: x,
            y: sy,
            stemUp: true,
            rowTop: staffTop,
            rowStartX: rowStartX,
            rowEndX: rowEndX,
            dynamic: symbol.dynamicMark != null,
          );
        }
        final text = '${symbol.fret ?? '?'}';
        final size = 9 * _scale;
        final font = textFont ?? musicFont;
        final w = font.stringMetrics(text).width * size;
        g
          ..setColor(PdfColors.white)
          ..drawRect(
            x - w / 2 - _scale,
            sy - size * 0.45,
            w + 2 * _scale,
            size * 0.9,
          )
          ..fillPath()
          ..setColor(_ink);
        _text(g, font, size, text, x - w / 2, sy - size * 0.35);
        continue;
      }
      if (symbol is Note) {
        if (symbol.reviewId case final id? when notePoints != null) {
          notePoints[id] = _PdfNotePoint(
            x: x,
            y: y,
            stemUp: layout.stemUp(i) ?? y < middleLineY,
            rowTop: staffTop,
            rowStartX: rowStartX,
            rowEndX: rowEndX,
            dynamic: symbol.dynamicMark != null,
          );
        }
        if ((symbol.dynamicMark, textFont) case (final mark?, final font?)) {
          final up = layout.stemUp(i) ?? y < middleLineY;
          final lowest = up
              ? y - 6 * _scale
              : y - ScoreNotationMetrics.stemLengthFor(_ls);
          _drawDynamic(
            g,
            font,
            mark,
            x,
            math.min(staffBottom - _dynamicsBelow, lowest - 12 * _scale),
          );
        }
        final noteTop = crossStaves[symbol.staffMove]?.top ?? staffTop;
        for (final line
            in singleLine
                ? <double>[]
                : ScoreNotationMetrics.ledgerYs((noteTop - y) / _scale)) {
          final half =
              ScoreNotationMetrics.ledgerHalfWidth *
              _scale *
              (symbol.grace == null ? 1 : graceScale);
          _line(
            g,
            x - half,
            noteTop - line * _scale,
            x + half,
            noteTop - line * _scale,
            ScoreNotationMetrics.staffLineStrokeWidth * _scale,
          );
        }
        _drawNote(
          g,
          musicFont,
          symbol,
          x: x,
          y: y,
          middleLineY: middleLineY,
          suppressFlag: beamedIndices.contains(i),
          // A beamed note's stem is drawn with its beam, to reach it.
          drawStem: !beamedIndices.contains(i),
          stemUp: geometry.stemUps[i],
          stemAnchorX: measureStartX + placement.stemX(partIndex, i) * _scale,
          stemStartY: y - geometry.stemStarts[i] * _scale,
          stemEndY: y - geometry.stemEnds[i] * _scale,
          accidentalOffset: placement.bar.staff[partIndex].accidentalOffsets[i],
        );
        if (symbol.marks.isNotEmpty && textFont != null) {
          final up = layout.stemUp(i) ?? y < middleLineY;
          _drawMarkShapes(
            g,
            textFont,
            markShapes(
              symbol.marks,
              stemUp: up,
              staffTop: (y - staffTop) / _scale,
              stemReach: up
                  ? ScoreNotationMetrics.stemLengthFor(_ls) / _scale
                  : 8,
            ),
            x,
            y,
          );
        }
      } else if (symbol is Rest) {
        // PDF y points up, so the editor's upward offset is added.
        if (clefSign != 'T') {
          _drawRest(
            g,
            musicFont,
            symbol,
            x: x,
            staffTop: staffTop - layout.restOffset(i) * _ls,
            singleLine: singleLine,
          );
        }
        if (symbol.reviewId case final id? when notePoints != null) {
          notePoints[id] = _PdfNotePoint(
            x: x,
            y: y,
            stemUp: false,
            rowTop: staffTop,
            rowStartX: rowStartX,
            rowEndX: rowEndX,
            dynamic: symbol.dynamicMark != null,
          );
        }
        if ((symbol.dynamicMark, textFont) case (final mark?, final font?)) {
          _drawDynamic(g, font, mark, x, staffBottom - _dynamicsBelow);
        }
        if (symbol.marks.isNotEmpty && textFont != null) {
          _drawMarkShapes(
            g,
            textFont,
            markShapes(
              symbol.marks,
              stemUp: false,
              staffTop: (y - staffTop) / _scale,
              stemReach: 10,
            ),
            x,
            y,
          );
        }
      }
    }

    if (textFont != null) {
      _drawTuplets(
        g,
        textFont,
        measure.symbols,
        xs,
        ys,
        stemUp: (i) => layout.stemUp(i) ?? ys[i] < middleLineY,
        beamed: beamedIndices,
        staffTop: staffTop,
      );
    }

    // Stems and beams for groups of 2+, as in the editor (PDF y points up).
    final stemLen = ScoreNotationMetrics.stemLengthFor(_ls);
    final thickness = ScoreNotationMetrics.beamThickness * _scale;
    final levelStep =
        (ScoreNotationMetrics.beamThickness + ScoreNotationMetrics.beamGap) *
        _scale;
    for (final group in beamGroups) {
      if (group.length < 2) continue;
      final headYs = [for (final i in group) ys[i]];
      final averageY = headYs.reduce((a, b) => a + b) / headYs.length;
      final stemUp = geometry.stemUps[group.first] ?? averageY < middleLineY;
      final dir = stemUp ? 1.0 : -1.0; // from the heads towards the beam
      final stemXs = [
        for (final i in group)
          measureStartX + placement.stemX(partIndex, i) * _scale,
      ];
      final run = stemXs.last - stemXs.first;
      final slope = run <= 0
          ? 0.0
          : ((headYs.last - headYs.first) / run).clamp(-0.2, 0.2);

      double line(double x) =>
          headYs.first + dir * stemLen + slope * (x - stemXs.first);
      // Move the beam away from the heads until no stem is shorter than
      // 85 % of a normal one.
      var shift = 0.0;
      for (var k = 0; k < group.length; k++) {
        final needed =
            headYs[k] - geometry.stemEnds[group[k]] * _scale - line(stemXs[k]);
        shift = stemUp ? math.max(shift, needed) : math.min(shift, needed);
      }
      double beamY(double x) => line(x) + shift;

      for (var k = 0; k < group.length; k++) {
        _line(
          g,
          stemXs[k],
          headYs[k] - geometry.stemStarts[group[k]] * _scale,
          stemXs[k],
          beamY(stemXs[k]),
          ScoreNotationMetrics.stemStrokeWidth * _scale,
        );
      }

      // Level 0 is the outer beam; inner levels sit nearer the heads.
      void bar(double x1, double x2, int level) {
        final y1 = beamY(x1) - dir * level * levelStep;
        final y2 = beamY(x2) - dir * level * levelStep;
        g.setColor(_ink);
        g.moveTo(x1, y1);
        g.lineTo(x2, y2);
        g.lineTo(x2, y2 - dir * thickness);
        g.lineTo(x1, y1 - dir * thickness);
        g.closePath();
        g.fillPath();
      }

      bar(stemXs.first, stemXs.last, 0);

      for (var level = 2; level <= 3; level++) {
        for (final secondary in BeamGrouping.groups(
          measure.symbols,
          level: level,
          within: group,
        )) {
          final first = group.indexOf(secondary.first);
          final last = group.indexOf(secondary.last);
          if (secondary.length > 1) {
            bar(stemXs[first], stemXs[last], level - 1);
          } else {
            final backwards =
                BeamGrouping.valuesFor(
                  measure.symbols,
                  secondary.first,
                )[level] ==
                BeamValue.backwardHook;
            final stub = 9.0 * _scale;
            bar(
              stemXs[first] - (backwards ? stub : 0),
              stemXs[first] + (backwards ? 0 : stub),
              level - 1,
            );
          }
        }
      }
    }
  }

  List<List<int>> _buildBeamGroups(List<ScoreSymbol> symbols) =>
      BeamGrouping.groups(symbols);

  double _yForPitch({
    required String step,
    required int octave,
    required double bottomLineY,
    required String clefSign,
    required int clefLine,
  }) {
    return StaffPitchMapper.yForPitch(
      step: step,
      octave: octave,
      bottomLineY: bottomLineY,
      lineSpacing: -_ls,
      clefSign: clefSign,
      clefLine: clefLine,
    );
  }

  // ── Note ──────────────────────────────────────────────────────────────────

  void _drawNote(
    PdfGraphics g,
    PdfFont font,
    Note note, {
    required double x,
    required double y,
    required double middleLineY,
    bool suppressFlag = false,
    bool drawStem = true,
    bool? stemUp,
    double? accidentalOffset,
    double? stemAnchorX,
    double? stemStartY,
    double? stemEndY,
  }) {
    if (note.grace case final grace?) {
      // Small, stem up and flagged; an acciaccatura's stem is slashed.
      g
        ..saveContext()
        ..setTransform(
          Matrix4.identity()
            ..translateByDouble(x, y, 0, 1)
            ..scaleByDouble(graceScale, graceScale, 1, 1)
            ..translateByDouble(-x, -y, 0, 1),
        );
      _drawNote(
        g,
        font,
        note.copyWith(grace: null),
        x: x,
        y: y,
        middleLineY: middleLineY,
        stemUp: true,
        accidentalOffset: accidentalOffset,
      );
      if (grace == Grace.acciaccatura) {
        final stemX = x + ScoreNotationMetrics.stemXOffset * _scale;
        final mid =
            y + ScoreNotationMetrics.stemLengthFor(_ls / _scale) * .6 * _scale;
        _line(
          g,
          stemX - 6 * _scale,
          mid - 5 * _scale,
          stemX + 8 * _scale,
          mid + 5 * _scale,
          1.4 * _scale,
        );
      }
      g.restoreContext();
      return;
    }
    final type = note.type.trim().toLowerCase();
    final isBreve = type == 'breve';
    final isWhole = type == 'whole' || isBreve;
    final isHalf = type == 'half';
    final isEighth = _isEighth(type);

    g.setColor(_ink);

    final accidental = _accidentalLabel(note.alter);
    if (accidental != null) {
      _text(
        g,
        font,
        ScoreNotationMetrics.accidentalFontSize * _scale,
        accidental,
        x +
            (accidentalOffset ?? -ScoreNotationMetrics.pdfAccidentalXOffset) *
                _scale,
        y - ScoreNotationMetrics.pdfAccidentalYOffset * _scale,
      );
    }

    final headW =
        (isWhole
            ? ScoreNotationMetrics.noteheadWholeWidth
            : ScoreNotationMetrics.noteheadDefaultWidth) *
        _scale;
    final headH =
        (isWhole
            ? ScoreNotationMetrics.noteheadWholeHeight
            : ScoreNotationMetrics.noteheadDefaultHeight) *
        _scale;
    final hw = headW / 2, hh = headH / 2;
    final head = note.notehead;
    if (head == 'x' || head == 'circle-x') {
      // A cymbal's cross, and an open hi-hat's circled cross.
      _line(g, x - hw, y - hh, x + hw, y + hh, 1.6 * _scale);
      _line(g, x - hw, y + hh, x + hw, y - hh, 1.6 * _scale);
      if (head == 'circle-x') {
        g
          ..setLineWidth(1.6 * _scale)
          ..drawEllipse(x, y, hw * 1.3, hw * 1.3)
          ..strokePath();
      }
    } else if (head == 'diamond') {
      g
        ..moveTo(x - hw, y)
        ..lineTo(x, y + hh * 1.2)
        ..lineTo(x + hw, y)
        ..lineTo(x, y - hh * 1.2)
        ..closePath();
      if (isWhole || isHalf) {
        g
          ..setLineWidth(ScoreNotationMetrics.openNoteStrokeWidth * _scale)
          ..strokePath();
      } else {
        g.fillPath();
      }
    } else if (isWhole || isHalf) {
      _drawRotatedOval(g, x: x, y: y, width: headW, height: headH, fill: false);
    } else {
      _drawRotatedOval(g, x: x, y: y, width: headW, height: headH, fill: true);
    }

    if (isBreve) {
      _line(
        g,
        x - hw * ScoreNotationMetrics.breveSideLineOffsetFactor * 2,
        y - ScoreNotationMetrics.breveSideLineHalfHeight * _scale,
        x - hw * ScoreNotationMetrics.breveSideLineOffsetFactor * 2,
        y + ScoreNotationMetrics.breveSideLineHalfHeight * _scale,
        ScoreNotationMetrics.openNoteStrokeWidth * _scale,
      );
      _line(
        g,
        x + hw * ScoreNotationMetrics.breveSideLineOffsetFactor * 2,
        y - ScoreNotationMetrics.breveSideLineHalfHeight * _scale,
        x + hw * ScoreNotationMetrics.breveSideLineOffsetFactor * 2,
        y + ScoreNotationMetrics.breveSideLineHalfHeight * _scale,
        ScoreNotationMetrics.openNoteStrokeWidth * _scale,
      );
    }

    if (note.dots > 0) {
      _drawAugmentationDots(
        g,
        x: x + headW * ScoreNotationMetrics.breveSideLineOffsetFactor,
        y: y,
        dots: note.dots,
      );
    }

    if (isWhole) return;

    if (note.isChordTone) {
      return;
    }

    if (!drawStem) return;
    _drawStem(
      g,
      x: x,
      y: y,
      stemUp: stemUp ?? y < middleLineY,
      stemAnchorX: stemAnchorX,
      stemStartY: stemStartY,
      stemEndY: stemEndY,
      flags: suppressFlag
          ? 0
          : isEighth
          ? 1
          : BeamGrouping.levels(note),
    );
  }

  static bool _isSixteenth(String type) {
    final normalized = type.trim().toLowerCase();
    return normalized == 'sixteenth' || normalized == '16th';
  }

  static bool _isEighth(String type) {
    final normalized = type.trim().toLowerCase();
    return normalized == 'eighth' ||
        normalized == 'flag8thup' ||
        normalized == 'flag8thdown';
  }

  String? accidentalLabelForTesting(int? alter) => _accidentalLabel(alter);

  static String? _accidentalLabel(int? alter) => switch (alter) {
    1 => ScoreNotationMetrics.sharpGlyph,
    -1 => ScoreNotationMetrics.flatGlyph,
    0 => ScoreNotationMetrics.naturalGlyph,
    2 => ScoreNotationMetrics.doubleSharpGlyph,
    -2 => ScoreNotationMetrics.doubleFlatGlyph,
    _ => null,
  };

  void _drawStem(
    PdfGraphics g, {
    required double x,
    required double y,
    required bool stemUp,
    required int flags,
    double? stemAnchorX,
    double? stemStartY,
    double? stemEndY,
  }) {
    final stemLen = ScoreNotationMetrics.stemLengthFor(_ls);
    final stemX =
        stemAnchorX ??
        (stemUp
            ? x + ScoreNotationMetrics.stemXOffset * _scale
            : x - ScoreNotationMetrics.stemXOffset * _scale);
    final endY = stemEndY ?? (stemUp ? y + stemLen : y - stemLen);

    g.setColor(_ink);
    _line(
      g,
      stemX,
      stemStartY ?? y,
      stemX,
      endY,
      ScoreNotationMetrics.stemStrokeWidth * _scale,
    );

    final stemTip = endY;
    // Each further flag sits a little nearer the notehead.
    for (var f = 0; f < flags; f++) {
      final endY = stemUp
          ? stemTip - f * ScoreNotationMetrics.flagSpacing * _scale
          : stemTip + f * ScoreNotationMetrics.flagSpacing * _scale;
      g.setLineWidth(ScoreNotationMetrics.flagStrokeWidth * _scale);
      g.setColor(_ink);
      if (stemUp) {
        final start = _pdfOffset(stemX, endY, 0, 0.5);
        g.moveTo(start.x, start.y);
        _quadraticCurveTo(
          g,
          fromX: start.x,
          fromY: start.y,
          controlX: stemX + 10 * _scale,
          controlY: endY - 2 * _scale,
          endX: stemX + 6 * _scale,
          endY: endY - 12 * _scale,
        );
        _quadraticCurveTo(
          g,
          fromX: stemX + 6 * _scale,
          fromY: endY - 12 * _scale,
          controlX: stemX + 8 * _scale,
          controlY: endY - 8 * _scale,
          endX: stemX + 1 * _scale,
          endY: endY - 6 * _scale,
        );
      } else {
        final start = _pdfOffset(stemX, endY, 0, -0.5);
        g.moveTo(start.x, start.y);
        // Flags point right on a down stem too, curving up towards the head.
        _quadraticCurveTo(
          g,
          fromX: start.x,
          fromY: start.y,
          controlX: stemX + 10 * _scale,
          controlY: endY + 2 * _scale,
          endX: stemX + 6 * _scale,
          endY: endY + 12 * _scale,
        );
        _quadraticCurveTo(
          g,
          fromX: stemX + 6 * _scale,
          fromY: endY + 12 * _scale,
          controlX: stemX + 8 * _scale,
          controlY: endY + 8 * _scale,
          endX: stemX + 1 * _scale,
          endY: endY + 6 * _scale,
        );
      }
      // Solid, as in the editor.
      g.fillAndStrokePath(close: true);
    }
  }

  // ── Rest ──────────────────────────────────────────────────────────────────

  void _drawRest(
    PdfGraphics g,
    PdfFont musicFont,
    Rest rest, {
    required double x,
    required double staffTop,
    bool singleLine = false,
  }) {
    // A bar rest is drawn as a whole rest in any meter.
    if (rest.measureRest) rest = rest.copyWith(type: 'whole', dots: 0);
    final type = rest.type.trim().toLowerCase();
    g.setColor(_ink);

    if (type == 'whole') {
      // Rectangle hanging below line 4 (from top)
      final lineY =
          staffTop -
          _ls * (singleLine ? 2 : ScoreNotationMetrics.wholeRestLineIndex);
      final height = ScoreNotationMetrics.restRectHeight * _scale;
      final centerY =
          lineY - ScoreNotationMetrics.wholeRestCenterYOffset * _scale;
      g.drawRect(
        x - ScoreNotationMetrics.restRectWidth * _scale / 2,
        centerY - height / 2,
        ScoreNotationMetrics.restRectWidth * _scale,
        height,
      );
      g.fillPath();
      _drawAugmentationDots(
        g,
        x: x + ScoreNotationMetrics.restDotXOffset * _scale,
        y: centerY,
        dots: rest.dots,
      );
      return;
    }

    if (type == 'half') {
      // Rectangle sitting on line 3 (from top)
      final lineY = staffTop - _ls * ScoreNotationMetrics.halfRestLineIndex;
      final height = ScoreNotationMetrics.restRectHeight * _scale;
      final centerY =
          lineY - ScoreNotationMetrics.halfRestCenterYOffset * _scale;
      g.drawRect(
        x - ScoreNotationMetrics.restRectWidth * _scale / 2,
        centerY - height / 2,
        ScoreNotationMetrics.restRectWidth * _scale,
        height,
      );
      g.fillPath();
      _drawAugmentationDots(
        g,
        x: x + ScoreNotationMetrics.restDotXOffset * _scale,
        y: centerY,
        dots: rest.dots,
      );
      return;
    }

    if (_isEighth(type) || _isSixteenth(type) || type == '32nd') {
      // The music font's rest glyphs, placed as the editor places them: the
      // line box centred on the middle line (a sixteenth one space lower).
      final glyph = _isEighth(type)
          ? ScoreNotationMetrics.eighthRestGlyph
          : type == '32nd'
          ? ScoreNotationMetrics.thirtySecondRestGlyph
          : ScoreNotationMetrics.sixteenthRestGlyph;
      final size = ScoreNotationMetrics.restGlyphFontSize * _scale;
      final ascentShare =
          musicFont.ascent / (musicFont.ascent - musicFont.descent);
      final middleY = staffTop - _ls * 2;
      final lineCentre = _isEighth(type)
          ? middleY
          : middleY - ScoreNotationMetrics.sixteenthRestYOffset * _scale;
      final width = musicFont.stringMetrics(glyph).advanceWidth * size;
      _text(
        g,
        musicFont,
        size,
        glyph,
        x - width / 2,
        lineCentre - size * (ascentShare - 0.5),
      );
      _drawAugmentationDots(
        g,
        x: x + ScoreNotationMetrics.quarterRestDotXOffset * _scale,
        y: middleY + _ls / 2,
        dots: rest.dots,
      );
      return;
    }

    final qy = staffTop - _ls * ScoreNotationMetrics.quarterRestLineIndex;
    _moveToOffset(g, x, qy, -3, -5);
    _lineToOffset(g, x, qy, 3, -1);
    _lineToOffset(g, x, qy, -2, 4);
    _lineToOffset(g, x, qy, 3, 9);
    _lineToOffset(g, x, qy, -1, 14);
    _lineToOffset(g, x, qy, 3, 19);
    _lineToOffset(g, x, qy, -4, 22);
    _lineToOffset(g, x, qy, -1, 16);
    _lineToOffset(g, x, qy, -6, 11);
    _lineToOffset(g, x, qy, -1, 5);
    g.closePath();
    g.fillPath();
    _drawAugmentationDots(
      g,
      x: x + ScoreNotationMetrics.quarterRestDotXOffset * _scale,
      y: qy - ScoreNotationMetrics.quarterRestDotYOffset * _scale,
      dots: rest.dots,
    );
  }

  void _drawAugmentationDots(
    PdfGraphics g, {
    required double x,
    required double y,
    required int dots,
  }) {
    if (dots <= 0) return;
    g.setColor(_ink);
    for (var i = 0; i < dots; i++) {
      g.drawEllipse(
        x + (i * ScoreNotationMetrics.dotSpacing * _scale),
        y - ScoreNotationMetrics.dotYOffset * _scale,
        ScoreNotationMetrics.dotRadius * _scale,
        ScoreNotationMetrics.dotRadius * _scale,
      );
      g.fillPath();
    }
  }

  void _drawRotatedOval(
    PdfGraphics g, {
    required double x,
    required double y,
    required double width,
    required double height,
    required bool fill,
  }) {
    const k = 0.5522847498307936;
    const angle = ScoreNotationMetrics.noteheadRotation;
    final hw = width / 2;
    final hh = height / 2;

    _PdfPoint p(double dx, double dy) =>
        _rotatedEditorPoint(x: x, y: y, dx: dx, dy: dy, angle: angle);

    final top = p(0, -hh);
    final right = p(hw, 0);
    final bottom = p(0, hh);
    final left = p(-hw, 0);

    g.setColor(_ink);
    g.moveTo(top.x, top.y);
    final c1 = p(k * hw, -hh);
    final c2 = p(hw, -k * hh);
    g.curveTo(c1.x, c1.y, c2.x, c2.y, right.x, right.y);
    final c3 = p(hw, k * hh);
    final c4 = p(k * hw, hh);
    g.curveTo(c3.x, c3.y, c4.x, c4.y, bottom.x, bottom.y);
    final c5 = p(-k * hw, hh);
    final c6 = p(-hw, k * hh);
    g.curveTo(c5.x, c5.y, c6.x, c6.y, left.x, left.y);
    final c7 = p(-hw, -k * hh);
    final c8 = p(-k * hw, -hh);
    g.curveTo(c7.x, c7.y, c8.x, c8.y, top.x, top.y);

    if (fill) {
      g.fillPath();
    } else {
      g.setLineWidth(ScoreNotationMetrics.openNoteStrokeWidth * _scale);
      g.strokePath();
    }
  }

  _PdfPoint _pdfOffset(double x, double y, double dx, double dy) {
    return _PdfPoint(x + dx * _scale, y - dy * _scale);
  }

  _PdfPoint _rotatedEditorPoint({
    required double x,
    required double y,
    required double dx,
    required double dy,
    required double angle,
  }) {
    final cosA = math.cos(angle);
    final sinA = math.sin(angle);
    final rotatedX = dx * cosA - dy * sinA;
    final rotatedYDown = dx * sinA + dy * cosA;
    return _PdfPoint(x + rotatedX, y - rotatedYDown);
  }

  void _moveToOffset(PdfGraphics g, double x, double y, double dx, double dy) {
    final p = _pdfOffset(x, y, dx, dy);
    g.moveTo(p.x, p.y);
  }

  void _lineToOffset(PdfGraphics g, double x, double y, double dx, double dy) {
    final p = _pdfOffset(x, y, dx, dy);
    g.lineTo(p.x, p.y);
  }

  void _quadraticCurveTo(
    PdfGraphics g, {
    required double fromX,
    required double fromY,
    required double controlX,
    required double controlY,
    required double endX,
    required double endY,
  }) {
    g.curveTo(
      fromX + (controlX - fromX) * 2 / 3,
      fromY + (controlY - fromY) * 2 / 3,
      endX + (controlX - endX) * 2 / 3,
      endY + (controlY - endY) * 2 / 3,
      endX,
      endY,
    );
  }

  // ── Clef ──────────────────────────────────────────────────────────────────

  void _drawTrebleClef(
    PdfGraphics g,
    PdfFont musicFont,
    double x,
    double staffTop,
  ) {
    _text(
      g,
      musicFont,
      ScoreNotationMetrics.trebleClefFontSize * _scale,
      ScoreNotationMetrics.trebleClefGlyph,
      x,
      ScoreNotationMetrics.trebleClefPdfBaselineForStaff(
        staffTop: staffTop,
        lineSpacing: _ls,
      ),
    );
  }

  void _drawBassClef(
    PdfGraphics g,
    double x,
    double staffTop,
    double staffBottom,
  ) {
    final cx = x + 10 * _scale;
    // Bass clef body centered on F3 (4th line from bottom = staffBottom + 3*ls)
    final f3y = staffBottom + _ls * 3;

    g.setColor(_ink);
    g.setLineWidth(ScoreNotationMetrics.bassClefStrokeWidth * _scale);

    g.moveTo(cx, f3y + _ls * 1.5);
    g.curveTo(
      cx + 14 * _scale,
      f3y + _ls * 1.5,
      cx + 18 * _scale,
      f3y + _ls * 0.5,
      cx + 12 * _scale,
      f3y,
    );
    g.curveTo(
      cx + 6 * _scale,
      f3y - _ls * 0.4,
      cx - 2 * _scale,
      f3y - _ls * 0.8,
      cx - 6 * _scale,
      f3y - _ls * 2,
    );
    g.strokePath();

    // Two dots to the right of the curl
    final dotX = cx + 20 * _scale;
    g.drawEllipse(
      dotX,
      f3y + _ls * 0.6,
      ScoreNotationMetrics.bassClefDotRadius * _scale,
      ScoreNotationMetrics.bassClefDotRadius * _scale,
    );
    g.fillPath();
    g.drawEllipse(
      dotX,
      f3y - _ls * 0.4,
      ScoreNotationMetrics.bassClefDotRadius * _scale,
      ScoreNotationMetrics.bassClefDotRadius * _scale,
    );
    g.fillPath();
  }

  void _drawCClef(
    PdfGraphics g,
    double x,
    double staffTop,
    double staffBottom, {
    required int clefLine,
  }) {
    final targetY = staffBottom + (clefLine - 1) * _ls;

    g.setColor(_ink);

    // Left vertical bar (spine) — drawn as a thick stroke
    g.setLineWidth(ScoreNotationMetrics.cClefSpineWidth * _scale);
    g.moveTo(x + ScoreNotationMetrics.cClefSpineWidth * _scale / 2, staffTop);
    g.lineTo(
      x + ScoreNotationMetrics.cClefSpineWidth * _scale / 2,
      staffBottom,
    );
    g.strokePath();

    // Upper bracket: horizontal then vertical down to targetY
    g.setLineWidth(ScoreNotationMetrics.cClefBracketStrokeWidth * _scale);
    g.moveTo(x + ScoreNotationMetrics.cClefSpineWidth * _scale, staffTop);
    g.lineTo(x + 14 * _scale, staffTop);
    g.strokePath();

    g.setLineWidth(ScoreNotationMetrics.cClefVerticalStrokeWidth * _scale);
    g.moveTo(x + 14 * _scale, staffTop);
    g.lineTo(x + 14 * _scale, targetY);
    g.strokePath();

    // Lower bracket: horizontal then vertical up to targetY
    g.setLineWidth(ScoreNotationMetrics.cClefBracketStrokeWidth * _scale);
    g.moveTo(x + ScoreNotationMetrics.cClefSpineWidth * _scale, staffBottom);
    g.lineTo(x + 14 * _scale, staffBottom);
    g.strokePath();

    g.setLineWidth(ScoreNotationMetrics.cClefVerticalStrokeWidth * _scale);
    g.moveTo(x + 14 * _scale, targetY);
    g.lineTo(x + 14 * _scale, staffBottom);
    g.strokePath();

    // Centre line at the target staff line
    g.setLineWidth(ScoreNotationMetrics.cClefCenterStrokeWidth * _scale);
    g.moveTo(x + ScoreNotationMetrics.cClefSpineWidth * _scale, targetY);
    g.lineTo(x + 12 * _scale, targetY);
    g.strokePath();
  }

  // ── Key signature ──────────────────────────────────────────────────────────

  double _drawKeySignature(
    PdfGraphics g,
    PdfFont font,
    double x,
    int fifths, {
    required double staffBottom,
    required String clefSign,
    int clefLine = 2,
  }) {
    if (fifths == 0) return x;
    final isSharp = fifths > 0;
    final count = fifths.abs().clamp(0, 7);

    const sharpOrderTreble = [
      ('F', 5),
      ('C', 5),
      ('G', 5),
      ('D', 5),
      ('A', 4),
      ('E', 5),
      ('B', 4),
    ];
    const flatOrderTreble = [
      ('B', 4),
      ('E', 5),
      ('A', 4),
      ('D', 5),
      ('G', 4),
      ('C', 5),
      ('F', 4),
    ];
    const sharpOrderBass = [
      ('F', 3),
      ('C', 3),
      ('G', 3),
      ('D', 3),
      ('A', 2),
      ('E', 3),
      ('B', 2),
    ];
    const flatOrderBass = [
      ('B', 2),
      ('E', 3),
      ('A', 2),
      ('D', 3),
      ('G', 2),
      ('C', 3),
      ('F', 2),
    ];
    const sharpOrderAlto = [
      ('F', 4),
      ('C', 4),
      ('G', 4),
      ('D', 4),
      ('A', 4),
      ('E', 4),
      ('B', 4),
    ];
    const flatOrderAlto = [
      ('B', 3),
      ('E', 4),
      ('A', 3),
      ('D', 4),
      ('G', 3),
      ('C', 4),
      ('F', 3),
    ];
    const sharpOrderTenor = [
      ('F', 3),
      ('C', 4),
      ('G', 3),
      ('D', 4),
      ('A', 3),
      ('E', 4),
      ('B', 3),
    ];
    const flatOrderTenor = [
      ('B', 3),
      ('E', 4),
      ('A', 3),
      ('D', 4),
      ('G', 3),
      ('C', 4),
      ('F', 3),
    ];

    final isBass = clefSign.toUpperCase() == 'F';
    final isAlto = clefSign.toUpperCase() == 'C' && clefLine == 3;
    final isTenor = clefSign.toUpperCase() == 'C' && clefLine == 4;
    final order = isSharp
        ? (isBass
              ? sharpOrderBass
              : isAlto
              ? sharpOrderAlto
              : isTenor
              ? sharpOrderTenor
              : sharpOrderTreble)
        : (isBass
              ? flatOrderBass
              : isAlto
              ? flatOrderAlto
              : isTenor
              ? flatOrderTenor
              : flatOrderTreble);

    // Baseline where the editor puts it: a line-height-1 box whose top is
    // 0.6 of the font size above the pitch.
    final size = ScoreNotationMetrics.keySignatureFontSize * _scale;
    final ascentShare = font.ascent / (font.ascent - font.descent);
    for (var i = 0; i < count; i++) {
      final pitch = order[i];
      final y = _yForPitch(
        step: pitch.$1,
        octave: pitch.$2,
        bottomLineY: staffBottom,
        // Written for the plain clef, as on screen.
        clefSign: clefSign[0],
        clefLine: clefLine,
      );
      _text(
        g,
        font,
        size,
        isSharp
            ? ScoreNotationMetrics.sharpGlyph
            : ScoreNotationMetrics.flatGlyph,
        x,
        y - size * (ascentShare - 0.6),
      );
      x += ScoreNotationMetrics.keySignatureSpacing * _scale;
    }
    return x;
  }

  // ── Time signature ─────────────────────────────────────────────────────────

  void _drawTimeSig(
    PdfGraphics g,
    PdfFont font,
    double x,
    double staffTop,
    TimeSignature signature,
  ) {
    final size = ScoreNotationMetrics.timeSignatureFontSize * _scale;
    if (signature.symbol case final symbol?) {
      // C or ¢ on the middle line, about two spaces tall (y points up; a
      // capital's middle sits about 0.35 of the size above the baseline).
      final mid = staffTop - 2 * _ls;
      _text(g, font, size * 1.35, 'C', x, mid - 0.35 * size * 1.35);
      if (symbol == TimeSymbol.cut) {
        final cx = x + font.stringMetrics('C').width * size * 1.35 / 2;
        _line(g, cx, mid + 2.6 * _ls, cx, mid - 2.6 * _ls, 1.2 * _scale);
      }
      return;
    }
    final beats = signature.beats, beatType = signature.beatType;
    _text(
      g,
      font,
      ScoreNotationMetrics.timeSignatureFontSize * _scale,
      '$beats',
      x,
      staffTop - 18 * _scale,
    );
    _text(
      g,
      font,
      ScoreNotationMetrics.timeSignatureFontSize * _scale,
      '$beatType',
      x,
      staffTop -
          ScoreNotationMetrics.timeSignatureBottomOffsetSpaces * _ls -
          18 * _scale,
    );
  }

  // ── Primitive helpers ──────────────────────────────────────────────────────

  void _line(
    PdfGraphics g,
    double x1,
    double y1,
    double x2,
    double y2,
    double w,
  ) {
    g.setColor(_ink);
    g.setLineWidth(w);
    g.moveTo(x1, y1);
    g.lineTo(x2, y2);
    g.strokePath();
  }

  void _text(
    PdfGraphics g,
    PdfFont font,
    double size,
    String text,
    double x,
    double y,
  ) {
    g.setColor(_ink);
    g.drawString(font, size, text, x, y);
  }

  void _drawFittedText(
    PdfGraphics g,
    PdfFont font,
    double preferredSize,
    String text,
    double left,
    double maxWidth,
    double y, {
    required _PdfTextAlign align,
    required double minSize,
  }) {
    final normalized = text.trim();
    if (normalized.isEmpty) return;

    var size = preferredSize;
    final unitWidth = font.stringMetrics(normalized).advanceWidth;
    if (unitWidth > 0) {
      size = math.min(preferredSize, math.max(minSize, maxWidth / unitWidth));
    }

    final fittedText = _truncateTextToWidth(font, normalized, size, maxWidth);
    if (fittedText.isEmpty) return;

    final width = _textWidth(font, size, fittedText);
    final x = switch (align) {
      _PdfTextAlign.left => left,
      _PdfTextAlign.center => left + (maxWidth - width) / 2,
      _PdfTextAlign.right => left + maxWidth - width,
    };
    _text(g, font, size, fittedText, x, y);
  }

  String _truncateTextToWidth(
    PdfFont font,
    String text,
    double size,
    double maxWidth,
  ) {
    if (_textWidth(font, size, text) <= maxWidth) return text;

    const suffix = '...';
    if (_textWidth(font, size, suffix) > maxWidth) return '';

    var low = 0;
    var high = text.length;
    while (low < high) {
      final mid = (low + high + 1) ~/ 2;
      final candidate = '${text.substring(0, mid).trimRight()}$suffix';
      if (_textWidth(font, size, candidate) <= maxWidth) {
        low = mid;
      } else {
        high = mid - 1;
      }
    }

    return '${text.substring(0, low).trimRight()}$suffix';
  }

  double _textWidth(PdfFont font, double size, String text) {
    return (font.stringMetrics(text) * size).advanceWidth;
  }

  static String _clefSign(List<Measure> measures) {
    for (final m in measures) {
      if (m.clef != null) return m.clef!.layoutSign;
    }
    return 'G';
  }

  static int _clefLine(List<Measure> measures) {
    for (final m in measures) {
      if (m.clef != null) return m.clef!.line;
    }
    return 2;
  }

  static String _headerTitle(Score score) {
    final title = score.title.trim();
    return title.isEmpty ? 'Untitled Score' : title;
  }

  static String _headerComposer(Score score) => score.composer.trim();
}

// ── Data class ────────────────────────────────────────────────────────────────

enum _PdfTextAlign { left, center, right }

class _PageData {
  const _PageData({
    required this.firstMeasureIndex,
    required this.measureCount,
    required this.measuresPerSystem,
    required this.rowsPerPage,
  });

  final int firstMeasureIndex;
  final int measureCount;
  final int measuresPerSystem;
  final int rowsPerPage;
}

class PdfHeaderLayoutInfo {
  const PdfHeaderLayoutInfo({
    required this.title,
    required this.composer,
    required this.firstPageStaffOffset,
    required this.headerTextBottom,
    required this.firstNotationTop,
  });

  final String title;
  final String composer;
  final double firstPageStaffOffset;
  final double headerTextBottom, firstNotationTop;
}

class PdfPageLayoutInfo {
  const PdfPageLayoutInfo({
    required this.firstMeasureIndex,
    required this.measureCount,
    required this.measuresPerSystem,
    required this.rowsPerPage,
  });

  final int firstMeasureIndex;
  final int measureCount;
  final int measuresPerSystem;
  final int rowsPerPage;
}

class _PdfPoint {
  const _PdfPoint(this.x, this.y);

  final double x;
  final double y;
}

/// A drawn note, for ties and slurs.
class _PdfNotePoint {
  const _PdfNotePoint({
    required this.x,
    required this.y,
    required this.stemUp,
    required this.rowTop,
    required this.rowStartX,
    required this.rowEndX,
    this.dynamic = false,
  });
  final double x, y, rowTop, rowStartX, rowEndX;
  final bool stemUp;

  /// Whether a dynamic is written under it.
  final bool dynamic;
}
