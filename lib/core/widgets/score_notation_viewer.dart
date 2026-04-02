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
    this.selectedMeasureIndex,
    this.selectedSymbolIndex,
    this.onSymbolTap,
    this.onSymbolReorder,
    this.insertionFeedback,
    this.onHorizontalScrollOffsetChanged,
  });

  final Score? score;
  final int measuresPerRow;
  final double minMeasureWidth;
  final double rowHeight;
  final EdgeInsets padding;
  final Color backgroundColor;
  final int? selectedMeasureIndex;
  final int? selectedSymbolIndex;
  final ValueChanged<NotationSymbolTarget?>? onSymbolTap;
  final ValueChanged<NotationSymbolReorder>? onSymbolReorder;
  final NotationInsertionFeedback? insertionFeedback;
  final ValueChanged<double>? onHorizontalScrollOffsetChanged;

  @override
  State<ScoreNotationViewer> createState() => _ScoreNotationViewerState();
}

class _ScoreNotationViewerState extends State<ScoreNotationViewer> {
  final ScrollController _horizontalController = ScrollController();
  final NotationLayoutCalculator _layoutCalculator =
      const NotationLayoutCalculator();
  _NotationDragSession? _dragSession;

  @override
  void initState() {
    super.initState();
    _horizontalController.addListener(_notifyHorizontalOffset);
  }

  @override
  void dispose() {
    _horizontalController.removeListener(_notifyHorizontalOffset);
    _horizontalController.dispose();
    super.dispose();
  }

  void _notifyHorizontalOffset() {
    widget.onHorizontalScrollOffsetChanged?.call(_horizontalController.offset);
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
      onTapUp: widget.onSymbolTap == null
          ? null
          : (position) {
              final adjusted = position.translate(
                _horizontalController.hasClients ? _horizontalController.offset : 0,
                0,
              );
              final targets = ScoreNotationPainter.buildSymbolTargets(
                measures: measures,
                measuresPerRow: layout.measuresPerRow,
                minMeasureWidth: widget.minMeasureWidth,
                rowHeight: widget.rowHeight,
                padding: widget.padding,
                rowPrefixWidth: layout.rowPrefixWidth,
              );
              final tapped = _nearestTarget(adjusted, targets);
              widget.onSymbolTap?.call(tapped);
            },
      onLongPressStart: widget.onSymbolReorder == null
          ? null
          : (position) => _beginDrag(measures: measures, layout: layout, position: position),
      onLongPressMoveUpdate: widget.onSymbolReorder == null
          ? null
          : (position) => _updateDrag(measures: measures, layout: layout, position: position),
      onLongPressEnd: widget.onSymbolReorder == null
          ? null
          : (position) => _endDrag(measures: measures, layout: layout, position: position),
      onLongPressCancel: widget.onSymbolReorder == null ? null : _cancelDrag,
      painter: ScoreNotationPainter(
        measures: measures,
        measuresPerRow: layout.measuresPerRow,
        minMeasureWidth: widget.minMeasureWidth,
        rowHeight: widget.rowHeight,
        padding: widget.padding,
        rowPrefixWidth: layout.rowPrefixWidth,
        selectedMeasureIndex: widget.selectedMeasureIndex,
        selectedSymbolIndex: widget.selectedSymbolIndex,
        dragFeedback: _dragSession == null
            ? null
            : NotationDragFeedback(
                measureIndex: _dragSession!.measureIndex,
                draggedSymbolIndex: _dragSession!.fromSymbolIndex,
                targetSymbolIndex: _dragSession!.toSymbolIndex,
                dragX: _dragSession!.dragPosition.dx,
              ),
        insertionFeedback: widget.insertionFeedback,
      ),
    );
  }

  void _beginDrag({
    required List<Measure> measures,
    required NotationLayout layout,
    required Offset position,
  }) {
    final adjusted = _adjustForHorizontalScroll(position);
    final targets = ScoreNotationPainter.buildSymbolTargets(
      measures: measures,
      measuresPerRow: layout.measuresPerRow,
      minMeasureWidth: widget.minMeasureWidth,
      rowHeight: widget.rowHeight,
      padding: widget.padding,
      rowPrefixWidth: layout.rowPrefixWidth,
    );
    final pressed = _nearestTarget(adjusted, targets);
    if (pressed == null) return;

    setState(() {
      _dragSession = _NotationDragSession(
        measureIndex: pressed.measureIndex,
        fromSymbolIndex: pressed.symbolIndex,
        toSymbolIndex: pressed.symbolIndex,
        dragPosition: adjusted,
      );
    });
  }

  void _updateDrag({
    required List<Measure> measures,
    required NotationLayout layout,
    required Offset position,
  }) {
    final drag = _dragSession;
    if (drag == null) return;
    final adjusted = _adjustForHorizontalScroll(position);
    final toIndex = _targetIndexForDrag(
      measures: measures,
      layout: layout,
      measureIndex: drag.measureIndex,
      fromSymbolIndex: drag.fromSymbolIndex,
      dragPosition: adjusted,
    );
    if (toIndex == null) return;

    setState(() {
      _dragSession = drag.copyWith(toSymbolIndex: toIndex, dragPosition: adjusted);
    });
  }

  void _endDrag({
    required List<Measure> measures,
    required NotationLayout layout,
    required Offset position,
  }) {
    final drag = _dragSession;
    if (drag == null) return;
    final adjusted = _adjustForHorizontalScroll(position);
    final toIndex = _targetIndexForDrag(
      measures: measures,
      layout: layout,
      measureIndex: drag.measureIndex,
      fromSymbolIndex: drag.fromSymbolIndex,
      dragPosition: adjusted,
    );
    final resolvedIndex = toIndex ?? drag.toSymbolIndex;

    if (resolvedIndex != drag.fromSymbolIndex) {
      widget.onSymbolReorder?.call(
        NotationSymbolReorder(
          measureIndex: drag.measureIndex,
          fromSymbolIndex: drag.fromSymbolIndex,
          toSymbolIndex: resolvedIndex,
        ),
      );
    }

    setState(() {
      _dragSession = null;
    });
  }

  void _cancelDrag() {
    if (_dragSession == null) return;
    setState(() {
      _dragSession = null;
    });
  }

  int? _targetIndexForDrag({
    required List<Measure> measures,
    required NotationLayout layout,
    required int measureIndex,
    required int fromSymbolIndex,
    required Offset dragPosition,
  }) {
    if (measureIndex < 0 || measureIndex >= measures.length) return null;
    final symbolCount = measures[measureIndex].symbols.length;
    if (symbolCount <= 1 || fromSymbolIndex < 0 || fromSymbolIndex >= symbolCount) {
      return null;
    }

    final targets = ScoreNotationPainter.buildSymbolTargets(
      measures: measures,
      measuresPerRow: layout.measuresPerRow,
      minMeasureWidth: widget.minMeasureWidth,
      rowHeight: widget.rowHeight,
      padding: widget.padding,
      rowPrefixWidth: layout.rowPrefixWidth,
    ).where((target) => target.measureIndex == measureIndex && target.symbolIndex != fromSymbolIndex);

    var insertIndex = 0;
    for (final target in targets) {
      if (dragPosition.dx > target.center.dx) {
        insertIndex++;
      }
    }
    return insertIndex.clamp(0, symbolCount - 1);
  }

  Offset _adjustForHorizontalScroll(Offset position) {
    return position.translate(
      _horizontalController.hasClients ? _horizontalController.offset : 0,
      0,
    );
  }

  NotationSymbolTarget? _nearestTarget(
    Offset position,
    List<NotationSymbolTarget> targets,
  ) {
    NotationSymbolTarget? best;
    double? bestDistance;
    for (final target in targets) {
      if (!target.hitRect.contains(position)) continue;
      final distance = (target.center - position).distanceSquared;
      if (best == null || distance < bestDistance!) {
        best = target;
        bestDistance = distance;
      }
    }
    return best;
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
    this.onTapUp,
    this.onLongPressStart,
    this.onLongPressMoveUpdate,
    this.onLongPressEnd,
    this.onLongPressCancel,
  });

  final Color backgroundColor;
  final ScrollController horizontalController;
  final Size size;
  final CustomPainter painter;
  final ValueChanged<Offset>? onTapUp;
  final ValueChanged<Offset>? onLongPressStart;
  final ValueChanged<Offset>? onLongPressMoveUpdate;
  final ValueChanged<Offset>? onLongPressEnd;
  final VoidCallback? onLongPressCancel;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFE5E7EB)),
      ),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapUp: onTapUp == null ? null : (details) => onTapUp!(details.localPosition),
        onLongPressStart: onLongPressStart == null
            ? null
            : (details) => onLongPressStart!(details.localPosition),
        onLongPressMoveUpdate: onLongPressMoveUpdate == null
            ? null
            : (details) => onLongPressMoveUpdate!(details.localPosition),
        onLongPressEnd:
            onLongPressEnd == null ? null : (details) => onLongPressEnd!(details.localPosition),
        onLongPressCancel: onLongPressCancel,
        child: SingleChildScrollView(
          controller: horizontalController,
          scrollDirection: Axis.horizontal,
          child: CustomPaint(size: size, painter: painter),
        ),
      ),
    );
  }
}

class NotationSymbolReorder {
  const NotationSymbolReorder({
    required this.measureIndex,
    required this.fromSymbolIndex,
    required this.toSymbolIndex,
  });

  final int measureIndex;
  final int fromSymbolIndex;
  final int toSymbolIndex;
}

class _NotationDragSession {
  const _NotationDragSession({
    required this.measureIndex,
    required this.fromSymbolIndex,
    required this.toSymbolIndex,
    required this.dragPosition,
  });

  final int measureIndex;
  final int fromSymbolIndex;
  final int toSymbolIndex;
  final Offset dragPosition;

  _NotationDragSession copyWith({
    int? toSymbolIndex,
    Offset? dragPosition,
  }) {
    return _NotationDragSession(
      measureIndex: measureIndex,
      fromSymbolIndex: fromSymbolIndex,
      toSymbolIndex: toSymbolIndex ?? this.toSymbolIndex,
      dragPosition: dragPosition ?? this.dragPosition,
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
