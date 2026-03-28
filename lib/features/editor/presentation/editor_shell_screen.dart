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
    _editorState = widget.args.initialState.copyWith(score: widget.args.score);
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

      if (isSameSelection) {
        return state.copyWith(clearSelection: true);
      }

      final parts = state.score.parts;
      if (parts.isEmpty || measureIndex < 0 || measureIndex >= parts.first.measures.length) {
        return state.copyWith(clearSelection: true);
      }
      final symbols = parts.first.measures[measureIndex].symbols;
      if (symbolIndex < 0 || symbolIndex >= symbols.length) {
        return state.copyWith(clearSelection: true);
      }

      return state.copyWith(
        selectedPartIndex: 0,
        selectedMeasureIndex: measureIndex,
        selectedSymbolIndex: symbolIndex,
        selectedSymbol: symbols[symbolIndex],
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final selected = _editorState.selectedSymbol;
    final hasSelection = _editorState.hasSelection;

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final horizontalPadding =
                ResponsiveLayout.horizontalPadding(constraints.maxWidth);

            return Column(
              children: [
                _EditorHeader(
                  title: _editorState.score.title.isEmpty
                      ? 'Untitled Score'
                      : _editorState.score.title,
                  hasUnsavedChanges: _editorState.hasUnsavedChanges,
                  horizontalPadding: horizontalPadding,
                ),
                Expanded(
                  child: Padding(
                    padding: EdgeInsets.symmetric(horizontal: horizontalPadding),
                    child: SingleChildScrollView(
                      child: Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: ScoreNotationViewer(
                          score: _editorState.score,
                          selectedMeasureIndex: _editorState.selectedMeasureIndex,
                          selectedSymbolIndex: _editorState.selectedSymbolIndex,
                          onSymbolTap: (target) {
                            if (target == null) {
                              _updateState((state) => state.copyWith(clearSelection: true));
                              return;
                            }
                            _onNotationSymbolTap(target.measureIndex, target.symbolIndex);
                          },
                        ),
                      ),
                    ),
                  ),
                ),
                _StatusStrip(
                  horizontalPadding: horizontalPadding,
                  symbolType: selected == null
                      ? 'None'
                      : selected is Note
                          ? 'Note'
                          : 'Rest',
                  pitch: selected is Note ? selected.pitch : '—',
                  durationType: selected == null
                      ? '—'
                      : selected is Note
                          ? selected.type
                          : (selected as Rest).type,
                  measure: _editorState.selectedMeasureIndex == null
                      ? '—'
                      : (_editorState.selectedMeasureIndex! + 1).toString(),
                ),
                _EditorActionBar(
                  horizontalPadding: horizontalPadding,
                  hasSelection: hasSelection,
                  canUndo: _editorState.canUndo,
                  canRedo: _editorState.canRedo,
                  onMoveUp: () => _updateState((s) => s.moveSelectedSymbolUp()),
                  onMoveDown: () =>
                      _updateState((s) => s.moveSelectedSymbolDown()),
                  onWhole: () =>
                      _updateState((s) => s.setSelectedDuration(wholeDuration)),
                  onHalf: () =>
                      _updateState((s) => s.setSelectedDuration(halfDuration)),
                  onQuarter: () => _updateState(
                    (s) => s.setSelectedDuration(quarterDuration),
                  ),
                  onEighth: () =>
                      _updateState((s) => s.setSelectedDuration(eighthDuration)),
                  onInsertNote: () =>
                      _updateState((s) => s.insertNoteAfterSelection()),
                  onInsertRest: () =>
                      _updateState((s) => s.insertRestAfterSelection()),
                  onDelete: () => _updateState((s) => s.deleteSelectedSymbol()),
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
  });

  final String title;
  final bool hasUnsavedChanges;
  final double horizontalPadding;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(horizontalPadding, 12, horizontalPadding, 8),
      child: Row(
        children: [
          Expanded(
            child: Text(
              hasUnsavedChanges ? '$title *' : title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: AppColors.textPrimary,
                fontSize: 18,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          FilledButton.icon(
            onPressed: () {},
            icon: const Icon(Icons.save_outlined),
            label: const Text('Save'),
          ),
        ],
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
  });

  final double horizontalPadding;
  final String symbolType;
  final String pitch;
  final String durationType;
  final String measure;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: EdgeInsets.fromLTRB(horizontalPadding, 8, horizontalPadding, 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          _StatusItem(label: 'Type', value: symbolType),
          _StatusItem(label: 'Pitch', value: pitch),
          _StatusItem(label: 'Duration', value: durationType),
          _StatusItem(label: 'Measure', value: measure),
        ],
      ),
    );
  }
}

class _StatusItem extends StatelessWidget {
  const _StatusItem({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Column(
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
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}

class _EditorActionBar extends StatelessWidget {
  const _EditorActionBar({
    required this.horizontalPadding,
    required this.hasSelection,
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
    required this.onUndo,
    required this.onRedo,
  });

  final double horizontalPadding;
  final bool hasSelection;
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
  final VoidCallback onUndo;
  final VoidCallback onRedo;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: AppColors.surfaceAlt,
      padding: EdgeInsets.fromLTRB(
        horizontalPadding / 2,
        8,
        horizontalPadding / 2,
        16,
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            _ActionButton(
              label: 'Move Up',
              onPressed: hasSelection ? onMoveUp : null,
            ),
            _ActionButton(
              label: 'Move Down',
              onPressed: hasSelection ? onMoveDown : null,
            ),
            _ActionButton(label: 'W', onPressed: hasSelection ? onWhole : null),
            _ActionButton(label: 'H', onPressed: hasSelection ? onHalf : null),
            _ActionButton(
              label: 'Q',
              onPressed: hasSelection ? onQuarter : null,
            ),
            _ActionButton(label: 'E', onPressed: hasSelection ? onEighth : null),
            _ActionButton(
              label: 'Insert Note',
              onPressed: onInsertNote,
            ),
            _ActionButton(
              label: 'Insert Rest',
              onPressed: onInsertRest,
            ),
            _ActionButton(
              label: 'Delete',
              onPressed: hasSelection ? onDelete : null,
            ),
            _ActionButton(label: 'Undo', onPressed: canUndo ? onUndo : null),
            _ActionButton(label: 'Redo', onPressed: canRedo ? onRedo : null),
          ],
        ),
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
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: OutlinedButton(
        onPressed: onPressed,
        style: OutlinedButton.styleFrom(
          foregroundColor: AppColors.textPrimary,
          side: const BorderSide(color: AppColors.border),
        ),
        child: Text(label),
      ),
    );
  }
}
