import 'dart:async' show StreamSubscription, unawaited;
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:note_vision/core/models/note.dart';
import 'package:note_vision/core/models/project.dart';
import 'package:note_vision/core/models/rest.dart';
import 'package:note_vision/core/models/score.dart';
import 'package:note_vision/core/models/score_symbol.dart';
import 'package:note_vision/core/services/playback_service.dart';
import 'package:note_vision/core/services/project_storage_service.dart';
import 'package:note_vision/core/widgets/score_notation/notation_layout.dart';
import 'package:note_vision/core/widgets/score_notation/score_notation_painter.dart';
import 'package:note_vision/core/theme/app_theme.dart';
import 'package:note_vision/core/widgets/score_notation_viewer.dart';
import 'package:note_vision/features/editor/domain/editor_actions.dart';
import 'package:note_vision/features/editor/model/editor_state.dart';
import 'package:note_vision/features/editor/presentation/widgets/playback_controls_bar.dart';
import 'package:note_vision/features/editor/presentation/widgets/symbol_palette.dart';
import 'package:note_vision/core/services/usage_stats_service.dart';
import 'package:note_vision/features/musicXML/musicxml_export_service.dart';
import 'package:note_vision/features/pdf/pdf_export_service.dart';

class EditorShellArgs {
  const EditorShellArgs({
    required this.score,
    required this.initialState,
    this.existingProject,
  });

  final Score score;
  final EditorState initialState;

  /// Non-null when the editor was opened from the project list screen.
  final Project? existingProject;
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
  bool _insertMode = false;
  bool _isDraggingNote = false;
  Offset _dragGlobal = Offset.zero;
  final GlobalKey _trashZoneKey = GlobalKey();
  NotationSymbolTarget? _dragTarget;
  PaletteSymbolType? _insertSymbolType;

  // Playback
  final _playback = PlaybackService.instance;
  PlaybackPosition _playbackPosition = PlaybackPosition.none;
  StreamSubscription<PlaybackPosition>? _positionSub;

  final _storage = ProjectStorageService();
  Project? _currentProject;
  int _scoreEditCount = 0;

  @override
  void initState() {
    super.initState();
    _currentProject = widget.args.existingProject;
    _editorState = _withDefaultMeasureContext(
      widget.args.initialState.copyWith(score: widget.args.score),
    );
    _initPlayback();
    _loadScoreEditCount();
  }

  Future<void> _initPlayback() async {
    await _playback.init();
    _positionSub = _playback.positionStream.listen((pos) {
      if (mounted) setState(() => _playbackPosition = pos);
    });
  }

  @override
  void dispose() {
    _positionSub?.cancel();
    _playback.stop();
    super.dispose();
  }

  // ── Save logic ─────────────────────────────────────────────────────────────

  Future<void> _onSave() async {
    if (_currentProject == null) {
      final defaultName = _editorState.score.title.trim().isEmpty
          ? 'Untitled'
          : _editorState.score.title.trim();
      final name = await _showNameDialog(defaultName);
      if (name == null || !mounted) return;

      final project = Project.create(name: name, score: _editorState.score);
      await _storage.saveProject(project);

      if (!mounted) return;
      setState(() {
        _currentProject = project;
        _editorState = _editorState.copyWith(hasUnsavedChanges: false);
      });
      _showSavedSnackbar(name);
    } else {
      final updated =
          _currentProject!.copyWithUpdated(score: _editorState.score);
      await _storage.saveProject(updated);

      if (!mounted) return;
      setState(() {
        _currentProject = updated;
        _editorState = _editorState.copyWith(hasUnsavedChanges: false);
      });
      _showSavedSnackbar(updated.name);
    }
  }

  Future<String?> _showNameDialog(String defaultName) {
    final controller = TextEditingController(text: defaultName);
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: const Text(
          'Name your project',
          style: TextStyle(color: AppColors.textPrimary),
        ),
        content: TextField(
          controller: controller,
          autofocus: true,
          style: const TextStyle(color: AppColors.textPrimary),
          decoration: const InputDecoration(
            hintText: 'Project name',
            hintStyle: TextStyle(color: AppColors.textSecondary),
            enabledBorder: UnderlineInputBorder(
              borderSide: BorderSide(color: AppColors.border),
            ),
            focusedBorder: UnderlineInputBorder(
              borderSide: BorderSide(color: AppColors.accent),
            ),
          ),
          onSubmitted: (v) {
            final trimmed = v.trim();
            Navigator.of(ctx).pop(trimmed.isEmpty ? null : trimmed);
          },
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text(
              'Cancel',
              style: TextStyle(color: AppColors.textSecondary),
            ),
          ),
          TextButton(
            onPressed: () {
              final trimmed = controller.text.trim();
              Navigator.of(ctx).pop(trimmed.isEmpty ? null : trimmed);
            },
            child: const Text(
              'Save',
              style: TextStyle(color: AppColors.accent),
            ),
          ),
        ],
      ),
    );
  }

  void _showSavedSnackbar(String name) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Saved as $name'),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  Future<void> _handlePopAttempt() async {
    final leave = await _showUnsavedChangesDialog();
    if (leave && mounted) Navigator.of(context).pop();
  }

  Future<bool> _showUnsavedChangesDialog() async {
    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: const Text(
          'Unsaved changes',
          style: TextStyle(color: AppColors.textPrimary),
        ),
        content: const Text(
          'You have unsaved changes. Leave without saving?',
          style: TextStyle(color: AppColors.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text(
              'Cancel',
              style: TextStyle(color: AppColors.textSecondary),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text(
              'Leave',
              style: TextStyle(color: AppColors.accent),
            ),
          ),
        ],
      ),
    );
    return result ?? false;
  }

  Future<void> _loadScoreEditCount() async {
    final count = await UsageStatsService.loadScoreEdits(_editorState.score.id);
    if (mounted) setState(() => _scoreEditCount = count);
  }

  void _updateState(EditorState Function(EditorState state) updater) {
    setState(() {
      final prev = _editorState;
      _editorState = updater(_editorState);
      if (_editorState.undoStack.length > prev.undoStack.length) {
        _scoreEditCount++;
        unawaited(UsageStatsService.incrementScoreEdits(_editorState.score.id));
      }
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
        partIndex: target.partIndex,
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
        partIndex: target.partIndex,
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
    final canDeleteMeasure = hasMeasureContext &&
        measureCount > 1 &&
        _editorState.score.parts[selectedPartIndex]
            .measures[selectedMeasureIndex].symbols.isEmpty;

    return PopScope(
      canPop: !_editorState.hasUnsavedChanges,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _handlePopAttempt();
      },
      child: Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final isLandscape = constraints.maxWidth > constraints.maxHeight;

            final notationArea = _NotationArea(
              editorState: _editorState,
              insertMode: _insertMode,
              insertSymbolType: _insertSymbolType,
              playbackPosition: _playbackPosition,
              isDraggingNote: _isDraggingNote,
              dragGlobal: _dragGlobal,
              trashZoneKey: _trashZoneKey,
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
              onDragStarted: (target) {
                setState(() {
                  _isDraggingNote = true;
                  _dragTarget = target;
                });
              },
              onDragGlobalUpdate: (global) {
                setState(() => _dragGlobal = global);
              },
              onDragCompleted: (reorder, global) {
                final trashBox =
                    _trashZoneKey.currentContext?.findRenderObject() as RenderBox?;
                final isOverTrash = trashBox != null &&
                    (trashBox.localToGlobal(Offset.zero) & trashBox.size).contains(global);
                if (isOverTrash && _dragTarget != null) {
                  final t = _dragTarget!;
                  _updateState((s) {
                    final symbol = s.score.parts[t.partIndex]
                        .measures[t.measureIndex].symbols[t.symbolIndex];
                    return s
                        .copyWith(
                          selectedPartIndex: t.partIndex,
                          selectedMeasureIndex: t.measureIndex,
                          selectedSymbolIndex: t.symbolIndex,
                          selectedSymbol: symbol,
                        )
                        .deleteSelectedSymbol();
                  });
                } else if (reorder != null) {
                  _updateState((s) => s.moveSymbolToDest(
                    fromPartIndex: reorder.fromPartIndex,
                    fromMeasureIndex: reorder.fromMeasureIndex,
                    fromSymbolIndex: reorder.fromSymbolIndex,
                    toPartIndex: reorder.toPartIndex,
                    toMeasureIndex: reorder.toMeasureIndex,
                    toSymbolIndex: reorder.toSymbolIndex,
                  ));
                }
                setState(() {
                  _isDraggingNote = false;
                  _dragGlobal = Offset.zero;
                  _dragTarget = null;
                });
              },
              onDragCancelled: () => setState(() {
                _isDraggingNote = false;
                _dragGlobal = Offset.zero;
                _dragTarget = null;
              }),
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
                        selectedPartIndex: selectedPartIndex,
                        selectedMeasureIndex: selectedMeasureIndex - 1,
                        selectedSymbolIndex: null,
                        selectedSymbol: null,
                      ))
                  : null,
              onNextMeasure: selectedMeasureIndex < measureCount - 1
                  ? () => _updateState((s) => s.copyWith(
                        selectedPartIndex: selectedPartIndex,
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
              onMoveToPrev: () => _updateState((s) => s.moveSelectedSymbolToMeasureOffset(-1)),
              onMoveToNext: () => _updateState((s) => s.moveSelectedSymbolToMeasureOffset(1)),
              onAddMeasure: () => _updateState((s) => s.addMeasureAfterSelected()),
              canDeleteMeasure: canDeleteMeasure,
              onDeleteMeasure: () => _updateState((s) => s.deleteSelectedMeasureIfEmpty()),
            );

            final scoreIsEmpty = _editorState.score.parts.isEmpty ||
                _editorState.score.parts.every((p) => p.measures.every((m) => m.symbols.isEmpty));

            return Column(
              children: [
                _EditorHeader(
                  title: _currentProject?.name ??
                      (_editorState.score.title.isEmpty
                          ? 'Untitled Score'
                          : _editorState.score.title),
                  hasUnsavedChanges: _editorState.hasUnsavedChanges,
                  editCount: _scoreEditCount,
                  canUndo: _editorState.canUndo,
                  canRedo: _editorState.canRedo,
                  onBack: () => Navigator.of(context).maybePop(),
                  onUndo: () => _updateState((s) => s.applyUndo()),
                  onRedo: () => _updateState((s) => s.applyRedo()),
                  onSave: _onSave,
                  onExportXml: () async {
                    try {
                      final path = await const MusicXmlExportService().exportToDevice(_editorState.score);
                      if (!context.mounted) return;
                      if (path != null) {
                        await UsageStatsService.incrementExports();
                        if (!context.mounted) return;
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('MusicXML saved'),
                            duration: Duration(seconds: 2),
                          ),
                        );
                      }
                    } catch (e) {
                      if (!context.mounted) return;
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('Export failed: $e')),
                      );
                    }
                  },
                  scoreIsEmpty: _editorState.score.parts.isEmpty ||
                      _editorState.score.parts.every((p) => p.measures.every((m) => m.symbols.isEmpty)),
                  onExportPdf: () async {
                    try {
                      final path = await const PdfExportService().exportToDevice(_editorState.score);
                      if (!context.mounted) return;
                      if (path != null) {
                        await UsageStatsService.incrementExports();
                        if (!context.mounted) return;
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('PDF saved'),
                            duration: Duration(seconds: 2),
                          ),
                        );
                      }
                    } catch (e) {
                      if (!context.mounted) return;
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('Export failed: $e')),
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
                PlaybackControlsBar(
                  isEmpty: scoreIsEmpty,
                  onPlay: () => _playback.play(_editorState.score),
                  onResume: _playback.resume,
                  onPause: _playback.pause,
                  onStop: _playback.stop,
                  onTempoChanged: _playback.setTempo,
                ),
              ],
            );
          },
        ),
      ),
    ),
    );
  }
}

// ---------------------------------------------------------------------------
// Header
// ---------------------------------------------------------------------------

enum _ExportOption { exportXml, exportPdf }

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
    required this.editCount,
    required this.canUndo,
    required this.canRedo,
    required this.onBack,
    required this.onUndo,
    required this.onRedo,
    required this.onSave,
    required this.onExportXml,
    required this.onExportPdf,
    required this.scoreIsEmpty,
  });

  final String title;
  final bool hasUnsavedChanges;
  final int editCount;
  final bool canUndo;
  final bool canRedo;
  final VoidCallback onBack;
  final VoidCallback onUndo;
  final VoidCallback onRedo;
  final VoidCallback onSave;
  final VoidCallback onExportXml;
  final VoidCallback onExportPdf;
  final bool scoreIsEmpty;

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
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        'Score Editor',
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(color: AppColors.textSecondary, fontSize: 10),
                      ),
                    ),
                    if (editCount > 0) ...[
                      const SizedBox(width: 6),
                      Flexible(
                        child: Text(
                          '· $editCount ${editCount == 1 ? 'edit' : 'edits'}',
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(color: AppColors.textSecondary, fontSize: 10),
                        ),
                      ),
                    ],
                  ],
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
            onPressed: onSave,
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
              if (option == _ExportOption.exportXml) {
                onExportXml();
              } else if (option == _ExportOption.exportPdf) {
                onExportPdf();
              }
            },
            tooltip: 'Export',
            icon: const Icon(Icons.ios_share_rounded, size: 18),
            color: AppColors.surface,
            itemBuilder: (_) => [
              const PopupMenuItem(
                value: _ExportOption.exportXml,
                child: _ExportMenuItem(
                  icon: Icons.download_rounded,
                  label: 'Export MusicXML…',
                ),
              ),
              PopupMenuItem(
                value: _ExportOption.exportPdf,
                enabled: !scoreIsEmpty,
                child: _ExportMenuItem(
                  icon: Icons.picture_as_pdf_rounded,
                  label: 'Export PDF…',
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
// Notation area — A4-like canvas with InteractiveViewer for pan/zoom
// ---------------------------------------------------------------------------

// Page geometry constants (portrait A4-like layout at logical pixels).
const double _kPageWidth = 760.0;
const double _kPagePaddingH = 16.0;
const double _kPagePaddingV = 28.0;
const int _kMeasuresPerRow = 3;
const double _kRowHeight = 140.0;
const double _kRowPrefixWidth = 86.0;
const double _kMeasureWidth =
    (_kPageWidth - _kPagePaddingH * 2 - _kRowPrefixWidth) / _kMeasuresPerRow;
const EdgeInsets _kPagePadding =
    EdgeInsets.symmetric(horizontal: _kPagePaddingH, vertical: _kPagePaddingV);

class _NotationArea extends StatefulWidget {
  const _NotationArea({
    required this.editorState,
    required this.insertMode,
    required this.insertSymbolType,
    required this.playbackPosition,
    required this.isDraggingNote,
    required this.dragGlobal,
    required this.trashZoneKey,
    required this.onToggleInsertMode,
    required this.onPaletteTypeTap,
    required this.onSymbolTap,
    required this.onInsertTap,
    required this.onDragStarted,
    required this.onDragGlobalUpdate,
    required this.onDragCompleted,
    required this.onDragCancelled,
    required this.onExternalDrop,
  });

  final EditorState editorState;
  final bool insertMode;
  final PaletteSymbolType? insertSymbolType;
  final PlaybackPosition playbackPosition;
  final bool isDraggingNote;
  final Offset dragGlobal;
  final GlobalKey trashZoneKey;
  final VoidCallback onToggleInsertMode;
  final ValueChanged<PaletteSymbolType> onPaletteTypeTap;
  final ValueChanged<NotationSymbolTarget?> onSymbolTap;
  final ValueChanged<NotationInsertTarget?> onInsertTap;
  final void Function(NotationSymbolTarget symbol) onDragStarted;
  final void Function(Offset global) onDragGlobalUpdate;
  final void Function(NotationSymbolReorder? reorder, Offset globalEndPosition) onDragCompleted;
  final VoidCallback onDragCancelled;
  final void Function(NotationInsertTarget, Object) onExternalDrop;

  @override
  State<_NotationArea> createState() => _NotationAreaState();
}

class _NotationAreaState extends State<_NotationArea> {
  final _transformController = TransformationController();
  Size? _viewportSize;
  Size? _contentSize;
  bool _fittedOnce = false;

  @override
  void initState() {
    super.initState();
    _transformController.addListener(_onTransformChanged);
  }

  @override
  void dispose() {
    _transformController.removeListener(_onTransformChanged);
    _transformController.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(_NotationArea oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Fit the whole score into view when playback starts so every note is visible.
    if (oldWidget.playbackPosition.isNone && !widget.playbackPosition.isNone) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _fitToScreen();
      });
    }
  }

  void _onTransformChanged() => setState(() {});

  void _fitToScreen() {
    final viewport = _viewportSize;
    final content = _contentSize;
    if (viewport == null || content == null) return;
    if (viewport.width <= 0 || viewport.height <= 0) return;

    final scale = math.min(
          viewport.width / content.width,
          viewport.height / content.height,
        ) *
        0.90;

    final tx = (viewport.width - content.width * scale) / 2;
    final ty = math.max(8.0, (viewport.height - content.height * scale) / 2);

    _transformController.value = Matrix4.identity()
      ..setEntry(0, 0, scale)
      ..setEntry(1, 1, scale)
      ..setEntry(0, 3, tx)
      ..setEntry(1, 3, ty);
  }

  void _zoomIn() => _applyScaleDelta(1.15);
  void _zoomOut() => _applyScaleDelta(1.0 / 1.15);

  void _applyScaleDelta(double delta) {
    final viewport = _viewportSize;
    if (viewport == null) return;
    final cx = viewport.width / 2;
    final cy = viewport.height / 2;

    final current = _transformController.value;
    final currentScale = current.getMaxScaleOnAxis();
    final translation = current.getTranslation();

    // Scale around the viewport centre.
    final newScale = currentScale * delta;
    final newTx = cx + delta * (translation.x - cx);
    final newTy = cy + delta * (translation.y - cy);

    _transformController.value = Matrix4.identity()
      ..setEntry(0, 0, newScale)
      ..setEntry(1, 1, newScale)
      ..setEntry(0, 3, newTx)
      ..setEntry(1, 3, newTy);
  }

  int get _zoomPercent =>
      (_transformController.value.getMaxScaleOnAxis() * 100).round();

  Size _computeContentSize() {
    final score = widget.editorState.score;
    if (score.parts.isEmpty) return const Size(_kPageWidth, 400);

    const calc = NotationLayoutCalculator();
    final layout = calc.calculate(
      measures: score.parts[0].measures,
      measuresPerRow: _kMeasuresPerRow,
      minMeasureWidth: _kMeasureWidth,
      rowHeight: _kRowHeight,
      padding: _kPagePadding,
      rowPrefixWidth: _kRowPrefixWidth,
      partCount: score.parts.length,
    );
    return layout.size;
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Expanded(
          child: Stack(
            children: [
              Positioned.fill(
                child: LayoutBuilder(
                  builder: (ctx, constraints) {
                    _viewportSize = constraints.biggest;
                    _contentSize = _computeContentSize();

                    if (!_fittedOnce &&
                        _viewportSize!.shortestSide > 0 &&
                        _contentSize!.width > 0) {
                      _fittedOnce = true;
                      WidgetsBinding.instance.addPostFrameCallback((_) {
                        if (mounted) _fitToScreen();
                      });
                    }

                    return ColoredBox(
                      color: const Color(0xFF1C1C1E),
                      child: ClipRect(
                        child: InteractiveViewer(
                          transformationController: _transformController,
                          // Disable pan while a note drag is in progress so the
                          // long-press drag isn't fought by the viewer's pan.
                          panEnabled: !widget.isDraggingNote,
                          scaleEnabled: true,
                          constrained: false,
                          minScale: 0.15,
                          maxScale: 5.0,
                          boundaryMargin: const EdgeInsets.all(double.infinity),
                          child: Container(
                            decoration: const BoxDecoration(
                              color: Colors.white,
                              boxShadow: [
                                BoxShadow(
                                  color: Color(0x40000000),
                                  blurRadius: 20,
                                  offset: Offset(0, 6),
                                ),
                              ],
                            ),
                            child: ScoreNotationViewer(
                              score: widget.editorState.score,
                              selectedPartIndex:
                                  widget.editorState.selectedPartIndex ?? 0,
                              measuresPerRow: _kMeasuresPerRow,
                              minMeasureWidth: _kMeasureWidth,
                              rowHeight: _kRowHeight,
                              padding: _kPagePadding,
                              backgroundColor: Colors.white,
                              selectedMeasureIndex:
                                  widget.editorState.selectedMeasureIndex,
                              selectedSymbolIndex:
                                  widget.editorState.selectedSymbolIndex,
                              playbackPartIndex: widget.playbackPosition.isNone
                                  ? null
                                  : widget.playbackPosition.partIndex,
                              playbackMeasureIndex:
                                  widget.playbackPosition.isNone
                                      ? null
                                      : widget.playbackPosition.measureIndex,
                              playbackSymbolIndex: widget.playbackPosition.isNone
                                  ? null
                                  : widget.playbackPosition.symbolIndex,
                              insertMode: widget.insertMode,
                              canAcceptExternalDrop: (data) =>
                                  data is PaletteDragData,
                              externalPreviewResolver:
                                  _previewGlyphForDragData,
                              onExternalDrop: widget.onExternalDrop,
                              onSymbolTap:
                                  widget.insertMode ? null : widget.onSymbolTap,
                              onInsertTap:
                                  widget.insertMode ? widget.onInsertTap : null,
                              onDragStarted: widget.insertMode
                                  ? null
                                  : widget.onDragStarted,
                              onDragGlobalUpdate: widget.onDragGlobalUpdate,
                              onDragCompleted: widget.onDragCompleted,
                              onDragCancelled: widget.onDragCancelled,
                            ),
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),

              // Insert mode banner
              if (widget.insertMode)
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
                        border: Border.all(
                            color: AppColors.accent.withValues(alpha: 0.5)),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.edit_rounded,
                              size: 12, color: AppColors.accent),
                          const SizedBox(width: 5),
                          Text(
                            widget.insertSymbolType != null
                                ? 'Insert mode — tap to place ${_typeLabel(widget.insertSymbolType!)}'
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

              // Trash zone — appears during note drag
              if (widget.isDraggingNote)
                Positioned(
                  bottom: 12,
                  left: 0,
                  right: 0,
                  child: Center(
                    child: _TrashZone(
                      key: widget.trashZoneKey,
                      isHovered: () {
                        if (widget.dragGlobal == Offset.zero) return false;
                        final box = widget.trashZoneKey.currentContext
                            ?.findRenderObject() as RenderBox?;
                        if (box == null) return false;
                        return (box.localToGlobal(Offset.zero) & box.size)
                            .contains(widget.dragGlobal);
                      }(),
                    ),
                  ),
                ),

              // Floating controls
              Positioned(
                right: 8,
                bottom: 8,
                child: _FloatingControls(
                  zoomPercent: _zoomPercent,
                  insertMode: widget.insertMode,
                  onZoomIn: _zoomIn,
                  onZoomOut: _zoomOut,
                  onFitToScreen: _fitToScreen,
                  onToggleInsertMode: widget.onToggleInsertMode,
                ),
              ),
            ],
          ),
        ),
        SymbolPalette(
          selectedType: widget.insertMode ? widget.insertSymbolType : null,
          onTypeTap: widget.onPaletteTypeTap,
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

  NotationPreviewGlyph? _previewGlyphForDragData(Object data) {
    if (data is! PaletteDragData) return null;
    return switch (data.type) {
      PaletteSymbolType.wholeNote => NotationPreviewGlyph.wholeNote,
      PaletteSymbolType.halfNote => NotationPreviewGlyph.halfNote,
      PaletteSymbolType.quarterNote => NotationPreviewGlyph.quarterNote,
      PaletteSymbolType.eighthNote => NotationPreviewGlyph.eighthNote,
      PaletteSymbolType.wholeRest => NotationPreviewGlyph.wholeRest,
      PaletteSymbolType.halfRest => NotationPreviewGlyph.halfRest,
      PaletteSymbolType.quarterRest => NotationPreviewGlyph.quarterRest,
    };
  }
}

class _FloatingControls extends StatelessWidget {
  const _FloatingControls({
    required this.zoomPercent,
    required this.insertMode,
    required this.onZoomIn,
    required this.onZoomOut,
    required this.onFitToScreen,
    required this.onToggleInsertMode,
  });

  final int zoomPercent;
  final bool insertMode;
  final VoidCallback onZoomIn;
  final VoidCallback onZoomOut;
  final VoidCallback onFitToScreen;
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
              const SizedBox(width: 2),
              _ZoomBtn(icon: Icons.fit_screen_rounded, onPressed: onFitToScreen),
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
    required this.onMoveToPrev,
    required this.onMoveToNext,
    required this.onAddMeasure,
    required this.canDeleteMeasure,
    required this.onDeleteMeasure,
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
  final VoidCallback onMoveToPrev;
  final VoidCallback onMoveToNext;
  final VoidCallback onAddMeasure;
  final bool canDeleteMeasure;
  final VoidCallback onDeleteMeasure;

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
          _ActionTile(icon: Icons.add_rounded, label: 'Add', onPressed: hasMeasureContext ? onAddMeasure : null),
          _ActionTile(icon: Icons.remove_rounded, label: 'Del', onPressed: canDeleteMeasure ? onDeleteMeasure : null, danger: true),
        ],
      ),
      _ActionGroup(
        label: 'INSERT',
        children: [
          _ActionTile(icon: Icons.music_note_rounded, label: 'Note', onPressed: hasMeasureContext ? onInsertNote : null),
          _ActionTile(icon: Icons.horizontal_rule_rounded, label: 'Rest', onPressed: hasMeasureContext ? onInsertRest : null),
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

// ---------------------------------------------------------------------------
// Trash zone (drag-to-delete target)
// ---------------------------------------------------------------------------

class _TrashZone extends StatelessWidget {
  const _TrashZone({super.key, required this.isHovered});

  final bool isHovered;

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 150),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: isHovered
            ? const Color(0xFFE05252).withValues(alpha: 0.92)
            : const Color(0xFF6B1A1A).withValues(alpha: 0.85),
        shape: BoxShape.circle,
        border: Border.all(
          color: isHovered ? const Color(0xFFFF6B6B) : const Color(0xFF8B2020),
          width: 1.5,
        ),
        boxShadow: isHovered
            ? [
                BoxShadow(
                  color: const Color(0xFFE05252).withValues(alpha: 0.4),
                  blurRadius: 12,
                  spreadRadius: 2,
                ),
              ]
            : [],
      ),
      child: Icon(
        isHovered ? Icons.delete_rounded : Icons.delete_outline_rounded,
        color: Colors.white,
        size: 24,
      ),
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
            Expanded(
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
                    Flexible(
                      child: Text(
                        _pitchLabel,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: AppColors.textPrimary,
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                    Flexible(
                      child: Text(
                        _durLabel,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(color: AppColors.textSecondary, fontSize: 11),
                      ),
                    ),
                  ] else
                    Expanded(
                      child: Text(
                        'Tap a symbol to select',
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(color: AppColors.textSecondary, fontSize: 12),
                      ),
                    ),
                ],
              ),
            ),
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
