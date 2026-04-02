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
import 'package:note_vision/features/editor/presentation/widgets/editor_shell_panels.dart';
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
  // For now, just insert at the end of current measure as placeholder
  _updateState((state) {
    if (symbol.isRest) {
      return state.insertRestAfterSelection();
    } else {
      return state.insertNoteAfterSelection();
    }
  });

  // Later (ticket 56): improve position-based insertion using globalPosition
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
            final horizontalPadding = ResponsiveLayout.horizontalPadding(constraints.maxWidth);
            final isLandscape = constraints.maxWidth > constraints.maxHeight;
            final controlPanelWidth = (constraints.maxWidth * 0.32).clamp(280.0, 360.0);
            final notationPanel = Container(
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: AppColors.border),
              ),
              child: DragTarget<MusicalSymbol>(
              onWillAcceptWithDetails: (details) => true,
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
                );
              },
            )
          );


            final statusStrip = EditorStatusStrip(
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

            final actionBar = EditorActionBarPanel(
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
                EditorHeaderPanel(
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
                                    const MusicSymbolPalette(showLabels: false),
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
                              const MusicSymbolPalette(showLabels: false),
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
