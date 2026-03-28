import 'package:flutter/material.dart';
import 'package:note_vision/core/models/note.dart';
import 'package:note_vision/core/models/rest.dart';
import 'package:note_vision/core/models/score.dart';
import 'package:note_vision/core/theme/app_theme.dart';
import 'package:note_vision/core/theme/responsive_layout.dart';
import 'package:note_vision/core/widgets/score_notation_viewer.dart';
import 'package:note_vision/features/editor/domain/editor_actions.dart';
import 'package:note_vision/features/editor/model/editor_state.dart';

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
  late EditorState _editorState;

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
                    child: Container(
                      margin: const EdgeInsets.only(bottom: 12),
                      decoration: BoxDecoration(
                        color: AppColors.surface,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: AppColors.border),
                      ),
                      child: SingleChildScrollView(
                        child: Padding(
                          padding: const EdgeInsets.all(8),
                          child: ScoreNotationViewer(
                            score: _editorState.score,
                            selectedMeasureIndex: _editorState.selectedMeasureIndex,
                            selectedSymbolIndex: _editorState.selectedSymbolIndex,
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
                      ),
                    ),
                  ),
                ),
                _StatusStrip(
                  horizontalPadding: horizontalPadding,
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
                ),
                _EditorActionBar(
                  horizontalPadding: horizontalPadding,
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
      margin: EdgeInsets.fromLTRB(horizontalPadding, 8, horizontalPadding, 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: Wrap(
        spacing: 12,
        runSpacing: 8,
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
          const Text(
            'TOOLS',
            style: TextStyle(
              fontSize: 11,
              color: AppColors.textSecondary,
              letterSpacing: 1.1,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _ActionButton(label: 'Move Up', onPressed: hasSelection ? onMoveUp : null),
              _ActionButton(label: 'Move Down', onPressed: hasSelection ? onMoveDown : null),
              _ActionButton(label: 'Whole', onPressed: hasSelection ? onWhole : null),
              _ActionButton(label: 'Half', onPressed: hasSelection ? onHalf : null),
              _ActionButton(label: 'Quarter', onPressed: hasSelection ? onQuarter : null),
              _ActionButton(label: 'Eighth', onPressed: hasSelection ? onEighth : null),
              _ActionButton(label: 'Insert Note', onPressed: hasMeasureContext ? onInsertNote : null),
              _ActionButton(label: 'Insert Rest', onPressed: hasMeasureContext ? onInsertRest : null),
              _ActionButton(label: 'Delete', onPressed: hasSelection ? onDelete : null),
              _ActionButton(
                label: 'To Prev Measure',
                onPressed: hasSelection ? onMoveToPrevMeasure : null,
              ),
              _ActionButton(
                label: 'To Next Measure',
                onPressed: hasSelection ? onMoveToNextMeasure : null,
              ),
              _ActionButton(label: 'Undo', onPressed: canUndo ? onUndo : null),
              _ActionButton(label: 'Redo', onPressed: canRedo ? onRedo : null),
            ],
          ),
        ],
      ),
    );
  }
}

class _ActionButton extends StatelessWidget {
  const _ActionButton({required this.label, required this.onPressed});

  final String label;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final enabled = onPressed != null;
    return OutlinedButton(
      onPressed: onPressed,
      style: OutlinedButton.styleFrom(
        backgroundColor: enabled ? AppColors.surface : AppColors.surfaceAlt,
        foregroundColor: enabled ? AppColors.textPrimary : AppColors.textSecondary,
        side: BorderSide(
          color: enabled ? AppColors.accent.withValues(alpha: 0.6) : AppColors.border,
        ),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      ),
      child: Text(label),
    );
  }
}
