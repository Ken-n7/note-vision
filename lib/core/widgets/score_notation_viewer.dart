import 'package:flutter/material.dart';

import '../models/measure.dart';
import '../models/score.dart';
import 'score_notation/notation_layout.dart';
import 'score_notation/score_notation_painter.dart';
import 'score_notation/staff_pitch_mapper.dart';

export 'score_notation/staff_pitch_mapper.dart';

/// Read-only sheet music renderer for a [Score] model.
///
/// Sprint 5 scope: rendering only (no editing interactions in this widget).
class ScoreNotationViewer extends StatefulWidget {
  const ScoreNotationViewer({
    super.key,
    required this.score,
    this.selectedPartIndex = 0,
    this.measuresPerRow = 4,
    this.minMeasureWidth = 140,
    this.rowHeight = 140,
    this.padding = const EdgeInsets.all(16),
    this.backgroundColor = const Color(0xFFF9FAFB),
    this.selectedMeasureIndex,
    this.selectedSymbolIndex,
    this.insertMode = false,
    this.onSymbolTap,
    this.onInsertTap,
    this.onSymbolReorder,
    this.canAcceptExternalDrop,
    this.onExternalDrop,
  });

  final Score? score;
  /// Which part index is active for editing/selection. All parts are displayed.
  final int selectedPartIndex;
  final int measuresPerRow;
  final double minMeasureWidth;
  final double rowHeight;
  final EdgeInsets padding;
  final Color backgroundColor;
  final int? selectedMeasureIndex;
  final int? selectedSymbolIndex;
  /// When true, taps resolve to [NotationInsertTarget] via [onInsertTap]
  /// instead of the normal symbol-selection [onSymbolTap].
  final bool insertMode;
  final ValueChanged<NotationSymbolTarget?>? onSymbolTap;
  final ValueChanged<NotationInsertTarget?>? onInsertTap;
  final ValueChanged<NotationSymbolReorder>? onSymbolReorder;
  final bool Function(Object data)? canAcceptExternalDrop;
  final void Function(NotationInsertTarget target, Object data)? onExternalDrop;

  @override
  State<ScoreNotationViewer> createState() => _ScoreNotationViewerState();
}

class _ScoreNotationViewerState extends State<ScoreNotationViewer> {
  final ScrollController _horizontalController = ScrollController();
  final NotationLayoutCalculator _layoutCalculator =
      const NotationLayoutCalculator();
  _NotationDragSession? _dragSession;
  NotationInsertTarget? _externalInsertTarget;

  @override
  void dispose() {
    _horizontalController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final allParts = _partsFor(widget.score);
    // Use the active part's measures for insert/drag interactions.
    final activeMeasures = _measuresFor(widget.score);

    if (allParts.isEmpty) {
      return _EmptyNotationState(backgroundColor: widget.backgroundColor);
    }

    final partCount = allParts.length;
    final layout = _layoutCalculator.calculate(
      measures: activeMeasures,
      measuresPerRow: widget.measuresPerRow,
      minMeasureWidth: widget.minMeasureWidth,
      rowHeight: widget.rowHeight,
      padding: widget.padding,
      partCount: partCount,
    );

    return _NotationCanvasFrame(
      backgroundColor: widget.backgroundColor,
      horizontalController: _horizontalController,
      size: layout.size,
      canAcceptExternalData: widget.canAcceptExternalDrop,
      onExternalDragMove: (position, data) {
        if (widget.canAcceptExternalDrop?.call(data) == false) return;
        final adjusted = _adjustForHorizontalScroll(position);
        final target = _resolveInsertTarget(measures: activeMeasures, layout: layout, position: adjusted);
        if (target == _externalInsertTarget) return;
        setState(() => _externalInsertTarget = target);
      },
      onExternalDragLeave: () {
        if (_externalInsertTarget == null) return;
        setState(() => _externalInsertTarget = null);
      },
      onExternalAccept: (position, data) {
        if (widget.canAcceptExternalDrop?.call(data) == false) return;
        final adjusted = _adjustForHorizontalScroll(position);
        final target = _resolveInsertTarget(measures: activeMeasures, layout: layout, position: adjusted);
        if (target != null) widget.onExternalDrop?.call(target, data);
        if (_externalInsertTarget != null) setState(() => _externalInsertTarget = null);
      },
      onTapUp: (widget.onSymbolTap == null && widget.onInsertTap == null)
          ? null
          : (position) {
              final adjusted = position.translate(
                _horizontalController.hasClients ? _horizontalController.offset : 0,
                0,
              );
              if (widget.insertMode) {
                final target = _resolveInsertTarget(
                  measures: activeMeasures,
                  layout: layout,
                  position: adjusted,
                );
                widget.onInsertTap?.call(target);
              } else {
                final targets = ScoreNotationPainter.buildSymbolTargets(
                  parts: allParts,
                  measuresPerRow: layout.measuresPerRow,
                  minMeasureWidth: widget.minMeasureWidth,
                  rowHeight: widget.rowHeight,
                  padding: widget.padding,
                  rowPrefixWidth: layout.rowPrefixWidth,
                );
                final tapped = _nearestTarget(adjusted, targets);
                widget.onSymbolTap?.call(tapped);
              }
            },
      onLongPressStart: widget.onSymbolReorder == null
          ? null
          : (position) => _beginDrag(measures: activeMeasures, layout: layout, position: position),
      onLongPressMoveUpdate: widget.onSymbolReorder == null
          ? null
          : (position) => _updateDrag(measures: activeMeasures, layout: layout, position: position),
      onLongPressEnd: widget.onSymbolReorder == null
          ? null
          : (position) => _endDrag(measures: activeMeasures, layout: layout, position: position),
      onLongPressCancel: widget.onSymbolReorder == null ? null : _cancelDrag,
      painter: ScoreNotationPainter(
        parts: allParts,
        measuresPerRow: layout.measuresPerRow,
        minMeasureWidth: widget.minMeasureWidth,
        rowHeight: widget.rowHeight,
        padding: widget.padding,
        rowPrefixWidth: layout.rowPrefixWidth,
        selectedPartIndex: widget.selectedPartIndex,
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
        insertionTarget: _externalInsertTarget,
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
      parts: [measures],
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
      parts: [measures],
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

  NotationInsertTarget? _resolveInsertTarget({
    required List<Measure> measures,
    required NotationLayout layout,
    required Offset position,
  }) {
    final rowCount = (measures.length / layout.measuresPerRow).ceil();
    final contentStartX = widget.padding.left + layout.rowPrefixWidth;
    const innerPadding = 16.0;

    for (var rowIndex = 0; rowIndex < rowCount; rowIndex++) {
      final rowStartMeasure = rowIndex * layout.measuresPerRow;
      final rowEndExclusive =
          (rowStartMeasure + layout.measuresPerRow).clamp(0, measures.length).toInt();
      if (rowStartMeasure >= rowEndExclusive) continue;

      final staffTop = widget.padding.top + rowIndex * widget.rowHeight + 28;
      final staffBottom = staffTop + ScoreNotationPainter.staffLineSpacing * 4;
      if (position.dy < staffTop - 28 || position.dy > staffBottom + 28) continue;

      for (var measureInRow = 0; measureInRow < rowEndExclusive - rowStartMeasure; measureInRow++) {
        final absoluteMeasureIndex = rowStartMeasure + measureInRow;
        final measureStartX = contentStartX + (measureInRow * widget.minMeasureWidth);
        final measureEndX = measureStartX + widget.minMeasureWidth;
        if (position.dx < measureStartX || position.dx > measureEndX) continue;

        final measure = measures[absoluteMeasureIndex];
        final drawableWidth = ((measureEndX - measureStartX) - (innerPadding * 2))
            .clamp(12.0, double.infinity)
            .toDouble();
        final clampedX = position.dx
            .clamp(measureStartX + innerPadding, measureEndX - innerPadding)
            .toDouble();
        final symbolCount = measure.symbols.length;
        var insertIndex = 0;

        for (var i = 0; i < symbolCount; i++) {
          final progress = (i + 1) / (symbolCount + 1);
          final symbolX = measureStartX + innerPadding + (drawableWidth * progress);
          if (clampedX > symbolX) insertIndex++;
        }

        final indicatorProgress = (insertIndex + 1) / (symbolCount + 2);
        final indicatorX = measureStartX + innerPadding + (drawableWidth * indicatorProgress);
        final clefSign = measure.clef?.sign ?? 'G';
        final pitch = StaffPitchMapper.pitchForY(
          y: position.dy,
          bottomLineY: staffBottom,
          lineSpacing: ScoreNotationPainter.staffLineSpacing,
          clefSign: clefSign,
        );

        return NotationInsertTarget(
          measureIndex: absoluteMeasureIndex,
          insertIndex: insertIndex,
          indicatorX: indicatorX,
          step: pitch.step,
          octave: pitch.octave,
        );
      }
    }
    return null;
  }

  /// All parts for display — passed to the painter to render every staff.
  List<List<Measure>> _partsFor(Score? score) {
    if (score == null || score.parts.isEmpty) return const [];
    return score.parts.map((p) => p.measures).toList(growable: false);
  }

  /// Active part's measures — used for insert/drag interactions only.
  List<Measure> _measuresFor(Score? score) {
    if (score == null || score.parts.isEmpty || widget.selectedPartIndex >= score.parts.length) {
      return const <Measure>[];
    }
    return score.parts[widget.selectedPartIndex].measures;
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
    this.canAcceptExternalData,
    this.onExternalDragMove,
    this.onExternalDragLeave,
    this.onExternalAccept,
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
  final bool Function(Object data)? canAcceptExternalData;
  final void Function(Offset position, Object data)? onExternalDragMove;
  final VoidCallback? onExternalDragLeave;
  final void Function(Offset position, Object data)? onExternalAccept;

  @override
  Widget build(BuildContext context) {
    final canvas = Container(
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

    if (canAcceptExternalData == null) return canvas;

    return DragTarget<Object>(
      onWillAcceptWithDetails: (details) =>
          canAcceptExternalData?.call(details.data) ?? false,
      onMove: (details) {
        if (onExternalDragMove == null) return;
        final box = context.findRenderObject() as RenderBox?;
        if (box == null) return;
        onExternalDragMove!(box.globalToLocal(details.offset), details.data);
      },
      onLeave: (_) => onExternalDragLeave?.call(),
      onAcceptWithDetails: (details) {
        if (onExternalAccept == null) return;
        final box = context.findRenderObject() as RenderBox?;
        if (box == null) return;
        onExternalAccept!(box.globalToLocal(details.offset), details.data);
      },
      builder: (context, _, _) => canvas,
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
