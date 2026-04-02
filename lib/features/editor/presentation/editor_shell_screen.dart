import 'package:flutter/material.dart';
import 'package:note_vision/core/models/note.dart';
import 'package:note_vision/core/models/rest.dart';
import 'package:note_vision/core/models/score.dart';
import 'package:note_vision/core/models/score_symbol.dart';
import 'package:note_vision/core/theme/app_theme.dart';
import 'package:note_vision/core/theme/responsive_layout.dart';
import 'package:note_vision/core/widgets/score_notation/notation_layout.dart';
import 'package:note_vision/core/widgets/score_notation/score_notation_painter.dart';
import 'package:note_vision/core/widgets/score_notation_viewer.dart';
import 'package:note_vision/features/detection/domain/detected_staff.dart';
import 'package:note_vision/features/detection/domain/detected_symbol.dart';
import 'package:note_vision/features/editor/domain/editor_actions.dart';
import 'package:note_vision/features/editor/domain/editor_actions.dart' as editor_actions;
import 'package:note_vision/features/editor/model/editor_state.dart';
import 'package:note_vision/features/editor/presentation/widgets/palette/music_symbol_palette.dart';
import 'package:note_vision/features/editor/domain/model/musical_symbol.dart';
import 'package:note_vision/features/mapping/domain/internal/pitch_calculator.dart';
import 'package:note_vision/features/mapping/domain/internal/mapping_types.dart';
import 'package:note_vision/core/models/clef.dart';

class EditorShellArgs {
  const EditorShellArgs({required this.score, required this.initialState});

  final Score score;
  final EditorState initialState;
}

class EditorShellScreen extends StatefulWidget {
  const EditorShellScreen({super.key, required this.args});

  static const routeName = '/editor';

  final EditorShellArgs args;

  @override
  State<EditorShellScreen> createState() => _EditorShellScreenState();
}

class _EditorShellScreenState extends State<EditorShellScreen> {
  static const _viewerMeasuresPerRow = 4;
  static const _viewerMinMeasureWidth = 140.0;
  static const _viewerRowHeight = 140.0;
  static const _viewerPadding = EdgeInsets.all(16);

  final GlobalKey _notationViewerKey = GlobalKey();
  final NotationLayoutCalculator _notationLayoutCalculator =
      const NotationLayoutCalculator();
  final PitchCalculator _pitchCalculator = const PitchCalculator();
  late EditorState _editorState;
  NotationInsertionFeedback? _dropInsertionFeedback;
  double _notationHorizontalScrollOffset = 0;

  void _handleSymbolDrop(MusicalSymbol symbol, Offset globalPosition) {
    final insertion = _resolveInsertionTarget(globalPosition);
    if (insertion == null) {
      _setDropInsertionFeedback(null);
      return;
    }

    final droppedSymbol = _toDroppedSymbol(
      symbol: symbol,
      localY: insertion.localPosition.dy,
      lineYs: insertion.measureTarget.lineYs,
    );
    if (droppedSymbol == null) {
      _setDropInsertionFeedback(null);
      return;
    }

    _updateState(
      (state) => state.insertSymbolAt(
        partIndex: 0,
        measureIndex: insertion.measureTarget.measureIndex,
        symbolIndex: insertion.insertIndex,
        symbol: droppedSymbol,
      ),
    );
    _setDropInsertionFeedback(null);
  }

  void _handleDragHover(Offset globalPosition) {
    final insertion = _resolveInsertionTarget(globalPosition);
    final feedback = insertion == null
        ? null
        : NotationInsertionFeedback(
            measureIndex: insertion.measureTarget.measureIndex,
            insertIndex: insertion.insertIndex,
          );
    _setDropInsertionFeedback(feedback);
  }

  void _setDropInsertionFeedback(NotationInsertionFeedback? feedback) {
    if (_dropInsertionFeedback == feedback) return;
    setState(() {
      _dropInsertionFeedback = feedback;
    });
  }

  _DropInsertionTarget? _resolveInsertionTarget(Offset globalPosition) {
    final viewerContext = _notationViewerKey.currentContext;
    final renderObject = viewerContext?.findRenderObject();
    if (renderObject is! RenderBox) return null;

    final localPosition =
        renderObject.globalToLocal(globalPosition).translate(_notationHorizontalScrollOffset, 0);
    final part = _editorState.score.parts.isEmpty ? null : _editorState.score.parts.first;
    final measures = part?.measures ?? const [];
    if (measures.isEmpty) return null;

    final layout = _notationLayoutCalculator.calculate(
      measures: measures,
      measuresPerRow: _viewerMeasuresPerRow,
      minMeasureWidth: _viewerMinMeasureWidth,
      rowHeight: _viewerRowHeight,
      padding: _viewerPadding,
    );

    NotationMeasureTarget? measureTarget;
    for (final entry in ScoreNotationPainter.buildMeasureTargets(
      measures: measures,
      measuresPerRow: layout.measuresPerRow,
      minMeasureWidth: _viewerMinMeasureWidth,
      rowHeight: _viewerRowHeight,
      padding: _viewerPadding,
      rowPrefixWidth: layout.rowPrefixWidth,
    )) {
      if (entry.dropRect.contains(localPosition)) {
        measureTarget = entry;
        break;
      }
    }

    if (measureTarget == null) return null;

    final symbolTargets = ScoreNotationPainter.buildSymbolTargets(
      measures: measures,
      measuresPerRow: layout.measuresPerRow,
      minMeasureWidth: _viewerMinMeasureWidth,
      rowHeight: _viewerRowHeight,
      padding: _viewerPadding,
      rowPrefixWidth: layout.rowPrefixWidth,
    ).where((entry) => entry.measureIndex == measureTarget.measureIndex).toList()
      ..sort((a, b) => a.center.dx.compareTo(b.center.dx));

    final insertIndex = _insertionIndexForX(localPosition.dx, symbolTargets);

    return _DropInsertionTarget(
      measureTarget: measureTarget,
      insertIndex: insertIndex,
      localPosition: localPosition,
    );
  }

  int _insertionIndexForX(double dropX, List<NotationSymbolTarget> targets) {
    if (targets.isEmpty) return 0;
    for (var i = 0; i < targets.length; i++) {
      if (dropX < targets[i].center.dx) {
        return i;
      }
    }
    return targets.length;
  }

  Pitch? _pitchForY(double y, List<double> lineYs) {
    if (lineYs.length < 2) return null;
    final sorted = [...lineYs]..sort();
    final staff = DetectedStaff(
      id: 'editor-drop',
      topY: sorted.first,
      bottomY: sorted.last,
      lineYs: sorted,
    );
    final symbol = DetectedSymbol(
      id: 'editor-drop-symbol',
      type: 'noteheadBlack',
      x: 0,
      y: y,
      width: 0,
      height: 0,
    );
    return _pitchCalculator.calculate(
      symbol: symbol,
      staff: staff,
      clef: const Clef(sign: 'G', line: 2),
    );
  }

  ScoreSymbol? _toDroppedSymbol({
    required MusicalSymbol symbol,
    required double localY,
    required List<double> lineYs,
  }) {
    if (symbol.isRest) {
      final spec = _durationFor(symbol);
      return Rest(duration: spec.divisions, type: spec.type);
    }

    final pitch = _pitchForY(localY, lineYs);
    if (pitch == null) return null;
    final clampedPitch = _clampToDemoTrebleRange(pitch);
    final spec = _durationFor(symbol);
    return Note(
      step: clampedPitch.step,
      octave: clampedPitch.octave,
      duration: spec.divisions,
      type: spec.type,
    );
  }

  Pitch _clampToDemoTrebleRange(Pitch pitch) {
    const minPitch = Pitch(step: 'C', octave: 4);
    const maxPitch = Pitch(step: 'G', octave: 5);
    if (_comparePitch(pitch, minPitch) < 0) return minPitch;
    if (_comparePitch(pitch, maxPitch) > 0) return maxPitch;
    return pitch;
  }

  int _comparePitch(Pitch left, Pitch right) {
    const steps = ['C', 'D', 'E', 'F', 'G', 'A', 'B'];
    final leftIndex = steps.indexOf(left.step.toUpperCase());
    final rightIndex = steps.indexOf(right.step.toUpperCase());
    final normalizedLeft = leftIndex < 0 ? 0 : leftIndex;
    final normalizedRight = rightIndex < 0 ? 0 : rightIndex;
    final leftAbsolute = (left.octave * steps.length) + normalizedLeft;
    final rightAbsolute = (right.octave * steps.length) + normalizedRight;
    return leftAbsolute.compareTo(rightAbsolute);
  }

  editor_actions.DurationSpec _durationFor(MusicalSymbol symbol) {
    switch (symbol) {
      case MusicalSymbol.wholeNote:
      case MusicalSymbol.wholeRest:
        return wholeDuration;
      case MusicalSymbol.halfNote:
      case MusicalSymbol.halfRest:
        return halfDuration;
      case MusicalSymbol.eighthNote:
        return eighthDuration;
      case MusicalSymbol.quarterNote:
      case MusicalSymbol.quarterRest:
        return quarterDuration;
    }
  }

  @override
  void initState() {
    super.initState();
    _editorState = _withDefaultMeasureContext(
      widget.args.initialState.copyWith(score: widget.args.score),
    );
  }

  void _updateState(EditorState Function(EditorState state) updater) {
    setState(() {
      _editorState = updater(_editorState);
    });
  }

  void _onNotationSymbolTap(int measureIndex, int symbolIndex) {
    _updateState((state) {
      final isSameSelection =
          state.selectedPartIndex == 0 &&
          state.selectedMeasureIndex == measureIndex &&
          state.selectedSymbolIndex == symbolIndex;

      if (isSameSelection) return _clearSymbolSelection(state);

      final parts = state.score.parts;
      if (parts.isEmpty || measureIndex < 0 || measureIndex >= parts.first.measures.length) {
        return state.copyWith(clearSelection: true);
      }
      final symbols = parts.first.measures[measureIndex].symbols;
      if (symbolIndex < 0 || symbolIndex >= symbols.length) {
        return _clearSymbolSelection(state);
      }

      return state.copyWith(
        selectedPartIndex: 0,
        selectedMeasureIndex: measureIndex,
        selectedSymbolIndex: symbolIndex,
        selectedSymbol: symbols[symbolIndex],
      );
    });
  }

  EditorState _withDefaultMeasureContext(EditorState state) {
    if (state.selectedPartIndex != null && state.selectedMeasureIndex != null) {
      return state;
    }
    if (state.score.parts.isEmpty || state.score.parts.first.measures.isEmpty) {
      return state;
    }
    return state.copyWith(selectedPartIndex: 0, selectedMeasureIndex: 0);
  }

  EditorState _clearSymbolSelection(EditorState state) {
    return EditorState(
      score: state.score,
      selectedPartIndex: state.selectedPartIndex,
      selectedMeasureIndex: state.selectedMeasureIndex,
      undoStack: state.undoStack,
      redoStack: state.redoStack,
      hasUnsavedChanges: state.hasUnsavedChanges,
    );
  }

  @override
  Widget build(BuildContext context) {
    final selected = _editorState.selectedSymbol;
    final hasSelection = _editorState.hasSelection;
    final hasMeasureContext =
        _editorState.selectedPartIndex != null && _editorState.selectedMeasureIndex != null;
    final selectedMeasureIndex = _editorState.selectedMeasureIndex ?? 0;
    final measureCount = _editorState.score.parts.isEmpty
        ? 0
        : _editorState.score.parts.first.measures.length;

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final horizontalPadding = ResponsiveLayout.horizontalPadding(constraints.maxWidth);
            final isLandscape = constraints.maxWidth > constraints.maxHeight;
            final controlPanelWidth = (constraints.maxWidth * 0.32).clamp(280.0, 360.0) as double;
            final notationPanel = Container(
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: AppColors.border),
              ),
              child: DragTarget<MusicalSymbol>(
              onWillAcceptWithDetails: (details) {
                _handleDragHover(details.offset);
                return true;
              },
              onMove: (details) => _handleDragHover(details.offset),
              onLeave: (_) => _setDropInsertionFeedback(null),
              onAcceptWithDetails: (details) {
                final symbol = details.data;
                final globalPosition = details.offset;
                _handleSymbolDrop(symbol, globalPosition);
              },
              builder: (context, candidateData, rejectedData) {
                return SingleChildScrollView(
                  child: Padding(
                    padding: const EdgeInsets.all(8),
                    child: ScoreNotationViewer(
                      key: _notationViewerKey,
                      score: _editorState.score,
                      selectedMeasureIndex: _editorState.selectedMeasureIndex,
                      selectedSymbolIndex: _editorState.selectedSymbolIndex,
                      insertionFeedback: _dropInsertionFeedback,
                      onHorizontalScrollOffsetChanged: (offset) {
                        _notationHorizontalScrollOffset = offset;
                      },
                      onSymbolTap: (target) {
                        if (target == null) {
                          _updateState((state) => _clearSymbolSelection(state));
                          return;
                        }
                        _onNotationSymbolTap(target.measureIndex, target.symbolIndex);
                      },
                      onSymbolReorder: (event) {
                        _updateState(
                          (state) => state.reorderSymbolWithinMeasure(
                            measureIndex: event.measureIndex,
                            fromSymbolIndex: event.fromSymbolIndex,
                            toSymbolIndex: event.toSymbolIndex,
                          ),
                        );
                      },
                    ),
                  ),
                );
              },
            )
          );


            final statusStrip = _StatusStrip(
              horizontalPadding: isLandscape ? 0 : horizontalPadding,
              symbolType: selected == null ? 'None' : selected is Note ? 'Note' : 'Rest',
              pitch: selected is Note ? selected.pitch : '—',
              durationType: selected == null
                  ? '—'
                  : selected is Note
                      ? selected.type
                      : (selected as Rest).type,
              measure: _editorState.selectedMeasureIndex == null
                  ? '—'
                  : (_editorState.selectedMeasureIndex! + 1).toString(),
              onPrevMeasure: selectedMeasureIndex > 0
                  ? () => _updateState(
                        (s) => s.copyWith(
                          selectedPartIndex: 0,
                          selectedMeasureIndex: selectedMeasureIndex - 1,
                          selectedSymbolIndex: null,
                          selectedSymbol: null,
                        ),
                      )
                  : null,
              onNextMeasure: selectedMeasureIndex < measureCount - 1
                  ? () => _updateState(
                        (s) => s.copyWith(
                          selectedPartIndex: 0,
                          selectedMeasureIndex: selectedMeasureIndex + 1,
                          selectedSymbolIndex: null,
                          selectedSymbol: null,
                        ),
                      )
                  : null,
            );

            final actionBar = _EditorActionBar(
              horizontalPadding: isLandscape ? 0 : horizontalPadding,
              hasSelection: hasSelection,
              hasMeasureContext: hasMeasureContext,
              canUndo: _editorState.canUndo,
              canRedo: _editorState.canRedo,
              onMoveUp: () => _updateState((s) => s.moveSelectedSymbolUp()),
              onMoveDown: () => _updateState((s) => s.moveSelectedSymbolDown()),
              onWhole: () => _updateState((s) => s.setSelectedDuration(wholeDuration)),
              onHalf: () => _updateState((s) => s.setSelectedDuration(halfDuration)),
              onQuarter: () => _updateState((s) => s.setSelectedDuration(quarterDuration)),
              onEighth: () => _updateState((s) => s.setSelectedDuration(eighthDuration)),
              onInsertNote: () => _updateState((s) => s.insertNoteAfterSelection()),
              onInsertRest: () => _updateState((s) => s.insertRestAfterSelection()),
              onDelete: () => _updateState((s) => s.deleteSelectedSymbol()),
              onMoveToPrevMeasure: () =>
                  _updateState((s) => s.moveSelectedSymbolToMeasureOffset(-1)),
              onMoveToNextMeasure: () =>
                  _updateState((s) => s.moveSelectedSymbolToMeasureOffset(1)),
              onUndo: () => _updateState((s) => s.applyUndo()),
              onRedo: () => _updateState((s) => s.applyRedo()),
            );

            return Column(
              children: [
                _EditorHeader(
                  title: _editorState.score.title.isEmpty ? 'Untitled Score' : _editorState.score.title,
                  hasUnsavedChanges: _editorState.hasUnsavedChanges,
                  horizontalPadding: horizontalPadding,
                  onBack: () => Navigator.of(context).maybePop(),
                ),
                Expanded(
                  child: Padding(
                    padding: EdgeInsets.symmetric(horizontal: horizontalPadding),
                    child: isLandscape
                        ? Row(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Expanded(
                                child: Column(
                                  children: [
                                    Expanded(child: notationPanel),
                                    const MusicSymbolPalette(),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 12),
                              SizedBox(
                                width: controlPanelWidth,
                                child: SingleChildScrollView(
                                  child: Column(
                                    children: [
                                      statusStrip,
                                      actionBar,
                                    ],
                                  ),
                                ),
                              ),
                            ],
                          )
                        : Column(
                            children: [
                              Expanded(child: notationPanel),
                              const MusicSymbolPalette(),
                              statusStrip,
                              actionBar,
                            ],
                          ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _EditorHeader extends StatelessWidget {
  const _EditorHeader({
    required this.title,
    required this.hasUnsavedChanges,
    required this.horizontalPadding,
    required this.onBack,
  });

  final String title;
  final bool hasUnsavedChanges;
  final double horizontalPadding;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(horizontalPadding, 12, horizontalPadding, 8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.border),
        ),
        child: Row(
          children: [
            IconButton(
              onPressed: onBack,
              icon: const Icon(Icons.arrow_back_ios_new, size: 16),
              color: AppColors.textPrimary,
              tooltip: 'Back',
            ),
            const SizedBox(width: 4),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    hasUnsavedChanges ? '$title *' : title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 2),
                  const Text(
                    'Editor Workspace',
                    style: TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
            FilledButton.icon(
              onPressed: () {},
              icon: const Icon(Icons.save_outlined, size: 18),
              label: const Text('Save'),
            ),
            const SizedBox(width: 8),
            OutlinedButton.icon(
              onPressed: () {},
              icon: const Icon(Icons.ios_share_outlined, size: 16),
              label: const Text('Export'),
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.textPrimary,
                side: const BorderSide(color: AppColors.border),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StatusStrip extends StatelessWidget {
  const _StatusStrip({
    required this.horizontalPadding,
    required this.symbolType,
    required this.pitch,
    required this.durationType,
    required this.measure,
    required this.onPrevMeasure,
    required this.onNextMeasure,
  });

  final double horizontalPadding;
  final String symbolType;
  final String pitch;
  final String durationType;
  final String measure;
  final VoidCallback? onPrevMeasure;
  final VoidCallback? onNextMeasure;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: EdgeInsets.fromLTRB(horizontalPadding, 4, horizontalPadding, 4), // ↓ from 8
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6), // ↓ from 12 / 10
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(8), // ↓ from 12
        border: Border.all(color: AppColors.border, width: 0.8), // slightly thinner
      ),
      child: Wrap(
        spacing: 8, // ↓ from 12
        runSpacing: 4, // ↓ from 8
        children: [
          _StatusItem(label: 'Type', value: symbolType),
          _StatusItem(label: 'Pitch', value: pitch),
          _StatusItem(label: 'Duration', value: durationType),
          _StatusItem(label: 'Measure', value: measure),
          _StatusNavButton(
            icon: Icons.chevron_left_rounded,
            onPressed: onPrevMeasure,
          ),
          _StatusNavButton(
            icon: Icons.chevron_right_rounded,
            onPressed: onNextMeasure,
          ),
        ],
      ),
    );
  }
}

class _StatusNavButton extends StatelessWidget {
  const _StatusNavButton({required this.icon, required this.onPressed});

  final IconData icon;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return OutlinedButton(
      onPressed: onPressed,
      style: OutlinedButton.styleFrom(
        side: const BorderSide(color: AppColors.border),
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
        minimumSize: const Size(32, 32),
      ),
      child: Icon(icon, size: 18),
    );
  }
}

class _StatusItem extends StatelessWidget {
  const _StatusItem({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minWidth: 82),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: AppColors.surfaceAlt,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(fontSize: 10, color: AppColors.textSecondary),
          ),
          Text(
            value,
            style: const TextStyle(
              color: AppColors.textPrimary,
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// EDITOR ACTION BAR — restructured layout
// ─────────────────────────────────────────────────────────────────────────────

class _EditorActionBar extends StatelessWidget {
  const _EditorActionBar({
    required this.horizontalPadding,
    required this.hasSelection,
    required this.hasMeasureContext,
    required this.canUndo,
    required this.canRedo,
    required this.onMoveUp,
    required this.onMoveDown,
    required this.onWhole,
    required this.onHalf,
    required this.onQuarter,
    required this.onEighth,
    required this.onInsertNote,
    required this.onInsertRest,
    required this.onDelete,
    required this.onMoveToPrevMeasure,
    required this.onMoveToNextMeasure,
    required this.onUndo,
    required this.onRedo,
  });

  final double horizontalPadding;
  final bool hasSelection;
  final bool hasMeasureContext;
  final bool canUndo;
  final bool canRedo;
  final VoidCallback onMoveUp;
  final VoidCallback onMoveDown;
  final VoidCallback onWhole;
  final VoidCallback onHalf;
  final VoidCallback onQuarter;
  final VoidCallback onEighth;
  final VoidCallback onInsertNote;
  final VoidCallback onInsertRest;
  final VoidCallback onDelete;
  final VoidCallback onMoveToPrevMeasure;
  final VoidCallback onMoveToNextMeasure;
  final VoidCallback onUndo;
  final VoidCallback onRedo;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: AppColors.surfaceAlt,
      padding: EdgeInsets.fromLTRB(horizontalPadding, 10, horizontalPadding, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── INSERT ROW ────────────────────────────────────────────────────
          const _SectionLabel('INSERT'),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: _InsertDropdown(
                  label: 'Note',
                  icon: Icons.music_note_rounded,
                  enabled: hasMeasureContext,
                  items: const ['Whole', 'Half', 'Quarter', 'Eighth'],
                  onSelected: (value) {
                    // First insert, then set duration based on selection
                    onInsertNote();
                    switch (value) {
                      case 'Whole':
                        onWhole();
                      case 'Half':
                        onHalf();
                      case 'Quarter':
                        onQuarter();
                      case 'Eighth':
                        onEighth();
                    }
                  },
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _InsertDropdown(
                  label: 'Rest',
                  icon: Icons.pause_rounded,
                  enabled: hasMeasureContext,
                  items: const ['Whole', 'Half', 'Quarter', 'Eighth'],
                  onSelected: (value) {
                    // First insert, then set duration based on selection
                    onInsertRest();
                    switch (value) {
                      case 'Whole':
                        onWhole();
                      case 'Half':
                        onHalf();
                      case 'Quarter':
                        onQuarter();
                      case 'Eighth':
                        onEighth();
                    }
                  },
                ),
              ),
            ],
          ),

          const SizedBox(height: 14),

          // ── DURATION ROW ─────────────────────────────────────────────────
          const _SectionLabel('DURATION'),
          const SizedBox(height: 8),
          Row(
            children: [
              _DurationChip(label: 'Whole', onPressed: hasSelection ? onWhole : null),
              const SizedBox(width: 6),
              _DurationChip(label: 'Half', onPressed: hasSelection ? onHalf : null),
              const SizedBox(width: 6),
              _DurationChip(label: 'Quarter', onPressed: hasSelection ? onQuarter : null),
              const SizedBox(width: 6),
              _DurationChip(label: 'Eighth', onPressed: hasSelection ? onEighth : null),
            ],
          ),

          const SizedBox(height: 14),

          // ── CONTROLS ROW ─────────────────────────────────────────────────
          const _SectionLabel('CONTROLS'),
          const SizedBox(height: 8),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              _ControlButton(
                icon: Icons.arrow_upward_rounded,
                label: 'Up',
                onPressed: hasSelection ? onMoveUp : null,
              ),
              _ControlButton(
                icon: Icons.arrow_downward_rounded,
                label: 'Down',
                onPressed: hasSelection ? onMoveDown : null,
              ),
              _ControlButton(
                icon: Icons.skip_previous_rounded,
                label: 'Prev',
                onPressed: hasSelection ? onMoveToPrevMeasure : null,
              ),
              _ControlButton(
                icon: Icons.skip_next_rounded,
                label: 'Next',
                onPressed: hasSelection ? onMoveToNextMeasure : null,
              ),
              _ControlButton(
                icon: Icons.undo_rounded,
                label: 'Undo',
                onPressed: canUndo ? onUndo : null,
              ),
              _ControlButton(
                icon: Icons.redo_rounded,
                label: 'Redo',
                onPressed: canRedo ? onRedo : null,
              ),
              _ControlButton(
                icon: Icons.delete_outline_rounded,
                label: 'Delete',
                onPressed: hasSelection ? onDelete : null,
                isDestructive: true,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// SUB-WIDGETS
// ─────────────────────────────────────────────────────────────────────────────

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: const TextStyle(
        fontSize: 10,
        color: AppColors.textSecondary,
        letterSpacing: 1.2,
        fontWeight: FontWeight.w600,
      ),
    );
  }
}

/// Dropdown button for inserting notes or rests with duration selection.
class _InsertDropdown extends StatelessWidget {
  const _InsertDropdown({
    required this.label,
    required this.icon,
    required this.enabled,
    required this.items,
    required this.onSelected,
  });

  final String label;
  final IconData icon;
  final bool enabled;
  final List<String> items;
  final void Function(String value) onSelected;

  @override
  Widget build(BuildContext context) {
    return MenuAnchor(
      menuChildren: items.map((item) {
        return MenuItemButton(
          onPressed: enabled ? () => onSelected(item) : null,
          leadingIcon: Icon(
            _durationIcon(item),
            size: 16,
            color: AppColors.textSecondary,
          ),
          child: Text(
            item,
            style: const TextStyle(fontSize: 13, color: AppColors.textPrimary),
          ),
        );
      }).toList(),
      builder: (context, controller, child) {
        return OutlinedButton.icon(
          onPressed: enabled
              ? () {
                  if (controller.isOpen) {
                    controller.close();
                  } else {
                    controller.open();
                  }
                }
              : null,
          icon: Icon(icon, size: 16),
          label: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('Insert $label'),
              const SizedBox(width: 4),
              const Icon(Icons.arrow_drop_down_rounded, size: 18),
            ],
          ),
          style: OutlinedButton.styleFrom(
            backgroundColor: enabled ? AppColors.surface : AppColors.surfaceAlt,
            foregroundColor: enabled ? AppColors.textPrimary : AppColors.textSecondary,
            side: BorderSide(
              color: enabled ? AppColors.accent.withValues(alpha: 0.6) : AppColors.border,
            ),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          ),
        );
      },
    );
  }

  IconData _durationIcon(String duration) {
    switch (duration) {
      case 'Whole':
        return Icons.radio_button_unchecked_rounded;
      case 'Half':
        return Icons.looks_two_outlined;
      case 'Quarter':
        return Icons.looks_one_outlined;
      case 'Eighth':
        return Icons.looks_3_outlined;
      default:
        return Icons.music_note_rounded;
    }
  }
}

/// Compact chip-style duration button (for the Duration row).
class _DurationChip extends StatelessWidget {
  const _DurationChip({required this.label, required this.onPressed});

  final String label;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final enabled = onPressed != null;
    return Expanded(
      child: OutlinedButton(
        onPressed: onPressed,
        style: OutlinedButton.styleFrom(
          backgroundColor: enabled ? AppColors.surface : AppColors.surfaceAlt,
          foregroundColor: enabled ? AppColors.textPrimary : AppColors.textSecondary,
          side: BorderSide(
            color: enabled ? AppColors.accent.withValues(alpha: 0.5) : AppColors.border,
          ),
          padding: const EdgeInsets.symmetric(vertical: 10),
          minimumSize: const Size(0, 36),
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        ),
        child: Text(label, style: const TextStyle(fontSize: 12)),
      ),
    );
  }
}

/// Icon + label control button used in the Controls section.
class _ControlButton extends StatelessWidget {
  const _ControlButton({
    required this.icon,
    required this.label,
    required this.onPressed,
    this.isDestructive = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onPressed;
  final bool isDestructive;

  @override
  Widget build(BuildContext context) {
    final enabled = onPressed != null;

    final Color fgColor;
    final Color borderColor;
    if (!enabled) {
      fgColor = AppColors.textSecondary;
      borderColor = AppColors.border;
    } else if (isDestructive) {
      fgColor = Colors.redAccent;
      borderColor = Colors.redAccent.withValues(alpha: 0.5);
    } else {
      fgColor = AppColors.textPrimary;
      borderColor = AppColors.accent.withValues(alpha: 0.5);
    }

    return OutlinedButton(
      onPressed: onPressed,
      style: OutlinedButton.styleFrom(
        backgroundColor: enabled ? AppColors.surface : AppColors.surfaceAlt,
        foregroundColor: fgColor,
        side: BorderSide(color: borderColor),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        minimumSize: const Size(0, 36),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 15),
          const SizedBox(width: 4),
          Text(label, style: const TextStyle(fontSize: 12)),
        ],
      ),
    );
  }
}

class _DropInsertionTarget {
  const _DropInsertionTarget({
    required this.measureTarget,
    required this.insertIndex,
    required this.localPosition,
  });

  final NotationMeasureTarget measureTarget;
  final int insertIndex;
  final Offset localPosition;
}
