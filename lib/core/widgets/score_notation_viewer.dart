import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/clef.dart';
import '../models/key_signature.dart';
import '../models/measure.dart';
import '../models/note.dart';
import '../models/score.dart';
import '../models/time_signature.dart';
import 'score_notation/notation_layout.dart';
import 'score_notation/score_notation_metrics.dart';
import 'score_notation/score_notation_painter.dart';
import 'score_notation/staff_pitch_mapper.dart';

export 'score_notation/staff_pitch_mapper.dart';

/// A page slice with the active clef, key, and meter carried into each measure.
List<Measure> sliceMeasuresWithInheritedMetadata({
  required List<Measure> measures,
  required int firstMeasureIndex,
  int? pageMeasureCount,
}) {
  final start = firstMeasureIndex.clamp(0, measures.length);
  final end = pageMeasureCount != null
      ? (start + pageMeasureCount).clamp(start, measures.length)
      : measures.length;

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
    final normalized = Measure(
      number: measure.number,
      clef: measure.clef ?? activeClef,
      timeSignature: measure.timeSignature ?? activeTimeSignature,
      keySignature: measure.keySignature ?? activeKeySignature,
      symbols: measure.symbols,
      startsNewPage: measure.startsNewPage,
      startsNewSystem: measure.startsNewSystem,
      leftBarlineType: measure.leftBarlineType,
      rightBarlineType: measure.rightBarlineType,
    );
    slice.add(normalized);
    activeClef = normalized.clef;
    activeTimeSignature = normalized.timeSignature;
    activeKeySignature = normalized.keySignature;
  }

  return slice;
}

class NotationPageSlice {
  const NotationPageSlice({required this.parts});

  final List<List<Measure>> parts;

  List<Measure> measuresForPart(int selectedPartIndex) {
    if (parts.isEmpty ||
        selectedPartIndex < 0 ||
        selectedPartIndex >= parts.length) {
      return const <Measure>[];
    }
    return parts[selectedPartIndex];
  }
}

@visibleForTesting
NotationPageSlice sliceScoreForLayout({
  required Score? score,
  required int firstMeasureIndex,
  int? pageMeasureCount,
}) {
  if (score == null || score.parts.isEmpty) {
    return const NotationPageSlice(parts: <List<Measure>>[]);
  }

  return NotationPageSlice(
    parts: score.parts
        .map(
          (part) => sliceMeasuresWithInheritedMetadata(
            measures: part.measures,
            firstMeasureIndex: firstMeasureIndex,
            pageMeasureCount: pageMeasureCount,
          ),
        )
        .toList(growable: false),
  );
}

/// Read-only sheet music renderer for a [Score] model.
///
/// Renders into a fixed-size [CustomPaint] — scrolling and zoom are handled
/// by the parent (typically an [InteractiveViewer]).
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
    this.firstMeasureIndex = 0,
    this.pageMeasureCount,
    this.selectedMeasureIndex,
    this.selectedSymbolIndex,
    this.selectedSymbolIndices = const {},
    this.playbackPartIndex,
    this.playbackMeasureIndex,
    this.playbackSymbolIndex,
    this.playbackNextPartIndex,
    this.playbackNextMeasureIndex,
    this.playbackNextSymbolIndex,
    this.playheadPartIndex,
    this.playheadMeasureIndex,
    this.playheadSymbolIndex,
    this.playbackProgress = 0,
    this.showPlaybackSymbolHighlight = true,
    this.issueMarks = const {},
    this.insertMode = false,
    this.onSymbolTap,
    this.onMeasureTap,
    this.onInsertTap,
    this.onDragStarted,
    this.onDragGlobalUpdate,
    this.onDragCompleted,
    this.onDragCancelled,
    this.canAcceptExternalDrop,
    this.onExternalDrop,
    this.externalPreviewResolver,
    this.suppressCanvasDragGhost = false,
  });

  final Score? score;
  final int selectedPartIndex;
  final int measuresPerRow;
  final double minMeasureWidth;
  final double rowHeight;
  final EdgeInsets padding;
  final Color backgroundColor;

  /// Index of the first measure to render (for multi-page display).
  final int firstMeasureIndex;

  /// Number of measures to render starting at [firstMeasureIndex]; null = all.
  final int? pageMeasureCount;

  final int? selectedMeasureIndex;
  final int? selectedSymbolIndex;
  final Set<int> selectedSymbolIndices;

  final int? playbackPartIndex;
  final int? playbackMeasureIndex;
  final int? playbackSymbolIndex;
  final int? playbackNextPartIndex;
  final int? playbackNextMeasureIndex;
  final int? playbackNextSymbolIndex;
  final int? playheadPartIndex;
  final int? playheadMeasureIndex;
  final int? playheadSymbolIndex;
  final double playbackProgress;
  final bool showPlaybackSymbolHighlight;

  /// Notation-check highlights, keyed as in [ScoreNotationPainter.issueMarks]
  /// with page-relative measure indices.
  final Map<String, Color> issueMarks;

  final bool insertMode;
  final ValueChanged<NotationSymbolTarget?>? onSymbolTap;
  final ValueChanged<NotationMeasureTarget?>? onMeasureTap;
  final ValueChanged<NotationInsertTarget?>? onInsertTap;

  final void Function(NotationSymbolTarget symbol)? onDragStarted;
  final void Function(Offset global)? onDragGlobalUpdate;
  final void Function(NotationSymbolReorder? reorder, Offset globalEndPosition)?
  onDragCompleted;
  final VoidCallback? onDragCancelled;

  final bool Function(Object data)? canAcceptExternalDrop;
  final void Function(NotationInsertTarget target, Object data)? onExternalDrop;
  final NotationPreviewGlyph? Function(Object data)? externalPreviewResolver;
  final bool suppressCanvasDragGhost;

  @override
  State<ScoreNotationViewer> createState() => _ScoreNotationViewerState();
}

class _ScoreNotationViewerState extends State<ScoreNotationViewer> {
  final NotationLayoutCalculator _layoutCalculator =
      const NotationLayoutCalculator();
  _NotationDragSession? _dragSession;
  NotationInsertTarget? _crossMeasureDragTarget;
  NotationInsertTarget? _externalInsertTarget;
  NotationPreviewGlyph? _externalPreviewGlyph;

  @override
  Widget build(BuildContext context) {
    final pageSlice = sliceScoreForLayout(
      score: widget.score,
      firstMeasureIndex: widget.firstMeasureIndex,
      pageMeasureCount: widget.pageMeasureCount,
    );
    final allParts = pageSlice.parts;
    final activeMeasures = pageSlice.measuresForPart(widget.selectedPartIndex);

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
      size: layout.size,
      canAcceptExternalData: widget.canAcceptExternalDrop,
      onExternalDragMove: (position, data) {
        if (widget.canAcceptExternalDrop?.call(data) == false) return;
        final target = _resolveInsertTarget(
          allParts: allParts,
          layout: layout,
          position: position,
        );
        final previewGlyph = target == null
            ? null
            : widget.externalPreviewResolver?.call(data);
        if (target == _externalInsertTarget &&
            previewGlyph == _externalPreviewGlyph) {
          return;
        }
        setState(() {
          _externalInsertTarget = target;
          _externalPreviewGlyph = previewGlyph;
        });
      },
      onExternalDragLeave: () {
        if (_externalInsertTarget == null && _externalPreviewGlyph == null) {
          return;
        }
        setState(() {
          _externalInsertTarget = null;
          _externalPreviewGlyph = null;
        });
      },
      onExternalAccept: (position, data) {
        if (widget.canAcceptExternalDrop?.call(data) == false) return;
        final target = _resolveInsertTarget(
          allParts: allParts,
          layout: layout,
          position: position,
        );
        if (target != null) widget.onExternalDrop?.call(target, data);
        if (_externalInsertTarget != null || _externalPreviewGlyph != null) {
          setState(() {
            _externalInsertTarget = null;
            _externalPreviewGlyph = null;
          });
        }
      },
      onTapUp:
          (widget.onSymbolTap == null &&
              widget.onMeasureTap == null &&
              widget.onInsertTap == null)
          ? null
          : (position) {
              if (widget.insertMode) {
                final target = _resolveInsertTarget(
                  allParts: allParts,
                  layout: layout,
                  position: position,
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
                final tapped = _nearestTarget(position, targets);
                widget.onSymbolTap?.call(tapped);
                if (tapped == null || widget.onSymbolTap == null) {
                  widget.onMeasureTap?.call(
                    _resolveMeasureTarget(
                      allParts: allParts,
                      layout: layout,
                      position: position,
                    ),
                  );
                }
              }
            },
      onLongPressStart: widget.onDragCompleted == null
          ? null
          : (position) => _beginDrag(
              allParts: allParts,
              layout: layout,
              position: position,
            ),
      onLongPressMoveUpdate: widget.onDragCompleted == null
          ? null
          : (local, global) {
              _updateDrag(allParts: allParts, layout: layout, position: local);
              widget.onDragGlobalUpdate?.call(global);
            },
      onLongPressEnd: widget.onDragCompleted == null
          ? null
          : (local, global) => _endDrag(
              allParts: allParts,
              layout: layout,
              localPosition: local,
              globalPosition: global,
            ),
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
        selectedSymbolIndices: widget.selectedSymbolIndices,
        playbackPartIndex: widget.playbackPartIndex,
        playbackMeasureIndex: widget.playbackMeasureIndex,
        playbackSymbolIndex: widget.playbackSymbolIndex,
        playbackNextPartIndex: widget.playbackNextPartIndex,
        playbackNextMeasureIndex: widget.playbackNextMeasureIndex,
        playbackNextSymbolIndex: widget.playbackNextSymbolIndex,
        playheadPartIndex: widget.playheadPartIndex,
        playheadMeasureIndex: widget.playheadMeasureIndex,
        playheadSymbolIndex: widget.playheadSymbolIndex,
        playbackProgress: widget.playbackProgress,
        showPlaybackSymbolHighlight: widget.showPlaybackSymbolHighlight,
        issueMarks: widget.issueMarks,
        dragFeedback:
            _dragSession == null ||
                _dragSession!.toPartIndex != _dragSession!.fromPartIndex ||
                _dragSession!.toMeasureIndex != _dragSession!.fromMeasureIndex
            ? null
            : NotationDragFeedback(
                measureIndex: _dragSession!.fromMeasureIndex,
                draggedSymbolIndex: _dragSession!.fromSymbolIndex,
                targetSymbolIndex: _dragSession!.toSymbolIndex,
                dragX: _dragSession!.dragPosition.dx,
                showGhostAtDrag: !widget.suppressCanvasDragGhost,
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
    final targets = ScoreNotationPainter.buildSymbolTargets(
      parts: allParts,
      measuresPerRow: layout.measuresPerRow,
      minMeasureWidth: widget.minMeasureWidth,
      rowHeight: widget.rowHeight,
      padding: widget.padding,
      rowPrefixWidth: layout.rowPrefixWidth,
    );
    final pressed = _nearestTarget(position, targets);
    if (pressed == null) return;

    HapticFeedback.mediumImpact();
    setState(() {
      _dragSession = _NotationDragSession(
        fromPartIndex: pressed.partIndex,
        fromMeasureIndex: pressed.measureIndex,
        fromSymbolIndex: pressed.symbolIndex,
        toPartIndex: pressed.partIndex,
        toMeasureIndex: pressed.measureIndex,
        toSymbolIndex: pressed.symbolIndex,
        dragPosition: position,
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

    final insertTarget = _resolveInsertTarget(
      allParts: allParts,
      layout: layout,
      position: position,
    );

    int toPartIndex = drag.toPartIndex;
    int toMeasureIndex = drag.toMeasureIndex;
    int toSymbolIndex = drag.toSymbolIndex;
    NotationInsertTarget? crossMeasureTarget;

    if (insertTarget != null) {
      toPartIndex = insertTarget.partIndex;
      toMeasureIndex = insertTarget.measureIndex;
      final sameMeasure =
          insertTarget.partIndex == drag.fromPartIndex &&
          insertTarget.measureIndex == drag.fromMeasureIndex;
      if (sameMeasure) {
        final idx = _targetIndexForDrag(
          measures: allParts[drag.fromPartIndex],
          layout: layout,
          measureIndex: drag.fromMeasureIndex,
          fromSymbolIndex: drag.fromSymbolIndex,
          dragPosition: position,
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
        dragPosition: position,
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

    final insertTarget = _resolveInsertTarget(
      allParts: allParts,
      layout: layout,
      position: localPosition,
    );

    int toPartIndex = drag.toPartIndex;
    int toMeasureIndex = drag.toMeasureIndex;
    int toSymbolIndex = drag.toSymbolIndex;

    if (insertTarget != null) {
      toPartIndex = insertTarget.partIndex;
      toMeasureIndex = insertTarget.measureIndex;
      final sameMeasure =
          insertTarget.partIndex == drag.fromPartIndex &&
          insertTarget.measureIndex == drag.fromMeasureIndex;
      if (sameMeasure) {
        final idx = _targetIndexForDrag(
          measures: allParts[drag.fromPartIndex],
          layout: layout,
          measureIndex: drag.fromMeasureIndex,
          fromSymbolIndex: drag.fromSymbolIndex,
          dragPosition: localPosition,
        );
        toSymbolIndex = idx ?? drag.fromSymbolIndex;
      } else {
        toSymbolIndex = insertTarget.insertIndex;
      }
    }

    final isSamePosition =
        toPartIndex == drag.fromPartIndex &&
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
    if (symbolCount <= 1 ||
        fromSymbolIndex < 0 ||
        fromSymbolIndex >= symbolCount) {
      return null;
    }

    final targets =
        ScoreNotationPainter.buildSymbolTargets(
          parts: [measures],
          measuresPerRow: layout.measuresPerRow,
          minMeasureWidth: widget.minMeasureWidth,
          rowHeight: widget.rowHeight,
          padding: widget.padding,
          rowPrefixWidth: layout.rowPrefixWidth,
        ).where(
          (target) =>
              target.measureIndex == measureIndex &&
              target.symbolIndex != fromSymbolIndex,
        );

    var insertIndex = 0;
    for (final target in targets) {
      if (dragPosition.dx > target.center.dx) {
        insertIndex++;
      }
    }
    return insertIndex.clamp(0, symbolCount - 1);
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
    final contentStartX = widget.padding.left + layout.rowPrefixWidth;
    const innerPadding = 16.0;

    for (final system in layout.systems) {
      for (var partIdx = 0; partIdx < partCount; partIdx++) {
        final measures = allParts[partIdx];
        final rowStartMeasure = system.startMeasureIndex;
        final rowEndExclusive = system.endMeasureIndexExclusive.clamp(
          0,
          measures.length,
        );
        if (rowStartMeasure >= rowEndExclusive) {
          continue;
        }

        final staffTop =
            widget.padding.top +
            system.systemIndex * (partCount * widget.rowHeight) +
            partIdx * widget.rowHeight +
            28;
        final staffBottom =
            staffTop + ScoreNotationPainter.staffLineSpacing * 4;
        if (position.dy < staffTop - 28 || position.dy > staffBottom + 28) {
          continue;
        }

        for (
          var measureInRow = 0;
          measureInRow < rowEndExclusive - rowStartMeasure;
          measureInRow++
        ) {
          final absoluteMeasureIndex = rowStartMeasure + measureInRow;
          final measureStartX =
              contentStartX + (measureInRow * widget.minMeasureWidth);
          final measureEndX = measureStartX + widget.minMeasureWidth;
          if (position.dx < measureStartX || position.dx > measureEndX) {
            continue;
          }

          final measure = measures[absoluteMeasureIndex];
          final inset = ScoreNotationMetrics.laneInset(
            timeInMeasure: ScoreNotationMetrics.timeSignatureInMeasure(
              measures,
              absoluteMeasureIndex,
              measureInRow: measureInRow,
              rowPrefixWidth: layout.rowPrefixWidth,
            ),
          );
          final drawableWidth =
              ((measureEndX - measureStartX) - inset - innerPadding)
                  .clamp(12.0, double.infinity)
                  .toDouble();
          final clampedX = position.dx
              .clamp(measureStartX + inset, measureEndX - innerPadding)
              .toDouble();
          // Symbols sit where the painter draws them: chord tones share the
          // slot of the note before them, and an insert never splits a chord.
          final symbols = measure.symbols;
          final slotCount = symbols
              .where((s) => !(s is Note && s.isChordTone))
              .length;
          var insertIndex = 0;
          var insertSlot = 0;
          var slot = 0;
          for (var i = 0; i < symbols.length; i++) {
            final symbol = symbols[i];
            if (symbol is Note && symbol.isChordTone) {
              if (insertIndex == i) insertIndex = i + 1;
              continue;
            }
            final progress = (slot + 1) / (slotCount + 1);
            slot++;
            if (clampedX > measureStartX + inset + drawableWidth * progress) {
              insertIndex = i + 1;
              insertSlot = slot;
            }
          }

          final indicatorProgress = (insertSlot + 1) / (slotCount + 2);
          final indicatorX =
              measureStartX + inset + (drawableWidth * indicatorProgress);
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

  NotationMeasureTarget? _resolveMeasureTarget({
    required List<List<Measure>> allParts,
    required NotationLayout layout,
    required Offset position,
  }) {
    final insertTarget = _resolveInsertTarget(
      allParts: allParts,
      layout: layout,
      position: position,
    );
    if (insertTarget == null) return null;
    return NotationMeasureTarget(
      partIndex: insertTarget.partIndex,
      measureIndex: insertTarget.measureIndex,
    );
  }
}

// ---------------------------------------------------------------------------
// Canvas frame — no scrolling; pan/zoom handled by InteractiveViewer above
// ---------------------------------------------------------------------------

class _NotationCanvasFrame extends StatelessWidget {
  const _NotationCanvasFrame({
    required this.backgroundColor,
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
    final canvas = GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapUp: onTapUp == null
          ? null
          : (details) => onTapUp!(details.localPosition),
      onLongPressStart: onLongPressStart == null
          ? null
          : (details) => onLongPressStart!(details.localPosition),
      onLongPressMoveUpdate: onLongPressMoveUpdate == null
          ? null
          : (details) => onLongPressMoveUpdate!(
              details.localPosition,
              details.globalPosition,
            ),
      onLongPressEnd: onLongPressEnd == null
          ? null
          : (details) =>
                onLongPressEnd!(details.localPosition, details.globalPosition),
      onLongPressCancel: onLongPressCancel,
      child: ColoredBox(
        color: backgroundColor,
        child: CustomPaint(size: size, painter: painter),
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

class NotationMeasureTarget {
  const NotationMeasureTarget({
    required this.partIndex,
    required this.measureIndex,
  });

  final int partIndex;
  final int measureIndex;
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
