import 'package:flutter/material.dart';

import '../models/measure.dart';
import '../models/score.dart';
import 'score_notation/notation_layout.dart';
import 'score_notation/score_notation_painter.dart';

export 'score_notation/staff_pitch_mapper.dart';

/// Read-only sheet music renderer for a [Score] model.
///
/// Sprint 5 scope: rendering only (no editing interactions in this widget).
class ScoreNotationViewer extends StatefulWidget {
  const ScoreNotationViewer({
    super.key,
    required this.score,
    this.measuresPerRow = 4,
    this.minMeasureWidth = 140,
    this.rowHeight = 140,
    this.padding = const EdgeInsets.all(16),
    this.backgroundColor = const Color(0xFFF9FAFB),
  });

  final Score? score;
  final int measuresPerRow;
  final double minMeasureWidth;
  final double rowHeight;
  final EdgeInsets padding;
  final Color backgroundColor;

  @override
  State<ScoreNotationViewer> createState() => _ScoreNotationViewerState();
}

class _ScoreNotationViewerState extends State<ScoreNotationViewer> {
  final ScrollController _horizontalController = ScrollController();
  final NotationLayoutCalculator _layoutCalculator =
      const NotationLayoutCalculator();

  @override
  void dispose() {
    _horizontalController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final measures = _measuresFor(widget.score);

    if (measures.isEmpty) {
      return _EmptyNotationState(backgroundColor: widget.backgroundColor);
    }

    final layout = _layoutCalculator.calculate(
      measures: measures,
      measuresPerRow: widget.measuresPerRow,
      minMeasureWidth: widget.minMeasureWidth,
      rowHeight: widget.rowHeight,
      padding: widget.padding,
    );

    return _NotationCanvasFrame(
      backgroundColor: widget.backgroundColor,
      horizontalController: _horizontalController,
      size: layout.size,
      painter: ScoreNotationPainter(
        measures: measures,
        measuresPerRow: layout.measuresPerRow,
        minMeasureWidth: widget.minMeasureWidth,
        rowHeight: widget.rowHeight,
        padding: widget.padding,
        rowPrefixWidth: layout.rowPrefixWidth,
      ),
    );
  }

  List<Measure> _measuresFor(Score? score) {
    final part = (score?.parts.isNotEmpty ?? false) ? score!.parts.first : null;
    return part?.measures ?? const <Measure>[];
  }
}

class _NotationCanvasFrame extends StatelessWidget {
  const _NotationCanvasFrame({
    required this.backgroundColor,
    required this.horizontalController,
    required this.size,
    required this.painter,
  });

  final Color backgroundColor;
  final ScrollController horizontalController;
  final Size size;
  final CustomPainter painter;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFE5E7EB)),
      ),
      child: SingleChildScrollView(
        controller: horizontalController,
        scrollDirection: Axis.horizontal,
        child: CustomPaint(size: size, painter: painter),
      ),
    );
  }
}

class _EmptyNotationState extends StatelessWidget {
  const _EmptyNotationState({required this.backgroundColor});

  final Color backgroundColor;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFE5E7EB)),
      ),
      child: const Text(
        'No notation to display.',
        style: TextStyle(
          color: Color(0xFF6B7280),
          fontSize: 13,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }
}
