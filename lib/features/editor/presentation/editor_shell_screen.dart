import 'package:flutter/material.dart';
import 'package:note_vision/core/models/note.dart';
import 'package:note_vision/core/models/rest.dart';
import 'package:note_vision/core/models/score.dart';
import 'package:note_vision/core/models/score_symbol.dart';
import 'package:note_vision/core/widgets/score_notation/score_notation_painter.dart';
import 'package:note_vision/core/theme/app_theme.dart';
import 'package:note_vision/core/widgets/score_notation_viewer.dart';
import 'package:note_vision/features/editor/domain/editor_actions.dart';
import 'package:note_vision/features/editor/model/editor_state.dart';
import 'package:note_vision/features/editor/presentation/widgets/symbol_palette.dart';
import 'package:note_vision/features/musicXML/musicxml_export_service.dart';

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
  double _canvasZoom = 1.0;
  bool _insertMode = false;
  PaletteSymbolType? _insertSymbolType;

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

  void _onNotationSymbolTap(int partIndex, int measureIndex, int symbolIndex) {
    _updateState((state) {
      final isSame =
          state.selectedPartIndex == partIndex &&
          state.selectedMeasureIndex == measureIndex &&
          state.selectedSymbolIndex == symbolIndex;
      if (isSame) return _clearSymbolSelection(state);

      final parts = state.score.parts;
      if (parts.isEmpty || partIndex >= parts.length) {
        return state.copyWith(clearSelection: true);
      }
      final measures = parts[partIndex].measures;
      if (measureIndex >= measures.length) {
        return state.copyWith(clearSelection: true);
      }
      final symbols = measures[measureIndex].symbols;
      if (symbolIndex < 0 || symbolIndex >= symbols.length) {
        return _clearSymbolSelection(state);
      }
      return state.copyWith(
        selectedPartIndex: partIndex,
        selectedMeasureIndex: measureIndex,
        selectedSymbolIndex: symbolIndex,
        selectedSymbol: symbols[symbolIndex],
      );
    });
  }

  void _onInsertTap(NotationInsertTarget? target) {
    if (target == null || _insertSymbolType == null) return;
    final symbol = _buildSymbol(_insertSymbolType!, target);
    _updateState(
      (state) => state.insertSymbolAtMeasureIndex(
        measureIndex: target.measureIndex,
        insertIndex: target.insertIndex,
        symbol: symbol,
      ),
    );
  }

  void _onPaletteDrop(NotationInsertTarget target, Object data) {
    if (data is! PaletteDragData) return;
    final symbol = _buildSymbol(data.type, target);
    _updateState(
      (state) => state.insertSymbolAtMeasureIndex(
        measureIndex: target.measureIndex,
        insertIndex: target.insertIndex,
        symbol: symbol,
      ),
    );
  }

  ScoreSymbol _buildSymbol(PaletteSymbolType type, NotationInsertTarget target) {
    switch (type) {
      case PaletteSymbolType.wholeNote:
        return Note(step: target.step, octave: target.octave.clamp(1, 7).toInt(), duration: 8, type: 'whole');
      case PaletteSymbolType.halfNote:
        return Note(step: target.step, octave: target.octave.clamp(1, 7).toInt(), duration: 4, type: 'half');
      case PaletteSymbolType.quarterNote:
        return Note(step: target.step, octave: target.octave.clamp(1, 7).toInt(), duration: 2, type: 'quarter');
      case PaletteSymbolType.eighthNote:
        return Note(step: target.step, octave: target.octave.clamp(1, 7).toInt(), duration: 1, type: 'eighth');
      case PaletteSymbolType.wholeRest:
        return const Rest(duration: 8, type: 'whole');
      case PaletteSymbolType.halfRest:
        return const Rest(duration: 4, type: 'half');
      case PaletteSymbolType.quarterRest:
        return const Rest(duration: 2, type: 'quarter');
    }
  }

  EditorState _withDefaultMeasureContext(EditorState state) {
    if (state.selectedPartIndex != null && state.selectedMeasureIndex != null) return state;
    if (state.score.parts.isEmpty || state.score.parts.first.measures.isEmpty) return state;
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

  void _onPaletteTypeTap(PaletteSymbolType type) {
    setState(() {
      if (!_insertMode) {
        _insertMode = true;
        _insertSymbolType = type;
      } else if (_insertSymbolType == type) {
        _insertMode = false;
        _insertSymbolType = null;
      } else {
        _insertSymbolType = type;
      }
    });
  }

  void _toggleInsertMode() {
    setState(() {
      _insertMode = !_insertMode;
      if (!_insertMode) _insertSymbolType = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final selected = _editorState.selectedSymbol;
    final hasSelection = _editorState.hasSelection;
    final hasMeasureContext =
        _editorState.selectedPartIndex != null && _editorState.selectedMeasureIndex != null;
    final selectedMeasureIndex = _editorState.selectedMeasureIndex ?? 0;
    final selectedPartIndex = _editorState.selectedPartIndex ?? 0;
    final measureCount = _editorState.score.parts.isEmpty ||
            selectedPartIndex >= _editorState.score.parts.length
        ? 0
        : _editorState.score.parts[selectedPartIndex].measures.length;

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final isLandscape = constraints.maxWidth > constraints.maxHeight;

            final notationArea = _NotationArea(
              editorState: _editorState,
              canvasZoom: _canvasZoom,
              insertMode: _insertMode,
              insertSymbolType: _insertSymbolType,
              onZoomIn: _canvasZoom < 2.0
                  ? () => setState(() => _canvasZoom = (_canvasZoom + 0.1).clamp(0.75, 2.0))
                  : null,
              onZoomOut: _canvasZoom > 0.75
                  ? () => setState(() => _canvasZoom = (_canvasZoom - 0.1).clamp(0.75, 2.0))
                  : null,
              onToggleInsertMode: _toggleInsertMode,
              onPaletteTypeTap: _onPaletteTypeTap,
              onSymbolTap: (target) {
                if (target == null) {
                  _updateState((s) => _clearSymbolSelection(s));
                } else {
                  _onNotationSymbolTap(target.partIndex, target.measureIndex, target.symbolIndex);
                }
              },
              onInsertTap: _onInsertTap,
              onSymbolReorder: (event) {
                _updateState(
                  (s) => s.reorderSymbolWithinMeasure(
                    measureIndex: event.measureIndex,
                    fromSymbolIndex: event.fromSymbolIndex,
                    toSymbolIndex: event.toSymbolIndex,
                  ),
                );
              },
              onExternalDrop: _onPaletteDrop,
            );

            final inspectorPanel = _InspectorPanel(
              isLandscape: isLandscape,
              selected: selected,
              hasSelection: hasSelection,
              hasMeasureContext: hasMeasureContext,
              selectedMeasureIndex: selectedMeasureIndex,
              measureCount: measureCount,
              onPrevMeasure: selectedMeasureIndex > 0
                  ? () => _updateState((s) => s.copyWith(
                        selectedPartIndex: 0,
                        selectedMeasureIndex: selectedMeasureIndex - 1,
                        selectedSymbolIndex: null,
                        selectedSymbol: null,
                      ))
                  : null,
              onNextMeasure: selectedMeasureIndex < measureCount - 1
                  ? () => _updateState((s) => s.copyWith(
                        selectedPartIndex: 0,
                        selectedMeasureIndex: selectedMeasureIndex + 1,
                        selectedSymbolIndex: null,
                        selectedSymbol: null,
                      ))
                  : null,
              onMoveUp: () => _updateState((s) => s.moveSelectedSymbolUp()),
              onMoveDown: () => _updateState((s) => s.moveSelectedSymbolDown()),
              onWhole: () => _updateState((s) => s.setSelectedDuration(wholeDuration)),
              onHalf: () => _updateState((s) => s.setSelectedDuration(halfDuration)),
              onQuarter: () => _updateState((s) => s.setSelectedDuration(quarterDuration)),
              onEighth: () => _updateState((s) => s.setSelectedDuration(eighthDuration)),
              onSetAccidental: (alter) => _updateState((s) => s.setSelectedNoteAccidental(alter)),
              onInsertNote: () => _updateState((s) => s.insertNoteAfterSelection()),
              onInsertRest: () => _updateState((s) => s.insertRestAfterSelection()),
              onDelete: () => _updateState((s) => s.deleteSelectedSymbol()),
              onMoveToPrev: () => _updateState((s) => s.moveSelectedSymbolToMeasureOffset(-1)),
              onMoveToNext: () => _updateState((s) => s.moveSelectedSymbolToMeasureOffset(1)),
            );

            return Column(
              children: [
                _EditorHeader(
                  title: _editorState.score.title.isEmpty
                      ? 'Untitled Score'
                      : _editorState.score.title,
                  hasUnsavedChanges: _editorState.hasUnsavedChanges,
                  canUndo: _editorState.canUndo,
                  canRedo: _editorState.canRedo,
                  onBack: () => Navigator.of(context).maybePop(),
                  onUndo: () => _updateState((s) => s.applyUndo()),
                  onRedo: () => _updateState((s) => s.applyRedo()),
                  onExport: () => const MusicXmlExportService().exportAndShare(_editorState.score),
                  onSaveToDevice: () async {
                    try {
                      final file = await const MusicXmlExportService().exportToDevice(_editorState.score);
                      if (!context.mounted) return;
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text('Saved to ${file.path}'),
                          duration: const Duration(seconds: 4),
                        ),
                      );
                    } catch (e) {
                      if (!context.mounted) return;
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('Save failed: $e')),
                      );
                    }
                  },
                ),
                Expanded(
                  child: isLandscape
                      ? Row(
                          children: [
                            Expanded(
                              child: Padding(
                                padding: const EdgeInsets.fromLTRB(12, 0, 6, 12),
                                child: notationArea,
                              ),
                            ),
                            SizedBox(
                              width: (constraints.maxWidth * 0.3).clamp(260.0, 320.0),
                              child: Padding(
                                padding: const EdgeInsets.fromLTRB(6, 0, 12, 12),
                                child: inspectorPanel,
                              ),
                            ),
                          ],
                        )
                      : Column(
                          children: [
                            Expanded(
                              child: Padding(
                                padding: const EdgeInsets.fromLTRB(12, 0, 12, 0),
                                child: notationArea,
                              ),
                            ),
                            SizedBox(
                              height: (constraints.maxHeight * 0.36).clamp(200.0, 280.0),
                              child: Padding(
                                padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                                child: inspectorPanel,
                              ),
                            ),
                          ],
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

// ---------------------------------------------------------------------------
// Header
// ---------------------------------------------------------------------------

enum _ExportOption { share, saveToDevice }

class _ExportMenuItem extends StatelessWidget {
  const _ExportMenuItem({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 16, color: AppColors.textPrimary),
        const SizedBox(width: 10),
        Text(
          label,
          style: const TextStyle(color: AppColors.textPrimary, fontSize: 13),
        ),
      ],
    );
  }
}

class _EditorHeader extends StatelessWidget {
  const _EditorHeader({
    required this.title,
    required this.hasUnsavedChanges,
    required this.canUndo,
    required this.canRedo,
    required this.onBack,
    required this.onUndo,
    required this.onRedo,
    required this.onExport,
    required this.onSaveToDevice,
  });

  final String title;
  final bool hasUnsavedChanges;
  final bool canUndo;
  final bool canRedo;
  final VoidCallback onBack;
  final VoidCallback onUndo;
  final VoidCallback onRedo;
  final VoidCallback onExport;
  final VoidCallback onSaveToDevice;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 56,
      decoration: const BoxDecoration(
        color: AppColors.surface,
        border: Border(bottom: BorderSide(color: AppColors.border)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Row(
        children: [
          IconButton(
            onPressed: onBack,
            icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 16),
            color: AppColors.textPrimary,
            tooltip: 'Back',
          ),
          const SizedBox(width: 4),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: AppColors.textPrimary,
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    if (hasUnsavedChanges) ...[
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: AppColors.accent.withValues(alpha: 0.18),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: const Text(
                          'Unsaved',
                          style: TextStyle(
                            color: AppColors.accent,
                            fontSize: 10,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
                const Text(
                  'Score Editor',
                  style: TextStyle(color: AppColors.textSecondary, fontSize: 10),
                ),
              ],
            ),
          ),
          IconButton(
            onPressed: canUndo ? onUndo : null,
            icon: const Icon(Icons.undo_rounded, size: 18),
            color: canUndo ? AppColors.textPrimary : AppColors.textSecondary.withValues(alpha: 0.3),
            tooltip: 'Undo',
            visualDensity: VisualDensity.compact,
          ),
          IconButton(
            onPressed: canRedo ? onRedo : null,
            icon: const Icon(Icons.redo_rounded, size: 18),
            color: canRedo ? AppColors.textPrimary : AppColors.textSecondary.withValues(alpha: 0.3),
            tooltip: 'Redo',
            visualDensity: VisualDensity.compact,
          ),
          const SizedBox(width: 6),
          FilledButton.icon(
            onPressed: () {},
            icon: const Icon(Icons.save_rounded, size: 15),
            label: const Text('Save', style: TextStyle(fontSize: 13)),
            style: FilledButton.styleFrom(
              minimumSize: const Size(0, 34),
              padding: const EdgeInsets.symmetric(horizontal: 12),
            ),
          ),
          const SizedBox(width: 6),
          PopupMenuButton<_ExportOption>(
            onSelected: (option) {
              if (option == _ExportOption.share) {
                onExport();
              } else {
                onSaveToDevice();
              }
            },
            tooltip: 'Export MusicXML',
            icon: const Icon(Icons.ios_share_rounded, size: 18),
            color: AppColors.surface,
            itemBuilder: (_) => [
              const PopupMenuItem(
                value: _ExportOption.share,
                child: _ExportMenuItem(
                  icon: Icons.ios_share_rounded,
                  label: 'Share…',
                ),
              ),
              const PopupMenuItem(
                value: _ExportOption.saveToDevice,
                child: _ExportMenuItem(
                  icon: Icons.download_rounded,
                  label: 'Save to Device',
                ),
              ),
            ],
          ),
          const SizedBox(width: 4),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Notation area
// ---------------------------------------------------------------------------

class _NotationArea extends StatelessWidget {
  const _NotationArea({
    required this.editorState,
    required this.canvasZoom,
    required this.insertMode,
    required this.insertSymbolType,
    required this.onZoomIn,
    required this.onZoomOut,
    required this.onToggleInsertMode,
    required this.onPaletteTypeTap,
    required this.onSymbolTap,
    required this.onInsertTap,
    required this.onSymbolReorder,
    required this.onExternalDrop,
  });

  final EditorState editorState;
  final double canvasZoom;
  final bool insertMode;
  final PaletteSymbolType? insertSymbolType;
  final VoidCallback? onZoomIn;
  final VoidCallback? onZoomOut;
  final VoidCallback onToggleInsertMode;
  final ValueChanged<PaletteSymbolType> onPaletteTypeTap;
  final ValueChanged<NotationSymbolTarget?> onSymbolTap;
  final ValueChanged<NotationInsertTarget?> onInsertTap;
  final ValueChanged<NotationSymbolReorder> onSymbolReorder;
  final void Function(NotationInsertTarget, Object) onExternalDrop;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Expanded(
          child: Stack(
            children: [
              Positioned.fill(
                child: Container(
                  decoration: BoxDecoration(
                    color: AppColors.surface,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: AppColors.border),
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(11),
                    child: SingleChildScrollView(
                      child: Padding(
                        padding: const EdgeInsets.all(8),
                        child: ScoreNotationViewer(
                          score: editorState.score,
                          selectedPartIndex: editorState.selectedPartIndex ?? 0,
                          minMeasureWidth: 220 * canvasZoom,
                          selectedMeasureIndex: editorState.selectedMeasureIndex,
                          selectedSymbolIndex: editorState.selectedSymbolIndex,
                          insertMode: insertMode,
                          canAcceptExternalDrop: (data) => data is PaletteDragData,
                          onExternalDrop: onExternalDrop,
                          onSymbolTap: insertMode ? null : onSymbolTap,
                          onInsertTap: insertMode ? onInsertTap : null,
                          onSymbolReorder: onSymbolReorder,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              // Insert mode banner
              if (insertMode)
                Positioned(
                  top: 8,
                  left: 0,
                  right: 0,
                  child: Center(
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
                      decoration: BoxDecoration(
                        color: AppColors.accent.withValues(alpha: 0.18),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: AppColors.accent.withValues(alpha: 0.5)),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.edit_rounded, size: 12, color: AppColors.accent),
                          const SizedBox(width: 5),
                          Text(
                            insertSymbolType != null
                                ? 'Insert mode — tap to place ${_typeLabel(insertSymbolType!)}'
                                : 'Insert mode — select a symbol below',
                            style: const TextStyle(
                              color: AppColors.accent,
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              // Floating controls
              Positioned(
                right: 8,
                bottom: 8,
                child: _FloatingControls(
                  zoomPercent: (canvasZoom * 100).round(),
                  insertMode: insertMode,
                  onZoomIn: onZoomIn,
                  onZoomOut: onZoomOut,
                  onToggleInsertMode: onToggleInsertMode,
                ),
              ),
            ],
          ),
        ),
        SymbolPalette(
          selectedType: insertMode ? insertSymbolType : null,
          onTypeTap: onPaletteTypeTap,
        ),
      ],
    );
  }

  String _typeLabel(PaletteSymbolType t) => switch (t) {
        PaletteSymbolType.wholeNote => 'whole note',
        PaletteSymbolType.halfNote => 'half note',
        PaletteSymbolType.quarterNote => 'quarter note',
        PaletteSymbolType.eighthNote => 'eighth note',
        PaletteSymbolType.wholeRest => 'whole rest',
        PaletteSymbolType.halfRest => 'half rest',
        PaletteSymbolType.quarterRest => 'quarter rest',
      };
}

class _FloatingControls extends StatelessWidget {
  const _FloatingControls({
    required this.zoomPercent,
    required this.insertMode,
    required this.onZoomIn,
    required this.onZoomOut,
    required this.onToggleInsertMode,
  });

  final int zoomPercent;
  final bool insertMode;
  final VoidCallback? onZoomIn;
  final VoidCallback? onZoomOut;
  final VoidCallback onToggleInsertMode;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        GestureDetector(
          onTap: onToggleInsertMode,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: insertMode
                  ? AppColors.accent.withValues(alpha: 0.2)
                  : AppColors.surface.withValues(alpha: 0.9),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: insertMode ? AppColors.accent : AppColors.border,
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  insertMode ? Icons.edit_rounded : Icons.touch_app_rounded,
                  size: 13,
                  color: insertMode ? AppColors.accent : AppColors.textSecondary,
                ),
                const SizedBox(width: 5),
                Text(
                  insertMode ? 'Insert' : 'Select',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: insertMode ? AppColors.accent : AppColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 6),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
          decoration: BoxDecoration(
            color: AppColors.surface.withValues(alpha: 0.9),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: AppColors.border),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _ZoomBtn(icon: Icons.remove_rounded, onPressed: onZoomOut),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 6),
                child: Text(
                  '$zoomPercent%',
                  style: const TextStyle(
                    fontSize: 11,
                    color: AppColors.textSecondary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              _ZoomBtn(icon: Icons.add_rounded, onPressed: onZoomIn),
            ],
          ),
        ),
      ],
    );
  }
}

class _ZoomBtn extends StatelessWidget {
  const _ZoomBtn({required this.icon, required this.onPressed});

  final IconData icon;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 28,
      height: 28,
      child: IconButton(
        onPressed: onPressed,
        icon: Icon(icon, size: 14),
        color: onPressed != null
            ? AppColors.textPrimary
            : AppColors.textSecondary.withValues(alpha: 0.4),
        padding: EdgeInsets.zero,
        visualDensity: VisualDensity.compact,
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Inspector panel (routes to landscape or portrait variant)
// ---------------------------------------------------------------------------

class _InspectorPanel extends StatelessWidget {
  const _InspectorPanel({
    required this.isLandscape,
    required this.selected,
    required this.hasSelection,
    required this.hasMeasureContext,
    required this.selectedMeasureIndex,
    required this.measureCount,
    required this.onPrevMeasure,
    required this.onNextMeasure,
    required this.onMoveUp,
    required this.onMoveDown,
    required this.onWhole,
    required this.onHalf,
    required this.onQuarter,
    required this.onEighth,
    required this.onSetAccidental,
    required this.onInsertNote,
    required this.onInsertRest,
    required this.onDelete,
    required this.onMoveToPrev,
    required this.onMoveToNext,
  });

  final bool isLandscape;
  final ScoreSymbol? selected;
  final bool hasSelection;
  final bool hasMeasureContext;
  final int selectedMeasureIndex;
  final int measureCount;
  final VoidCallback? onPrevMeasure;
  final VoidCallback? onNextMeasure;
  final VoidCallback onMoveUp;
  final VoidCallback onMoveDown;
  final VoidCallback onWhole;
  final VoidCallback onHalf;
  final VoidCallback onQuarter;
  final VoidCallback onEighth;
  final void Function(int? alter) onSetAccidental;
  final VoidCallback onInsertNote;
  final VoidCallback onInsertRest;
  final VoidCallback onDelete;
  final VoidCallback onMoveToPrev;
  final VoidCallback onMoveToNext;

  @override
  Widget build(BuildContext context) {
    final selectionCard = _SelectionCard(
      selected: selected,
      hasSelection: hasSelection,
      selectedMeasureIndex: selectedMeasureIndex,
      measureCount: measureCount,
      onPrevMeasure: onPrevMeasure,
      onNextMeasure: onNextMeasure,
      compact: !isLandscape,
    );

    final isNoteSelected = selected is Note;
    final currentAlter = isNoteSelected ? (selected as Note).alter : null;

    final groups = [
      _ActionGroup(
        label: 'PITCH',
        children: [
          _ActionTile(icon: Icons.keyboard_arrow_up_rounded, label: 'Up', onPressed: hasSelection ? onMoveUp : null),
          _ActionTile(icon: Icons.keyboard_arrow_down_rounded, label: 'Down', onPressed: hasSelection ? onMoveDown : null),
        ],
      ),
      _ActionGroup(
        label: 'ACCIDENTAL',
        children: [
          _AccTile(label: '—', sublabel: 'None', isActive: isNoteSelected && currentAlter == null,
              onPressed: isNoteSelected ? () => onSetAccidental(null) : null),
          _AccTile(label: '♯', sublabel: 'Sharp', isActive: isNoteSelected && currentAlter == 1,
              onPressed: isNoteSelected ? () => onSetAccidental(1) : null),
          _AccTile(label: '♭', sublabel: 'Flat', isActive: isNoteSelected && currentAlter == -1,
              onPressed: isNoteSelected ? () => onSetAccidental(-1) : null),
          _AccTile(label: '♮', sublabel: 'Natural', isActive: isNoteSelected && currentAlter == 0,
              onPressed: isNoteSelected ? () => onSetAccidental(0) : null),
        ],
      ),
      _ActionGroup(
        label: 'DURATION',
        children: [
          _DurTile(label: 'W', sublabel: 'Whole', onPressed: hasSelection ? onWhole : null),
          _DurTile(label: 'H', sublabel: 'Half', onPressed: hasSelection ? onHalf : null),
          _DurTile(label: '♩', sublabel: 'Qtr', onPressed: hasSelection ? onQuarter : null),
          _DurTile(label: '♪', sublabel: '8th', onPressed: hasSelection ? onEighth : null),
        ],
      ),
      _ActionGroup(
        label: 'MEASURE',
        children: [
          _ActionTile(icon: Icons.skip_previous_rounded, label: 'Prev', onPressed: hasSelection ? onMoveToPrev : null),
          _ActionTile(icon: Icons.skip_next_rounded, label: 'Next', onPressed: hasSelection ? onMoveToNext : null),
        ],
      ),
      _ActionGroup(
        label: 'INSERT',
        children: [
          _ActionTile(icon: Icons.music_note_rounded, label: 'Note', onPressed: hasMeasureContext ? onInsertNote : null),
          _ActionTile(icon: Icons.horizontal_rule_rounded, label: 'Rest', onPressed: hasMeasureContext ? onInsertRest : null),
        ],
      ),
      _ActionGroup(
        label: 'EDIT',
        children: [
          _ActionTile(icon: Icons.delete_outline_rounded, label: 'Delete', onPressed: hasSelection ? onDelete : null, danger: true),
        ],
      ),
    ];

    if (isLandscape) {
      return Container(
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.border),
        ),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              selectionCard,
              const SizedBox(height: 14),
              ...groups.map((g) => Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: _LandscapeGroup(group: g),
                  )),
            ],
          ),
        ),
      );
    }

    // Portrait — drag handle + compact selection + horizontal action scroll
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        children: [
          Center(
            child: Container(
              margin: const EdgeInsets.only(top: 8),
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: AppColors.border,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
            child: selectionCard,
          ),
          const SizedBox(height: 8),
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: groups
                    .map((g) => _PortraitGroup(group: g))
                    .expand((w) => [w, _Divider()])
                    .toList()
                  ..removeLast(),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Action group data model
// ---------------------------------------------------------------------------

class _ActionGroup {
  const _ActionGroup({required this.label, required this.children});

  final String label;
  final List<Widget> children;
}

class _LandscapeGroup extends StatelessWidget {
  const _LandscapeGroup({required this.group});

  final _ActionGroup group;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          group.label,
          style: const TextStyle(
            fontSize: 10,
            color: AppColors.textSecondary,
            letterSpacing: 0.8,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 6),
        Wrap(spacing: 6, runSpacing: 6, children: group.children),
      ],
    );
  }
}

class _PortraitGroup extends StatelessWidget {
  const _PortraitGroup({required this.group});

  final _ActionGroup group;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          group.label,
          style: const TextStyle(
            fontSize: 9,
            color: AppColors.textSecondary,
            letterSpacing: 0.8,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 4),
        Row(
          children: group.children
              .map((c) => Padding(padding: const EdgeInsets.only(right: 4), child: c))
              .toList(),
        ),
      ],
    );
  }
}

class _Divider extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      width: 1,
      height: 52,
      margin: const EdgeInsets.symmetric(horizontal: 8),
      color: AppColors.border,
    );
  }
}

// ---------------------------------------------------------------------------
// Selection card
// ---------------------------------------------------------------------------

class _SelectionCard extends StatelessWidget {
  const _SelectionCard({
    required this.selected,
    required this.hasSelection,
    required this.selectedMeasureIndex,
    required this.measureCount,
    required this.onPrevMeasure,
    required this.onNextMeasure,
    this.compact = false,
  });

  final ScoreSymbol? selected;
  final bool hasSelection;
  final int selectedMeasureIndex;
  final int measureCount;
  final VoidCallback? onPrevMeasure;
  final VoidCallback? onNextMeasure;
  final bool compact;

  String get _pitchLabel => selected is Note ? (selected as Note).pitch : '—';
  String get _durLabel {
    if (selected is Note) return (selected as Note).type;
    if (selected is Rest) return (selected as Rest).type;
    return '—';
  }

  bool get _isNote => selected is Note;

  @override
  Widget build(BuildContext context) {
    final measureNav = _MeasureNav(
      selectedMeasureIndex: selectedMeasureIndex,
      measureCount: measureCount,
      onPrev: onPrevMeasure,
      onNext: onNextMeasure,
    );

    if (compact) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: AppColors.surfaceAlt,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: AppColors.border),
        ),
        child: Row(
          children: [
            if (hasSelection) ...[
              Container(
                padding: const EdgeInsets.all(4),
                decoration: BoxDecoration(
                  color: AppColors.accent.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(5),
                ),
                child: Icon(
                  _isNote ? Icons.music_note_rounded : Icons.horizontal_rule_rounded,
                  size: 13,
                  color: AppColors.accent,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                _pitchLabel,
                style: const TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(width: 6),
              Text(
                _durLabel,
                style: const TextStyle(color: AppColors.textSecondary, fontSize: 11),
              ),
            ] else
              const Text(
                'Tap a symbol to select',
                style: TextStyle(color: AppColors.textSecondary, fontSize: 12),
              ),
            const Spacer(),
            measureNav,
          ],
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.surfaceAlt,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text(
                'SELECTION',
                style: TextStyle(
                  fontSize: 10,
                  color: AppColors.textSecondary,
                  letterSpacing: 1.0,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const Spacer(),
              measureNav,
            ],
          ),
          const SizedBox(height: 10),
          if (hasSelection)
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: AppColors.accent.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Icon(
                    _isNote ? Icons.music_note_rounded : Icons.horizontal_rule_rounded,
                    size: 16,
                    color: AppColors.accent,
                  ),
                ),
                const SizedBox(width: 10),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _isNote ? _pitchLabel : 'Rest',
                      style: const TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    Text(
                      _durLabel,
                      style: const TextStyle(color: AppColors.textSecondary, fontSize: 11),
                    ),
                  ],
                ),
              ],
            )
          else
            const Text(
              'Tap a note or rest to select it',
              style: TextStyle(color: AppColors.textSecondary, fontSize: 12),
            ),
        ],
      ),
    );
  }
}

class _MeasureNav extends StatelessWidget {
  const _MeasureNav({
    required this.selectedMeasureIndex,
    required this.measureCount,
    required this.onPrev,
    required this.onNext,
  });

  final int selectedMeasureIndex;
  final int measureCount;
  final VoidCallback? onPrev;
  final VoidCallback? onNext;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _NavBtn(icon: Icons.chevron_left_rounded, onPressed: onPrev),
        Container(
          constraints: const BoxConstraints(minWidth: 42),
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: AppColors.border),
          ),
          child: Text(
            measureCount > 0 ? 'M ${selectedMeasureIndex + 1}' : '—',
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 11,
              color: AppColors.textPrimary,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        _NavBtn(icon: Icons.chevron_right_rounded, onPressed: onNext),
      ],
    );
  }
}

class _NavBtn extends StatelessWidget {
  const _NavBtn({required this.icon, required this.onPressed});

  final IconData icon;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 28,
      height: 28,
      child: IconButton(
        onPressed: onPressed,
        icon: Icon(icon, size: 16),
        padding: EdgeInsets.zero,
        color: onPressed != null
            ? AppColors.textPrimary
            : AppColors.textSecondary.withValues(alpha: 0.3),
        visualDensity: VisualDensity.compact,
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Action tiles
// ---------------------------------------------------------------------------

class _ActionTile extends StatelessWidget {
  const _ActionTile({
    required this.icon,
    required this.label,
    required this.onPressed,
    this.danger = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onPressed;
  final bool danger;

  @override
  Widget build(BuildContext context) {
    final enabled = onPressed != null;
    final activeColor = danger ? const Color(0xFFEF4444) : AppColors.textPrimary;
    final iconColor = enabled
        ? (danger ? const Color(0xFFEF4444) : AppColors.textPrimary)
        : AppColors.textSecondary.withValues(alpha: 0.35);

    return Tooltip(
      message: label,
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(8),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          width: 52,
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
          decoration: BoxDecoration(
            color: enabled ? AppColors.surfaceAlt : AppColors.background,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: enabled
                  ? (danger
                      ? const Color(0xFFEF4444).withValues(alpha: 0.4)
                      : AppColors.border)
                  : AppColors.border.withValues(alpha: 0.4),
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 17, color: iconColor),
              const SizedBox(height: 3),
              Text(
                label,
                style: TextStyle(
                  fontSize: 9,
                  color: enabled
                      ? activeColor.withValues(alpha: 0.7)
                      : AppColors.textSecondary.withValues(alpha: 0.3),
                  fontWeight: FontWeight.w500,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AccTile extends StatelessWidget {
  const _AccTile({
    required this.label,
    required this.sublabel,
    required this.isActive,
    required this.onPressed,
  });

  final String label;
  final String sublabel;
  final bool isActive;
  final VoidCallback? onPressed;

  static const _accent = Color(0xFFD4A96A);

  @override
  Widget build(BuildContext context) {
    final enabled = onPressed != null;

    return Tooltip(
      message: sublabel,
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(8),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          width: 44,
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
          decoration: BoxDecoration(
            color: isActive
                ? _accent.withValues(alpha: 0.15)
                : enabled
                    ? AppColors.surfaceAlt
                    : AppColors.background,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: isActive
                  ? _accent.withValues(alpha: 0.6)
                  : enabled
                      ? AppColors.border
                      : AppColors.border.withValues(alpha: 0.4),
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                label,
                style: TextStyle(
                  fontSize: 15,
                  color: isActive
                      ? _accent
                      : enabled
                          ? AppColors.textPrimary
                          : AppColors.textSecondary.withValues(alpha: 0.35),
                  fontWeight: FontWeight.w700,
                  height: 1.2,
                ),
              ),
              const SizedBox(height: 1),
              Text(
                sublabel,
                style: TextStyle(
                  fontSize: 9,
                  color: isActive
                      ? _accent.withValues(alpha: 0.8)
                      : enabled
                          ? AppColors.textSecondary.withValues(alpha: 0.7)
                          : AppColors.textSecondary.withValues(alpha: 0.3),
                  fontWeight: FontWeight.w500,
                ),
                maxLines: 1,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DurTile extends StatelessWidget {
  const _DurTile({
    required this.label,
    required this.sublabel,
    required this.onPressed,
  });

  final String label;
  final String sublabel;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final enabled = onPressed != null;

    return Tooltip(
      message: sublabel,
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(8),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          width: 44,
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
          decoration: BoxDecoration(
            color: enabled ? AppColors.surfaceAlt : AppColors.background,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: enabled ? AppColors.border : AppColors.border.withValues(alpha: 0.4),
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                label,
                style: TextStyle(
                  fontSize: 15,
                  color: enabled
                      ? AppColors.textPrimary
                      : AppColors.textSecondary.withValues(alpha: 0.35),
                  fontWeight: FontWeight.w700,
                  height: 1.2,
                ),
              ),
              const SizedBox(height: 1),
              Text(
                sublabel,
                style: TextStyle(
                  fontSize: 9,
                  color: enabled
                      ? AppColors.textSecondary.withValues(alpha: 0.7)
                      : AppColors.textSecondary.withValues(alpha: 0.3),
                  fontWeight: FontWeight.w500,
                ),
                maxLines: 1,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
