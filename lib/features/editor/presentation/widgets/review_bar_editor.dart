import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:note_vision/core/models/clef.dart';
import 'package:note_vision/core/models/key_signature.dart';
import 'package:note_vision/core/models/measure.dart';
import 'package:note_vision/core/models/note.dart';
import 'package:note_vision/core/models/rest.dart';
import 'package:note_vision/core/models/score.dart';
import 'package:note_vision/core/models/time_signature.dart';
import 'package:note_vision/core/widgets/score_notation/engraving_layout.dart';
import 'package:note_vision/core/widgets/score_notation/notation_layout.dart';
import 'package:note_vision/core/widgets/score_notation/score_notation_painter.dart';
import 'package:note_vision/core/widgets/score_notation_viewer.dart';
import 'package:note_vision/features/editor/domain/editor_actions.dart';
import 'package:note_vision/features/editor/domain/scan_key_correction.dart';
import 'package:note_vision/features/editor/model/editor_state.dart';
import 'scan_key_correction_sheet.dart';

/// Small, selection-scoped corrections without leaving the photo comparison.
class ReviewBarEditor extends StatelessWidget {
  const ReviewBarEditor({
    super.key,
    required this.score,
    required this.part,
    required this.measure,
    required this.selectedSymbol,
    required this.onSelect,
    required this.onCorrect,
    required this.canEdit,
    required this.setupOpen,
    this.selectionOnly = false,
    this.selectionPrompt,
  });

  final Score score;
  final int part, measure;
  final int? selectedSymbol;
  final ValueChanged<int?> onSelect;
  final void Function(Score base, Score corrected, String label) onCorrect;
  final bool canEdit, setupOpen;
  final bool selectionOnly;
  final String? selectionPrompt;

  Measure get bar => score.parts[part].measures[measure];
  EditorState get selection => EditorState(score: score).selectSymbolAt(
    partIndex: part,
    measureIndex: measure,
    symbolIndex: selectedSymbol!,
  );

  void _metadata(Measure changed, String label) {
    final parts = score.parts.toList();
    final bars = parts[part].measures.toList()..[measure] = changed;
    parts[part] = parts[part].copyWith(measures: bars);
    onCorrect(score, score.copyWith(parts: parts), label);
  }

  @override
  Widget build(BuildContext context) {
    Clef? clef;
    TimeSignature? meter;
    KeySignature? keySignature;
    for (final m in score.parts[part].measures.take(measure + 1)) {
      clef = m.clef ?? clef;
      meter = m.timeSignature ?? meter;
      keySignature = m.keySignature ?? keySignature;
    }
    final selected = selectedSymbol == null
        ? null
        : bar.symbols.elementAtOrNull(selectedSymbol!);
    final clefs = <Clef>{
      ?clef,
      const Clef(sign: 'G', line: 2),
      const Clef(sign: 'F', line: 4),
      const Clef(sign: 'C', line: 3),
      const Clef(sign: 'C', line: 4),
    };
    final meters = <TimeSignature>{
      ?meter,
      for (final (n, d) in [
        (2, 4),
        (3, 4),
        (4, 4),
        (6, 8),
        (3, 8),
        (2, 2),
        (9, 8),
        (12, 8),
      ])
        TimeSignature(beats: n, beatType: d),
    };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          selectionPrompt ??
              '${score.isScannedMusic ? 'Scanned' : 'Current'} bar · Tap a note to correct it',
        ),
        const SizedBox(height: 6),
        _ReviewBarPreview(
          key: ValueKey((part, measure)),
          score: score,
          part: part,
          measure: measure,
          selectedSymbol: selectedSymbol,
          onSelect: onSelect,
          canEdit: canEdit,
        ),
        if (bar.symbols.any((s) => s is Note || s is Rest))
          Row(
            children: [
              IconButton(
                tooltip: 'Previous note in bar',
                onPressed: !canEdit
                    ? null
                    : () {
                        final before =
                            math.min(
                              selectedSymbol ?? bar.symbols.length,
                              bar.symbols.length,
                            ) -
                            1;
                        for (var i = before; i >= 0; i--) {
                          if (bar.symbols[i] is Note ||
                              bar.symbols[i] is Rest) {
                            onSelect(i);
                            return;
                          }
                        }
                      },
                icon: const Icon(Icons.chevron_left),
              ),
              Expanded(
                child: Text(switch (selected) {
                  Note(:final pitch, :final type) => '$pitch · $type note',
                  Rest(:final type) => '$type rest',
                  _ => 'Select a note or rest',
                }, textAlign: TextAlign.center),
              ),
              IconButton(
                tooltip: 'Next note in bar',
                onPressed: !canEdit
                    ? null
                    : () {
                        for (
                          var i = (selectedSymbol ?? -1) + 1;
                          i < bar.symbols.length;
                          i++
                        ) {
                          if (bar.symbols[i] is Note ||
                              bar.symbols[i] is Rest) {
                            onSelect(i);
                            return;
                          }
                        }
                      },
                icon: const Icon(Icons.chevron_right),
              ),
            ],
          ),
        if (!selectionOnly && (selected is Note || selected is Rest)) ...[
          if (selected is Note)
            Wrap(
              spacing: 8,
              children: [
                for (final (step, label, icon) in [
                  (1, 'Note up', Icons.arrow_upward),
                  (-1, 'Note down', Icons.arrow_downward),
                ])
                  OutlinedButton.icon(
                    onPressed: canEdit && selection.canMoveSelectedPitch(step)
                        ? () => onCorrect(
                            score,
                            selection.moveSelectedPitch(step).score,
                            label,
                          )
                        : null,
                    icon: Icon(icon),
                    label: Text(label),
                  ),
              ],
            ),
          Wrap(
            spacing: 6,
            children: [
              for (final (spec, glyph, label) in [
                (wholeDuration, '𝅝', 'Whole'),
                (halfDuration, '𝅗𝅥', 'Half'),
                (quarterDuration, '♩', 'Quarter'),
                (eighthDuration, '♪', 'Eighth'),
                (sixteenthDuration, '𝅘𝅥𝅯', 'Sixteenth'),
              ])
                Tooltip(
                  message: '$label note length',
                  child: ChoiceChip(
                    label: Text.rich(
                      TextSpan(
                        children: [
                          TextSpan(
                            text: glyph,
                            style: const TextStyle(fontFamily: 'NotoMusic'),
                          ),
                          TextSpan(text: ' $label'),
                        ],
                      ),
                    ),
                    selected: switch (selected) {
                      Note(:final type) ||
                      Rest(:final type) => type == spec.type,
                      _ => false,
                    },
                    onSelected:
                        canEdit &&
                            selection.canSetSelectedDuration(
                              spec,
                              allowOverfull: score.isScannedMusic,
                            )
                        ? (_) => onCorrect(
                            score,
                            selection
                                .setSelectedDuration(
                                  spec,
                                  allowOverfull: score.isScannedMusic,
                                )
                                .score,
                            'Set $label length',
                          )
                        : null,
                  ),
                ),
            ],
          ),
          const Text(
            'Use Undo to reverse a correction.',
            style: TextStyle(fontSize: 12),
          ),
        ],
        if (!selectionOnly)
          ExpansionTile(
            key: ValueKey(('setup', part, measure)),
            tilePadding: EdgeInsets.zero,
            initiallyExpanded: setupOpen,
            title: const Text('Clef, key and time signature'),
            children: [
              const Text(
                'Changes apply from this bar to the next written change on this staff.',
              ),
              const SizedBox(height: 8),
              DropdownButtonFormField<Clef>(
                initialValue: clef,
                decoration: const InputDecoration(labelText: 'Clef'),
                isExpanded: true,
                hint: const Text('Not read'),
                items: [
                  for (final c in clefs)
                    DropdownMenuItem(
                      value: c,
                      child: Text(switch ((c.sign, c.line)) {
                        ('G', 2) => '𝄞 Treble',
                        ('F', 4) => '𝄢 Bass',
                        ('C', 3) => 'Alto',
                        ('C', 4) => 'Tenor',
                        _ => '${c.sign} · line ${c.line}',
                      }),
                    ),
                ],
                onChanged: canEdit
                    ? (v) {
                        if (v != null) {
                          _metadata(bar.copyWith(clef: v), 'Correct clef');
                        }
                      }
                    : null,
              ),
              const SizedBox(height: 8),
              DropdownButtonFormField<int>(
                initialValue: keySignature?.fifths,
                hint: const Text('Not shown / not read'),
                decoration: const InputDecoration(
                  labelText: 'Sharps or flats at the start',
                ),
                isExpanded: true,
                items: [
                  for (var n = -7; n <= 7; n++)
                    DropdownMenuItem(
                      value: n,
                      child: Text(
                        n == 0
                            ? 'No sharps or flats'
                            : '${n.abs()} ${n > 0 ? 'sharps ♯' : 'flats ♭'}',
                      ),
                    ),
                ],
                onChanged: canEdit
                    ? (v) {
                        if (v != null) {
                          _metadata(
                            bar.copyWith(keySignature: KeySignature(fifths: v)),
                            'Correct key signature',
                          );
                        }
                      }
                    : null,
              ),
              const SizedBox(height: 8),
              if (ScanKeyCorrection.supports(score))
                OutlinedButton.icon(
                  icon: const Icon(Icons.playlist_add_check),
                  label: const Text('Correct key across rows…'),
                  onPressed: !canEdit
                      ? null
                      : () async {
                          final plan = await ScanKeyCorrectionSheet.show(
                            context,
                            score,
                            part,
                          );
                          final corrected = plan?.applyTo(score);
                          if (corrected != null) {
                            onCorrect(
                              score,
                              corrected,
                              'Correct key on ${plan!.changes.length} scanned ${plan.changes.length == 1 ? 'row' : 'rows'}',
                            );
                          }
                        },
                ),
              DropdownButtonFormField<TimeSignature>(
                initialValue: meter,
                decoration: const InputDecoration(labelText: 'Time signature'),
                isExpanded: true,
                hint: const Text('Not shown / not read'),
                items: [
                  if (measure == 0)
                    const DropdownMenuItem(
                      value: null,
                      child: Text('Not shown on the photo'),
                    ),
                  for (final t in meters)
                    DropdownMenuItem(
                      value: t,
                      child: Text('${t.beats}/${t.beatType}'),
                    ),
                ],
                onChanged: canEdit
                    ? (v) => _metadata(
                        bar.copyWith(timeSignature: v),
                        'Correct time signature',
                      )
                    : null,
              ),
              const SizedBox(height: 8),
              const Text(
                'Check the barlines and any stacked notes too. Use Edit manually for missing notes, barlines or chords.',
              ),
            ],
          ),
      ],
    );
  }
}

/// Owns preview zoom and panning separately from the review sheet's scroll.
class _ReviewBarPreview extends StatefulWidget {
  const _ReviewBarPreview({
    super.key,
    required this.score,
    required this.part,
    required this.measure,
    required this.selectedSymbol,
    required this.onSelect,
    required this.canEdit,
  });

  final Score score;
  final int part, measure;
  final int? selectedSymbol;
  final ValueChanged<int?> onSelect;
  final bool canEdit;

  @override
  State<_ReviewBarPreview> createState() => _ReviewBarPreviewState();
}

class _ReviewBarPreviewState extends State<_ReviewBarPreview> {
  final _scroll = ScrollController();
  final _verticalScroll = ScrollController();
  (Score, int?, double, double, double, double)? _lastRequest;
  bool _revealScheduled = false;
  bool _revealDefault = false;
  Score? _sourceScore, _previewScore;
  EngravingLayout? _barEngraving;
  NotationVerticalLayout? _vertical;
  double _measureWidth = 0;
  double _viewportHeight = 0;
  double _zoom = 1, _resolvedZoom = 1, _fitZoom = 1;
  bool _fitBar = false;
  static const _padding = EdgeInsets.all(12);
  static const _rowHeight = 145.0;

  double get _minimumZoom => math.min(.25, _fitZoom);

  void _setZoom(double? value) => setState(() {
    _fitBar = value == null;
    if (value != null) _zoom = value.clamp(_minimumZoom, 3.0);
    _lastRequest = null;
  });

  Score get _score {
    if (!identical(_sourceScore, widget.score)) {
      _sourceScore = widget.score;
      _previewScore = widget.score.copyWith(
        parts: [widget.score.parts[widget.part]],
      );
      _barEngraving = null;
      _vertical = null;
    }
    return _previewScore!;
  }

  NotationVerticalLayout get _verticalLayout {
    final score = _score;
    return _vertical ??= NotationVerticalLayout.forParts(
      EngravingLayout.forScore(score).parts,
      rowHeight: _rowHeight,
      padding: _padding,
    );
  }

  EngravingLayout get _engraving {
    final score = _score;
    return _barEngraving ??= EngravingLayout(
      [
        sliceMeasuresWithInheritedMetadata(
          measures: score.parts.single.measures,
          firstMeasureIndex: widget.measure,
          pageMeasureCount: 1,
        ),
      ],
      score: score,
      firstMeasure: widget.measure,
    );
  }

  NotationLayout _layout(double width) =>
      const NotationLayoutCalculator().calculate(
        measures: _engraving.parts.single,
        measuresPerRow: 1,
        minMeasureWidth: width,
        rowHeight: _verticalLayout.rowHeight,
        padding: _verticalLayout.padding,
      );

  @override
  void dispose() {
    _scroll.dispose();
    _verticalScroll.dispose();
    super.dispose();
  }

  void _scheduleReveal() {
    if (_revealScheduled) return;
    _revealScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _revealScheduled = false;
      if (!mounted) return;
      if (widget.selectedSymbol == null && !_revealDefault) return;
      final index = widget.selectedSymbol ?? 0;
      final bar = widget.score.parts[widget.part].measures[widget.measure];
      if (index < 0 ||
          (bar.symbols.isNotEmpty && index >= bar.symbols.length)) {
        return;
      }
      final layout = _layout(_measureWidth);
      final part = _score.parts.single;
      final target = ScoreNotationPainter.buildSymbolTargets(
        parts: _engraving.parts,
        engraving: _engraving,
        measuresPerRow: 1,
        minMeasureWidth: _measureWidth,
        rowHeight: _verticalLayout.rowHeight,
        padding: _verticalLayout.padding,
        rowPrefixWidth: layout.rowPrefixWidth,
        tabTunings: {
          if (part.isTab && part.tabTuning != null) 0: part.tabTuning!,
        },
        singleLineParts: {if (part.singleLine) 0},
      ).where((t) => t.symbolIndex == index).firstOrNull;
      if (target != null && widget.selectedSymbol != null) {
        _revealAxis(
          _scroll,
          target.hitRect.left * _resolvedZoom - 20,
          target.hitRect.right * _resolvedZoom + 20,
        );
      }
      // Include stems/ledger lines around the head, matching actual tap geometry.
      final region =
          target?.hitRect ??
          Rect.fromLTWH(0, _verticalLayout.padding.top + 28, 0, 48);
      _revealAxis(
        _verticalScroll,
        region.top * _resolvedZoom - 32,
        region.bottom * _resolvedZoom + 32,
      );
    });
  }

  void _revealAxis(ScrollController controller, double start, double end) {
    if (!controller.hasClients ||
        !controller.position.hasContentDimensions ||
        !start.isFinite ||
        !end.isFinite) {
      return;
    }
    final position = controller.position;
    final target = start < position.pixels
        ? start
        : end > position.pixels + position.viewportDimension
        ? end - position.viewportDimension
        : position.pixels;
    final offset = target.clamp(
      position.minScrollExtent,
      position.maxScrollExtent,
    );
    if ((offset - position.pixels).abs() > .5) controller.jumpTo(offset);
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final minimum = _engraving.minimumBarWidth;
      final prefix = _layout(minimum).rowPrefixWidth;
      // Keep the shared engraving minimum; use the rest of the viewport when
      // this bar fits. Other bars/staves must not stretch this preview.
      _measureWidth = math.max(
        minimum,
        constraints.hasBoundedWidth
            ? constraints.maxWidth - _padding.horizontal - prefix
            : minimum,
      );
      final layout = _layout(_measureWidth);
      _fitZoom = math.min(
        1.0,
        math.min(
          constraints.hasBoundedWidth
              ? constraints.maxWidth / layout.size.width
              : 1.0,
          240 / layout.size.height,
        ),
      );
      _resolvedZoom = _fitBar ? _fitZoom : _zoom;
      final canvasSize = layout.size * _resolvedZoom;
      _viewportHeight = canvasSize.height.clamp(155.0, 240.0);
      final request = (
        widget.score,
        widget.selectedSymbol,
        _measureWidth,
        constraints.maxWidth,
        _viewportHeight,
        _resolvedZoom,
      );
      if (_lastRequest != request) {
        _revealDefault =
            _lastRequest == null || !identical(_lastRequest!.$1, widget.score);
        _lastRequest = request;
        _scheduleReveal();
      }
      final preview = Scrollbar(
        controller: _verticalScroll,
        thumbVisibility: canvasSize.height > _viewportHeight,
        notificationPredicate: (notification) =>
            notification.metrics.axis == Axis.vertical,
        child: ColoredBox(
          color: Colors.white,
          child: SizedBox(
            height: _viewportHeight,
            child: SingleChildScrollView(
              controller: _scroll,
              scrollDirection: Axis.horizontal,
              child: SizedBox(
                width: math.max(
                  canvasSize.width,
                  constraints.hasBoundedWidth ? constraints.maxWidth : 0,
                ),
                height: _viewportHeight,
                child: SingleChildScrollView(
                  controller: _verticalScroll,
                  child: Align(
                    alignment: Alignment.topLeft,
                    child: SizedBox(
                      width: canvasSize.width,
                      height: canvasSize.height,
                      child: FittedBox(
                        alignment: Alignment.topLeft,
                        child: SizedBox(
                          width: layout.size.width,
                          height: layout.size.height,
                          child: ScoreNotationViewer(
                            score: _score,
                            firstMeasureIndex: widget.measure,
                            pageMeasureCount: 1,
                            measuresPerRow: 1,
                            minMeasureWidth: _measureWidth,
                            rowHeight: _rowHeight,
                            padding: _padding,
                            backgroundColor: Colors.white,
                            selectedPartIndex: 0,
                            selectedMeasureIndex: 0,
                            selectedSymbolIndex: widget.selectedSymbol,
                            onSymbolTap: widget.canEdit
                                ? (target) =>
                                      widget.onSelect(target?.symbolIndex)
                                : null,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      final percent = _resolvedZoom * 100;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Wrap(
            alignment: WrapAlignment.end,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              IconButton(
                tooltip: 'Review zoom out',
                onPressed: _resolvedZoom <= _minimumZoom + .000001
                    ? null
                    : () => _setZoom(_resolvedZoom / 1.25),
                icon: const Icon(Icons.remove),
              ),
              Tooltip(
                message: 'Reset review zoom to 100%',
                child: TextButton(
                  onPressed: () => _setZoom(1),
                  child: Text(
                    '${percent < 10 ? percent.toStringAsFixed(1) : percent.round()}%',
                  ),
                ),
              ),
              IconButton(
                tooltip: 'Review zoom in',
                onPressed: _resolvedZoom >= 3
                    ? null
                    : () => _setZoom(_resolvedZoom * 1.25),
                icon: const Icon(Icons.add),
              ),
              Semantics(
                selected: _fitBar,
                child: TextButton.icon(
                  onPressed: () => _setZoom(null),
                  style: _fitBar
                      ? TextButton.styleFrom(
                          backgroundColor: Theme.of(
                            context,
                          ).colorScheme.primary.withValues(alpha: .12),
                        )
                      : null,
                  icon: const Icon(Icons.fit_screen),
                  label: const Text('Fit bar'),
                ),
              ),
            ],
          ),
          preview,
        ],
      );
    },
  );
}
