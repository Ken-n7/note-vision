import 'package:flutter/material.dart';
import 'package:note_vision/core/models/note.dart';
import 'package:note_vision/core/models/rest.dart';
import 'package:note_vision/core/models/score.dart';
import 'package:note_vision/core/models/score_symbol.dart';
import 'package:note_vision/core/widgets/score_notation/score_notation_painter.dart';
import 'package:note_vision/core/theme/app_theme.dart';
import 'package:note_vision/core/theme/responsive_layout.dart';
import 'package:note_vision/core/widgets/score_notation_viewer.dart';
import 'package:note_vision/features/editor/domain/editor_actions.dart';
import 'package:note_vision/features/editor/model/editor_state.dart';
import 'package:note_vision/features/editor/presentation/widgets/symbol_palette.dart';

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

enum _BottomPanelTab { tools, symbols, file }

class _EditorShellScreenState extends State<EditorShellScreen> {
  late EditorState _editorState;
  _BottomPanelTab? _activeBottomTab;

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

  void _onPaletteDrop(NotationInsertTarget target, Object data) {
    if (data is! PaletteDragData) return;
    final symbol = _buildDroppedSymbol(data.type, target);
    _updateState(
      (state) => state.insertSymbolAtMeasureIndex(
        measureIndex: target.measureIndex,
        insertIndex: target.insertIndex,
        symbol: symbol,
      ),
    );
  }

  ScoreSymbol _buildDroppedSymbol(PaletteSymbolType type, NotationInsertTarget target) {
    switch (type) {
      case PaletteSymbolType.wholeNote:
        return Note(
          step: target.step,
          octave: target.octave.clamp(1, 7).toInt(),
          duration: 4,
          type: 'whole',
        );
      case PaletteSymbolType.halfNote:
        return Note(
          step: target.step,
          octave: target.octave.clamp(1, 7).toInt(),
          duration: 2,
          type: 'half',
        );
      case PaletteSymbolType.quarterNote:
        return Note(
          step: target.step,
          octave: target.octave.clamp(1, 7).toInt(),
          duration: 1,
          type: 'quarter',
        );
      case PaletteSymbolType.eighthNote:
        return Note(
          step: target.step,
          octave: target.octave.clamp(1, 7).toInt(),
          duration: 1,
          type: 'eighth',
        );
      case PaletteSymbolType.wholeRest:
        return const Rest(duration: 4, type: 'whole');
      case PaletteSymbolType.halfRest:
        return const Rest(duration: 2, type: 'half');
      case PaletteSymbolType.quarterRest:
        return const Rest(duration: 1, type: 'quarter');
    }
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

  void _togglePanel(_BottomPanelTab tab) {
    setState(() {
      _activeBottomTab = _activeBottomTab == tab ? null : tab;
    });
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
            final notationPanel = Container(
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
                    minMeasureWidth: 220,
                    selectedMeasureIndex: _editorState.selectedMeasureIndex,
                    selectedSymbolIndex: _editorState.selectedSymbolIndex,
                    canAcceptExternalDrop: (data) => data is PaletteDragData,
                    onExternalDrop: _onPaletteDrop,
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
            );


            final canvasView = notationPanel;

            final statusStrip = _StatusStrip(
              horizontalPadding: 0,
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
              horizontalPadding: 0,
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
                    child: Column(
                      children: [
                        Expanded(child: canvasView),
                        AnimatedSwitcher(
                          duration: const Duration(milliseconds: 220),
                          child: _BottomPanelHost(
                            key: ValueKey(_activeBottomTab),
                            activeTab: _activeBottomTab,
                            toolsPanel: SingleChildScrollView(
                              child: Column(
                                children: [
                                  statusStrip,
                                  actionBar,
                                ],
                              ),
                            ),
                            symbolsPanel: const SymbolPalette(),
                            filePanel: _FilePanel(
                              onSave: () {},
                              onExport: () {},
                            ),
                          ),
                        ),
                        _BottomTabBar(
                          activeTab: _activeBottomTab,
                          onTapTools: () => _togglePanel(_BottomPanelTab.tools),
                          onTapSymbols: () => _togglePanel(_BottomPanelTab.symbols),
                          onTapFile: () => _togglePanel(_BottomPanelTab.file),
                        ),
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
      child: LayoutBuilder(
        builder: (context, constraints) {
          final isCompact = constraints.maxWidth < 520;
          final titleStyle = TextStyle(
            color: AppColors.textPrimary,
            fontSize: isCompact ? 16 : 18,
            fontWeight: FontWeight.w700,
          );

          return Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppColors.border),
            ),
            child: Column(
              children: [
                Row(
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
                            style: titleStyle,
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
                  ],
                ),
              ],
            ),
          );
        },
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
      child: LayoutBuilder(
        builder: (context, constraints) {
          final cardWidth = ((constraints.maxWidth - 12) / 2).clamp(120.0, 200.0);
          return Wrap(
            spacing: 12,
            runSpacing: 8,
            children: [
              _StatusItem(label: 'Type', value: symbolType, width: cardWidth),
              _StatusItem(label: 'Pitch', value: pitch, width: cardWidth),
              _StatusItem(label: 'Duration', value: durationType, width: cardWidth),
              _StatusItem(label: 'Measure', value: measure, width: cardWidth),
              _StatusNavButton(
                icon: Icons.chevron_left_rounded,
                onPressed: onPrevMeasure,
              ),
              _StatusNavButton(
                icon: Icons.chevron_right_rounded,
                onPressed: onNextMeasure,
              ),
            ],
          );
        },
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
  const _StatusItem({required this.label, required this.value, required this.width});

  final String label;
  final String value;
  final double width;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
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

class _BottomPanelHost extends StatelessWidget {
  const _BottomPanelHost({
    super.key,
    required this.activeTab,
    required this.toolsPanel,
    required this.symbolsPanel,
    required this.filePanel,
  });

  final _BottomPanelTab? activeTab;
  final Widget toolsPanel;
  final Widget symbolsPanel;
  final Widget filePanel;

  @override
  Widget build(BuildContext context) {
    if (activeTab == null) return const SizedBox.shrink();

    Widget child;
    switch (activeTab!) {
      case _BottomPanelTab.tools:
        child = toolsPanel;
        break;
      case _BottomPanelTab.symbols:
        child = symbolsPanel;
        break;
      case _BottomPanelTab.file:
        child = filePanel;
        break;
    }

    return Container(
      constraints: const BoxConstraints(maxHeight: 300),
      decoration: const BoxDecoration(
        color: AppColors.surfaceAlt,
        border: Border(
          top: BorderSide(color: AppColors.border),
        ),
      ),
      child: child,
    );
  }
}

class _BottomTabBar extends StatelessWidget {
  const _BottomTabBar({
    required this.activeTab,
    required this.onTapTools,
    required this.onTapSymbols,
    required this.onTapFile,
  });

  final _BottomPanelTab? activeTab;
  final VoidCallback onTapTools;
  final VoidCallback onTapSymbols;
  final VoidCallback onTapFile;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 64,
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
      decoration: const BoxDecoration(
        color: AppColors.surface,
        border: Border(top: BorderSide(color: AppColors.border)),
      ),
      child: Row(
        children: [
          Expanded(
            child: _BottomTabButton(
              label: 'Tools',
              icon: Icons.build_outlined,
              isActive: activeTab == _BottomPanelTab.tools,
              onPressed: onTapTools,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: _BottomTabButton(
              label: 'Symbols',
              icon: Icons.music_note_outlined,
              isActive: activeTab == _BottomPanelTab.symbols,
              onPressed: onTapSymbols,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: _BottomTabButton(
              label: 'File',
              icon: Icons.folder_open_outlined,
              isActive: activeTab == _BottomPanelTab.file,
              onPressed: onTapFile,
            ),
          ),
        ],
      ),
    );
  }
}

class _BottomTabButton extends StatelessWidget {
  const _BottomTabButton({
    required this.label,
    required this.icon,
    required this.isActive,
    required this.onPressed,
  });

  final String label;
  final IconData icon;
  final bool isActive;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return OutlinedButton.icon(
      onPressed: onPressed,
      icon: Icon(icon, size: 16),
      label: Text(label),
      style: OutlinedButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
        backgroundColor: isActive ? AppColors.accent.withValues(alpha: 0.14) : AppColors.surfaceAlt,
        foregroundColor: AppColors.textPrimary,
        side: BorderSide(color: isActive ? AppColors.accent : AppColors.border),
      ),
    );
  }
}

class _FilePanel extends StatelessWidget {
  const _FilePanel({required this.onSave, required this.onExport});

  final VoidCallback onSave;
  final VoidCallback onExport;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 16),
      child: Row(
        children: [
          Expanded(
            child: FilledButton.icon(
              onPressed: onSave,
              icon: const Icon(Icons.save_outlined, size: 16),
              label: const Text('Save'),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: OutlinedButton.icon(
              onPressed: onExport,
              icon: const Icon(Icons.ios_share_outlined, size: 16),
              label: const Text('Export'),
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.textPrimary,
                side: const BorderSide(color: AppColors.border),
              ),
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
