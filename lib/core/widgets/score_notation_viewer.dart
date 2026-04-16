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
    this.playbackPartIndex,
    this.playbackMeasureIndex,
    this.playbackSymbolIndex,
    this.verticalScrollController,
    this.insertMode = false,
    this.onSymbolTap,
    this.onInsertTap,
    this.onDragStarted,
    this.onDragGlobalUpdate,
    this.onDragCompleted,
    this.onDragCancelled,
    this.canAcceptExternalDrop,
    this.onExternalDrop,
    this.externalPreviewResolver,
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

  /// Currently playing symbol coordinates from PlaybackService.
  /// All three must be non-null for the playback highlight to render.
  final int? playbackPartIndex;
  final int? playbackMeasureIndex;
  final int? playbackSymbolIndex;

  /// When provided, the viewer animates this controller vertically (in addition
  /// to its own internal horizontal controller) to keep the active note centred
  /// in the viewport during playback.
  final ScrollController? verticalScrollController;

  /// When true, taps resolve to [NotationInsertTarget] via [onInsertTap]
  /// instead of the normal symbol-selection [onSymbolTap].
  final bool insertMode;
  final ValueChanged<NotationSymbolTarget?>? onSymbolTap;
  final ValueChanged<NotationInsertTarget?>? onInsertTap;

  /// Called when a long-press drag begins on a symbol.
  final void Function(NotationSymbolTarget symbol)? onDragStarted;

  /// Called on every drag move with the global screen position.
  /// Use to drive trash-zone hover state.
  final void Function(Offset global)? onDragGlobalUpdate;

  /// Called when the drag ends. [reorder] is non-null if the drag moved the
  /// symbol to a new position. [globalEndPosition] lets the caller decide
  /// whether the drop landed on a delete zone.
  final void Function(NotationSymbolReorder? reorder, Offset globalEndPosition)? onDragCompleted;

  /// Called when a drag is cancelled (e.g. interrupted by a system event).
  final VoidCallback? onDragCancelled;

  final bool Function(Object data)? canAcceptExternalDrop;
  final void Function(NotationInsertTarget target, Object data)? onExternalDrop;
  final NotationPreviewGlyph? Function(Object data)? externalPreviewResolver;

  @override
  State<ScoreNotationViewer> createState() => _ScoreNotationViewerState();
}

class _ScoreNotationViewerState extends State<ScoreNotationViewer> {
  final ScrollController _horizontalController = ScrollController();
  final NotationLayoutCalculator _layoutCalculator =
      const NotationLayoutCalculator();
  _NotationDragSession? _dragSession;
  NotationInsertTarget? _crossMeasureDragTarget;
  NotationInsertTarget? _externalInsertTarget;
  NotationPreviewGlyph? _externalPreviewGlyph;

  @override
  void dispose() {
    _horizontalController.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(ScoreNotationViewer oldWidget) {
    super.didUpdateWidget(oldWidget);
    final posChanged =
        widget.playbackPartIndex != oldWidget.playbackPartIndex ||
        widget.playbackMeasureIndex != oldWidget.playbackMeasureIndex ||
        widget.playbackSymbolIndex != oldWidget.playbackSymbolIndex;
    if (posChanged && widget.playbackPartIndex != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _scrollToPlaybackPosition();
      });
    }
  }

  void _scrollToPlaybackPosition() {
    final pIdx = widget.playbackPartIndex;
    final mIdx = widget.playbackMeasureIndex;
    final sIdx = widget.playbackSymbolIndex;
    if (pIdx == null || mIdx == null || sIdx == null) return;

    final allParts = _partsFor(widget.score);
    if (allParts.isEmpty) return;

    final layout = _layoutCalculator.calculate(
      measures: _measuresFor(widget.score),
      measuresPerRow: widget.measuresPerRow,
      minMeasureWidth: widget.minMeasureWidth,
      rowHeight: widget.rowHeight,
      padding: widget.padding,
      partCount: allParts.length,
    );

    final targets = ScoreNotationPainter.buildSymbolTargets(
      parts: allParts,
      measuresPerRow: layout.measuresPerRow,
      minMeasureWidth: widget.minMeasureWidth,
      rowHeight: widget.rowHeight,
      padding: widget.padding,
      rowPrefixWidth: layout.rowPrefixWidth,
    );

    NotationSymbolTarget? match;
    for (final t in targets) {
      if (t.partIndex == pIdx && t.measureIndex == mIdx && t.symbolIndex == sIdx) {
        match = t;
        break;
      }
    }
    if (match == null) return;

    const duration = Duration(milliseconds: 300);
    const curve = Curves.easeInOut;

    if (_horizontalController.hasClients) {
      final vw = _horizontalController.position.viewportDimension;
      final maxH = _horizontalController.position.maxScrollExtent;
      final hTarget = (match.center.dx - vw / 2).clamp(0.0, maxH);
      _horizontalController.animateTo(hTarget, duration: duration, curve: curve);
    }

    final vCtrl = widget.verticalScrollController;
    if (vCtrl != null && vCtrl.hasClients) {
      final vh = vCtrl.position.viewportDimension;
      final maxV = vCtrl.position.maxScrollExtent;
      final vTarget = (match.center.dy - vh / 2).clamp(0.0, maxV);
      vCtrl.animateTo(vTarget, duration: duration, curve: curve);
    }
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
        final target = _resolveInsertTarget(allParts: allParts, layout: layout, position: adjusted);
        final previewGlyph = target == null ? null : widget.externalPreviewResolver?.call(data);
        if (target == _externalInsertTarget && previewGlyph == _externalPreviewGlyph) return;
        setState(() {
          _externalInsertTarget = target;
          _externalPreviewGlyph = previewGlyph;
        });
      },
      onExternalDragLeave: () {
        if (_externalInsertTarget == null && _externalPreviewGlyph == null) return;
        setState(() {
          _externalInsertTarget = null;
          _externalPreviewGlyph = null;
        });
      },
      onExternalAccept: (position, data) {
        if (widget.canAcceptExternalDrop?.call(data) == false) return;
        final adjusted = _adjustForHorizontalScroll(position);
        final target = _resolveInsertTarget(allParts: allParts, layout: layout, position: adjusted);
        if (target != null) widget.onExternalDrop?.call(target, data);
        if (_externalInsertTarget != null || _externalPreviewGlyph != null) {
          setState(() {
            _externalInsertTarget = null;
            _externalPreviewGlyph = null;
          });
        }
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
                  allParts: allParts,
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
      onLongPressStart: widget.onDragCompleted == null
          ? null
          : (position) => _beginDrag(allParts: allParts, layout: layout, position: position),
      onLongPressMoveUpdate: widget.onDragCompleted == null
          ? null
          : (local, global) {
              _updateDrag(allParts: allParts, layout: layout, position: local);
              widget.onDragGlobalUpdate?.call(global);
            },
      onLongPressEnd: widget.onDragCompleted == null
          ? null
          : (local, global) =>
              _endDrag(allParts: allParts, layout: layout, localPosition: local, globalPosition: global),
      onLongPressCancel: widget.onDragCompleted == null ? null : _cancelDrag,
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
        playbackPartIndex: widget.playbackPartIndex,
        playbackMeasureIndex: widget.playbackMeasureIndex,
        playbackSymbolIndex: widget.playbackSymbolIndex,
        dragFeedback: _dragSession == null ||
                _dragSession!.toPartIndex != _dragSession!.fromPartIndex ||
                _dragSession!.toMeasureIndex != _dragSession!.fromMeasureIndex
            ? null
            : NotationDragFeedback(
                measureIndex: _dragSession!.fromMeasureIndex,
                draggedSymbolIndex: _dragSession!.fromSymbolIndex,
                targetSymbolIndex: _dragSession!.toSymbolIndex,
                dragX: _dragSession!.dragPosition.dx,
              ),
        insertionTarget: _externalInsertTarget ?? _crossMeasureDragTarget,
        insertionPreviewGlyph: _externalPreviewGlyph,
      ),
    );
  }

  void _beginDrag({
    required List<List<Measure>> allParts,
    required NotationLayout layout,
    required Offset position,
  }) {
    final adjusted = _adjustForHorizontalScroll(position);
    final targets = ScoreNotationPainter.buildSymbolTargets(
      parts: allParts,
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
        fromPartIndex: pressed.partIndex,
        fromMeasureIndex: pressed.measureIndex,
        fromSymbolIndex: pressed.symbolIndex,
        toPartIndex: pressed.partIndex,
        toMeasureIndex: pressed.measureIndex,
        toSymbolIndex: pressed.symbolIndex,
        dragPosition: adjusted,
      );
    });
    widget.onDragStarted?.call(
      NotationSymbolTarget(
        partIndex: pressed.partIndex,
        measureIndex: pressed.measureIndex,
        symbolIndex: pressed.symbolIndex,
        center: pressed.center,
        hitRect: pressed.hitRect,
      ),
    );
  }

  void _updateDrag({
    required List<List<Measure>> allParts,
    required NotationLayout layout,
    required Offset position,
  }) {
    final drag = _dragSession;
    if (drag == null) return;
    final adjusted = _adjustForHorizontalScroll(position);

    final insertTarget = _resolveInsertTarget(
      allParts: allParts,
      layout: layout,
      position: adjusted,
    );

    int toPartIndex = drag.toPartIndex;
    int toMeasureIndex = drag.toMeasureIndex;
    int toSymbolIndex = drag.toSymbolIndex;
    NotationInsertTarget? crossMeasureTarget;

    if (insertTarget != null) {
      toPartIndex = insertTarget.partIndex;
      toMeasureIndex = insertTarget.measureIndex;
      final sameMeasure = insertTarget.partIndex == drag.fromPartIndex &&
          insertTarget.measureIndex == drag.fromMeasureIndex;
      if (sameMeasure) {
        final idx = _targetIndexForDrag(
          measures: allParts[drag.fromPartIndex],
          layout: layout,
          measureIndex: drag.fromMeasureIndex,
          fromSymbolIndex: drag.fromSymbolIndex,
          dragPosition: adjusted,
        );
        toSymbolIndex = idx ?? drag.fromSymbolIndex;
      } else {
        toSymbolIndex = insertTarget.insertIndex;
        crossMeasureTarget = insertTarget;
      }
    }

    setState(() {
      _dragSession = drag.copyWith(
        toPartIndex: toPartIndex,
        toMeasureIndex: toMeasureIndex,
        toSymbolIndex: toSymbolIndex,
        dragPosition: adjusted,
      );
      _crossMeasureDragTarget = crossMeasureTarget;
    });
  }

  void _endDrag({
    required List<List<Measure>> allParts,
    required NotationLayout layout,
    required Offset localPosition,
    required Offset globalPosition,
  }) {
    final drag = _dragSession;
    if (drag == null) return;
    final adjusted = _adjustForHorizontalScroll(localPosition);

    final insertTarget = _resolveInsertTarget(
      allParts: allParts,
      layout: layout,
      position: adjusted,
    );

    int toPartIndex = drag.toPartIndex;
    int toMeasureIndex = drag.toMeasureIndex;
    int toSymbolIndex = drag.toSymbolIndex;

    if (insertTarget != null) {
      toPartIndex = insertTarget.partIndex;
      toMeasureIndex = insertTarget.measureIndex;
      final sameMeasure = insertTarget.partIndex == drag.fromPartIndex &&
          insertTarget.measureIndex == drag.fromMeasureIndex;
      if (sameMeasure) {
        final idx = _targetIndexForDrag(
          measures: allParts[drag.fromPartIndex],
          layout: layout,
          measureIndex: drag.fromMeasureIndex,
          fromSymbolIndex: drag.fromSymbolIndex,
          dragPosition: adjusted,
        );
        toSymbolIndex = idx ?? drag.fromSymbolIndex;
      } else {
        toSymbolIndex = insertTarget.insertIndex;
      }
    }

    final isSamePosition = toPartIndex == drag.fromPartIndex &&
        toMeasureIndex == drag.fromMeasureIndex &&
        toSymbolIndex == drag.fromSymbolIndex;

    final reorder = !isSamePosition
        ? NotationSymbolReorder(
            fromPartIndex: drag.fromPartIndex,
            fromMeasureIndex: drag.fromMeasureIndex,
            fromSymbolIndex: drag.fromSymbolIndex,
            toPartIndex: toPartIndex,
            toMeasureIndex: toMeasureIndex,
            toSymbolIndex: toSymbolIndex,
          )
        : null;

    widget.onDragCompleted?.call(reorder, globalPosition);

    setState(() {
      _dragSession = null;
      _crossMeasureDragTarget = null;
    });
  }

  void _cancelDrag() {
    if (_dragSession == null) return;
    setState(() {
      _dragSession = null;
      _crossMeasureDragTarget = null;
    });
    widget.onDragCancelled?.call();
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
    required List<List<Measure>> allParts,
    required NotationLayout layout,
    required Offset position,
  }) {
    if (allParts.isEmpty) return null;
    final partCount = allParts.length;
    final rowCount = (allParts[0].length / layout.measuresPerRow).ceil();
    final contentStartX = widget.padding.left + layout.rowPrefixWidth;
    const innerPadding = 16.0;

    for (var systemIndex = 0; systemIndex < rowCount; systemIndex++) {
      for (var partIdx = 0; partIdx < partCount; partIdx++) {
        final measures = allParts[partIdx];
        final rowStartMeasure = systemIndex * layout.measuresPerRow;
        final rowEndExclusive =
            (rowStartMeasure + layout.measuresPerRow).clamp(0, measures.length).toInt();
        if (rowStartMeasure >= rowEndExclusive) continue;

        // Each system row is partCount * rowHeight tall; staves are stacked within.
        final staffTop = widget.padding.top +
            systemIndex * (partCount * widget.rowHeight) +
            partIdx * widget.rowHeight +
            28;
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
            partIndex: partIdx,
            measureIndex: absoluteMeasureIndex,
            insertIndex: insertIndex,
            indicatorX: indicatorX,
            step: pitch.step,
            octave: pitch.octave,
          );
        }
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
  final void Function(Offset local, Offset global)? onLongPressMoveUpdate;
  final void Function(Offset local, Offset global)? onLongPressEnd;
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
            : (details) => onLongPressMoveUpdate!(details.localPosition, details.globalPosition),
        onLongPressEnd: onLongPressEnd == null
            ? null
            : (details) => onLongPressEnd!(details.localPosition, details.globalPosition),
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
    required this.fromPartIndex,
    required this.fromMeasureIndex,
    required this.fromSymbolIndex,
    required this.toPartIndex,
    required this.toMeasureIndex,
    required this.toSymbolIndex,
  });

  final int fromPartIndex;
  final int fromMeasureIndex;
  final int fromSymbolIndex;
  final int toPartIndex;
  final int toMeasureIndex;
  final int toSymbolIndex;
}

class _NotationDragSession {
  const _NotationDragSession({
    required this.fromPartIndex,
    required this.fromMeasureIndex,
    required this.fromSymbolIndex,
    required this.toPartIndex,
    required this.toMeasureIndex,
    required this.toSymbolIndex,
    required this.dragPosition,
  });

  final int fromPartIndex;
  final int fromMeasureIndex;
  final int fromSymbolIndex;
  final int toPartIndex;
  final int toMeasureIndex;
  final int toSymbolIndex;
  final Offset dragPosition;

  _NotationDragSession copyWith({
    int? toPartIndex,
    int? toMeasureIndex,
    int? toSymbolIndex,
    Offset? dragPosition,
  }) {
    return _NotationDragSession(
      fromPartIndex: fromPartIndex,
      fromMeasureIndex: fromMeasureIndex,
      fromSymbolIndex: fromSymbolIndex,
      toPartIndex: toPartIndex ?? this.toPartIndex,
      toMeasureIndex: toMeasureIndex ?? this.toMeasureIndex,
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
