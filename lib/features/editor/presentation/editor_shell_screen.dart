import 'package:flutter/material.dart';
import 'package:note_vision/core/models/note.dart';
import 'package:note_vision/core/models/rest.dart';
import 'package:note_vision/core/models/score.dart';
import 'package:note_vision/core/theme/app_theme.dart';
import 'package:note_vision/core/theme/responsive_layout.dart';
import 'package:note_vision/core/widgets/score_notation_viewer.dart';
import 'package:note_vision/features/editor/domain/editor_actions.dart';
import 'package:note_vision/features/editor/model/editor_state.dart';
import 'package:note_vision/features/editor/presentation/widgets/palette/music_symbol_palette.dart';
import 'package:note_vision/features/editor/domain/model/musical_symbol.dart';

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

  void _handleSymbolDrop(MusicalSymbol symbol, Offset globalPosition) {
    _updateState((state) {
      if (symbol.isRest) {
        return state.insertRestAfterSelection();
      } else {
        return state.insertNoteAfterSelection();
      }
    });

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Dropped ${symbol.label} — position logic coming in ticket 56'),
        duration: const Duration(seconds: 1),
      ),
    );
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
            final horizontalPadding =
                ResponsiveLayout.horizontalPadding(constraints.maxWidth);
            final isLandscape = constraints.maxWidth > constraints.maxHeight;
            final controlPanelWidth =
                (constraints.maxWidth * 0.32).clamp(280.0, 360.0) as double;

            final notationPanel = Container(
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: AppColors.border),
              ),
              child: DragTarget<MusicalSymbol>(
                onWillAcceptWithDetails: (details) => true,
                onAcceptWithDetails: (details) {
                  _handleSymbolDrop(details.data, details.offset);
                },
                builder: (context, candidateData, rejectedData) {
                  return SingleChildScrollView(
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
                          _onNotationSymbolTap(
                              target.measureIndex, target.symbolIndex);
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
              ),
            );

            final statusStrip = _StatusStrip(
              horizontalPadding: isLandscape ? 0 : horizontalPadding,
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

            // ── Redesigned action bar ──────────────────────────────────────
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
                  title: _editorState.score.title.isEmpty
                      ? 'Untitled Score'
                      : _editorState.score.title,
                  hasUnsavedChanges: _editorState.hasUnsavedChanges,
                  horizontalPadding: horizontalPadding,
                  onBack: () => Navigator.of(context).maybePop(),
                ),
                Expanded(
                  child: Padding(
                    padding:
                        EdgeInsets.symmetric(horizontal: horizontalPadding),
                    child: isLandscape
                        ? Row(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Expanded(child: notationPanel),
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
                              statusStrip,
                              const MusicSymbolPalette(),
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

// ─────────────────────────────────────────────────────────────────────────────
// HEADER
// ─────────────────────────────────────────────────────────────────────────────

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
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
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
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 30, minHeight: 30),
            ),
            const SizedBox(width: 6),
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
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 1),
                  const Text(
                    'Editor workspace',
                    style: TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 11,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            FilledButton.icon(
              onPressed: () {},
              icon: const Icon(Icons.save_outlined, size: 15),
              label: const Text('Save'),
              style: FilledButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 0),
                minimumSize: const Size(0, 28),
                textStyle: const TextStyle(fontSize: 11),
              ),
            ),
            const SizedBox(width: 6),
            OutlinedButton.icon(
              onPressed: () {},
              icon: const Icon(Icons.ios_share_outlined, size: 14),
              label: const Text('Export'),
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.textPrimary,
                side: const BorderSide(color: AppColors.border),
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 0),
                minimumSize: const Size(0, 28),
                textStyle: const TextStyle(fontSize: 11),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// STATUS STRIP
// ─────────────────────────────────────────────────────────────────────────────

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
      margin: EdgeInsets.fromLTRB(horizontalPadding, 6, horizontalPadding, 6),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      // Horizontal scroll so chips never wrap on narrow screens
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            _StatusItem(label: 'Type', value: symbolType),
            const SizedBox(width: 5),
            _StatusItem(label: 'Pitch', value: pitch),
            const SizedBox(width: 5),
            _StatusItem(label: 'Duration', value: durationType),
            const SizedBox(width: 5),
            _StatusItem(label: 'Measure', value: measure),
            const SizedBox(width: 5),
            _StatusNavButton(
              icon: Icons.chevron_left_rounded,
              onPressed: onPrevMeasure,
            ),
            const SizedBox(width: 4),
            _StatusNavButton(
              icon: Icons.chevron_right_rounded,
              onPressed: onNextMeasure,
            ),
          ],
        ),
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
    return SizedBox(
      width: 28,
      height: 28,
      child: OutlinedButton(
        onPressed: onPressed,
        style: OutlinedButton.styleFrom(
          side: const BorderSide(color: AppColors.border),
          padding: EdgeInsets.zero,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
          ),
        ),
        child: Icon(icon, size: 16),
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
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: AppColors.surfaceAlt,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(label,
              style: const TextStyle(
                  fontSize: 10, color: AppColors.textSecondary)),
          Text(value,
              style: const TextStyle(
                color: AppColors.textPrimary,
                fontSize: 12,
                fontWeight: FontWeight.w500,
              )),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// ACTION BAR  (redesigned)
// ─────────────────────────────────────────────────────────────────────────────

class _EditorActionBar extends StatefulWidget {
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
  State<_EditorActionBar> createState() => _EditorActionBarState();
}

class _EditorActionBarState extends State<_EditorActionBar> {
  bool _noteMenuOpen = false;
  bool _restMenuOpen = false;

  void _closeAll() => setState(() {
        _noteMenuOpen = false;
        _restMenuOpen = false;
      });

  void _toggleNote() => setState(() {
        _noteMenuOpen = !_noteMenuOpen;
        _restMenuOpen = false;
      });

  void _toggleRest() => setState(() {
        _restMenuOpen = !_restMenuOpen;
        _noteMenuOpen = false;
      });

  @override
  Widget build(BuildContext context) {
    return Container(
      color: AppColors.surfaceAlt,
      padding: EdgeInsets.fromLTRB(
          widget.horizontalPadding, 9, widget.horizontalPadding, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── INSERT row ──────────────────────────────────────────────────
          _SectionRow(
            label: 'INSERT',
            children: [
              // Note dropdown
              _InsertDropdown(
                label: 'Note',
                icon: Icons.music_note_outlined,
                isOpen: _noteMenuOpen,
                enabled: widget.hasMeasureContext,
                onTap: widget.hasMeasureContext ? _toggleNote : null,
                items: [
                  _DropdownItem(
                    label: 'Whole',
                    badge: '4 beats',
                    onTap: () {
                      _closeAll();
                      widget.onWhole();
                      widget.onInsertNote();
                    },
                  ),
                  _DropdownItem(
                    label: 'Half',
                    badge: '2 beats',
                    onTap: () {
                      _closeAll();
                      widget.onHalf();
                      widget.onInsertNote();
                    },
                  ),
                  _DropdownItem(
                    label: 'Quarter',
                    badge: '1 beat',
                    onTap: () {
                      _closeAll();
                      widget.onQuarter();
                      widget.onInsertNote();
                    },
                  ),
                  _DropdownItem(
                    label: 'Eighth',
                    badge: '½ beat',
                    onTap: () {
                      _closeAll();
                      widget.onEighth();
                      widget.onInsertNote();
                    },
                  ),
                ],
              ),
              const SizedBox(width: 6),
              // Rest dropdown
              _InsertDropdown(
                label: 'Rest',
                icon: Icons.pause_outlined,
                isOpen: _restMenuOpen,
                enabled: widget.hasMeasureContext,
                onTap: widget.hasMeasureContext ? _toggleRest : null,
                items: [
                  _DropdownItem(
                    label: 'Whole',
                    badge: '4 beats',
                    onTap: () {
                      _closeAll();
                      widget.onWhole();
                      widget.onInsertRest();
                    },
                  ),
                  _DropdownItem(
                    label: 'Half',
                    badge: '2 beats',
                    onTap: () {
                      _closeAll();
                      widget.onHalf();
                      widget.onInsertRest();
                    },
                  ),
                  _DropdownItem(
                    label: 'Quarter',
                    badge: '1 beat',
                    onTap: () {
                      _closeAll();
                      widget.onQuarter();
                      widget.onInsertRest();
                    },
                  ),
                ],
              ),
            ],
          ),

          const SizedBox(height: 6),
          const Divider(height: 1, thickness: 0.5),
          const SizedBox(height: 6),

          // ── CONTROLS row ────────────────────────────────────────────────
          _SectionRow(
            label: 'CONTROLS',
            children: [
              _ControlButton(
                icon: Icons.arrow_upward_rounded,
                label: 'Up',
                enabled: widget.hasSelection,
                onTap: widget.onMoveUp,
              ),
              _ControlButton(
                icon: Icons.arrow_downward_rounded,
                label: 'Down',
                enabled: widget.hasSelection,
                onTap: widget.onMoveDown,
              ),
              _ControlButton(
                icon: Icons.skip_previous_rounded,
                label: 'Prev',
                enabled: widget.hasSelection,
                onTap: widget.onMoveToPrevMeasure,
              ),
              _ControlButton(
                icon: Icons.skip_next_rounded,
                label: 'Next',
                enabled: widget.hasSelection,
                onTap: widget.onMoveToNextMeasure,
              ),
              _ControlButton(
                icon: Icons.undo_rounded,
                label: 'Undo',
                enabled: widget.canUndo,
                onTap: widget.onUndo,
              ),
              _ControlButton(
                icon: Icons.redo_rounded,
                label: 'Redo',
                enabled: widget.canRedo,
                onTap: widget.onRedo,
              ),
              _ControlButton(
                icon: Icons.delete_outline_rounded,
                label: 'Delete',
                enabled: widget.hasSelection,
                onTap: widget.onDelete,
                isDanger: true,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// SHARED SMALL WIDGETS
// ─────────────────────────────────────────────────────────────────────────────

/// Row with a muted left label and wrapping children
class _SectionRow extends StatelessWidget {
  const _SectionRow({required this.label, required this.children});

  final String label;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 58,
          child: Padding(
            padding: const EdgeInsets.only(top: 7),
            child: Text(
              label,
              style: const TextStyle(
                fontSize: 10,
                color: AppColors.textSecondary,
                letterSpacing: 0.8,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ),
        Expanded(
          child: Wrap(
            spacing: 5,
            runSpacing: 5,
            children: children,
          ),
        ),
      ],
    );
  }
}

/// Compact icon+label button used in the Controls row
class _ControlButton extends StatelessWidget {
  const _ControlButton({
    required this.icon,
    required this.label,
    required this.enabled,
    required this.onTap,
    this.isDanger = false,
  });

  final IconData icon;
  final String label;
  final bool enabled;
  final VoidCallback onTap;
  final bool isDanger;

  @override
  Widget build(BuildContext context) {
    final errorColor = Theme.of(context).colorScheme.error;

    final fgColor = !enabled
        ? AppColors.textSecondary
        : isDanger
            ? errorColor
            : AppColors.textPrimary;

    final borderColor = !enabled
        ? AppColors.border
        : isDanger
            ? errorColor.withValues(alpha: 0.45)
            : AppColors.border;

    return OutlinedButton(
      onPressed: enabled ? onTap : null,
      style: OutlinedButton.styleFrom(
        foregroundColor: fgColor,
        side: BorderSide(color: borderColor),
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 0),
        minimumSize: const Size(0, 28),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        textStyle: const TextStyle(fontSize: 11),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: fgColor),
          const SizedBox(width: 4),
          Text(label),
        ],
      ),
    );
  }
}

/// Data class for a single item inside an insert dropdown
class _DropdownItem {
  const _DropdownItem({
    required this.label,
    required this.badge,
    required this.onTap,
  });

  final String label;
  final String badge;
  final VoidCallback onTap;
}

/// Dropdown button + overlay menu used in the Insert row
class _InsertDropdown extends StatelessWidget {
  const _InsertDropdown({
    required this.label,
    required this.icon,
    required this.isOpen,
    required this.enabled,
    required this.onTap,
    required this.items,
  });

  final String label;
  final IconData icon;
  final bool isOpen;
  final bool enabled;
  final VoidCallback? onTap;
  final List<_DropdownItem> items;

  @override
  Widget build(BuildContext context) {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        // ── Trigger button ────────────────────────────────────────────────
        OutlinedButton(
          onPressed: onTap,
          style: OutlinedButton.styleFrom(
            backgroundColor: AppColors.surfaceAlt,
            foregroundColor:
                enabled ? AppColors.textPrimary : AppColors.textSecondary,
            side: BorderSide(color: AppColors.border),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 0),
            minimumSize: const Size(0, 28),
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            textStyle: const TextStyle(fontSize: 11),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 13),
              const SizedBox(width: 4),
              Text(label),
              const SizedBox(width: 4),
              AnimatedRotation(
                turns: isOpen ? 0.5 : 0,
                duration: const Duration(milliseconds: 150),
                child: const Icon(Icons.keyboard_arrow_down_rounded, size: 14),
              ),
            ],
          ),
        ),

        // ── Dropdown menu (pops upward) ───────────────────────────────────
        if (isOpen)
          Positioned(
            bottom: 32,
            left: 0,
            child: Material(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(12),
              child: Container(
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppColors.border),
                ),
                padding: const EdgeInsets.all(4),
                child: IntrinsicWidth(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    mainAxisSize: MainAxisSize.min,
                    children: items.map((item) {
                      return InkWell(
                        onTap: item.onTap,
                        borderRadius: BorderRadius.circular(8),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 7),
                          child: Row(
                            children: [
                              Expanded(
                                child: Text(
                                  item.label,
                                  style: const TextStyle(
                                    fontSize: 12,
                                    color: AppColors.textPrimary,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 10),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(
                                  color: AppColors.surfaceAlt,
                                  borderRadius: BorderRadius.circular(10),
                                  border: Border.all(color: AppColors.border),
                                ),
                                child: Text(
                                  item.badge,
                                  style: const TextStyle(
                                    fontSize: 10,
                                    color: AppColors.textSecondary,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}