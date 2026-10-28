import 'dart:async' show StreamSubscription, Timer, unawaited;
import 'dart:convert' show jsonEncode;
import '../../../core/models/score_annotation.dart';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:note_vision/core/config/app_features.dart';
import 'package:note_vision/core/models/clef.dart';
import 'package:note_vision/core/models/beam_grouping.dart';
import 'package:note_vision/core/models/note.dart';
import 'package:note_vision/core/models/project.dart';
import 'package:note_vision/core/models/rest.dart';
import 'package:note_vision/core/models/score.dart';
import 'package:note_vision/core/models/score_review.dart';
import 'package:note_vision/core/models/time_signature.dart';
import 'package:note_vision/core/models/score_symbol.dart';
import 'package:note_vision/core/utils/emoji_blocking_formatter.dart';
import 'package:note_vision/core/utils/image_picker_helper.dart';
import 'package:note_vision/features/scan/presentation/scan_screen.dart';
import 'package:note_vision/core/services/playback_display_preferences_service.dart';
import 'package:note_vision/core/services/playback_service.dart';
import 'package:note_vision/core/services/project_storage_service.dart';
import 'package:note_vision/core/services/nvscore_export_service.dart';
import 'package:note_vision/core/services/notation_checker.dart';
import 'package:note_vision/core/services/notation_review_service.dart';
import 'package:note_vision/core/services/score_classifier.dart';
import 'package:note_vision/core/services/user_profile_service.dart';
import 'package:note_vision/core/widgets/score_notation/notation_layout.dart';
import 'package:note_vision/core/widgets/score_notation/score_notation_painter.dart';
import 'package:note_vision/core/theme/app_theme.dart';
import 'package:note_vision/core/widgets/score_notation_viewer.dart';
import 'package:note_vision/core/widgets/score_page_thumbnail.dart';
import 'package:note_vision/features/editor/domain/editor_actions.dart';
import 'package:note_vision/features/editor/domain/editor_command.dart';
import 'package:note_vision/features/editor/model/editor_state.dart';
import 'package:note_vision/features/editor/model/editor_state_history.dart';
import 'package:note_vision/features/editor/presentation/editor_layout_policy.dart';
import 'package:note_vision/features/editor/presentation/widgets/notation_check_sheet.dart';
import 'package:note_vision/features/editor/presentation/widgets/notation_review_panel.dart';
import 'package:note_vision/features/editor/presentation/widgets/beam_editor_sheet.dart';
import 'package:note_vision/features/editor/presentation/widgets/staves_sheet.dart';
import 'package:note_vision/features/editor/presentation/widgets/lyrics_sheet.dart';
import 'package:note_vision/features/editor/presentation/widgets/annotations_sheet.dart';
import 'package:note_vision/features/editor/presentation/widgets/transpose_sheet.dart';
import 'package:note_vision/features/editor/presentation/widgets/editor_tool_dock.dart';
import 'package:note_vision/features/editor/presentation/widgets/editor_help_sheet.dart';
import 'package:note_vision/features/editor/presentation/widgets/editor_command_palette.dart';
import 'package:note_vision/features/editor/presentation/widgets/playback_controls_bar.dart';
import 'package:note_vision/features/editor/presentation/widgets/symbol_palette.dart';
import 'package:note_vision/core/services/usage_stats_service.dart';
import 'package:note_vision/features/musicXML/musicxml_export_service.dart';
import 'package:note_vision/features/musicXML/musicxml_preserving_exporter.dart';
import 'package:note_vision/features/pdf/pdf_export_service.dart';

class EditorShellArgs {
  const EditorShellArgs({
    required this.score,
    required this.initialState,
    this.existingProject,
    this.reviewMode = false,
    this.canEditTeacherComments = true,
  });

  final Score score;
  final EditorState initialState;

  /// Non-null when the editor was opened from the project list screen.
  final Project? existingProject;

  final bool reviewMode;
  final bool canEditTeacherComments;
}

class EditorShellScreen extends StatefulWidget {
  const EditorShellScreen({
    super.key,
    required this.args,
    this.playbackService,
    this.projectStorageService,
  });

  static const routeName = '/editor';

  final EditorShellArgs args;
  final PlaybackService? playbackService;
  final ProjectStorageService? projectStorageService;

  @override
  State<EditorShellScreen> createState() => _EditorShellScreenState();
}

class _EditorShellScreenState extends State<EditorShellScreen> {
  late EditorState _editorState;
  bool _insertMode = false;

  /// Copied notes and rests; kept for this editing session.
  EditorClipboard? _clipboard;

  /// Touch stand-in for Shift: the next tap extends the selection.
  bool _extendMode = false;

  /// The voice (1–4) chosen for note entry; null follows the selection.
  int? _inputVoice;

  int get _effectiveInputVoice =>
      _inputVoice ??
      switch (_editorState.selectedEditableSymbol) {
        Note(:final voice) || Rest(:final voice) => voice ?? 1,
        _ => 1,
      };

  /// [symbol] in the chosen entry voice.
  ScoreSymbol _inInputVoice(ScoreSymbol symbol) {
    final voice = _inputVoice;
    if (voice == null || voice == 1) return symbol;
    return switch (symbol) {
      Note() => symbol.copyWith(voice: voice),
      Rest() => symbol.copyWith(voice: voice),
      _ => symbol,
    };
  }

  bool _isDraggingNote = false;
  Offset _dragGlobal = Offset.zero;
  final GlobalKey _trashZoneKey = GlobalKey();
  NotationSymbolTarget? _dragTarget;
  PaletteSymbolType? _insertSymbolType;

  OverlayEntry? _dragGhostEntry;
  final ValueNotifier<Offset> _ghostPosition = ValueNotifier(Offset.zero);
  PaletteSymbolType? _dragSymbolType;

  // Playback
  late final PlaybackService _playback;
  PlaybackPosition _playbackPosition = PlaybackPosition.none;
  PlaybackStatus _playbackStatus = PlaybackStatus.stopped;
  // Per-note AnimationController anchor in _NotationAreaState.
  // Epoch increments on every position event; the state responds by calling
  // forward(from:0) so T sweeps 0→1 over exactly pos.durationMs.
  int _playheadEpoch = 0;
  int _playheadSymbolIndex = 0;
  int _playheadNoteDurationMs = 0;
  bool _showPlaybackSymbolHighlight =
      PlaybackDisplayPreferencesService.showSymbolGlowNotifier.value;
  StreamSubscription<PlaybackPosition>? _positionSub;
  StreamSubscription<PlaybackState>? _stateSub;

  late final ProjectStorageService _storage;
  Project? _currentProject;
  int _scoreEditCount = 0;
  bool _isSaving = false;
  bool _playbackPending = false;
  int _transportRequest = 0;
  late String _savedScoreJson;
  bool _isSubmitting = false;
  String? _role;
  _EditorBannerData? _banner;
  Score? _clearSymbolsUndoScore;

  // Notation check, turned on by the user from the header menu. While it is
  // on, the issues are worked out again after every edit (a few ms).
  bool _notationCheckOn = false;
  bool _reviewOpen = false;
  bool _reviewPreview = false;
  bool _reviewListening = false;
  bool _reviewStarting = false;
  int _reviewListenRequest = 0;
  double _reviewPanelFraction = .62;
  String? _focusedIssueKey;
  NotationReviewPlan? _reviewPlan;
  final GlobalKey<_NotationAreaState> _notationAreaKey = GlobalKey();
  Score? _checkedScore;
  List<NotationIssue> _checkedIssues = const [];
  Timer? _bannerTimer;

  /// Genre shown in the header. Worked out again shortly after the edits
  /// stop, so pressing keys stays quick while the genre model runs.
  ScoreLabel? _scoreLabel;
  Timer? _scoreLabelTimer;

  int _currentPageIndex = 0;

  EditorLayoutPolicy get _layoutPolicy =>
      EditorLayoutPolicy.forScore(_editorState.score);

  bool get _isReviewMode =>
      AppFeatures.classroomWorkflow && widget.args.reviewMode;
  bool get _isStudent => AppFeatures.classroomWorkflow && _role == 'student';
  bool get _canEditTeacherComments =>
      AppFeatures.classroomWorkflow && widget.args.canEditTeacherComments;

  EditorPageMetrics get _pageMetrics {
    final score = _editorState.score;
    if (score.parts.isEmpty) {
      return EditorPageMetrics(
        layoutPolicy: _layoutPolicy,
        pageStartIndices: [0],
        currentPageIndex: 0,
        totalMeasures: 0,
      );
    }

    final measures = score.parts.first.measures;
    return EditorPageMetrics(
      layoutPolicy: _layoutPolicy,
      pageStartIndices: pageStartIndicesForMeasures(
        measures,
        layoutPolicy: _layoutPolicy,
      ),
      currentPageIndex: _currentPageIndex,
      totalMeasures: measures.length,
    );
  }

  @override
  void initState() {
    super.initState();
    _playback = widget.playbackService ?? PlaybackService.instance;
    _storage = widget.projectStorageService ?? ProjectStorageService();
    _currentProject = widget.args.existingProject;
    final initial = widget.args.initialState;
    final identifiedScore = NotationReviewService.ensureIdentity(
      widget.args.score,
    );
    _editorState = _withDefaultMeasureContext(
      initial.copyWith(
        score: identifiedScore,
        selectedSymbol: initial.hasSymbolSelection
            ? identifiedScore.getSymbolAt(
                initial.selectedPartIndex!,
                initial.selectedMeasureIndex!,
                initial.selectedSymbolIndex!,
              )
            : null,
      ),
    );
    _savedScoreJson = jsonEncode(_editorState.score.toJson());
    _notationCheckOn = _editorState.score.sourcePages.isNotEmpty;
    _initPlayback();
    PlaybackDisplayPreferencesService.showSymbolGlowNotifier.addListener(
      _onPlaybackDisplayPreferencesChanged,
    );
    _loadPlaybackDisplayPreferences();
    _loadScoreEditCount();
    _loadRole();
    _scoreLabel = ScoreClassifier.classify(_editorState.score);
  }

  void _scheduleScoreLabelUpdate() {
    _scoreLabelTimer?.cancel();
    _scoreLabelTimer = Timer(const Duration(milliseconds: 600), () {
      if (!mounted) return;
      final label = ScoreClassifier.classify(_editorState.score);
      if (label != _scoreLabel) setState(() => _scoreLabel = label);
    });
  }

  Future<void> _loadRole() async {
    if (!AppFeatures.classroomWorkflow) return;
    final role = await UserProfileService.loadRole();
    if (mounted) setState(() => _role = role);
  }

  Future<void> _loadPlaybackDisplayPreferences() async {
    final showSymbolGlow =
        await PlaybackDisplayPreferencesService.getShowSymbolGlow();
    if (!mounted) return;
    setState(() => _showPlaybackSymbolHighlight = showSymbolGlow);
  }

  void _onPlaybackDisplayPreferencesChanged() {
    if (!mounted) return;
    setState(() {
      _showPlaybackSymbolHighlight =
          PlaybackDisplayPreferencesService.showSymbolGlowNotifier.value;
    });
  }

  Future<void> _initPlayback() async {
    // Subscribe before awaiting init so state changes are received even if
    // the soundfont load is slow or fails (and in tests where it never completes).
    _positionSub = _playback.positionStream.listen((pos) {
      if (!mounted) return;
      setState(() {
        _playbackPosition = pos;
        _syncPageToPlaybackPosition(pos);
        // Each position event starts a fresh per-note AnimationController sweep
        // in _NotationAreaState (epoch change → forward(from:0)). The painter
        // uses T (0→1) + the symbol index to interpolate X directly from slot
        // geometry — no base-ms accumulation needed.
        if (!pos.isNone) {
          _playheadSymbolIndex = pos.symbolIndex;
          _playheadNoteDurationMs = pos.durationMs;
          _playheadEpoch++;
        }
      });
    });
    _stateSub = _playback.stateStream.listen((state) {
      if (!mounted) return;
      setState(() {
        _playbackStatus = state.status;
        if (!_reviewStarting &&
            (state.status == PlaybackStatus.stopped ||
                state.status == PlaybackStatus.error)) {
          _reviewListening = false;
        }
        if (state.status == PlaybackStatus.stopped ||
            state.status == PlaybackStatus.error) {
          _playheadEpoch = 0;
          _playheadSymbolIndex = 0;
          _playheadNoteDurationMs = 0;
        }
      });
    });
    await _playback.init();
  }

  @override
  void dispose() {
    _positionSub?.cancel();
    _stateSub?.cancel();
    PlaybackDisplayPreferencesService.showSymbolGlowNotifier.removeListener(
      _onPlaybackDisplayPreferencesChanged,
    );
    _bannerTimer?.cancel();
    _scoreLabelTimer?.cancel();
    _playback.stop();
    _dragGhostEntry?.remove();
    _ghostPosition.dispose();
    super.dispose();
  }

  PaletteSymbolType? _paletteTypeForSymbol(ScoreSymbol? symbol) {
    if (symbol is Note) {
      return switch (symbol.type.trim().toLowerCase()) {
        'whole' => PaletteSymbolType.wholeNote,
        'half' => PaletteSymbolType.halfNote,
        'quarter' => PaletteSymbolType.quarterNote,
        'eighth' => PaletteSymbolType.eighthNote,
        'sixteenth' || '16th' => PaletteSymbolType.sixteenthNote,
        _ => null,
      };
    }
    if (symbol is Rest) {
      return switch (symbol.type.trim().toLowerCase()) {
        'whole' => PaletteSymbolType.wholeRest,
        'half' => PaletteSymbolType.halfRest,
        'quarter' => PaletteSymbolType.quarterRest,
        'eighth' => PaletteSymbolType.eighthRest,
        'sixteenth' || '16th' => PaletteSymbolType.sixteenthRest,
        _ => null,
      };
    }
    return null;
  }

  // ── Save logic ─────────────────────────────────────────────────────────────

  Future<bool> _trySaveProject(Project project) async {
    try {
      await _storage.saveProject(project);
      return true;
    } catch (e) {
      debugPrint('Save failed: $e');
      _showEditorBanner(
        _EditorBannerData.error(
          'Could not save. Check the phone has free space, then retry.',
          duration: const Duration(seconds: 6),
          actionLabel: 'Retry',
          onAction: _onSave,
        ),
      );
      return false;
    }
  }

  Future<void> _runExport({
    required Future<String?> Function() export,
    required String successMessage,
  }) async {
    try {
      final path = await export();
      if (!context.mounted || path == null) return;

      await UsageStatsService.incrementExports();
      if (!context.mounted) return;
      _showEditorBanner(_EditorBannerData.success(successMessage));
    } catch (e) {
      debugPrint('Export failed: $e');
      _showEditorBanner(
        _EditorBannerData.error(
          e is MusicXmlPreservationException
              ? e.message
              : 'Could not export the score. Try again.',
          duration: Duration(
            seconds: e is MusicXmlPreservationException ? 14 : 6,
          ),
        ),
      );
    }
  }

  Future<void> _onSubmit() async {
    if (_isSubmitting || _playbackStatus == PlaybackStatus.playing) return;
    setState(() => _isSubmitting = true);

    try {
      final profile = await UserProfileService.loadProfile();
      final submittedBy = profile?.name.trim();
      if (submittedBy == null || submittedBy.isEmpty) {
        _showEditorBanner(
          const _EditorBannerData.error('Submit failed: profile name missing.'),
        );
        return;
      }
      final submittedById = await UserProfileService.loadOrCreateUserId();

      final project =
          (_currentProject ??
                  Project.create(
                    name: _editorState.score.title.trim().isEmpty
                        ? 'Untitled'
                        : _editorState.score.title.trim(),
                    score: _editorState.score,
                  ))
              .copyWithUpdated(
                score: _editorState.score,
                submittedBy: submittedBy,
                submittedById: submittedById,
              );

      await _runExport(
        export: () => const NvscoreExportService().exportProject(
          project,
          fileName: NvscoreExportService.submissionFileName(
            project: project,
            studentName: submittedBy,
            studentId: submittedById,
          ),
        ),
        successMessage: 'Submission exported',
      );
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  Future<void> _onSave() async {
    if (_isReviewMode) return;
    if (_isSaving) return;
    setState(() => _isSaving = true);
    try {
      if (_currentProject == null) {
        final defaultName = _editorState.score.title.trim().isEmpty
            ? 'Untitled'
            : _editorState.score.title.trim();
        final name = await _showNameDialog(defaultName);
        if (name == null || !mounted) return;

        final project = Project.create(name: name, score: _editorState.score);
        if (!await _trySaveProject(project)) return;

        if (!mounted) return;
        setState(() {
          _currentProject = project;
          _savedScoreJson = project.scoreJson;
          _editorState = _editorState.copyWith(
            rangeAnchor: _editorState.rangeAnchor,
            hasUnsavedChanges:
                jsonEncode(_editorState.score.toJson()) != _savedScoreJson,
          );
        });
        _showSavedBanner(name);
      } else {
        final updated = _currentProject!.copyWithUpdated(
          score: _editorState.score,
        );
        if (!await _trySaveProject(updated)) return;

        if (!mounted) return;
        setState(() {
          _currentProject = updated;
          _savedScoreJson = updated.scoreJson;
          _editorState = _editorState.copyWith(
            rangeAnchor: _editorState.rangeAnchor,
            hasUnsavedChanges:
                jsonEncode(_editorState.score.toJson()) != _savedScoreJson,
          );
        });
        _showSavedBanner(updated.name);
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  Future<String?> _showNameDialog(String defaultName) {
    final controller = TextEditingController(text: defaultName);
    return showDialog<String>(
      context: context,
      builder: (ctx) {
        String? errorText;
        return StatefulBuilder(
          builder: (ctx, setDialogState) => AlertDialog(
            backgroundColor: AppColors.surface,
            title: const Text(
              'Name your project',
              style: TextStyle(color: AppColors.textPrimary),
            ),
            content: TextField(
              controller: controller,
              autofocus: true,
              maxLength: 60,
              inputFormatters: [
                EmojiBlockingFormatter(
                  onBlocked: () {
                    setDialogState(() => errorText = 'Emoji not allowed');
                  },
                ),
              ],
              buildCounter:
                  (_, {required currentLength, required isFocused, maxLength}) {
                    if (maxLength == null || currentLength <= maxLength - 20) {
                      return null;
                    }
                    return Text(
                      '$currentLength / $maxLength',
                      style: TextStyle(
                        color: currentLength >= maxLength
                            ? const Color(0xFFE05252)
                            : AppColors.textSecondary,
                        fontSize: 11,
                      ),
                    );
                  },
              style: const TextStyle(color: AppColors.textPrimary),
              decoration: InputDecoration(
                hintText: 'Project name',
                hintStyle: const TextStyle(color: AppColors.textSecondary),
                errorText: errorText,
                enabledBorder: const UnderlineInputBorder(
                  borderSide: BorderSide(color: AppColors.border),
                ),
                focusedBorder: const UnderlineInputBorder(
                  borderSide: BorderSide(color: AppColors.accent),
                ),
              ),
              onChanged: (_) {
                if (errorText != null) {
                  setDialogState(() => errorText = null);
                }
              },
              onSubmitted: (v) {
                final trimmed = v.trim();
                if (trimmed.isEmpty) {
                  setDialogState(() => errorText = 'Name cannot be empty');
                  return;
                }
                Navigator.of(ctx).pop(trimmed);
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
                  if (trimmed.isEmpty) {
                    setDialogState(() => errorText = 'Name cannot be empty');
                    return;
                  }
                  Navigator.of(ctx).pop(trimmed);
                },
                child: const Text(
                  'Save',
                  style: TextStyle(color: AppColors.accent),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  void _showSavedBanner(String name) {
    _showEditorBanner(
      _EditorBannerData.success(
        _editorState.hasUnsavedChanges
            ? 'Saved $name. Newer edits still need saving.'
            : 'Saved as $name',
      ),
    );
  }

  String? _commentForSelectedMeasure() {
    final measureNumber = _selectedMeasureNumber();
    if (measureNumber == null) return null;
    return _currentProject?.teacherComments?[measureNumber];
  }

  int? _selectedMeasureNumber() {
    final selectedPartIndex = _editorState.selectedPartIndex ?? 0;
    final selectedMeasureIndex = _editorState.selectedMeasureIndex;
    if (selectedMeasureIndex == null ||
        _editorState.score.parts.isEmpty ||
        selectedPartIndex >= _editorState.score.parts.length) {
      return null;
    }
    final measures = _editorState.score.parts[selectedPartIndex].measures;
    if (selectedMeasureIndex < 0 || selectedMeasureIndex >= measures.length) {
      return null;
    }
    return measures[selectedMeasureIndex].number;
  }

  void _selectMeasureForReview(NotationMeasureTarget? target) {
    if (target == null) return;
    setState(() {
      _editorState = _editorState.copyWith(
        selectedPartIndex: target.partIndex,
        selectedMeasureIndex: target.measureIndex,
        selectedSymbolIndex: null,
        selectedSymbol: null,
      );
      _syncPageToEditorState(_editorState);
    });
  }

  Future<void> _showMeasureCommentDialog() async {
    if (!_canEditTeacherComments) return;
    final measureNumber = _selectedMeasureNumber();
    final currentProject = _currentProject;
    if (measureNumber == null || currentProject == null) return;

    final currentComment = currentProject.teacherComments?[measureNumber] ?? '';
    final result = await showDialog<String?>(
      context: context,
      builder: (_) => _MeasureCommentDialog(
        measureNumber: measureNumber,
        initialComment: currentComment,
      ),
    );

    if (result == null || !mounted) return;
    await Future<void>.delayed(Duration.zero);
    if (!mounted) return;

    final comments = Map<int, String>.from(
      currentProject.teacherComments ?? const <int, String>{},
    );
    if (result.isEmpty) {
      comments.remove(measureNumber);
    } else {
      comments[measureNumber] = result;
    }

    final updatedProject = currentProject.copyWithUpdated(
      score: _editorState.score,
      teacherComments: comments,
    );
    if (!await _trySaveProject(updatedProject)) return;
    if (!mounted) return;
    setState(() => _currentProject = updatedProject);
    _showEditorBanner(const _EditorBannerData.success('Comment saved'));
  }

  Future<void> _exportCurrentNvscoreProject() async {
    final project = _currentProject;
    if (project == null) return;

    await _runExport(
      export: () => const NvscoreExportService().exportProject(
        project,
        fileName: NvscoreExportService.feedbackFileName(project),
      ),
      successMessage: 'Reviewed score exported',
    );
  }

  // ── Notation check ─────────────────────────────────────────────────────────

  List<NotationIssue> get _notationIssues {
    final score = _editorState.score;
    if (!identical(score, _checkedScore)) {
      _checkedIssues = NotationReviewService.issues(score);
      _checkedScore = score;
    }
    return _checkedIssues;
  }

  NotationIssue? get _focusedIssue =>
      _notationIssues
          .where(
            (i) =>
                NotationReviewService.key(_editorState.score, i) ==
                _focusedIssueKey,
          )
          .firstOrNull ??
      _notationIssues.firstOrNull;

  Map<String, Color> get _issueMarks {
    if (!_notationCheckOn) return const {};
    if (_reviewPreview && _reviewPlan != null) {
      return {
        for (final change in _reviewPlan!.changes)
          '${change.partIndex}:${change.measureIndex}': AppColors.accent,
      };
    }
    return {
      for (final issue in _notationIssues)
        [issue.partIndex, issue.measureIndex, ?issue.symbolIndex].join(':'):
            notationIssueColor(issue.kind),
    };
  }

  void _startNotationCheck() {
    if (_reviewOpen) return;
    setState(() {
      _notationCheckOn = true;
      _reviewOpen = true;
    });
    final issue = _focusedIssue;
    if (issue != null) _showIssue(issue);
  }

  void _stopNotationCheck() {
    _stopReviewListening();
    setState(() {
      _reviewOpen = false;
      _notationCheckOn = false;
      _reviewPlan = null;
      _reviewPreview = false;
    });
  }

  bool get _canApplyIssueFix =>
      !_isReviewMode &&
      !_playbackPending &&
      !_reviewListening &&
      _playbackStatus != PlaybackStatus.playing;

  void _applyReviewPlan(NotationReviewPlan plan) {
    if (!_canApplyIssueFix) return;
    final next = plan.applyTo(_editorState.score);
    if (next == null) {
      _showEditorBanner(
        const _EditorBannerData.error(
          'The score changed. Preview these suggestions again.',
        ),
      );
      return;
    }
    final index = _focusedIssue == null
        ? 0
        : _notationIssues.indexOf(_focusedIssue!);
    _updateState((s) => s.applyEdit(score: next, clearSelection: true));
    _advanceReview(preferredIndex: index);
    final appliedScore = _editorState.score;
    _showEditorBanner(
      _EditorBannerData(
        message:
            '${plan.entries.length} ${plan.entries.length == 1 ? 'change' : 'changes'} applied',
        backgroundColor: AppColors.surfaceAlt,
        duration: const Duration(seconds: 5),
        actionLabel: 'Undo',
        onAction: () {
          if (identical(_editorState.score, appliedScore) &&
              _canApplyIssueFix) {
            _updateState((s) => s.applyUndo());
            _advanceReview();
          }
        },
      ),
    );
  }

  void _keepIssue(NotationIssue issue) {
    if (!_canApplyIssueFix) return;
    final index = _notationIssues.indexOf(issue);
    _updateState(
      (s) => s.applyEdit(
        score: NotationReviewService.keep(s.score, issue),
        clearSelection: true,
      ),
    );
    _advanceReview(preferredIndex: index);
  }

  void _restoreReview(ScoreReviewEntry entry) {
    if (!_canApplyIssueFix) return;
    final restored = NotationReviewService.restore(_editorState.score, entry);
    if (restored == null) return;
    _updateState((s) => s.applyEdit(score: restored, clearSelection: true));
    final issue = _notationIssues
        .where(
          (i) =>
              NotationReviewService.key(_editorState.score, i) ==
              entry.issueKey,
        )
        .firstOrNull;
    if (issue != null) {
      _showIssue(issue);
    } else {
      _advanceReview();
    }
  }

  void _advanceReview({int? preferredIndex}) {
    final issues = _notationIssues;
    if (issues.isEmpty) return;
    final next = preferredIndex == null
        ? _focusedIssue
        : issues[preferredIndex.clamp(0, issues.length) % issues.length];
    if (next != null) _showIssue(next);
  }

  void _showIssue(NotationIssue issue) {
    _stopReviewListening();
    setState(() {
      _focusedIssueKey = NotationReviewService.key(_editorState.score, issue);
      _reviewPlan = null;
      _reviewPreview = false;
      _editorState = issue.symbolIndex == null
          ? _editorState.copyWith(
              selectedPartIndex: issue.partIndex,
              selectedMeasureIndex: issue.measureIndex,
              selectedSymbolIndex: null,
              selectedSymbol: null,
            )
          : _editorState.selectSymbolAt(
              partIndex: issue.partIndex,
              measureIndex: issue.measureIndex,
              symbolIndex: issue.symbolIndex!,
            );
      _syncPageToEditorState(_editorState);
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _notationAreaKey.currentState?.focusMeasure(
          issue.partIndex,
          issue.measureIndex,
        );
      }
    });
  }

  void _editReviewManually() {
    final issue = _focusedIssue;
    if (issue != null) _showIssue(issue);
    setState(() {
      _reviewOpen = false;
      _reviewPreview = false;
      _reviewPlan = null;
    });
  }

  Future<void> _listenReview(Score score, int part, int first, int last) async {
    if (_isReviewMode) return;
    _playback.stop();
    final request = ++_reviewListenRequest;
    setState(() {
      _reviewListening = true;
      _reviewStarting = true;
    });
    try {
      await _playback.play(
        score,
        fromPartIndex: part,
        fromMeasureIndex: first,
        throughMeasureIndex: last,
      );
      if (!mounted || request != _reviewListenRequest) return;
      _reviewStarting = false;
      if (_playback.status != PlaybackStatus.playing) {
        setState(() => _reviewListening = false);
        _showEditorBanner(
          const _EditorBannerData.error(
            'Could not play this passage. Try again.',
          ),
        );
      }
    } catch (_) {
      if (!mounted || request != _reviewListenRequest) return;
      _reviewStarting = false;
      setState(() => _reviewListening = false);
      _showEditorBanner(
        const _EditorBannerData.error(
          'Could not play this passage. Try again.',
        ),
      );
    }
  }

  void _stopReviewListening() {
    _reviewListenRequest++;
    if (_reviewListening) _playback.stop();
    _reviewStarting = false;
    _reviewListening = false;
  }

  void _showEditorBanner(_EditorBannerData banner) {
    _bannerTimer?.cancel();
    if (!mounted) return;
    setState(() {
      _banner = banner;
      _clearSymbolsUndoScore = null;
    });
    _bannerTimer = Timer(banner.duration, () {
      if (!mounted) return;
      setState(() => _banner = null);
    });
  }

  // ── Scan new page ──────────────────────────────────────────────────────────

  Future<void> _onScanPage() async {
    final useCamera = await showModalBottomSheet<bool>(
      context: context,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 12),
              ListTile(
                leading: const Icon(
                  Icons.camera_alt_rounded,
                  color: AppColors.accent,
                ),
                title: const Text(
                  'Camera',
                  style: TextStyle(color: AppColors.textPrimary),
                ),
                onTap: () => Navigator.pop(ctx, true),
              ),
              ListTile(
                leading: const Icon(
                  Icons.photo_library_rounded,
                  color: AppColors.accent,
                ),
                title: const Text(
                  'Gallery',
                  style: TextStyle(color: AppColors.textPrimary),
                ),
                onTap: () => Navigator.pop(ctx, false),
              ),
            ],
          ),
        ),
      ),
    );
    if (useCamera == null || !mounted) return;

    // mounted checked above; ImagePickerHelper also guards context.mounted internally
    // ignore: use_build_context_synchronously
    final file = await (useCamera
        ? ImagePickerHelper.pickFromCamera(context)
        : ImagePickerHelper.pickFromGallery(context));
    if (file == null || !mounted) return;

    final bytes = await file.readAsBytes();
    if (!mounted) return;

    final navigator = Navigator.of(context);
    final scanned = await navigator.push<Score>(
      PageRouteBuilder(
        pageBuilder: (_, _, _) =>
            ScanScreenProvider(imageBytes: bytes, appendMode: true),
        transitionsBuilder: (_, animation, _, child) =>
            FadeTransition(opacity: animation, child: child),
        transitionDuration: const Duration(milliseconds: 400),
      ),
    );

    if (scanned == null || !mounted) return;
    _appendScannedPage(scanned);
  }

  void _appendScannedPage(Score scanned) {
    if (scanned.parts.isEmpty) return;
    setState(() {
      final prev = _editorState;
      final merged = prev.score.appendScore(scanned);
      _notationCheckOn = true;
      _reviewOpen = false;
      _reviewPlan = null;
      _reviewPreview = false;
      _editorState = prev.applyEdit(score: merged, clearSelection: true);
      if (_editorState.undoStack.length > prev.undoStack.length) {
        _scoreEditCount++;
        unawaited(UsageStatsService.incrementScoreEdits(_editorState.score.id));
      }
      _jumpToLastPage();
    });
    _scheduleScoreLabelUpdate();
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

  int _clampPageIndexForStarts(List<int> pageStarts, int pageIndex) {
    return pageIndex.clamp(0, pageStarts.length - 1);
  }

  void _setCurrentPageIndex(int pageIndex) {
    _currentPageIndex = _clampPageIndexForStarts(
      _pageMetrics.pageStartIndices,
      pageIndex,
    );
  }

  int _pageIndexForEditorState(EditorState state) {
    final pageStarts = state.score.parts.isEmpty
        ? const [0]
        : pageStartIndicesForMeasures(
            state.score.parts.first.measures,
            layoutPolicy: _layoutPolicy,
          );

    if (state.selectedMeasureIndex != null &&
        state.score.parts.isNotEmpty &&
        state.score.parts.first.measures.isNotEmpty) {
      final measureIndex = state.selectedMeasureIndex!.clamp(
        0,
        state.score.parts.first.measures.length - 1,
      );
      return _clampPageIndexForStarts(
        pageStarts,
        pageIndexForMeasure(pageStarts, measureIndex),
      );
    }

    return _clampPageIndexForStarts(pageStarts, _currentPageIndex);
  }

  void _syncPageToEditorState(EditorState state) {
    _currentPageIndex = _pageIndexForEditorState(state);
  }

  void _syncPageToPlaybackPosition(PlaybackPosition position) {
    if (position.isNone) {
      _setCurrentPageIndex(_currentPageIndex);
      return;
    }

    _setCurrentPageIndex(
      _pageMetrics.pageIndexForMeasureIndex(position.measureIndex),
    );
  }

  Future<void> _showPageOverview() async {
    final metrics = _pageMetrics;
    final selectedPageIndex = await showModalBottomSheet<int>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _PageOverviewSheet(
        score: _editorState.score,
        currentPageIndex: _currentPageIndex,
        totalPages: metrics.totalPages,
      ),
    );

    if (!mounted || selectedPageIndex == null) return;
    setState(() => _setCurrentPageIndex(selectedPageIndex));
  }

  Future<void> _playFromMeasure(
    int fromMeasureIndex, {
    int partIndex = 0,
  }) async {
    final request = ++_transportRequest;
    setState(() => _playbackPending = true);
    try {
      await _playback.play(
        _editorState.score,
        fromMeasureIndex: fromMeasureIndex,
        fromPartIndex: partIndex,
      );
    } catch (_) {
      if (mounted && request == _transportRequest) {
        _showEditorBanner(
          const _EditorBannerData.error('Playback is unavailable. Try again.'),
        );
      }
    } finally {
      if (mounted && request == _transportRequest) {
        setState(() => _playbackPending = false);
      }
    }
  }

  Future<void> _seekPlayback(int step) async {
    if (_editorState.score.playbackLayout ==
        ScorePlaybackLayout.simultaneousParts) {
      final parts = _editorState.score.parts;
      var part = _editorState.selectedPartIndex ?? 0;
      if (part >= parts.length || step >= parts[part].measures.length) {
        part = parts.indexWhere((p) => step < p.measures.length);
      }
      if (part < 0) return;
      if (_playbackStatus == PlaybackStatus.playing) {
        await _playFromMeasure(step, partIndex: part);
      } else {
        _selectMeasureForReview(
          NotationMeasureTarget(partIndex: part, measureIndex: step),
        );
        await _playback.seek(
          _editorState.score,
          fromMeasureIndex: step,
          fromPartIndex: part,
        );
      }
      return;
    }
    var remaining = step;
    for (var part = 0; part < _editorState.score.parts.length; part++) {
      final count = _editorState.score.parts[part].measures.length;
      if (remaining >= count) {
        remaining -= count;
        continue;
      }
      if (_playbackStatus == PlaybackStatus.playing) {
        await _playFromMeasure(remaining, partIndex: part);
      } else {
        _selectMeasureForReview(
          NotationMeasureTarget(partIndex: part, measureIndex: remaining),
        );
        await _playback.seek(
          _editorState.score,
          fromMeasureIndex: remaining,
          fromPartIndex: part,
        );
      }
      return;
    }
  }

  void _stopVisualPlayback() {
    _transportRequest++;
    setState(() {
      _playbackPending = false;
      _playheadEpoch = 0;
      _playheadSymbolIndex = 0;
      _playheadNoteDurationMs = 0;
    });
  }

  void _setPlaybackTempo(int bpm) {
    // Tempo only affects the *next* note's animation duration (pos.durationMs),
    // exactly as it affects the audio timer — no mid-note visual correction needed.
    _playback.setTempo(bpm);
  }

  void _jumpToLastPage() {
    _setCurrentPageIndex(_pageMetrics.totalPages - 1);
  }

  Future<void> _showMetadataSheet() async {
    final result =
        await showModalBottomSheet<({String title, String composer})>(
          context: context,
          isScrollControlled: true,
          backgroundColor: AppColors.surface,
          shape: const RoundedRectangleBorder(
            borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
          ),
          builder: (_) => _MetadataSheet(
            initialTitle: _editorState.score.title,
            initialComposer: _editorState.score.composer,
          ),
        );

    if (result == null || !mounted) return;
    _updateState(
      (s) => s.copyWith(
        score: s.score.copyWith(title: result.title, composer: result.composer),
        hasUnsavedChanges: true,
      ),
    );
    _onSave();
  }

  void _updateState(EditorState Function(EditorState state) updater) {
    if (_isReviewMode) return;
    final prevScore = _editorState.score;
    setState(() {
      final prev = _editorState;
      final nextState = updater(_editorState);
      final identified = NotationReviewService.ensureIdentity(nextState.score);
      // Assigning review IDs rebuilds every symbol in place, so the
      // selection is found again by its position.
      _editorState = nextState.copyWith(
        score: identified,
        selectedSymbol: nextState.hasSymbolSelection
            ? identified.getSymbolAt(
                nextState.selectedPartIndex!,
                nextState.selectedMeasureIndex!,
                nextState.selectedSymbolIndex!,
              )
            : null,
        rangeAnchor: nextState.rangeAnchor,
      );
      if (!identical(prevScore, _editorState.score)) {
        if (_clearSymbolsUndoScore != null &&
            !identical(_clearSymbolsUndoScore, _editorState.score)) {
          _bannerTimer?.cancel();
          _banner = null;
          _clearSymbolsUndoScore = null;
        }
        _editorState = _editorState.copyWith(
          rangeAnchor: _editorState.rangeAnchor,
          hasUnsavedChanges:
              jsonEncode(_editorState.score.toJson()) != _savedScoreJson,
        );
        _reviewPlan = null;
        _reviewPreview = false;
      }
      _syncPageToEditorState(nextState);
      if (_editorState.undoStack.length > prev.undoStack.length) {
        _scoreEditCount++;
        unawaited(UsageStatsService.incrementScoreEdits(_editorState.score.id));
      }
    });
    if (!identical(_editorState.score, prevScore)) _scheduleScoreLabelUpdate();
  }

  bool get _canClearAllSymbols =>
      _canApplyIssueFix &&
      !_isDraggingNote &&
      _editorState.musicSymbolCount > 0;

  Future<void> _confirmClearAllSymbols() async {
    if (!_canClearAllSymbols) return;
    final originalScore = _editorState.score;
    final count = _editorState.musicSymbolCount;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: AppColors.surface,
        scrollable: true,
        title: const Text('Clear all symbols?'),
        content: Text(
          'Remove all $count ${count == 1 ? 'note or rest' : 'notes and rests'} '
          'from every page and staff.\n\n'
          'Measures, clefs, key and time signatures, and score details will stay. '
          'You can undo this in one step.',
        ),
        actions: [
          TextButton(
            autofocus: true,
            style: TextButton.styleFrom(minimumSize: const Size(48, 48)),
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.error,
              foregroundColor: Colors.white,
              minimumSize: const Size(48, 48),
            ),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Clear all symbols'),
          ),
        ],
      ),
    );
    if (!mounted || confirmed != true || !_canClearAllSymbols) return;
    if (!identical(originalScore, _editorState.score)) {
      _showEditorBanner(
        const _EditorBannerData.error(
          'The score changed. Choose Clear all symbols again.',
        ),
      );
      return;
    }

    _stopReviewListening();
    _playback.stop();
    _stopVisualPlayback();
    _updateState((state) => state.clearAllSymbols());
    final clearedScore = _editorState.score;
    setState(() {
      _playbackPosition = PlaybackPosition.none;
      _focusedIssueKey = null;
      _reviewOpen = false;
      _insertMode = false;
      _insertSymbolType = null;
      _scoreLabelTimer?.cancel();
      _scoreLabel = null;
    });
    _showEditorBanner(
      _EditorBannerData(
        message: 'All notes and rests cleared',
        backgroundColor: AppColors.surfaceAlt,
        duration: const Duration(seconds: 8),
        actionLabel: 'Undo',
        onAction: () {
          if (!identical(_editorState.score, clearedScore) ||
              !_canApplyIssueFix) {
            return;
          }
          _updateState((state) => state.applyUndo());
          _bannerTimer?.cancel();
          setState(() => _banner = null);
        },
      ),
    );
    _clearSymbolsUndoScore = clearedScore;
  }

  void _onNotationSymbolTap(int partIndex, int measureIndex, int symbolIndex) {
    if (_extendMode || HardwareKeyboard.instance.isShiftPressed) {
      _extendMode = false;
      _updateState(
        (state) => state.extendSelectionTo(
          partIndex: partIndex,
          measureIndex: measureIndex,
          symbolIndex: symbolIndex,
        ),
      );
      return;
    }
    _updateState((state) {
      final isSame =
          state.selectedPartIndex == partIndex &&
          state.selectedMeasureIndex == measureIndex &&
          state.selectedSymbolIndex == symbolIndex;
      if (isSame) return state.clearSymbolSelectionPreservingMeasureContext();

      return state.selectSymbolAt(
        partIndex: partIndex,
        measureIndex: measureIndex,
        symbolIndex: symbolIndex,
      );
    });
  }

  void _onInsertTap(NotationInsertTarget? target) {
    if (target == null || _insertSymbolType == null) return;
    final symbol = _inInputVoice(_buildSymbol(_insertSymbolType!, target));
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
    final symbol = _inInputVoice(_buildSymbol(data.type, target));
    _updateState(
      (state) => state.insertSymbolAtMeasureIndex(
        partIndex: target.partIndex,
        measureIndex: target.measureIndex,
        insertIndex: target.insertIndex,
        symbol: symbol,
      ),
    );
  }

  ScoreSymbol _buildSymbol(
    PaletteSymbolType type,
    NotationInsertTarget target,
  ) {
    switch (type) {
      case PaletteSymbolType.wholeNote:
        return Note(
          step: target.step,
          octave: target.octave.clamp(1, 7).toInt(),
          duration: 8,
          type: 'whole',
        );
      case PaletteSymbolType.halfNote:
        return Note(
          step: target.step,
          octave: target.octave.clamp(1, 7).toInt(),
          duration: 4,
          type: 'half',
        );
      case PaletteSymbolType.quarterNote:
        return Note(
          step: target.step,
          octave: target.octave.clamp(1, 7).toInt(),
          duration: 2,
          type: 'quarter',
        );
      case PaletteSymbolType.eighthNote:
        return Note(
          step: target.step,
          octave: target.octave.clamp(1, 7).toInt(),
          duration: 1,
          type: 'eighth',
        );
      case PaletteSymbolType.sixteenthNote:
        return Note(
          step: target.step,
          octave: target.octave.clamp(1, 7).toInt(),
          duration: sixteenthDuration.divisions,
          type: sixteenthDuration.type,
        );
      case PaletteSymbolType.wholeRest:
        return const Rest(duration: 8, type: 'whole');
      case PaletteSymbolType.halfRest:
        return const Rest(duration: 4, type: 'half');
      case PaletteSymbolType.quarterRest:
        return const Rest(duration: 2, type: 'quarter');
      case PaletteSymbolType.eighthRest:
        return const Rest(duration: 1, type: 'eighth');
      case PaletteSymbolType.sixteenthRest:
        return Rest(
          duration: sixteenthDuration.divisions,
          type: sixteenthDuration.type,
        );
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

  bool get _canEditStaves =>
      _canApplyIssueFix && !_isDraggingNote && !_isReviewMode;

  Future<void> _showAnnotations({
    int? initialIndex,
    AnnotationKind? kind,
  }) async {
    if (_commandEditLock != null || !_editorState.hasMeasureContext) return;
    final original = _editorState.score;
    final p = _editorState.selectedPartIndex!,
        m = _editorState.selectedMeasureIndex!;
    final offset = _editorState.selectedAnnotationOffset;
    final existing = original.parts[p].measures[m].annotations.indexWhere(
      (a) => a.kind == kind && a.offset == offset,
    );
    final annotations = await showModalBottomSheet<List<ScoreAnnotation>>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      backgroundColor: AppColors.surface,
      constraints: const BoxConstraints(maxWidth: 640),
      builder: (_) => AnnotationsSheet(
        annotations: original.parts[p].measures[m].annotations,
        offset: offset,
        beatType: _editorState.selectedMeasureTimeSignature?.beatType ?? 4,
        initialIndex: initialIndex ?? (existing < 0 ? null : existing),
        initialKind: kind,
      ),
    );
    if (!mounted ||
        annotations == null ||
        !identical(original, _editorState.score) ||
        _commandEditLock != null) {
      return;
    }
    if (jsonEncode(
          original.parts[p].measures[m].annotations
              .map((a) => a.toJson())
              .toList(),
        ) ==
        jsonEncode(annotations.map((a) => a.toJson()).toList())) {
      return;
    }
    _updateState((s) => s.setAnnotations(annotations));
  }

  Future<void> _showLyrics() async {
    if (_commandEditLock != null ||
        _editorState.lyricUnavailableReason != null) {
      return;
    }
    final original = _editorState.score;
    final edited = await showModalBottomSheet<Score>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      backgroundColor: AppColors.surface,
      constraints: const BoxConstraints(maxWidth: 640),
      builder: (_) => LyricsSheet(initialState: _editorState),
    );
    if (!mounted ||
        edited == null ||
        (identical(edited, original) ||
            jsonEncode(edited.notationProjection()) ==
                jsonEncode(original.notationProjection())) ||
        !identical(_editorState.score, original) ||
        _commandEditLock != null) {
      return;
    }
    _updateState(
      (s) => s.applyEditWithSymbolSelection(
        score: edited,
        partIndex: s.selectedPartIndex!,
        measureIndex: s.selectedMeasureIndex!,
        symbolIndex: s.selectedSymbolIndex!,
        symbol: edited.getSymbolAt(
          s.selectedPartIndex!,
          s.selectedMeasureIndex!,
          s.selectedSymbolIndex!,
        )!,
      ),
    );
  }

  /// Adds, renames, reorders or removes staves as one undo step.
  Future<void> _showStaves() async {
    if (!_canEditStaves || _commandEditLock != null) return;
    final original = _editorState.score;
    final plan = await showModalBottomSheet<List<StaffPlanEntry>>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      backgroundColor: AppColors.surface,
      constraints: const BoxConstraints(maxWidth: 560),
      builder: (_) => StavesSheet(
        staves: [
          for (final part in original.parts)
            (part.name, part.measures.firstOrNull?.clef, part.joinsPrevious),
        ],
        addBlockedReason: _editorState.addStaffBlockedReason,
      ),
    );
    // Playback or another edit can start while the sheet is open.
    if (!mounted ||
        plan == null ||
        !identical(_editorState.score, original) ||
        _commandEditLock != null) {
      return;
    }
    _updateState((state) => state.rearrangeParts(plan));
  }

  /// Moves every note by the interval chosen in [TransposeSheet].
  bool get _canTranspose =>
      _canApplyIssueFix &&
      !_isDraggingNote &&
      !_isReviewMode &&
      _editorState.hasPlaybackContent;

  Future<void> _showTranspose() async {
    if (!_canTranspose || _commandEditLock != null) return;
    final original = _editorState.score;
    final selection = _editorState.hasRange
        ? _editorState.selectionPositions
              .where(
                (p) =>
                    original.getSymbolAt(
                          _editorState.selectedPartIndex!,
                          p.measure,
                          p.symbol,
                        )
                        is Note,
              )
              .length
        : null;
    final request = await showModalBottomSheet<TransposeRequest>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      backgroundColor: AppColors.surface,
      constraints: const BoxConstraints(maxWidth: 560),
      builder: (_) => TransposeSheet(
        selectionCount: selection == 0 ? null : selection,
        currentKey:
            original
                .parts
                .firstOrNull
                ?.measures
                .firstOrNull
                ?.keySignature
                ?.fifths ??
            0,
      ),
    );
    // Playback or another edit can start while the sheet is open.
    if (!mounted ||
        request == null ||
        !identical(_editorState.score, original) ||
        _commandEditLock != null) {
      return;
    }
    _updateState(
      (state) => request.selectionOnly
          ? state.transposeSelection(request.options)
          : state.transposeScore(request.options),
    );
  }

  Future<void> _showBeamEditor() async {
    if (_isReviewMode ||
        _playbackPending ||
        _playbackStatus == PlaybackStatus.playing ||
        !_editorState.hasMeasureContext) {
      return;
    }
    final original = _editorState.score;
    final part = _editorState.selectedPartIndex!;
    final measure = _editorState.selectedMeasureIndex!;
    final preview = sliceMeasuresWithInheritedMetadata(
      measures: original.parts[part].measures,
      firstMeasureIndex: measure,
      pageMeasureCount: 1,
    ).first;
    final time =
        preview.timeSignature ?? const TimeSignature(beats: 4, beatType: 4);
    final pickup =
        measure == 0 &&
        original.parts[part].measures.length > 1 &&
        BeamGrouping.quarters(preview.symbols) <
            time.beats * 4.0 / time.beatType - 1e-7;
    final symbols = await showModalBottomSheet<List<ScoreSymbol>>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      backgroundColor: AppColors.surface,
      constraints: const BoxConstraints(maxWidth: 760),
      builder: (_) => BeamEditorSheet(
        measure: preview,
        selectedSymbolIndex: _editorState.selectedSymbolIndex,
        isPickup: pickup,
      ),
    );
    if (!mounted ||
        symbols == null ||
        !identical(_editorState.score, original) ||
        _playbackPending ||
        _playbackStatus == PlaybackStatus.playing) {
      return;
    }
    _updateState((state) => state.applyBeamEdits(symbols));
  }

  void _onPaletteTypeTap(PaletteSymbolType type) {
    if (!_canApplyIssueFix) return;
    setState(() {
      _insertMode = true;
      _insertSymbolType = type;
    });
  }

  static final _pitchLetters = {
    LogicalKeyboardKey.keyA: 'A',
    LogicalKeyboardKey.keyB: 'B',
    LogicalKeyboardKey.keyC: 'C',
    LogicalKeyboardKey.keyD: 'D',
    LogicalKeyboardKey.keyE: 'E',
    LogicalKeyboardKey.keyF: 'F',
    LogicalKeyboardKey.keyG: 'G',
  };

  /// Alt + 2–9 adds that interval above the selected note.
  static final _intervalDigits = {
    LogicalKeyboardKey.digit2: 2,
    LogicalKeyboardKey.digit3: 3,
    LogicalKeyboardKey.digit4: 4,
    LogicalKeyboardKey.digit5: 5,
    LogicalKeyboardKey.digit6: 6,
    LogicalKeyboardKey.digit7: 7,
    LogicalKeyboardKey.digit8: 8,
    LogicalKeyboardKey.digit9: 9,
  };

  /// Writes the letter's note (or a rest when [step] is null) in the chosen
  /// value after the input position, starting in the first bar if nothing is
  /// selected.
  void _enterFromKeyboard(String? step) {
    final type = _insertSymbolType ?? PaletteSymbolType.quarterNote;
    final spec = [
      wholeDuration,
      halfDuration,
      quarterDuration,
      eighthDuration,
      sixteenthDuration,
    ][type.index % 5];
    _updateState((state) {
      final input = state.hasMeasureContext
          ? state
          : state.copyWith(selectedPartIndex: 0, selectedMeasureIndex: 0);
      final next = step == null
          ? input.enterRest(spec, voice: _inputVoice)
          : input.enterNote(step, spec, voice: _inputVoice);
      return identical(next, input) ? state : next;
    });
  }

  void _toggleInsertMode() {
    if (!_canApplyIssueFix) return;
    setState(() {
      _insertMode = !_insertMode;
      _inputVoice = null;
      _insertSymbolType = _insertMode ? PaletteSymbolType.quarterNote : null;
    });
  }

  ({int part, int measure, int symbol})? _adjacentSymbol(int direction) {
    final part = _editorState.selectedPartIndex;
    if (part == null) return null;
    final measures = _editorState.score.parts[part].measures;
    var measure = _editorState.selectedMeasureIndex ?? 0;
    var symbol = _editorState.selectedSymbolIndex != null
        ? _editorState.selectedSymbolIndex! + direction
        : direction > 0
        ? 0
        : measures[measure].symbols.length - 1;
    while (measure >= 0 && measure < measures.length) {
      final symbols = measures[measure].symbols;
      while (symbol >= 0 && symbol < symbols.length) {
        if (symbols[symbol] is Note || symbols[symbol] is Rest) {
          return (part: part, measure: measure, symbol: symbol);
        }
        symbol += direction;
      }
      measure += direction;
      if (measure >= 0 && measure < measures.length) {
        symbol = direction > 0 ? 0 : measures[measure].symbols.length - 1;
      }
    }
    return null;
  }

  void _selectAdjacentSymbol(int direction) {
    if (!_canApplyIssueFix || _reviewOpen) return;
    final next = _adjacentSymbol(direction);
    if (next == null) return;
    _updateState(
      (s) => s.selectSymbolAt(
        partIndex: next.part,
        measureIndex: next.measure,
        symbolIndex: next.symbol,
      ),
    );
    unawaited(
      WidgetsBinding.instance.endOfFrame.then((_) {
        if (mounted) {
          _notationAreaKey.currentState?.focusMeasure(next.part, next.measure);
        }
      }),
    );
  }

  void _showEditorHelp() {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      backgroundColor: AppColors.surface,
      constraints: BoxConstraints(
        maxWidth: 600,
        maxHeight: MediaQuery.sizeOf(context).height * .9,
      ),
      builder: (_) => const EditorHelpSheet(),
    );
  }

  String? get _commandEditLock {
    if (_isReviewMode) return 'This score is open for review';
    if (_reviewOpen) return 'Close notation review to edit the score';
    if (!_canApplyIssueFix) return 'Pause playback to edit the score';
    if (_isDraggingNote) return 'Finish moving the symbol first';
    return null;
  }

  void _copySelection() {
    final clipboard = _editorState.copySelection();
    if (clipboard == null) return;
    setState(() => _clipboard = clipboard);
    _showEditorBanner(
      _EditorBannerData.success(
        'Copied ${clipboard.symbolCount} '
        '${clipboard.symbolCount == 1 ? 'symbol' : 'symbols'}',
      ),
    );
  }

  void _cutSelection() {
    if (_commandEditLock != null || !_editorState.hasEditableSelection) return;
    _copySelection();
    _runEditorCommand(EditorCommand.delete);
  }

  /// Pastes after the selection, over a range, or into the selected bar.
  void _pasteClipboard() {
    final clipboard = _clipboard;
    if (_commandEditLock != null || clipboard == null) return;
    final next = _editorState.paste(clipboard);
    if (identical(next, _editorState)) {
      _showEditorBanner(
        _EditorBannerData(
          message: _editorState.hasMeasureContext
              ? 'Not enough room to paste here. Select a bar with space, or a range to replace.'
              : 'Select a bar or symbol to paste into.',
          backgroundColor: AppColors.surfaceAlt,
          duration: const Duration(seconds: 4),
        ),
      );
      return;
    }
    _updateState((_) => next);
  }

  void _runEditorCommand(EditorCommand command) {
    if (_commandEditLock != null) return;
    _updateState(command.execute);
  }

  Future<void> _showScoreCommands() async {
    if (_isDraggingNote || _dragGhostEntry != null) return;
    final lock = _commandEditLock;
    final state = _editorState;
    final choices = [
      for (final command in EditorCommand.values)
        EditorCommandChoice(
          id: command.name,
          label: command.label,
          group: command.group,
          description: command.description,
          shortcut: command.shortcut,
          disabledReason: lock ?? command.unavailableReason(state),
        ),
      for (final (id, label, keys) in const [
        ('annotations', 'Text, tempo & chords…', null),
        ('tempo', 'Tempo marking…', 'Ctrl/Cmd + Alt + T'),
        ('chord', 'Chord symbol…', 'Ctrl/Cmd + Alt + K'),
        ('rehearsal', 'Rehearsal mark…', null),
      ])
        EditorCommandChoice(
          id: 'workspace.$id',
          label: label,
          group: 'Text',
          description: 'Add or edit beat-attached score markings',
          shortcut: keys,
          disabledReason:
              lock ?? (state.hasMeasureContext ? null : 'Select a bar'),
        ),
      EditorCommandChoice(
        id: 'workspace.lyrics',
        label: 'Lyrics…',
        group: 'Text',
        description: 'Enter syllables, verses and extension lines on notes',
        shortcut: 'Ctrl / ⌘ + L',
        disabledReason: lock ?? state.lyricUnavailableReason,
      ),
      EditorCommandChoice(
        id: 'workspace.entry',
        label: 'Toggle note entry',
        group: 'Input',
        description: 'Choose a value, then tap or drag onto the staff',
        shortcut: 'N',
        disabledReason: lock,
      ),
      EditorCommandChoice(
        id: 'workspace.beams',
        label: 'Edit beams',
        group: 'Rhythm',
        description: 'Join, separate or group notes by beat',
        disabledReason:
            lock ??
            (!state.hasMeasureContext
                ? 'Select a bar with eighth or sixteenth notes'
                : !state
                      .score
                      .parts[state.selectedPartIndex!]
                      .measures[state.selectedMeasureIndex!]
                      .symbols
                      .any(BeamGrouping.eligible)
                ? 'Select a bar with eighth or sixteenth notes'
                : null),
      ),
      for (final sign in BarSign.values)
        EditorCommandChoice(
          id: 'workspace.bar.${sign.name}',
          label: sign.label,
          group: 'Repeats',
          description: 'Add or remove it on the selected bars in every staff',
          disabledReason:
              lock ?? (state.barSignOn(sign) == null ? 'Select a bar' : null),
        ),
      for (final mark in editorDynamics)
        EditorCommandChoice(
          id: 'workspace.dynamic.$mark',
          label: 'Dynamic $mark',
          group: 'Dynamics',
          description: 'Put $mark on the first selected note or rest',
          disabledReason:
              lock ?? state.hairpinUnavailableReason(SpannerKind.crescendo),
        ),
      EditorCommandChoice(
        id: 'workspace.copy',
        label: 'Copy',
        group: 'Selection',
        description: 'Copy the selected notes and rests',
        shortcut: 'Ctrl / ⌘ + C',
        disabledReason: state.hasEditableSelection
            ? null
            : 'Select notes or rests',
      ),
      EditorCommandChoice(
        id: 'workspace.cut',
        label: 'Cut',
        group: 'Selection',
        description: 'Copy the selection, then delete it',
        shortcut: 'Ctrl / ⌘ + X',
        disabledReason:
            lock ??
            (state.hasEditableSelection ? null : 'Select notes or rests'),
      ),
      EditorCommandChoice(
        id: 'workspace.paste',
        label: 'Paste',
        group: 'Selection',
        description: 'Paste after the selection, over a range, or into a bar',
        shortcut: 'Ctrl / ⌘ + V',
        disabledReason:
            lock ??
            (_clipboard == null
                ? 'Copy notes or rests first'
                : !state.hasMeasureContext
                ? 'Select a bar or symbol'
                : null),
      ),
      EditorCommandChoice(
        id: 'workspace.staves',
        label: 'Staves and instruments…',
        group: 'Structure',
        description: 'Add, rename, reorder or remove staves',
        disabledReason: lock,
      ),
      EditorCommandChoice(
        id: 'workspace.transpose',
        label: 'Transpose…',
        group: 'Pitch',
        description: 'Move the score to another key or by an interval',
        disabledReason:
            lock ??
            (state.hasPlaybackContent
                ? null
                : 'Add notes or chord symbols first'),
      ),
      EditorCommandChoice(
        id: 'workspace.addBar',
        label: 'Add bar',
        group: 'Structure',
        description: 'Append a measure in every staff',
        disabledReason:
            lock ??
            (state.score.parts.isEmpty ? 'Open a score with a staff' : null),
      ),
      EditorCommandChoice(
        id: 'workspace.fit',
        label: 'Fit page',
        group: 'View',
        description: 'Show the whole page',
      ),
      EditorCommandChoice(
        id: 'workspace.focus',
        label: 'Focus selected bar',
        group: 'View',
        description: 'Zoom to the current measure',
        disabledReason: state.hasMeasureContext ? null : 'Select a bar',
      ),
      EditorCommandChoice(
        id: 'workspace.save',
        label: 'Save score',
        group: 'File',
        description: 'Save the current project on this device',
        shortcut: 'Ctrl / ⌘ + S',
        disabledReason: _isReviewMode
            ? 'This score is open for review'
            : _isSaving
            ? 'A save is in progress'
            : null,
      ),
      const EditorCommandChoice(
        id: 'workspace.help',
        label: 'Editor guide',
        group: 'Help',
        description: 'Learn editing gestures and keyboard shortcuts',
      ),
    ];
    final id = await showDialog<String>(
      context: context,
      builder: (context) => Dialog(
        backgroundColor: AppColors.surface,
        insetPadding: const EdgeInsets.all(16),
        child: SizedBox(
          width: 640,
          height: math.min(640, MediaQuery.sizeOf(context).height * .82),
          child: EditorCommandPalette(choices: choices),
        ),
      ),
    );
    if (!mounted || id == null) return;
    final command = EditorCommand.values.where((c) => c.name == id).firstOrNull;
    if (command != null) {
      _runEditorCommand(command);
      return;
    }
    // Recheck state after dismissal: playback can have changed with search open.
    switch (id) {
      case 'workspace.annotations':
        await _showAnnotations();
      case 'workspace.tempo':
        await _showAnnotations(kind: AnnotationKind.tempo);
      case 'workspace.chord':
        await _showAnnotations(kind: AnnotationKind.chord);
      case 'workspace.rehearsal':
        await _showAnnotations(kind: AnnotationKind.rehearsal);
      case 'workspace.lyrics':
        await _showLyrics();
      case 'workspace.entry':
        if (_commandEditLock == null) _toggleInsertMode();
      case 'workspace.beams':
        if (_commandEditLock == null) await _showBeamEditor();
      case 'workspace.transpose':
        await _showTranspose();
      case 'workspace.staves':
        await _showStaves();
      case final id when id.startsWith('workspace.bar.'):
        final sign = BarSign.values.byName(
          id.substring('workspace.bar.'.length),
        );
        if (_commandEditLock == null) {
          _updateState((s) => s.toggleBarSign(sign));
        }
      case final id when id.startsWith('workspace.dynamic.'):
        if (_commandEditLock == null) {
          _updateState(
            (s) => s.setDynamic(id.substring('workspace.dynamic.'.length)),
          );
        }
      case 'workspace.copy':
        _copySelection();
      case 'workspace.cut':
        _cutSelection();
      case 'workspace.paste':
        _pasteClipboard();
      case 'workspace.addBar':
        if (_commandEditLock == null) {
          _updateState((s) => s.appendMeasureAtEnd());
          setState(_jumpToLastPage);
        }
      case 'workspace.fit':
        _notationAreaKey.currentState?._fitToScreen();
      case 'workspace.focus':
        if (_editorState.hasMeasureContext) {
          _notationAreaKey.currentState?.focusMeasure(
            _editorState.selectedPartIndex!,
            _editorState.selectedMeasureIndex!,
          );
        }
      case 'workspace.save':
        if (!_isReviewMode && !_isSaving) await _onSave();
      case 'workspace.help':
        _showEditorHelp();
    }
  }

  KeyEventResult _handleEditorKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    final focused = FocusManager.instance.primaryFocus?.context;
    if (ModalRoute.of(context)?.isCurrent != true ||
        focused?.widget is EditableText ||
        focused?.findAncestorWidgetOfExactType<EditableText>() != null ||
        _reviewOpen ||
        _isReviewMode) {
      return KeyEventResult.ignored;
    }
    final key = event.logicalKey;
    final keyboard = HardwareKeyboard.instance;
    final command = keyboard.isControlPressed || keyboard.isMetaPressed;
    if (command &&
        keyboard.isAltPressed &&
        (key == LogicalKeyboardKey.keyT || key == LogicalKeyboardKey.keyK)) {
      unawaited(
        _showAnnotations(
          kind: key == LogicalKeyboardKey.keyT
              ? AnnotationKind.tempo
              : AnnotationKind.chord,
        ),
      );
      return KeyEventResult.handled;
    }
    if (command && key == LogicalKeyboardKey.keyK && !keyboard.isAltPressed) {
      unawaited(_showScoreCommands());
      return KeyEventResult.handled;
    }
    if (command && key == LogicalKeyboardKey.keyS) {
      if (!_isSaving) _onSave();
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.space && !command && !keyboard.isAltPressed) {
      if (_playbackStatus == PlaybackStatus.playing) {
        _playback.pause();
      } else if (_playbackStatus == PlaybackStatus.paused) {
        _playback.resume(score: _editorState.score);
      } else if (!_playbackPending && _editorState.hasPlaybackContent) {
        unawaited(
          _playFromMeasure(
            _editorState.selectedMeasureIndex ?? 0,
            partIndex: _editorState.selectedPartIndex ?? 0,
          ),
        );
      }
      return KeyEventResult.handled;
    }
    if (_commandEditLock != null) return KeyEventResult.ignored;
    if (command) {
      if (key == LogicalKeyboardKey.keyL) {
        unawaited(_showLyrics());
        return KeyEventResult.handled;
      }
      if (key == LogicalKeyboardKey.keyZ) {
        _runEditorCommand(
          keyboard.isShiftPressed ? EditorCommand.redo : EditorCommand.undo,
        );
        return KeyEventResult.handled;
      }
      if (key == LogicalKeyboardKey.keyY) {
        _runEditorCommand(EditorCommand.redo);
        return KeyEventResult.handled;
      }
      if (keyboard.isAltPressed) {
        final voice =
            const [
              LogicalKeyboardKey.digit1,
              LogicalKeyboardKey.digit2,
              LogicalKeyboardKey.digit3,
              LogicalKeyboardKey.digit4,
            ].indexOf(key) +
            1;
        if (voice > 0) {
          setState(() => _inputVoice = voice);
          return KeyEventResult.handled;
        }
      }
      // Ctrl + 3, 5, 6, 7: tuplets, as in MuseScore.
      final tuplet = {
        LogicalKeyboardKey.digit3: 3,
        LogicalKeyboardKey.digit5: 5,
        LogicalKeyboardKey.digit6: 6,
        LogicalKeyboardKey.digit7: 7,
      }[key];
      if (tuplet != null && !keyboard.isAltPressed) {
        _updateState((s) => s.makeTuplet(tuplet));
        return KeyEventResult.handled;
      }
      if (key == LogicalKeyboardKey.keyA) {
        _runEditorCommand(EditorCommand.selectAll);
        return KeyEventResult.handled;
      }
      if (key == LogicalKeyboardKey.keyC) {
        _copySelection();
        return KeyEventResult.handled;
      }
      if (key == LogicalKeyboardKey.keyX) {
        _cutSelection();
        return KeyEventResult.handled;
      }
      if (key == LogicalKeyboardKey.keyV) {
        _pasteClipboard();
        return KeyEventResult.handled;
      }
      if (keyboard.isShiftPressed &&
          (key == LogicalKeyboardKey.arrowLeft ||
              key == LogicalKeyboardKey.arrowRight)) {
        _updateState(
          (s) => s.extendSelectionByBar(
            key == LogicalKeyboardKey.arrowLeft ? -1 : 1,
          ),
        );
        return KeyEventResult.handled;
      }
      if (!keyboard.isAltPressed &&
          !keyboard.isShiftPressed &&
          (key == LogicalKeyboardKey.arrowUp ||
              key == LogicalKeyboardKey.arrowDown)) {
        _runEditorCommand(
          key == LogicalKeyboardKey.arrowUp
              ? EditorCommand.octaveUp
              : EditorCommand.octaveDown,
        );
        return KeyEventResult.handled;
      }
      return KeyEventResult.ignored;
    }
    final letter = _pitchLetters[key];
    if (keyboard.isAltPressed && !keyboard.isShiftPressed) {
      final interval = _intervalDigits[key];
      if (interval == null) return KeyEventResult.ignored;
      _updateState((s) => s.addChordInterval(interval));
      return KeyEventResult.handled;
    }
    // MuseScore's +: tie (in note entry, a new tied note of the same pitch).
    if (key == LogicalKeyboardKey.numpadAdd ||
        key == LogicalKeyboardKey.add ||
        (keyboard.isShiftPressed && key == LogicalKeyboardKey.equal)) {
      if (_insertMode) {
        final type = _insertSymbolType ?? PaletteSymbolType.quarterNote;
        final spec = [
          wholeDuration,
          halfDuration,
          quarterDuration,
          eighthDuration,
          sixteenthDuration,
        ][type.index % 5];
        _updateState((s) => s.enterTiedNote(spec));
      } else {
        _runEditorCommand(EditorCommand.tie);
      }
      return KeyEventResult.handled;
    }
    if (keyboard.isShiftPressed &&
        !keyboard.isAltPressed &&
        (key == LogicalKeyboardKey.arrowLeft ||
            key == LogicalKeyboardKey.arrowRight)) {
      _updateState(
        (s) => s.extendSelection(key == LogicalKeyboardKey.arrowLeft ? -1 : 1),
      );
      return KeyEventResult.handled;
    }
    // MuseScore's articulation shortcuts.
    final markCommand = keyboard.isShiftPressed && !keyboard.isAltPressed
        ? {
            LogicalKeyboardKey.keyS: EditorCommand.staccato,
            LogicalKeyboardKey.keyN: EditorCommand.tenuto,
            LogicalKeyboardKey.keyV: EditorCommand.accent,
            LogicalKeyboardKey.keyO: EditorCommand.marcato,
          }[key]
        : null;
    if (markCommand != null) {
      _runEditorCommand(markCommand);
      return KeyEventResult.handled;
    }
    // MuseScore's < and >: hairpins.
    final hairpinCommand =
        key == LogicalKeyboardKey.less ||
            (keyboard.isShiftPressed && key == LogicalKeyboardKey.comma)
        ? EditorCommand.crescendo
        : key == LogicalKeyboardKey.greater ||
              (keyboard.isShiftPressed && key == LogicalKeyboardKey.period)
        ? EditorCommand.diminuendo
        : null;
    if (hairpinCommand != null) {
      _runEditorCommand(hairpinCommand);
      return KeyEventResult.handled;
    }
    if (keyboard.isShiftPressed && !keyboard.isAltPressed && letter != null) {
      _updateState((s) => s.addChordStep(letter));
      return KeyEventResult.handled;
    }
    if (keyboard.isAltPressed || keyboard.isShiftPressed) {
      return KeyEventResult.ignored;
    }
    if (key == LogicalKeyboardKey.keyS) {
      _runEditorCommand(EditorCommand.slur);
      return KeyEventResult.handled;
    }
    if (letter != null) {
      if (_insertMode) {
        _enterFromKeyboard(letter);
      } else {
        _updateState((s) => s.setSelectedNoteStep(letter));
      }
      return KeyEventResult.handled;
    }
    if (_insertMode &&
        (key == LogicalKeyboardKey.digit0 ||
            key == LogicalKeyboardKey.numpad0)) {
      _enterFromKeyboard(null);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.escape) {
      setState(() {
        _insertMode = false;
        _insertSymbolType = null;
        _extendMode = false;
      });
      _updateState((s) => s.clearSymbolSelectionPreservingMeasureContext());
    } else if (key == LogicalKeyboardKey.keyN) {
      _toggleInsertMode();
    } else if (key == LogicalKeyboardKey.arrowLeft ||
        key == LogicalKeyboardKey.arrowRight) {
      _selectAdjacentSymbol(key == LogicalKeyboardKey.arrowLeft ? -1 : 1);
    } else if (key == LogicalKeyboardKey.arrowUp ||
        key == LogicalKeyboardKey.arrowDown) {
      _runEditorCommand(
        key == LogicalKeyboardKey.arrowUp
            ? EditorCommand.pitchUp
            : EditorCommand.pitchDown,
      );
    } else if (key == LogicalKeyboardKey.delete ||
        key == LogicalKeyboardKey.backspace) {
      _runEditorCommand(EditorCommand.delete);
    } else {
      final rhythm = switch (key) {
        LogicalKeyboardKey.digit3 ||
        LogicalKeyboardKey.numpad3 => EditorCommand.sixteenth,
        LogicalKeyboardKey.digit4 ||
        LogicalKeyboardKey.numpad4 => EditorCommand.eighth,
        LogicalKeyboardKey.digit5 ||
        LogicalKeyboardKey.numpad5 => EditorCommand.quarter,
        LogicalKeyboardKey.digit6 ||
        LogicalKeyboardKey.numpad6 => EditorCommand.half,
        LogicalKeyboardKey.digit7 ||
        LogicalKeyboardKey.numpad7 => EditorCommand.whole,
        LogicalKeyboardKey.period ||
        LogicalKeyboardKey.numpadDecimal => EditorCommand.dot,
        _ => null,
      };
      if (rhythm == null) return KeyEventResult.ignored;
      if (_insertMode && rhythm.duration != null) {
        final index = switch (rhythm) {
          EditorCommand.whole => 0,
          EditorCommand.half => 1,
          EditorCommand.quarter => 2,
          EditorCommand.eighth => 3,
          _ => 4,
        };
        _onPaletteTypeTap(
          PaletteSymbolType.values[index +
              ((_insertSymbolType?.isRest ?? false) ? 5 : 0)],
        );
      } else {
        // While entering notes a dot applies to the note just written.
        _runEditorCommand(rhythm);
      }
    }
    return KeyEventResult.handled;
  }

  @override
  Widget build(BuildContext context) {
    final isPlaybackActive =
        _playbackStatus == PlaybackStatus.playing ||
        _reviewListening ||
        _playbackPending;
    final isReadOnly = _isReviewMode;
    final selected = _editorState.selectedSymbol;
    final simultaneousParts =
        _editorState.score.playbackLayout ==
        ScorePlaybackLayout.simultaneousParts;
    final hasSelection = _editorState.hasSelection;
    final hasMeasureContext =
        _editorState.selectedPartIndex != null &&
        _editorState.selectedMeasureIndex != null;
    final selectedMeasureIndex = _editorState.selectedMeasureIndex ?? 0;
    final selectedPartIndex = _editorState.selectedPartIndex ?? 0;
    final measureCount =
        _editorState.score.parts.isEmpty ||
            selectedPartIndex >= _editorState.score.parts.length
        ? 0
        : _editorState.score.parts[selectedPartIndex].measures.length;
    final canDeleteMeasure = hasMeasureContext && measureCount > 1;
    final measuresPerPart = _editorState.score.parts.isEmpty
        ? 1
        : _editorState.score.parts
              .map((p) => p.measures.length)
              .reduce((a, b) => a > b ? a : b)
              .clamp(1, 1 << 30);
    final currentMeasureClef =
        _editorState.score.parts.isNotEmpty &&
            selectedPartIndex < _editorState.score.parts.length &&
            _editorState.score.parts[selectedPartIndex].measures.isNotEmpty
        ? _editorState.score.parts[selectedPartIndex].measures.first.clef
        : null;
    final selectedMeasureNumber = hasMeasureContext
        ? _editorState
              .score
              .parts[selectedPartIndex]
              .measures[selectedMeasureIndex]
              .number
        : null;

    final editor = PopScope(
      canPop: isReadOnly || !_editorState.hasUnsavedChanges,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _handlePopAttempt();
      },
      child: Scaffold(
        backgroundColor: AppColors.background,
        // Text entry lives in dialogs/sheets that handle their own insets.
        // Keep the score workspace stable behind their on-screen keyboard.
        resizeToAvoidBottomInset: false,
        body: SafeArea(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final isLandscape =
                  constraints.maxWidth >= 900 ||
                  (constraints.maxWidth >= 600 && constraints.maxHeight < 500);

              final shownScore = _reviewPreview && _reviewPlan != null
                  ? _reviewPlan!.preview
                  : _editorState.score;
              final notationArea = _NotationArea(
                key: _notationAreaKey,
                issueMarks: _issueMarks,
                reviewFocusMeasure: _reviewOpen
                    ? _focusedIssue?.measureIndex
                    : null,
                reviewFocusPart: _focusedIssue?.partIndex ?? 0,
                fitInsets: const EdgeInsets.only(
                  bottom: _kFloatingControlsReserve,
                ),
                editorState: identical(shownScore, _editorState.score)
                    ? _editorState
                    : EditorState(
                        score: shownScore,
                        selectedPartIndex: _editorState.selectedPartIndex,
                        selectedMeasureIndex: _editorState.selectedMeasureIndex,
                      ),
                layoutPolicy: _pageMetrics.layoutPolicy,
                pageFirstMeasure: _pageMetrics.pageFirstMeasure,
                pageMeasureCount: _pageMetrics.pageMeasureCount,
                insertMode: _insertMode,
                insertSymbolType: _insertSymbolType,
                playbackPosition: _playbackPosition,
                playheadEpoch: _playheadEpoch,
                playheadSymbolIndex: _playheadSymbolIndex,
                playheadNoteDurationMs: _playheadNoteDurationMs,
                showPlaybackSymbolHighlight: _showPlaybackSymbolHighlight,
                isDraggingNote: _isDraggingNote,
                dragGlobal: _dragGlobal,
                trashZoneKey: _trashZoneKey,
                showTrashZone: isLandscape,
                isPlaybackActive: isPlaybackActive,
                isReadOnly: isReadOnly || _reviewOpen,
                suppressCanvasDragGhost: _dragSymbolType != null,
                onAnnotationTap: (p, m, i) {
                  if (_commandEditLock != null) return;
                  setState(
                    () => _editorState = _editorState.copyWith(
                      selectedPartIndex: p,
                      selectedMeasureIndex: m,
                      selectedSymbolIndex: null,
                      selectedSymbol: null,
                    ),
                  );
                  unawaited(_showAnnotations(initialIndex: i));
                },
                onMeasureTap: (target) {
                  if (_reviewOpen &&
                      target != null &&
                      !_reviewPreview &&
                      !isPlaybackActive) {
                    final issue = _notationIssues
                        .where(
                          (i) =>
                              i.partIndex == target.partIndex &&
                              i.measureIndex == target.measureIndex,
                        )
                        .firstOrNull;
                    if (issue != null &&
                        NotationReviewService.key(_editorState.score, issue) !=
                            _focusedIssueKey) {
                      _showIssue(issue);
                    }
                  } else {
                    _selectMeasureForReview(target);
                  }
                },
                onSymbolTap: (target) {
                  if (target == null) {
                    _updateState(
                      (s) => s.clearSymbolSelectionPreservingMeasureContext(),
                    );
                  } else {
                    _onNotationSymbolTap(
                      target.partIndex,
                      target.measureIndex,
                      target.symbolIndex,
                    );
                  }
                },
                onInsertTap: _onInsertTap,
                onDragStarted: (target) {
                  final symbol = _editorState.score.getSymbolAt(
                    target.partIndex,
                    target.measureIndex,
                    target.symbolIndex,
                  );
                  setState(() {
                    _isDraggingNote = true;
                    _dragTarget = target;
                    _dragSymbolType = _paletteTypeForSymbol(symbol);
                  });
                },
                onDragGlobalUpdate: (global) {
                  setState(() => _dragGlobal = global);
                  _ghostPosition.value = global;
                  if (_dragGhostEntry == null &&
                      _dragSymbolType != null &&
                      mounted) {
                    _dragGhostEntry = OverlayEntry(
                      builder: (_) => _DragGhostOverlay(
                        positionNotifier: _ghostPosition,
                        type: _dragSymbolType!,
                      ),
                    );
                    Overlay.of(context).insert(_dragGhostEntry!);
                  }
                },
                onDragCompleted: (reorder, global) {
                  _dragGhostEntry?.remove();
                  _dragGhostEntry = null;
                  final trashBox =
                      _trashZoneKey.currentContext?.findRenderObject()
                          as RenderBox?;
                  final isOverTrash =
                      trashBox != null &&
                      (trashBox.localToGlobal(Offset.zero) & trashBox.size)
                          .contains(global);
                  if (isOverTrash && _dragTarget != null) {
                    final t = _dragTarget!;
                    _updateState(
                      (s) => s.deleteSymbolAtSelectionTarget(
                        partIndex: t.partIndex,
                        measureIndex: t.measureIndex,
                        symbolIndex: t.symbolIndex,
                      ),
                    );
                  } else if (reorder != null) {
                    _updateState(
                      (s) => s.moveSymbolToDest(
                        fromPartIndex: reorder.fromPartIndex,
                        fromMeasureIndex: reorder.fromMeasureIndex,
                        fromSymbolIndex: reorder.fromSymbolIndex,
                        toPartIndex: reorder.toPartIndex,
                        toMeasureIndex: reorder.toMeasureIndex,
                        toSymbolIndex: reorder.toSymbolIndex,
                      ),
                    );
                  }
                  setState(() {
                    _isDraggingNote = false;
                    _dragGlobal = Offset.zero;
                    _dragTarget = null;
                    _dragSymbolType = null;
                  });
                },
                onDragCancelled: () {
                  _dragGhostEntry?.remove();
                  _dragGhostEntry = null;
                  setState(() {
                    _isDraggingNote = false;
                    _dragGlobal = Offset.zero;
                    _dragTarget = null;
                    _dragSymbolType = null;
                  });
                },
                onExternalDrop: _onPaletteDrop,
              );

              final onPrevPage = _currentPageIndex > 0
                  ? () => setState(
                      () => _setCurrentPageIndex(_currentPageIndex - 1),
                    )
                  : null;
              final onNextPage = _currentPageIndex < _pageMetrics.totalPages - 1
                  ? () => setState(
                      () => _setCurrentPageIndex(_currentPageIndex + 1),
                    )
                  : null;
              final inspectorPanel = isReadOnly
                  ? _ReviewPanel(
                      isLandscape: isLandscape,
                      isPlaybackActive: isPlaybackActive,
                      selectedMeasureNumber: selectedMeasureNumber,
                      currentComment: _commentForSelectedMeasure(),
                      currentPageIndex: _currentPageIndex,
                      totalPages: _pageMetrics.totalPages,
                      canEditComment: _canEditTeacherComments,
                      onPrevPage: onPrevPage,
                      onNextPage: onNextPage,
                      onPageOverviewTap: _showPageOverview,
                      onEditComment:
                          !_canEditTeacherComments ||
                              selectedMeasureNumber == null ||
                              isPlaybackActive
                          ? null
                          : _showMeasureCommentDialog,
                      onExportProject:
                          _canEditTeacherComments && _currentProject != null
                          ? _exportCurrentNvscoreProject
                          : null,
                    )
                  : _InspectorPanel(
                      isLandscape: isLandscape,
                      insertMode: _insertMode,
                      insertSymbolType: _insertSymbolType,
                      inputVoice: _effectiveInputVoice,
                      onVoiceSelected: (voice) =>
                          setState(() => _inputVoice = voice),
                      onToggleInsertMode: _toggleInsertMode,
                      onPaletteTypeTap: _onPaletteTypeTap,
                      onPreviousSymbol: _adjacentSymbol(-1) == null
                          ? null
                          : () => _selectAdjacentSymbol(-1),
                      onNextSymbol: _adjacentSymbol(1) == null
                          ? null
                          : () => _selectAdjacentSymbol(1),
                      isPlaybackActive: isPlaybackActive,
                      selected: selected,
                      hasSelection: hasSelection,
                      hasMeasureContext: hasMeasureContext,
                      selectedMeasureNumber: selectedMeasureNumber,
                      onMoveUp: () => _runEditorCommand(EditorCommand.pitchUp),
                      onMoveDown: () =>
                          _runEditorCommand(EditorCommand.pitchDown),
                      onOctaveUp:
                          EditorCommand.octaveUp.unavailableReason(
                                _editorState,
                              ) ==
                              null
                          ? () => _runEditorCommand(EditorCommand.octaveUp)
                          : null,
                      onOctaveDown:
                          EditorCommand.octaveDown.unavailableReason(
                                _editorState,
                              ) ==
                              null
                          ? () => _runEditorCommand(EditorCommand.octaveDown)
                          : null,
                      onAddThird:
                          EditorCommand.addThird.unavailableReason(
                                _editorState,
                              ) ==
                              null
                          ? () => _runEditorCommand(EditorCommand.addThird)
                          : null,
                      onTie: _editorState.tieUnavailableReason == null
                          ? () => _runEditorCommand(EditorCommand.tie)
                          : null,
                      onSlur: _editorState.slurUnavailableReason == null
                          ? () => _runEditorCommand(EditorCommand.slur)
                          : null,
                      onAnnotations: _editorState.hasMeasureContext
                          ? () => _showAnnotations()
                          : null,
                      onLyrics: _editorState.lyricUnavailableReason == null
                          ? _showLyrics
                          : null,
                      onTriplet: _editorState.tupletUnavailableReason(3) == null
                          ? () => _runEditorCommand(EditorCommand.triplet)
                          : null,
                      markStates: {
                        for (final mark in Articulation.values)
                          mark: _editorState.markUnavailableReason(mark) == null
                              ? _editorState.hasMark(mark)
                              : null,
                      },
                      onToggleMark: (mark) =>
                          _updateState((s) => s.toggleMark(mark)),
                      dynamicMark: _editorState.selectedDynamic,
                      onDynamic:
                          _editorState.hairpinUnavailableReason(
                                SpannerKind.crescendo,
                              ) ==
                              null
                          ? (mark) => _updateState((s) => s.setDynamic(mark))
                          : null,
                      onHairpin:
                          _editorState.hairpinUnavailableReason(
                                SpannerKind.crescendo,
                              ) ==
                              null
                          ? (kind) => _runEditorCommand(
                              kind == SpannerKind.crescendo
                                  ? EditorCommand.crescendo
                                  : EditorCommand.diminuendo,
                            )
                          : null,
                      rangeCount: _editorState.hasRange
                          ? _editorState.selectionPositions.length
                          : 0,
                      extendMode: _extendMode,
                      onToggleExtend: () =>
                          setState(() => _extendMode = !_extendMode),
                      onSelectBar:
                          EditorCommand.selectBar.unavailableReason(
                                _editorState,
                              ) ==
                              null
                          ? () => _runEditorCommand(EditorCommand.selectBar)
                          : null,
                      onCopy: _editorState.hasEditableSelection
                          ? _copySelection
                          : null,
                      onCut: _editorState.hasEditableSelection
                          ? _cutSelection
                          : null,
                      onPaste:
                          _clipboard != null && _editorState.hasMeasureContext
                          ? _pasteClipboard
                          : null,
                      onConvertSymbol: _editorState.hasRange
                          ? null
                          : selected is Rest
                          ? () => _runEditorCommand(EditorCommand.restToNote)
                          : _editorState.canConvertSelectedNoteToRest
                          ? () => _runEditorCommand(EditorCommand.noteToRest)
                          : null,
                      onWhole: () => _runEditorCommand(EditorCommand.whole),
                      onHalf: () => _runEditorCommand(EditorCommand.half),
                      onQuarter: () => _runEditorCommand(EditorCommand.quarter),
                      onEighth: () => _runEditorCommand(EditorCommand.eighth),
                      onSixteenth: () =>
                          _runEditorCommand(EditorCommand.sixteenth),
                      onSetAccidental: (alter) => _updateState(
                        (s) => s.setSelectedNoteAccidental(alter),
                      ),
                      allowedDurations: {
                        if (!_editorState.hasRange)
                          for (final spec in [
                            wholeDuration,
                            halfDuration,
                            quarterDuration,
                            eighthDuration,
                            sixteenthDuration,
                          ])
                            if (_editorState.canSetSelectedDuration(spec))
                              spec.type,
                      },
                      canToggleDot:
                          !_editorState.hasRange &&
                          _editorState.canToggleSelectedDot,
                      onBeams:
                          hasMeasureContext &&
                              _editorState
                                  .score
                                  .parts[selectedPartIndex]
                                  .measures[selectedMeasureIndex]
                                  .symbols
                                  .any(BeamGrouping.eligible)
                          ? _showBeamEditor
                          : null,
                      currentMeasureClef: currentMeasureClef,
                      currentTimeSignature:
                          _editorState.selectedMeasureTimeSignature,
                      onSetTimeSignature: (timeSignature) => _updateState(
                        (s) =>
                            s.setTimeSignatureAtSelectedMeasure(timeSignature),
                      ),
                      barSignOn: _editorState.barSignOn,
                      onBarSign: (sign) =>
                          _updateState((s) => s.toggleBarSign(sign)),
                      onSetClef: (clef) {
                        if (clef != null) {
                          _updateState((s) => s.setPartClef(clef));
                        }
                      },
                      onMoveToPrev: () => _updateState(
                        (s) => s.moveSelectedSymbolToMeasureOffset(-1),
                      ),
                      onMoveToNext: () => _updateState(
                        (s) => s.moveSelectedSymbolToMeasureOffset(1),
                      ),
                      onStaves: _canEditStaves ? _showStaves : null,
                      onAddMeasure: () {
                        _updateState((s) => s.appendMeasureAtEnd());
                        setState(_jumpToLastPage);
                      },
                      onAddPage: () {
                        _updateState((s) => s.addPageAtEnd());
                        setState(_jumpToLastPage);
                      },
                      canDeleteMeasure: canDeleteMeasure,
                      onDeleteMeasure: () =>
                          _updateState((s) => s.deleteSelectedMeasure()),
                      onDeleteSymbol: () =>
                          _runEditorCommand(EditorCommand.delete),
                      onToggleDot: () => _runEditorCommand(EditorCommand.dot),
                    );

              final scoreIsEmpty =
                  _editorState.score.parts.isEmpty ||
                  _editorState.score.parts.every(
                    (p) => p.measures.every(
                      (m) => m.symbols.isEmpty && m.annotations.isEmpty,
                    ),
                  );

              return _EditorWorkspace(
                isLandscape: isLandscape,
                isDraggingNote: _isDraggingNote,
                dragGlobal: _dragGlobal,
                trashZoneKey: _trashZoneKey,
                banner: _banner,
                reviewPanelFraction: _reviewPanelFraction,
                onReviewResize: (fraction) =>
                    setState(() => _reviewPanelFraction = fraction),
                reviewPanel: !_reviewOpen
                    ? null
                    : NotationReviewPanel(
                        score: _editorState.score,
                        issues: _notationIssues,
                        focusedKey: _focusedIssueKey,
                        onFocus: _showIssue,
                        onApply: _applyReviewPlan,
                        onKeep: _keepIssue,
                        onPlanChanged: (plan) =>
                            setState(() => _reviewPlan = plan),
                        onPreviewChanged: (preview) =>
                            setState(() => _reviewPreview = preview),
                        onClose: _stopNotationCheck,
                        onEditManually: _editReviewManually,
                        onListen: (score, part, first, last) =>
                            unawaited(_listenReview(score, part, first, last)),
                        onRestore: _restoreReview,
                        previewing: _reviewPreview,
                        canEdit: _canApplyIssueFix,
                        listening: _reviewListening,
                        onStopListening: () {
                          _stopReviewListening();
                          setState(() {});
                        },
                      ),
                checkBar: _notationCheckOn && !_reviewOpen
                    ? NotationCheckBar(
                        issueCount: _notationIssues.length,
                        appliedCount: _editorState.score.reviewHistory
                            .where(
                              (e) => e.disposition == ReviewDisposition.applied,
                            )
                            .length,
                        keptCount: _editorState.score.reviewHistory
                            .where(
                              (e) => e.disposition == ReviewDisposition.kept,
                            )
                            .length,
                        onReview: _startNotationCheck,
                        onClose: _stopNotationCheck,
                      )
                    : null,
                navigation: _WorkspaceNavigation(
                  location: hasMeasureContext
                      ? '${_editorState.score.parts[selectedPartIndex].name} · Bar $selectedMeasureNumber'
                      : 'Choose a bar to begin',
                  currentPageIndex: _currentPageIndex,
                  totalPages: _pageMetrics.totalPages,
                  onPrevPage: onPrevPage,
                  onNextPage: onNextPage,
                  onPageOverviewTap: _showPageOverview,
                  onHelp: _showEditorHelp,
                  onCommands: _showScoreCommands,
                ),
                header: _EditorHeader(
                  title:
                      _currentProject?.name ??
                      (_editorState.score.title.isEmpty
                          ? 'Untitled Score'
                          : _editorState.score.title),
                  hasUnsavedChanges: _editorState.hasUnsavedChanges,
                  editCount: _scoreEditCount,
                  scoreLabel: _scoreLabel,
                  isReviewMode: isReadOnly,
                  reviewModeLabel: _canEditTeacherComments
                      ? 'Review Mode'
                      : 'Feedback Mode',
                  canUndo:
                      _editorState.canUndo && !isPlaybackActive && !isReadOnly,
                  canRedo:
                      _editorState.canRedo && !isPlaybackActive && !isReadOnly,
                  onBack: () => Navigator.of(context).maybePop(),
                  onUndo: () => _updateState((s) => s.applyUndo()),
                  onRedo: () => _updateState((s) => s.applyRedo()),
                  onClearAllSymbols: _canClearAllSymbols
                      ? _confirmClearAllSymbols
                      : null,
                  onTranspose: _canTranspose ? _showTranspose : null,
                  onStaves: _canEditStaves ? _showStaves : null,
                  onSave: isReadOnly ? null : _onSave,
                  isSaving: _isSaving,
                  showSubmitButton: _isStudent && !isReadOnly,
                  onSubmit:
                      _isStudent &&
                          !isReadOnly &&
                          !isPlaybackActive &&
                          !_isSubmitting
                      ? _onSubmit
                      : null,
                  onMetadataTap: isReadOnly || isPlaybackActive
                      ? null
                      : _showMetadataSheet,
                  onExportXml: () => _runExport(
                    export: () => const MusicXmlExportService().exportToDevice(
                      _editorState.score,
                    ),
                    successMessage: 'MusicXML saved',
                  ),
                  scoreIsEmpty: scoreIsEmpty,
                  onExportPdf: () => _runExport(
                    export: () => const PdfExportService().exportToDevice(
                      _editorState.score,
                    ),
                    successMessage: 'PDF saved',
                  ),
                  onScanPage: isPlaybackActive || isReadOnly
                      ? null
                      : _onScanPage,
                  onCheckNotation:
                      isPlaybackActive ||
                          isReadOnly ||
                          (scoreIsEmpty &&
                              _editorState.score.reviewHistory.isEmpty)
                      ? null
                      : _startNotationCheck,
                ),
                notationArea: notationArea,
                inspectorPanel: inspectorPanel,
                playbackControls: PlaybackControlsBar(
                  relativeTempo: _editorState.score.parts.any(
                    (p) => p.measures.any(
                      (m) => m.annotations.any((a) => a.tempo != null),
                    ),
                  ),
                  playbackService: _playback,
                  isLoading: _playbackPending,
                  initialMeasure: simultaneousParts
                      ? selectedMeasureIndex
                      : _editorState.score.parts
                                .take(selectedPartIndex)
                                .fold(
                                  0,
                                  (sum, part) => sum + part.measures.length,
                                ) +
                            selectedMeasureIndex,
                  measureCounts: simultaneousParts
                      ? null
                      : [
                          for (final part in _editorState.score.parts)
                            part.measures.length,
                        ],
                  isEmpty: !_editorState.hasPlaybackContent,
                  // The scrubber covers every staff in reading order.
                  measuresPerPart: simultaneousParts ? null : measuresPerPart,
                  totalMeasures: simultaneousParts
                      ? measuresPerPart
                      : _editorState.score.totalMeasures,
                  onPlay: () => unawaited(
                    _playFromMeasure(
                      _editorState.selectedMeasureIndex ?? 0,
                      partIndex: _editorState.selectedPartIndex ?? 0,
                    ),
                  ),
                  onResume: () {
                    _playback.resume(score: _editorState.score);
                  },
                  onPause: () {
                    _playback.pause();
                  },
                  onStop: () {
                    _stopVisualPlayback();
                    _playback.stop();
                  },
                  onTempoChanged: _setPlaybackTempo,
                  onSeek: (step) => unawaited(_seekPlayback(step)),
                ),
              );
            },
          ),
        ),
      ),
    );
    return Focus(
      autofocus: true,
      includeSemantics: false,
      onKeyEvent: _handleEditorKey,
      child: editor,
    );
  }
}

class _WorkspaceNavigation extends StatelessWidget {
  const _WorkspaceNavigation({
    required this.location,
    required this.currentPageIndex,
    required this.totalPages,
    required this.onPrevPage,
    required this.onNextPage,
    required this.onPageOverviewTap,
    required this.onHelp,
    required this.onCommands,
  });
  final String location;
  final int currentPageIndex, totalPages;
  final VoidCallback? onPrevPage, onNextPage;
  final VoidCallback onPageOverviewTap, onHelp, onCommands;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
    child: Row(
      children: [
        Expanded(
          child: Text(
            location,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 12,
              color: AppColors.textSecondary,
            ),
          ),
        ),
        _PageNav(
          currentPageIndex: currentPageIndex,
          totalPages: totalPages,
          onPrev: onPrevPage,
          onNext: onNextPage,
          onPageOverviewTap: onPageOverviewTap,
        ),
        IconButton(
          tooltip: 'Score commands (Ctrl/Cmd+K)',
          onPressed: onCommands,
          constraints: const BoxConstraints.tightFor(width: 44, height: 44),
          icon: const Icon(Icons.manage_search_rounded, size: 22),
          color: AppColors.accent,
        ),
        IconButton(
          tooltip: 'Editor guide',
          onPressed: onHelp,
          constraints: const BoxConstraints.tightFor(width: 44, height: 44),
          icon: const Icon(Icons.help_outline_rounded, size: 20),
          color: AppColors.textSecondary,
        ),
      ],
    ),
  );
}

class _EditorWorkspace extends StatelessWidget {
  const _EditorWorkspace({
    required this.isLandscape,
    required this.isDraggingNote,
    required this.dragGlobal,
    required this.trashZoneKey,
    required this.banner,
    this.checkBar,
    this.reviewPanel,
    this.reviewPanelFraction = .62,
    this.onReviewResize,
    required this.header,
    required this.navigation,
    required this.notationArea,
    required this.inspectorPanel,
    required this.playbackControls,
  });

  final bool isLandscape;
  final bool isDraggingNote;
  final Offset dragGlobal;
  final GlobalKey trashZoneKey;
  final _EditorBannerData? banner;
  final Widget? checkBar;
  final Widget? reviewPanel;
  final double reviewPanelFraction;
  final ValueChanged<double>? onReviewResize;
  final Widget header;
  final Widget navigation;
  final Widget notationArea;
  final Widget inspectorPanel;
  final Widget playbackControls;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        return Stack(
          children: [
            Column(
              children: [
                header,
                ?checkBar,
                navigation,
                Expanded(
                  child: reviewPanel != null
                      ? LayoutBuilder(
                          builder: (context, area) {
                            final wide =
                                area.maxWidth >= 720 ||
                                area.maxWidth > area.maxHeight;
                            final canvas = Padding(
                              padding: const EdgeInsets.all(8),
                              child: notationArea,
                            );
                            if (wide) {
                              return Row(
                                children: [
                                  Expanded(child: canvas),
                                  SizedBox(
                                    width: (area.maxWidth * .38).clamp(
                                      320.0,
                                      440.0,
                                    ),
                                    child: Padding(
                                      padding: const EdgeInsets.fromLTRB(
                                        0,
                                        8,
                                        8,
                                        8,
                                      ),
                                      child: reviewPanel,
                                    ),
                                  ),
                                ],
                              );
                            }
                            return Column(
                              children: [
                                Expanded(child: canvas),
                                Semantics(
                                  label: 'Resize review panel',
                                  onIncrease: () => onReviewResize?.call(
                                    (reviewPanelFraction + .1).clamp(.35, .8),
                                  ),
                                  onDecrease: () => onReviewResize?.call(
                                    (reviewPanelFraction - .1).clamp(.35, .8),
                                  ),
                                  child: GestureDetector(
                                    behavior: HitTestBehavior.opaque,
                                    onVerticalDragUpdate: (details) =>
                                        onReviewResize?.call(
                                          (reviewPanelFraction -
                                                  details.delta.dy /
                                                      area.maxHeight)
                                              .clamp(.35, .8),
                                        ),
                                    child: SizedBox(
                                      height: 20,
                                      child: Center(
                                        child: Container(
                                          width: 40,
                                          height: 4,
                                          decoration: BoxDecoration(
                                            color: AppColors.textSecondary,
                                            borderRadius: BorderRadius.circular(
                                              4,
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                                SizedBox(
                                  height: (area.maxHeight * reviewPanelFraction)
                                      .clamp(0.0, area.maxHeight - 20),
                                  child: Padding(
                                    padding: const EdgeInsets.fromLTRB(
                                      8,
                                      0,
                                      8,
                                      8,
                                    ),
                                    child: reviewPanel,
                                  ),
                                ),
                              ],
                            );
                          },
                        )
                      : isLandscape
                      ? Row(
                          children: [
                            Expanded(
                              child: Padding(
                                padding: const EdgeInsets.fromLTRB(
                                  12,
                                  0,
                                  6,
                                  12,
                                ),
                                child: notationArea,
                              ),
                            ),
                            SizedBox(
                              width: (constraints.maxWidth * 0.3).clamp(
                                320.0,
                                360.0,
                              ),
                              child: Padding(
                                padding: const EdgeInsets.fromLTRB(
                                  6,
                                  0,
                                  12,
                                  12,
                                ),
                                child: inspectorPanel,
                              ),
                            ),
                          ],
                        )
                      : LayoutBuilder(
                          builder: (context, area) {
                            final dockHeight = math.min(
                              272 +
                                  (MediaQuery.textScalerOf(context).scale(12) -
                                          12) *
                                      3,
                              area.maxHeight * .52,
                            );
                            return Column(
                              children: [
                                Expanded(
                                  child: Padding(
                                    padding: const EdgeInsets.fromLTRB(
                                      8,
                                      0,
                                      8,
                                      8,
                                    ),
                                    child: notationArea,
                                  ),
                                ),
                                SizedBox(
                                  height: dockHeight,
                                  child: Stack(
                                    children: [
                                      Positioned.fill(child: inspectorPanel),
                                      if (isDraggingNote)
                                        Positioned.fill(
                                          child: Center(
                                            child: _TrashZone(
                                              key: trashZoneKey,
                                              isHovered: () {
                                                final box =
                                                    trashZoneKey.currentContext
                                                            ?.findRenderObject()
                                                        as RenderBox?;
                                                return box != null &&
                                                    (box.localToGlobal(
                                                              Offset.zero,
                                                            ) &
                                                            box.size)
                                                        .contains(dragGlobal);
                                              }(),
                                            ),
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
                if (reviewPanel == null) playbackControls,
              ],
            ),
            Positioned(
              top: _EditorHeader.heightFor(context, constraints.maxWidth) + 8,
              left: 12,
              right: 12,
              child: IgnorePointer(
                ignoring: banner == null,
                child: AnimatedSlide(
                  duration: const Duration(milliseconds: 220),
                  curve: Curves.easeOutCubic,
                  offset: banner == null ? const Offset(0, -1.2) : Offset.zero,
                  child: AnimatedOpacity(
                    duration: const Duration(milliseconds: 180),
                    opacity: banner == null ? 0 : 1,
                    child: _TransientEditorBanner(
                      message: banner?.message ?? '',
                      backgroundColor:
                          banner?.backgroundColor ?? AppColors.surfaceAlt,
                      actionLabel: banner?.actionLabel,
                      onAction: banner?.onAction,
                    ),
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

// ---------------------------------------------------------------------------
// Header
// ---------------------------------------------------------------------------

class _TransientEditorBanner extends StatelessWidget {
  const _TransientEditorBanner({
    required this.message,
    required this.backgroundColor,
    this.actionLabel,
    this.onAction,
  });

  final String message;
  final Color backgroundColor;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      liveRegion: true,
      child: Material(
        color: Colors.transparent,
        child: Container(
          decoration: BoxDecoration(
            color: backgroundColor,
            borderRadius: BorderRadius.circular(12),
            boxShadow: const [
              BoxShadow(
                color: Color(0x40000000),
                blurRadius: 18,
                offset: Offset(0, 8),
              ),
            ],
            border: Border.all(color: Colors.white12),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  message,
                  style: const TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              if (actionLabel != null && onAction != null) ...[
                const SizedBox(width: 12),
                TextButton(
                  onPressed: onAction,
                  style: TextButton.styleFrom(
                    foregroundColor: AppColors.textPrimary,
                    minimumSize: const Size(0, 32),
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  child: Text(actionLabel!),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _EditorBannerData {
  const _EditorBannerData({
    required this.message,
    required this.backgroundColor,
    required this.duration,
    this.actionLabel,
    this.onAction,
  });

  const _EditorBannerData.success(
    String message, {
    Duration duration = const Duration(seconds: 2),
  }) : this(
         message: message,
         backgroundColor: AppColors.surfaceAlt,
         duration: duration,
       );

  const _EditorBannerData.error(
    String message, {
    Duration duration = const Duration(seconds: 2),
    String? actionLabel,
    VoidCallback? onAction,
  }) : this(
         message: message,
         backgroundColor: const Color(0xFFB91C1C),
         duration: duration,
         actionLabel: actionLabel,
         onAction: onAction,
       );

  final String message;
  final Color backgroundColor;
  final Duration duration;
  final String? actionLabel;
  final VoidCallback? onAction;
}

enum _HeaderMenuAction {
  scanPage,
  checkNotation,
  exportXml,
  exportPdf,
  transpose,
  staves,
  clearAllSymbols,
}

class _HeaderMenuItem extends StatelessWidget {
  const _HeaderMenuItem({
    required this.icon,
    required this.label,
    this.color = AppColors.textPrimary,
  });

  final IconData icon;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 16, color: color),
        const SizedBox(width: 10),
        Flexible(
          child: Text(label, style: TextStyle(color: color, fontSize: 13)),
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
    required this.scoreLabel,
    required this.isReviewMode,
    required this.reviewModeLabel,
    required this.canUndo,
    required this.canRedo,
    required this.onBack,
    required this.onUndo,
    required this.onRedo,
    required this.onSave,
    required this.onExportXml,
    required this.onExportPdf,
    required this.scoreIsEmpty,
    required this.onMetadataTap,
    this.showSubmitButton = false,
    this.onSubmit,
    this.onScanPage,
    this.onCheckNotation,
    this.onClearAllSymbols,
    this.onTranspose,
    this.onStaves,
    this.isSaving = false,
  });

  final String title;
  final bool hasUnsavedChanges;
  final int editCount;
  final ScoreLabel? scoreLabel;
  final bool isReviewMode;
  final String reviewModeLabel;
  final bool canUndo;
  final bool canRedo;
  final VoidCallback onBack;
  final VoidCallback onUndo;
  final VoidCallback onRedo;
  final VoidCallback? onSave;
  final VoidCallback onExportXml;
  final VoidCallback onExportPdf;
  final bool scoreIsEmpty;
  final VoidCallback? onMetadataTap;
  final bool showSubmitButton;
  final VoidCallback? onSubmit;
  final VoidCallback? onScanPage;
  final VoidCallback? onCheckNotation;
  final VoidCallback? onClearAllSymbols;
  final VoidCallback? onTranspose;
  final VoidCallback? onStaves;
  final bool isSaving;

  static final ButtonStyle _compactIconButtonStyle = IconButton.styleFrom(
    visualDensity: VisualDensity.compact,
    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
    minimumSize: const Size(44, 44),
    padding: const EdgeInsets.all(6),
  );

  static bool _isStacked(BuildContext context, double width) =>
      width < 500 ||
      (width < 700 && MediaQuery.textScalerOf(context).scale(14) > 21);

  static double heightFor(BuildContext context, double width) =>
      56 +
      (MediaQuery.textScalerOf(context).scale(15) - 15) +
      (MediaQuery.textScalerOf(context).scale(10) - 10) +
      (_isStacked(context, width) ? 52 : 0);

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final stacked = _isStacked(context, constraints.maxWidth);
        final reviewAction = Tooltip(
          message: 'Review & Correct',
          child: TextButton.icon(
            onPressed: onCheckNotation,
            icon: const Icon(Icons.fact_check_outlined, size: 18),
            label: const Text('Review', style: TextStyle(fontSize: 12)),
            style: TextButton.styleFrom(
              minimumSize: const Size(44, 44),
              padding: const EdgeInsets.symmetric(horizontal: 8),
            ),
          ),
        );
        final actions = <Widget>[
          if (stacked)
            Expanded(
              child: Align(
                alignment: Alignment.centerLeft,
                child: reviewAction,
              ),
            )
          else
            reviewAction,
          IconButton(
            onPressed: canUndo ? onUndo : null,
            icon: const Icon(Icons.undo_rounded, size: 18),
            color: AppColors.textPrimary,
            tooltip: 'Undo',
            style: _compactIconButtonStyle,
          ),
          IconButton(
            onPressed: canRedo ? onRedo : null,
            icon: const Icon(Icons.redo_rounded, size: 18),
            color: AppColors.textPrimary,
            tooltip: 'Redo',
            style: _compactIconButtonStyle,
          ),
          if (showSubmitButton)
            IconButton(
              onPressed: onSubmit,
              icon: const Icon(Icons.upload_rounded, size: 18),
              color: AppColors.accent,
              tooltip: 'Submit',
              style: _compactIconButtonStyle,
            ),
          if (onSave != null)
            FilledButton.icon(
              onPressed: isSaving ? null : onSave,
              icon: isSaving
                  ? const SizedBox.square(
                      dimension: 15,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.save_rounded, size: 15),
              label: Text(
                isSaving ? 'Saving…' : 'Save',
                style: const TextStyle(fontSize: 13),
              ),
              style: FilledButton.styleFrom(
                minimumSize: const Size(76, 44),
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                padding: const EdgeInsets.symmetric(horizontal: 12),
              ),
            ),
        ];
        return Container(
          height: heightFor(context, constraints.maxWidth),
          decoration: const BoxDecoration(
            color: AppColors.surface,
            border: Border(bottom: BorderSide(color: AppColors.border)),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 6),
          child: Column(
            children: [
              Expanded(
                child: Row(
                  children: [
                    IconButton(
                      onPressed: onBack,
                      icon: const Icon(
                        Icons.arrow_back_ios_new_rounded,
                        size: 16,
                      ),
                      color: AppColors.textPrimary,
                      tooltip: 'Back',
                      style: _compactIconButtonStyle,
                    ),
                    const SizedBox(width: 2),
                    Expanded(
                      child: Tooltip(
                        message: title,
                        child: Semantics(
                          label: 'Score details: $title',
                          value: hasUnsavedChanges ? 'Unsaved changes' : null,
                          button: onMetadataTap != null,
                          onTap: onMetadataTap,
                          excludeSemantics: true,
                          child: GestureDetector(
                            onTap: onMetadataTap,
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
                                      const SizedBox(width: 5),
                                      Flexible(
                                        child: Container(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 5,
                                            vertical: 2,
                                          ),
                                          decoration: BoxDecoration(
                                            color: AppColors.accent.withValues(
                                              alpha: 0.18,
                                            ),
                                            borderRadius: BorderRadius.circular(
                                              4,
                                            ),
                                          ),
                                          child: const Text(
                                            'Unsaved',
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: TextStyle(
                                              color: AppColors.accent,
                                              fontSize: 10,
                                              fontWeight: FontWeight.w600,
                                            ),
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
                                        [
                                          isReviewMode
                                              ? reviewModeLabel
                                              : 'Score Editor',
                                          if (scoreLabel != null)
                                            scoreLabel!.displayName,
                                        ].join(' · '),
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(
                                          color: AppColors.textSecondary,
                                          fontSize: 10,
                                        ),
                                      ),
                                    ),
                                    if (editCount > 0) ...[
                                      const SizedBox(width: 6),
                                      Flexible(
                                        child: Text(
                                          '· $editCount ${editCount == 1 ? 'edit' : 'edits'}',
                                          overflow: TextOverflow.ellipsis,
                                          style: const TextStyle(
                                            color: AppColors.textSecondary,
                                            fontSize: 10,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                    if (!stacked) ...actions,
                    const SizedBox(width: 2),
                    PopupMenuButton<_HeaderMenuAction>(
                      onSelected: (action) {
                        if (action == _HeaderMenuAction.scanPage) {
                          onScanPage?.call();
                        } else if (action == _HeaderMenuAction.checkNotation) {
                          onCheckNotation?.call();
                        } else if (action == _HeaderMenuAction.exportXml) {
                          onExportXml();
                        } else if (action == _HeaderMenuAction.exportPdf) {
                          onExportPdf();
                        } else if (action == _HeaderMenuAction.transpose) {
                          onTranspose?.call();
                        } else if (action == _HeaderMenuAction.staves) {
                          onStaves?.call();
                        } else if (action ==
                            _HeaderMenuAction.clearAllSymbols) {
                          onClearAllSymbols?.call();
                        }
                      },
                      tooltip: 'More',
                      icon: const Icon(Icons.more_vert_rounded, size: 18),
                      style: _compactIconButtonStyle,
                      color: AppColors.surface,
                      itemBuilder: (_) => [
                        PopupMenuItem(
                          value: _HeaderMenuAction.scanPage,
                          enabled: onScanPage != null,
                          child: const _HeaderMenuItem(
                            icon: Icons.add_photo_alternate_rounded,
                            label: 'Scan New Page',
                          ),
                        ),
                        PopupMenuItem(
                          value: _HeaderMenuAction.checkNotation,
                          enabled: onCheckNotation != null,
                          child: const _HeaderMenuItem(
                            icon: Icons.fact_check_rounded,
                            label: 'Check Notation',
                          ),
                        ),
                        const PopupMenuItem(
                          value: _HeaderMenuAction.exportXml,
                          child: _HeaderMenuItem(
                            icon: Icons.download_rounded,
                            label: 'Export MusicXML…',
                          ),
                        ),
                        PopupMenuItem(
                          value: _HeaderMenuAction.exportPdf,
                          enabled: !scoreIsEmpty,
                          child: _HeaderMenuItem(
                            icon: Icons.picture_as_pdf_rounded,
                            label: 'Export PDF…',
                          ),
                        ),
                        if (!isReviewMode) ...[
                          PopupMenuItem(
                            value: _HeaderMenuAction.transpose,
                            enabled: onTranspose != null,
                            child: const _HeaderMenuItem(
                              icon: Icons.swap_vert_rounded,
                              label: 'Transpose…',
                            ),
                          ),
                          PopupMenuItem(
                            value: _HeaderMenuAction.staves,
                            enabled: onStaves != null,
                            child: const _HeaderMenuItem(
                              icon: Icons.queue_music_rounded,
                              label: 'Staves and instruments…',
                            ),
                          ),
                          const PopupMenuDivider(),
                          PopupMenuItem(
                            value: _HeaderMenuAction.clearAllSymbols,
                            enabled: onClearAllSymbols != null,
                            child: _HeaderMenuItem(
                              icon: Icons.delete_sweep_rounded,
                              label: 'Clear all symbols…',
                              color: onClearAllSymbols != null
                                  ? AppColors.error
                                  : AppColors.textSecondary,
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(width: 2),
                  ],
                ),
              ),
              if (stacked) SizedBox(height: 52, child: Row(children: actions)),
            ],
          ),
        );
      },
    );
  }
}

// ---------------------------------------------------------------------------
// Notation area — A4-like canvas with InteractiveViewer for pan/zoom
// ---------------------------------------------------------------------------

/// Leave space below the paper for the floating zoom controls.
const double _kFloatingControlsReserve = 54.0;

class _NotationArea extends StatefulWidget {
  const _NotationArea({
    super.key,
    this.fitInsets = EdgeInsets.zero,
    this.issueMarks = const {},
    this.reviewFocusMeasure,
    this.reviewFocusPart = 0,
    required this.editorState,
    required this.layoutPolicy,
    required this.pageFirstMeasure,
    required this.pageMeasureCount,
    required this.insertMode,
    required this.insertSymbolType,
    required this.playbackPosition,
    required this.playheadEpoch,
    required this.playheadSymbolIndex,
    required this.playheadNoteDurationMs,
    required this.showPlaybackSymbolHighlight,
    required this.isDraggingNote,
    required this.dragGlobal,
    required this.trashZoneKey,
    this.showTrashZone = true,
    required this.isPlaybackActive,
    required this.isReadOnly,
    this.suppressCanvasDragGhost = false,
    this.onAnnotationTap,
    required this.onMeasureTap,
    required this.onSymbolTap,
    required this.onInsertTap,
    required this.onDragStarted,
    required this.onDragGlobalUpdate,
    required this.onDragCompleted,
    required this.onDragCancelled,
    required this.onExternalDrop,
  });

  /// Strips of the viewport covered by floating UI; fit-to-screen keeps the
  /// page out of them.
  final EdgeInsets fitInsets;
  final int? reviewFocusMeasure;
  final int reviewFocusPart;
  final EditorState editorState;
  final EditorLayoutPolicy layoutPolicy;
  final int pageFirstMeasure;
  final int pageMeasureCount;
  final bool insertMode;
  final PaletteSymbolType? insertSymbolType;
  final PlaybackPosition playbackPosition;
  final int playheadEpoch;
  final int playheadSymbolIndex;
  final int playheadNoteDurationMs;

  /// Notation-check highlights keyed with absolute measure indices.
  final Map<String, Color> issueMarks;
  final bool showPlaybackSymbolHighlight;
  final bool isDraggingNote;
  final Offset dragGlobal;
  final GlobalKey trashZoneKey;
  final bool showTrashZone;
  final bool isPlaybackActive;
  final bool isReadOnly;
  final bool suppressCanvasDragGhost;
  final void Function(int, int, int)? onAnnotationTap;
  final ValueChanged<NotationMeasureTarget?> onMeasureTap;
  final ValueChanged<NotationSymbolTarget?> onSymbolTap;
  final ValueChanged<NotationInsertTarget?> onInsertTap;
  final void Function(NotationSymbolTarget symbol) onDragStarted;
  final void Function(Offset global) onDragGlobalUpdate;
  final void Function(NotationSymbolReorder? reorder, Offset globalEndPosition)
  onDragCompleted;
  final VoidCallback onDragCancelled;
  final void Function(NotationInsertTarget, Object) onExternalDrop;

  @override
  State<_NotationArea> createState() => _NotationAreaState();
}

class _NotationAreaState extends State<_NotationArea>
    with SingleTickerProviderStateMixin {
  final _transformController = TransformationController();
  late final AnimationController _playheadController;
  Size? _viewportSize;
  Size? _contentSize;
  bool _fittedOnce = false;

  @override
  void initState() {
    super.initState();
    _playheadController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 1),
    );
  }

  @override
  void dispose() {
    _transformController.dispose();
    _playheadController.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(_NotationArea oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.reviewFocusMeasure == null &&
        oldWidget.playbackPosition.isNone &&
        !widget.playbackPosition.isNone) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _fitToScreen();
      });
    }
    if (oldWidget.pageFirstMeasure != widget.pageFirstMeasure &&
        !widget.isPlaybackActive) {
      _fittedOnce = false;
    }
    if (oldWidget.playheadEpoch != widget.playheadEpoch &&
        widget.playheadNoteDurationMs > 0) {
      _playheadController.duration = Duration(
        milliseconds: widget.playheadNoteDurationMs,
      );
      _playheadController.forward(from: 0.0);
    } else if (!widget.isPlaybackActive && oldWidget.isPlaybackActive) {
      _playheadController.stop();
      _playheadController.value = 0;
    }
  }

  // Converts an absolute measure index to page-relative; returns null when
  // the index is outside the current page so the viewer shows no highlight.
  /// [key] ('part:measure[:symbol]') with a page-relative measure, or null
  /// when the measure is not on this page.
  String? _relMark(String key) {
    final parts = key.split(':');
    final rel = _rel(int.parse(parts[1]));
    if (rel == null) return null;
    return [parts[0], rel, ...parts.skip(2)].join(':');
  }

  int? _rel(int? abs) {
    if (abs == null) return null;
    final rel = abs - widget.pageFirstMeasure;
    if (rel < 0 || rel >= widget.pageMeasureCount) return null;
    return rel;
  }

  void _fitToScreen() {
    final viewport = _viewportSize;
    final content = _contentSize;
    if (viewport == null || content == null) return;
    if (viewport.width <= 0 || viewport.height <= 0) return;

    final freeHeight = viewport.height - widget.fitInsets.vertical;
    if (freeHeight <= 0) return;

    final scale =
        (math.min(viewport.width / content.width, freeHeight / content.height) *
                0.90)
            .clamp(.15, 5.0);

    final tx = (viewport.width - content.width * scale) / 2;
    final ty =
        widget.fitInsets.top +
        math.max(8.0, (freeHeight - content.height * scale) / 2);

    _transformController.value = Matrix4.identity()
      ..setEntry(0, 0, scale)
      ..setEntry(1, 1, scale)
      ..setEntry(0, 3, tx)
      ..setEntry(1, 3, ty);
  }

  void focusMeasure(int partIndex, int absoluteMeasure) {
    final viewport = _viewportSize;
    if (viewport == null || viewport.isEmpty) return;
    final relative = absoluteMeasure - widget.pageFirstMeasure;
    if (relative < 0 || relative >= widget.pageMeasureCount) return;
    final policy = widget.layoutPolicy;
    final row = relative ~/ policy.measuresPerRow;
    final column = relative % policy.measuresPerRow;
    final x =
        policy.horizontalPadding +
        policy.rowPrefixWidth +
        column * policy.minMeasureWidth;
    final y =
        policy.verticalPadding +
        (row * widget.editorState.score.parts.length + partIndex) *
            policy.rowHeight;
    final freeHeight = math.max(
      20.0,
      viewport.height - widget.fitInsets.vertical,
    );
    final scale = math
        .min(
          viewport.width / (policy.minMeasureWidth * 1.7),
          freeHeight / (policy.rowHeight * 1.3),
        )
        .clamp(.15, 2.5);
    _transformController.value = Matrix4.identity()
      ..setEntry(0, 0, scale)
      ..setEntry(1, 1, scale)
      ..setEntry(
        0,
        3,
        viewport.width / 2 - (x + policy.minMeasureWidth / 2) * scale,
      )
      ..setEntry(
        1,
        3,
        widget.fitInsets.top +
            freeHeight / 2 -
            (y + policy.rowHeight / 2) * scale,
      );
  }

  void _zoomIn() => _applyScaleDelta(1.15);
  void _zoomOut() => _applyScaleDelta(1.0 / 1.15);

  void _applyScaleDelta(double delta) {
    final viewport = _viewportSize;
    if (viewport == null) return;
    final cx = viewport.width / 2;
    final cy = viewport.height / 2;

    final current = _transformController.value;
    final currentScale = _scale;
    final translation = current.getTranslation();

    // Scale around the viewport centre.
    final newScale = (currentScale * delta).clamp(.15, 5.0);
    final effectiveDelta = newScale / currentScale;
    final newTx = cx + effectiveDelta * (translation.x - cx);
    final newTy = cy + effectiveDelta * (translation.y - cy);

    _transformController.value = Matrix4.identity()
      ..setEntry(0, 0, newScale)
      ..setEntry(1, 1, newScale)
      ..setEntry(0, 3, newTx)
      ..setEntry(1, 3, newTy);
  }

  // The page is scaled evenly in x and y. getMaxScaleOnAxis also looks at the
  // untouched z axis, so it reads 1.0 for any zoom below 100 %.
  double get _scale => _transformController.value.entry(0, 0);

  Size _computeContentSize() {
    final score = widget.editorState.score;
    if (score.parts.isEmpty) {
      return Size(widget.layoutPolicy.pageWidth, 400);
    }

    final allMeasures = score.parts[0].measures;
    final start = widget.pageFirstMeasure.clamp(0, allMeasures.length);
    final end = (start + widget.pageMeasureCount).clamp(
      start,
      allMeasures.length,
    );
    final pageMeasures = allMeasures.sublist(start, end);

    const calc = NotationLayoutCalculator();
    final layout = calc.calculate(
      measures: pageMeasures,
      measuresPerRow: widget.layoutPolicy.measuresPerRow,
      minMeasureWidth: widget.layoutPolicy.minMeasureWidth,
      rowHeight: widget.layoutPolicy.rowHeight,
      padding: EdgeInsets.symmetric(
        horizontal: widget.layoutPolicy.horizontalPadding,
        vertical: widget.layoutPolicy.verticalPadding,
      ),
      rowPrefixWidth: widget.layoutPolicy.rowPrefixWidth,
      partCount: score.parts.length,
    );
    return Size(widget.layoutPolicy.pageWidth, layout.size.height);
  }

  ScoreNotationViewer _buildScoreNotationViewer() {
    final pos = widget.playbackPosition;
    final playheadPartIndex = pos.isNone ? null : pos.partIndex;
    final playheadMeasureIndex = pos.isNone ? null : _rel(pos.measureIndex);
    final canEdit = !widget.isPlaybackActive && !widget.isReadOnly;

    // AnimationController runs 0→1 over the current note's scaled duration.
    // The painter uses T + the symbol index to interpolate X directly from
    // slot geometry — no accumulated base-ms needed.
    final playbackT = widget.isPlaybackActive ? _playheadController.value : 0.0;

    return ScoreNotationViewer(
      score: widget.editorState.score,
      selectedPartIndex: widget.editorState.selectedPartIndex ?? 0,
      measuresPerRow: widget.layoutPolicy.measuresPerRow,
      minMeasureWidth: widget.layoutPolicy.minMeasureWidth,
      rowHeight: widget.layoutPolicy.rowHeight,
      padding: EdgeInsets.symmetric(
        horizontal: widget.layoutPolicy.horizontalPadding,
        vertical: widget.layoutPolicy.verticalPadding,
      ),
      backgroundColor: Colors.white,
      firstMeasureIndex: widget.pageFirstMeasure,
      pageMeasureCount: widget.pageMeasureCount,
      selectedMeasureIndex: _rel(widget.editorState.selectedMeasureIndex),
      selectedSymbolIndex: widget.editorState.selectedSymbolIndex,
      rangeSymbols: {
        if (widget.editorState.hasRange)
          for (final p in widget.editorState.selectionPositions)
            if (_rel(p.measure) case final measure?) (measure, p.symbol),
      },
      playbackPartIndex: widget.playbackPosition.isNone
          ? null
          : widget.playbackPosition.partIndex,
      playbackMeasureIndex: widget.playbackPosition.isNone
          ? null
          : _rel(widget.playbackPosition.measureIndex),
      playbackSymbolIndex: widget.playbackPosition.isNone
          ? null
          : widget.playbackPosition.symbolIndex,
      playbackNextPartIndex: widget.playbackPosition.hasNext
          ? widget.playbackPosition.nextPartIndex
          : null,
      playbackNextMeasureIndex: widget.playbackPosition.hasNext
          ? _rel(widget.playbackPosition.nextMeasureIndex)
          : null,
      playbackNextSymbolIndex: widget.playbackPosition.hasNext
          ? widget.playbackPosition.nextSymbolIndex
          : null,
      playheadPartIndex: playheadPartIndex,
      playheadMeasureIndex: playheadMeasureIndex,
      playheadSymbolIndex: pos.isNone ? null : widget.playheadSymbolIndex,
      playbackProgress: playbackT,
      showPlaybackSymbolHighlight: widget.showPlaybackSymbolHighlight,
      issueMarks: {
        for (final MapEntry(:key, :value) in widget.issueMarks.entries)
          ?_relMark(key): value,
      },
      insertMode: widget.insertMode,
      canAcceptExternalDrop: canEdit ? (data) => data is PaletteDragData : null,
      externalPreviewResolver: _previewGlyphForDragData,
      onExternalDrop: !canEdit
          ? null
          : (target, data) => widget.onExternalDrop(
              NotationInsertTarget(
                partIndex: target.partIndex,
                measureIndex: target.measureIndex + widget.pageFirstMeasure,
                insertIndex: target.insertIndex,
                indicatorX: target.indicatorX,
                step: target.step,
                octave: target.octave,
              ),
              data,
            ),
      onAnnotationTap:
          !widget.insertMode && canEdit && widget.onAnnotationTap != null
          ? (p, m, i) =>
                widget.onAnnotationTap!(p, m + widget.pageFirstMeasure, i)
          : null,
      onMeasureTap: !widget.insertMode && !widget.isPlaybackActive
          ? widget.onMeasureTap
          : null,
      onSymbolTap: (widget.insertMode || !canEdit)
          ? null
          : (target) => widget.onSymbolTap(
              target == null
                  ? null
                  : NotationSymbolTarget(
                      partIndex: target.partIndex,
                      measureIndex:
                          target.measureIndex + widget.pageFirstMeasure,
                      symbolIndex: target.symbolIndex,
                      center: target.center,
                      hitRect: target.hitRect,
                    ),
            ),
      onInsertTap: (widget.insertMode && canEdit)
          ? (target) => widget.onInsertTap(
              target == null
                  ? null
                  : NotationInsertTarget(
                      partIndex: target.partIndex,
                      measureIndex:
                          target.measureIndex + widget.pageFirstMeasure,
                      insertIndex: target.insertIndex,
                      indicatorX: target.indicatorX,
                      step: target.step,
                      octave: target.octave,
                    ),
            )
          : null,
      onDragStarted: (widget.insertMode || !canEdit)
          ? null
          : (target) => widget.onDragStarted(
              NotationSymbolTarget(
                partIndex: target.partIndex,
                measureIndex: target.measureIndex + widget.pageFirstMeasure,
                symbolIndex: target.symbolIndex,
                center: target.center,
                hitRect: target.hitRect,
              ),
            ),
      onDragGlobalUpdate: canEdit ? widget.onDragGlobalUpdate : null,
      onDragCompleted: canEdit
          ? (reorder, global) => widget.onDragCompleted(
              reorder == null
                  ? null
                  : NotationSymbolReorder(
                      fromPartIndex: reorder.fromPartIndex,
                      fromMeasureIndex:
                          reorder.fromMeasureIndex + widget.pageFirstMeasure,
                      fromSymbolIndex: reorder.fromSymbolIndex,
                      toPartIndex: reorder.toPartIndex,
                      toMeasureIndex:
                          reorder.toMeasureIndex + widget.pageFirstMeasure,
                      toSymbolIndex: reorder.toSymbolIndex,
                    ),
              global,
            )
          : null,
      onDragCancelled: canEdit ? widget.onDragCancelled : null,
      suppressCanvasDragGhost: widget.suppressCanvasDragGhost,
    );
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
                    final viewportChanged =
                        _viewportSize != constraints.biggest;
                    _viewportSize = constraints.biggest;
                    _contentSize = _computeContentSize();
                    if (viewportChanged && !widget.isPlaybackActive) {
                      WidgetsBinding.instance.addPostFrameCallback((_) {
                        if (!mounted) return;
                        if (widget.reviewFocusMeasure != null) {
                          focusMeasure(
                            widget.reviewFocusPart,
                            widget.reviewFocusMeasure!,
                          );
                        } else {
                          _fitToScreen();
                        }
                      });
                    }

                    if (!_fittedOnce &&
                        _viewportSize!.shortestSide > 0 &&
                        _contentSize!.width > 0) {
                      _fittedOnce = true;
                      WidgetsBinding.instance.addPostFrameCallback((_) {
                        if (!mounted) return;
                        if (widget.reviewFocusMeasure != null) {
                          focusMeasure(
                            widget.reviewFocusPart,
                            widget.reviewFocusMeasure!,
                          );
                        } else {
                          _fitToScreen();
                        }
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
                          child: AnimatedSwitcher(
                            duration: const Duration(milliseconds: 250),
                            transitionBuilder: (child, animation) =>
                                FadeTransition(
                                  opacity: animation,
                                  child: child,
                                ),
                            child: Container(
                              key: ValueKey(widget.pageFirstMeasure),
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
                              child: AnimatedBuilder(
                                animation: _playheadController,
                                builder: (context, _) =>
                                    _buildScoreNotationViewer(),
                              ),
                            ),
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),

              // Trash zone — only shown here in landscape; portrait renders it
              // in the outer Stack so it overlays the inspector bar.
              if (widget.showTrashZone && widget.isDraggingNote)
                Positioned(
                  bottom: 12,
                  left: 0,
                  right: 0,
                  child: Center(
                    child: _TrashZone(
                      key: widget.trashZoneKey,
                      isHovered: () {
                        if (widget.dragGlobal == Offset.zero) return false;
                        final box =
                            widget.trashZoneKey.currentContext
                                    ?.findRenderObject()
                                as RenderBox?;
                        if (box == null) return false;
                        return (box.localToGlobal(Offset.zero) & box.size)
                            .contains(widget.dragGlobal);
                      }(),
                    ),
                  ),
                ),

              // Floating controls
              Positioned(
                left: 8,
                right: 8,
                bottom: 8,
                // Only the zoom readout follows pan and zoom; rebuilding the
                // page on every frame would repaint the whole score.
                child: ValueListenableBuilder<Matrix4>(
                  valueListenable: _transformController,
                  builder: (context, transform, _) => _FloatingControls(
                    zoomPercent: (transform.entry(0, 0) * 100).round(),
                    onZoomIn: transform.entry(0, 0) >= 5 ? null : _zoomIn,
                    onZoomOut: transform.entry(0, 0) <= .15 ? null : _zoomOut,
                    onFitToScreen: _fitToScreen,
                    onFocusBar: widget.editorState.hasMeasureContext
                        ? () => focusMeasure(
                            widget.editorState.selectedPartIndex!,
                            widget.editorState.selectedMeasureIndex!,
                          )
                        : null,
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  NotationPreviewGlyph? _previewGlyphForDragData(Object data) {
    if (data is! PaletteDragData) return null;
    return switch (data.type) {
      PaletteSymbolType.wholeNote => NotationPreviewGlyph.wholeNote,
      PaletteSymbolType.halfNote => NotationPreviewGlyph.halfNote,
      PaletteSymbolType.quarterNote => NotationPreviewGlyph.quarterNote,
      PaletteSymbolType.eighthNote => NotationPreviewGlyph.eighthNote,
      PaletteSymbolType.sixteenthNote => NotationPreviewGlyph.sixteenthNote,
      PaletteSymbolType.wholeRest => NotationPreviewGlyph.wholeRest,
      PaletteSymbolType.halfRest => NotationPreviewGlyph.halfRest,
      PaletteSymbolType.quarterRest => NotationPreviewGlyph.quarterRest,
      PaletteSymbolType.eighthRest => NotationPreviewGlyph.eighthRest,
      PaletteSymbolType.sixteenthRest => NotationPreviewGlyph.sixteenthRest,
    };
  }
}

class _FloatingControls extends StatelessWidget {
  const _FloatingControls({
    required this.zoomPercent,
    required this.onZoomIn,
    required this.onZoomOut,
    required this.onFitToScreen,
    required this.onFocusBar,
  });

  final int zoomPercent;
  final VoidCallback? onZoomIn;
  final VoidCallback? onZoomOut;
  final VoidCallback onFitToScreen;
  final VoidCallback? onFocusBar;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      alignment: WrapAlignment.end,
      spacing: 6,
      runSpacing: 6,
      children: [
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
              _ZoomBtn(
                icon: Icons.remove_rounded,
                tooltip: 'Zoom out',
                onPressed: onZoomOut,
              ),
              Flexible(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 6),
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      '$zoomPercent%',
                      style: const TextStyle(
                        fontSize: 11,
                        color: AppColors.textSecondary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
              ),
              _ZoomBtn(
                icon: Icons.add_rounded,
                tooltip: 'Zoom in',
                onPressed: onZoomIn,
              ),
              const SizedBox(width: 2),
              _ZoomBtn(
                icon: Icons.fit_screen_rounded,
                tooltip: 'Fit page',
                onPressed: onFitToScreen,
              ),
              _ZoomBtn(
                icon: Icons.center_focus_strong_rounded,
                tooltip: 'Focus selected bar',
                onPressed: onFocusBar,
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _ZoomBtn extends StatelessWidget {
  const _ZoomBtn({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 44,
      height: 44,
      child: IconButton(
        onPressed: onPressed,
        tooltip: tooltip,
        icon: Icon(icon, size: 16),
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

class _ReviewPanel extends StatelessWidget {
  const _ReviewPanel({
    required this.isLandscape,
    required this.isPlaybackActive,
    required this.selectedMeasureNumber,
    required this.currentComment,
    required this.currentPageIndex,
    required this.totalPages,
    required this.canEditComment,
    required this.onPrevPage,
    required this.onNextPage,
    required this.onPageOverviewTap,
    required this.onEditComment,
    required this.onExportProject,
  });

  final bool isLandscape;
  final bool isPlaybackActive;
  final int? selectedMeasureNumber;
  final String? currentComment;
  final int currentPageIndex;
  final int totalPages;
  final bool canEditComment;
  final VoidCallback? onPrevPage;
  final VoidCallback? onNextPage;
  final VoidCallback onPageOverviewTap;
  final VoidCallback? onEditComment;
  final VoidCallback? onExportProject;

  @override
  Widget build(BuildContext context) {
    final comment = currentComment?.trim();
    final hasComment = comment != null && comment.isNotEmpty;
    final measureLabel = selectedMeasureNumber == null
        ? 'No measure selected'
        : 'Measure $selectedMeasureNumber';
    final pageNav = _PageNav(
      currentPageIndex: currentPageIndex,
      totalPages: totalPages,
      onPrev: onPrevPage,
      onNext: onNextPage,
      onPageOverviewTap: onPageOverviewTap,
    );

    if (!isLandscape) {
      return Stack(
        children: [
          Positioned(
            top: 8,
            left: 8,
            right: 8,
            child: _ReviewMeasureBar(
              measureLabel: measureLabel,
              pageNav: pageNav,
              compact: true,
            ),
          ),
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: Container(
              height: 56,
              padding: const EdgeInsets.symmetric(horizontal: 10),
              decoration: const BoxDecoration(
                color: AppColors.surface,
                border: Border(top: BorderSide(color: AppColors.border)),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      hasComment ? comment : 'No comment',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 12,
                      ),
                    ),
                  ),
                  if (canEditComment)
                    IconButton(
                      onPressed: onEditComment,
                      icon: Icon(
                        hasComment
                            ? Icons.mode_comment_rounded
                            : Icons.add_comment_rounded,
                        size: 20,
                      ),
                      color: onEditComment == null
                          ? AppColors.textSecondary.withValues(alpha: 0.35)
                          : AppColors.accent,
                      tooltip: isPlaybackActive
                          ? 'Playback active'
                          : hasComment
                          ? 'Edit Comment'
                          : 'Add Comment',
                    ),
                  if (onExportProject != null)
                    IconButton(
                      onPressed: onExportProject,
                      icon: const Icon(Icons.ios_share_rounded, size: 20),
                      color: AppColors.accent,
                      tooltip: 'Export Reviewed Score',
                    ),
                ],
              ),
            ),
          ),
        ],
      );
    }

    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _ReviewMeasureBar(measureLabel: measureLabel, pageNav: pageNav),
          const SizedBox(height: 16),
          const Text(
            'COMMENT',
            style: TextStyle(
              color: AppColors.textSecondary,
              fontSize: 10,
              letterSpacing: 1.0,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: SingleChildScrollView(
              child: Text(
                hasComment ? comment : 'No comment',
                style: TextStyle(
                  color: hasComment
                      ? AppColors.textPrimary
                      : AppColors.textSecondary,
                  fontSize: 13,
                  height: 1.45,
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),
          if (canEditComment)
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: onEditComment,
                icon: Icon(
                  hasComment
                      ? Icons.mode_comment_rounded
                      : Icons.add_comment_rounded,
                  size: 17,
                ),
                label: Text(
                  isPlaybackActive
                      ? 'Playback Active'
                      : hasComment
                      ? 'Edit Comment'
                      : 'Add Comment',
                ),
              ),
            ),
          if (onExportProject != null) ...[
            if (canEditComment) const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: onExportProject,
                icon: const Icon(Icons.ios_share_rounded, size: 17),
                label: const Text('Export Reviewed Score'),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _ReviewMeasureBar extends StatelessWidget {
  const _ReviewMeasureBar({
    required this.measureLabel,
    required this.pageNav,
    this.compact = false,
  });

  final String measureLabel;
  final Widget pageNav;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 10 : 0,
        vertical: compact ? 6 : 0,
      ),
      decoration: compact
          ? BoxDecoration(
              color: AppColors.surfaceAlt,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: AppColors.border),
            )
          : null,
      child: Row(
        children: [
          Expanded(
            child: Text(
              measureLabel,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: AppColors.textPrimary,
                fontSize: 14,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          pageNav,
        ],
      ),
    );
  }
}

class _MeasureCommentDialog extends StatefulWidget {
  const _MeasureCommentDialog({
    required this.measureNumber,
    required this.initialComment,
  });

  final int measureNumber;
  final String initialComment;

  @override
  State<_MeasureCommentDialog> createState() => _MeasureCommentDialogState();
}

class _MeasureCommentDialogState extends State<_MeasureCommentDialog> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialComment);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: AppColors.surface,
      title: Text(
        'Measure ${widget.measureNumber} Comment',
        style: const TextStyle(color: AppColors.textPrimary),
      ),
      content: TextField(
        controller: _controller,
        autofocus: true,
        minLines: 3,
        maxLines: 6,
        style: const TextStyle(color: AppColors.textPrimary),
        decoration: const InputDecoration(
          hintText: 'Teacher comment',
          hintStyle: TextStyle(color: AppColors.textSecondary),
          enabledBorder: UnderlineInputBorder(
            borderSide: BorderSide(color: AppColors.border),
          ),
          focusedBorder: UnderlineInputBorder(
            borderSide: BorderSide(color: AppColors.accent),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(null),
          child: const Text(
            'Cancel',
            style: TextStyle(color: AppColors.textSecondary),
          ),
        ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(_controller.text.trim()),
          child: const Text('Save', style: TextStyle(color: AppColors.accent)),
        ),
      ],
    );
  }
}

class _InspectorPanel extends StatefulWidget {
  const _InspectorPanel({
    required this.isLandscape,
    required this.insertMode,
    required this.insertSymbolType,
    required this.inputVoice,
    required this.onVoiceSelected,
    required this.onToggleInsertMode,
    required this.onPaletteTypeTap,
    required this.onPreviousSymbol,
    required this.onNextSymbol,
    required this.isPlaybackActive,
    required this.selected,
    required this.hasSelection,
    required this.hasMeasureContext,
    required this.selectedMeasureNumber,
    required this.onMoveUp,
    required this.onMoveDown,
    required this.onOctaveUp,
    required this.onOctaveDown,
    required this.onConvertSymbol,
    required this.onAddThird,
    required this.onTie,
    required this.onSlur,
    required this.onTriplet,
    required this.onLyrics,
    required this.onAnnotations,
    required this.rangeCount,
    required this.markStates,
    required this.onToggleMark,
    required this.dynamicMark,
    required this.onDynamic,
    required this.onHairpin,
    required this.extendMode,
    required this.onToggleExtend,
    required this.onSelectBar,
    required this.onCopy,
    required this.onCut,
    required this.onPaste,
    required this.onWhole,
    required this.onHalf,
    required this.onQuarter,
    required this.onEighth,
    required this.onSixteenth,
    required this.onSetAccidental,
    required this.currentMeasureClef,
    required this.currentTimeSignature,
    required this.onSetTimeSignature,
    required this.barSignOn,
    required this.onBarSign,
    required this.onSetClef,
    required this.onMoveToPrev,
    required this.onMoveToNext,
    required this.onAddMeasure,
    required this.onStaves,
    required this.onAddPage,
    required this.canDeleteMeasure,
    required this.onDeleteMeasure,
    required this.onDeleteSymbol,
    required this.onToggleDot,
    required this.allowedDurations,
    required this.canToggleDot,
    required this.onBeams,
  });

  final bool isLandscape;
  final bool insertMode;
  final PaletteSymbolType? insertSymbolType;

  /// The voice new notes go into (1–4).
  final int inputVoice;
  final ValueChanged<int> onVoiceSelected;
  final VoidCallback onToggleInsertMode;
  final ValueChanged<PaletteSymbolType> onPaletteTypeTap;
  final VoidCallback? onPreviousSymbol, onNextSymbol;
  final bool isPlaybackActive;
  final ScoreSymbol? selected;
  final bool hasSelection;
  final bool hasMeasureContext;
  final int? selectedMeasureNumber;
  final VoidCallback onMoveUp;
  final VoidCallback onMoveDown;
  final VoidCallback? onOctaveUp, onOctaveDown, onConvertSymbol, onAddThird;
  final VoidCallback? onTie, onSlur, onTriplet, onLyrics, onAnnotations;

  /// Symbols in a range selection; 0 without one.
  final int rangeCount;

  /// Each mark's state for the selection: on, off, or null when it cannot
  /// be added.
  final Map<Articulation, bool?> markStates;
  final ValueChanged<Articulation> onToggleMark;

  /// The selection's dynamic, and null callbacks when none can be added.
  final String? dynamicMark;
  final ValueChanged<String>? onDynamic;
  final ValueChanged<SpannerKind>? onHairpin;

  /// Whether the next tap extends the selection (touch stand-in for Shift).
  final bool extendMode;
  final VoidCallback onToggleExtend;
  final VoidCallback? onSelectBar, onCopy, onCut, onPaste;
  final VoidCallback onWhole;
  final VoidCallback onHalf;
  final VoidCallback onQuarter;
  final VoidCallback onEighth;
  final VoidCallback onSixteenth;
  final void Function(int? alter) onSetAccidental;
  final Clef? currentMeasureClef;
  final TimeSignature? currentTimeSignature;
  final ValueChanged<TimeSignature> onSetTimeSignature;
  final bool? Function(BarSign sign) barSignOn;
  final ValueChanged<BarSign> onBarSign;
  final ValueChanged<Clef?> onSetClef;
  final VoidCallback onMoveToPrev;
  final VoidCallback onMoveToNext;
  final VoidCallback onAddMeasure;
  final VoidCallback? onStaves;
  final VoidCallback onAddPage;
  final bool canDeleteMeasure;
  final VoidCallback onDeleteMeasure;
  final VoidCallback onDeleteSymbol;
  final VoidCallback onToggleDot;
  final Set<String> allowedDurations;
  final bool canToggleDot;
  final VoidCallback? onBeams;

  @override
  State<_InspectorPanel> createState() => _InspectorPanelState();
}

class _InspectorPanelState extends State<_InspectorPanel> {
  bool _barTools = false;
  int _barGroup = 5;

  VoidCallback? _wrapAction(VoidCallback? action) =>
      widget.isPlaybackActive ? null : action;

  List<_ActionGroup> _buildGroups() {
    // Pitch moves apply to a whole range; single-note edits do not.
    final hasRange = widget.rangeCount > 1;
    final canMovePitch = hasRange || widget.selected is Note;
    final isNoteSelected = !hasRange && widget.selected is Note;
    final currentAlter = isNoteSelected
        ? (widget.selected as Note).alter
        : null;
    final currentClef = widget.currentMeasureClef;
    final hasMeasureContext = widget.hasMeasureContext;

    final currentType = widget.selected is Note
        ? (widget.selected as Note).type.trim().toLowerCase()
        : widget.selected is Rest
        ? (widget.selected as Rest).type.trim().toLowerCase()
        : null;
    final currentDots = widget.selected is Note
        ? (widget.selected as Note).dots
        : widget.selected is Rest
        ? (widget.selected as Rest).dots
        : 0;
    final canDot = currentType != null;
    final isDotted = currentDots > 0;

    return [
      _ActionGroup(
        label: 'PITCH',
        children: [
          _ActionTile(
            icon: Icons.keyboard_arrow_up_rounded,
            label: 'Up',
            tooltip: 'Raise pitch by one step (↑)',
            onPressed: _wrapAction(canMovePitch ? widget.onMoveUp : null),
          ),
          _ActionTile(
            icon: Icons.keyboard_arrow_down_rounded,
            label: 'Down',
            tooltip: 'Lower pitch by one step (↓)',
            onPressed: _wrapAction(canMovePitch ? widget.onMoveDown : null),
          ),
          _ActionTile(
            icon: Icons.delete_rounded,
            label: 'Delete',
            danger: true,
            onPressed: _wrapAction(
              widget.hasSelection ? widget.onDeleteSymbol : null,
            ),
          ),
        ],
      ),
      _ActionGroup(
        label: 'ACCIDENTAL',
        children: [
          _AccTile(
            label: '—',
            sublabel: 'None',
            isActive: isNoteSelected && currentAlter == null,
            onPressed: _wrapAction(
              isNoteSelected ? () => widget.onSetAccidental(null) : null,
            ),
          ),
          _AccTile(
            label: '♯',
            sublabel: 'Sharp',
            isActive: isNoteSelected && currentAlter == 1,
            onPressed: _wrapAction(
              isNoteSelected ? () => widget.onSetAccidental(1) : null,
            ),
          ),
          _AccTile(
            label: '♭',
            sublabel: 'Flat',
            isActive: isNoteSelected && currentAlter == -1,
            onPressed: _wrapAction(
              isNoteSelected ? () => widget.onSetAccidental(-1) : null,
            ),
          ),
          _AccTile(
            label: '♮',
            sublabel: 'Natural',
            isActive: isNoteSelected && currentAlter == 0,
            onPressed: _wrapAction(
              isNoteSelected ? () => widget.onSetAccidental(0) : null,
            ),
          ),
        ],
      ),
      _ActionGroup(
        label: 'CLEF',
        children: [
          _ClefTile(
            shortLabel: 'G',
            label: 'Treble',
            isActive: currentClef?.sign == 'G' && currentClef?.line == 2,
            onPressed: _wrapAction(
              hasMeasureContext
                  ? () => widget.onSetClef(const Clef(sign: 'G', line: 2))
                  : null,
            ),
          ),
          _ClefTile(
            shortLabel: 'F',
            label: 'Bass',
            isActive: currentClef?.sign == 'F' && currentClef?.line == 4,
            onPressed: _wrapAction(
              hasMeasureContext
                  ? () => widget.onSetClef(const Clef(sign: 'F', line: 4))
                  : null,
            ),
          ),
          if (AppFeatures.cClefs) ...[
            _ClefTile(
              shortLabel: 'C3',
              label: 'Alto',
              isActive: currentClef?.sign == 'C' && currentClef?.line == 3,
              onPressed: _wrapAction(
                hasMeasureContext
                    ? () => widget.onSetClef(const Clef(sign: 'C', line: 3))
                    : null,
              ),
            ),
            _ClefTile(
              shortLabel: 'C4',
              label: 'Tenor',
              isActive: currentClef?.sign == 'C' && currentClef?.line == 4,
              onPressed: _wrapAction(
                hasMeasureContext
                    ? () => widget.onSetClef(const Clef(sign: 'C', line: 4))
                    : null,
              ),
            ),
          ],
        ],
      ),
      _ActionGroup(
        label: 'TIME',
        children: [
          for (final (beats, beatType, name) in const [
            (2, 4, 'Two'),
            (3, 4, 'Three'),
            (4, 4, 'Common'),
            (2, 2, 'Cut'),
            (3, 8, 'Three'),
            (6, 8, 'Six'),
          ])
            _ClefTile(
              shortLabel: '$beats/$beatType',
              label: name,
              isActive:
                  widget.currentTimeSignature?.beats == beats &&
                  widget.currentTimeSignature?.beatType == beatType,
              onPressed: _wrapAction(
                hasMeasureContext
                    ? () => widget.onSetTimeSignature(
                        TimeSignature(beats: beats, beatType: beatType),
                      )
                    : null,
              ),
            ),
        ],
      ),
      _ActionGroup(
        label: 'DURATION',
        children: [
          _ActionTile(
            icon: Icons.linear_scale_rounded,
            label: 'Beams',
            onPressed: _wrapAction(widget.onBeams),
          ),
          _DurTile(
            isRest: widget.selected is Rest,
            label: 'W',
            sublabel: 'Whole',
            isActive: currentType == 'whole',
            onPressed: _wrapAction(
              widget.allowedDurations.contains('whole') ? widget.onWhole : null,
            ),
          ),
          _DurTile(
            isRest: widget.selected is Rest,
            label: 'H',
            sublabel: 'Half',
            isActive: currentType == 'half',
            onPressed: _wrapAction(
              widget.allowedDurations.contains('half') ? widget.onHalf : null,
            ),
          ),
          _DurTile(
            isRest: widget.selected is Rest,
            label: '♩',
            sublabel: 'Quarter',
            isActive: currentType == 'quarter',
            onPressed: _wrapAction(
              widget.allowedDurations.contains('quarter')
                  ? widget.onQuarter
                  : null,
            ),
          ),
          _DurTile(
            isRest: widget.selected is Rest,
            label: '♪',
            sublabel: 'Eighth',
            isActive: currentType == 'eighth',
            onPressed: _wrapAction(
              widget.allowedDurations.contains('eighth')
                  ? widget.onEighth
                  : null,
            ),
          ),
          _DurTile(
            isRest: widget.selected is Rest,
            label: '♬',
            sublabel: '16th',
            isActive: currentType == 'sixteenth' || currentType == '16th',
            onPressed: _wrapAction(
              widget.allowedDurations.contains('sixteenth')
                  ? widget.onSixteenth
                  : null,
            ),
          ),
          _DurTile(
            isRest: widget.selected is Rest,
            label: '.',
            sublabel: 'Dot',
            isActive: isDotted,
            onPressed: _wrapAction(
              canDot && widget.canToggleDot ? widget.onToggleDot : null,
            ),
          ),
        ],
      ),
      _ActionGroup(
        label: 'MEASURE',
        children: [
          _ActionTile(
            icon: Icons.skip_previous_rounded,
            label: 'Previous bar',
            tooltip: 'Move the selected symbol to the previous bar',
            onPressed: _wrapAction(
              widget.hasSelection ? widget.onMoveToPrev : null,
            ),
          ),
          _ActionTile(
            icon: Icons.skip_next_rounded,
            label: 'Next bar',
            tooltip: 'Move the selected symbol to the next bar',
            onPressed: _wrapAction(
              widget.hasSelection ? widget.onMoveToNext : null,
            ),
          ),
          _ActionTile(
            icon: Icons.add_rounded,
            label: 'Add bar',
            tooltip: 'Add a bar at the end of the score',
            onPressed: _wrapAction(widget.onAddMeasure),
          ),
          _ActionTile(
            icon: Icons.add_box_rounded,
            label: 'Add page',
            tooltip: 'Add a page at the end of the score',
            onPressed: _wrapAction(widget.onAddPage),
          ),
          _ActionTile(
            icon: Icons.remove_rounded,
            label: 'Delete bar',
            tooltip: 'Delete the selected bar',
            onPressed: _wrapAction(
              widget.canDeleteMeasure ? widget.onDeleteMeasure : null,
            ),
            danger: true,
          ),
        ],
      ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final groups = _buildGroups();
    final selected = widget.selected;
    final mode = widget.insertMode
        ? EditorToolMode.insert
        : _barTools
        ? EditorToolMode.measure
        : EditorToolMode.edit;
    final type = selected is Note
        ? selected.type
        : selected is Rest
        ? selected.type
        : '';
    final duration = switch (type) {
      'sixteenth' || '16th' => '16th',
      '' => '',
      _ => '${type[0].toUpperCase()}${type.substring(1)}',
    };
    final dots = selected is Note
        ? selected.dots
        : selected is Rest
        ? selected.dots
        : 0;
    final insertionType =
        widget.insertSymbolType ?? PaletteSymbolType.quarterNote;
    final insertionName = [
      'Whole',
      'Half',
      'Quarter',
      'Eighth',
      '16th',
    ][insertionType.index % 5];
    final title = switch (mode) {
      EditorToolMode.insert =>
        '$insertionName ${insertionType.isRest ? 'rest' : 'note'}',
      EditorToolMode.measure => 'Bar ${widget.selectedMeasureNumber ?? '—'}',
      EditorToolMode.edit =>
        selected is Note
            ? selected.pitch
            : selected is Rest
            ? 'Rest'
            : 'Select a note or rest',
    };

    Widget content;
    if (mode == EditorToolMode.insert) {
      content = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 4,
            children: [
              for (final rests in [false, true]) ...[
                ChoiceChip(
                  label: Text(rests ? 'Rests' : 'Notes'),
                  selected: insertionType.isRest == rests,
                  onSelected: widget.isPlaybackActive
                      ? null
                      : (_) => widget.onPaletteTypeTap(
                          PaletteSymbolType.values[insertionType.index % 5 +
                              (rests ? 5 : 0)],
                        ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 4),
          Wrap(
            spacing: 6,
            runSpacing: 4,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              const Text(
                'Voice',
                style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
              ),
              for (var voice = 1; voice <= 4; voice++)
                Tooltip(
                  message:
                      'Voice $voice (Ctrl/Cmd + Alt + $voice)${voice == 1 ? '' : ' · starts where the selected note starts'}',
                  child: ChoiceChip(
                    avatar: CircleAvatar(
                      radius: 5,
                      backgroundColor: _voiceColors[voice - 1],
                    ),
                    label: Text('$voice'),
                    showCheckmark: false,
                    selected: widget.inputVoice == voice,
                    onSelected: widget.isPlaybackActive
                        ? null
                        : (_) => widget.onVoiceSelected(voice),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 4),
          IgnorePointer(
            ignoring: widget.isPlaybackActive,
            child: SymbolPalette(
              selectedType: insertionType,
              restsOnly: insertionType.isRest,
              onTypeTap: widget.isPlaybackActive
                  ? null
                  : widget.onPaletteTypeTap,
            ),
          ),
        ],
      );
    } else if (mode == EditorToolMode.measure) {
      content = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          EditorToolRow(
            wrap: true,
            children: [
              for (final (index, label) in [
                (5, 'Measures'),
                (3, 'Time'),
                (6, 'Repeats'),
                (2, 'Clef'),
              ])
                ChoiceChip(
                  label: Text(label),
                  selected: _barGroup == index,
                  onSelected: widget.isPlaybackActive
                      ? null
                      : (_) => setState(() => _barGroup = index),
                ),
            ],
          ),
          const SizedBox(height: 8),
          EditorToolRow(
            wrap: widget.isLandscape,
            children: [
              if (_barGroup == 6)
                for (final sign in BarSign.values)
                  _ClefTile(
                    shortLabel: sign.short,
                    label: sign.label,
                    semanticLabel: sign.label,
                    isActive: widget.barSignOn(sign) ?? false,
                    onPressed: _wrapAction(
                      widget.barSignOn(sign) == null
                          ? null
                          : () => widget.onBarSign(sign),
                    ),
                  )
              else
                ...groups[_barGroup].children,
              if (_barGroup == 5) groups[4].children.first,
              if (_barGroup == 2)
                _ActionTile(
                  icon: Icons.queue_music_rounded,
                  label: 'Staves',
                  tooltip: 'Add, rename, reorder or remove staves',
                  onPressed: _wrapAction(widget.onStaves),
                ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            _barGroup == 2
                ? 'Clef changes apply to this staff. Staves adds, renames or reorders instruments.'
                : _barGroup == 3
                ? 'Time signature starts at this bar in every staff.'
                : _barGroup == 6
                ? 'Repeats, endings and jumps apply to the selected bars in every staff; playback follows them.'
                : 'Prev / Next moves the selected symbol to the neighboring bar.',
            style: const TextStyle(
              fontSize: 11,
              color: AppColors.textSecondary,
            ),
          ),
        ],
      );
    } else if (!widget.hasSelection) {
      content = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 10),
            child: Text(
              'Tap a note or rest on the score to change it. To write music, choose Add notes, then tap the staff. Hold a symbol to drag it.',
              style: TextStyle(
                fontSize: 12,
                height: 1.5,
                color: AppColors.textSecondary,
              ),
            ),
          ),
          if (widget.onPaste != null)
            EditorToolRow(
              wrap: widget.isLandscape,
              children: [
                _ActionTile(
                  icon: Icons.content_paste_rounded,
                  label: 'Paste',
                  tooltip: 'Paste into this bar (Ctrl/Cmd + V)',
                  onPressed: _wrapAction(widget.onPaste),
                ),
              ],
            ),
        ],
      );
    } else {
      final durationTools = groups[4].children;
      content = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          EditorToolRow(
            wrap: widget.isLandscape,
            children: [
              ...durationTools.skip(1),
              durationTools.first,
              _ActionTile(
                icon: Icons.filter_3_rounded,
                label: 'Triplet',
                tooltip:
                    'Three shorter notes in this note\'s time (Ctrl/Cmd + 3; 5, 6, 7 for other tuplets)',
                onPressed: _wrapAction(widget.onTriplet),
              ),
            ],
          ),
          const SizedBox(height: 8),
          EditorToolRow(
            wrap: widget.isLandscape,
            children: [...groups[0].children.take(2), ...groups[1].children],
          ),
          const SizedBox(height: 8),
          EditorToolRow(
            wrap: widget.isLandscape,
            children: [
              _ActionTile(
                icon: Icons.keyboard_double_arrow_up_rounded,
                label: 'Octave up',
                tooltip: 'Raise by one octave (Ctrl/Cmd + Up)',
                onPressed: _wrapAction(widget.onOctaveUp),
              ),
              _ActionTile(
                icon: Icons.keyboard_double_arrow_down_rounded,
                label: 'Octave down',
                tooltip: 'Lower by one octave (Ctrl/Cmd + Down)',
                onPressed: _wrapAction(widget.onOctaveDown),
              ),
              _ActionTile(
                icon: Icons.swap_horiz_rounded,
                label: selected is Rest ? 'To C4 note' : 'To rest',
                tooltip: selected is Rest
                    ? 'Replace with a C4 note, keeping duration'
                    : 'Replace a note outside a chord with a rest, keeping duration',
                onPressed: _wrapAction(widget.onConvertSymbol),
              ),
              _ActionTile(
                icon: Icons.library_add_rounded,
                label: 'Add 3rd',
                tooltip:
                    'Add a chord note a third above (Alt + 3; Shift + A–G adds a letter)',
                onPressed: _wrapAction(widget.onAddThird),
              ),
              _ActionTile(
                icon: Icons.link_rounded,
                label: 'Tie',
                tooltip:
                    'Tie to the next note of the same pitch, or remove the tie (+)',
                onPressed: _wrapAction(widget.onTie),
              ),
              _ActionTile(
                icon: Icons.gesture_rounded,
                label: 'Slur',
                tooltip:
                    'Slur the selected notes, or this note to the next (S)',
                onPressed: _wrapAction(widget.onSlur),
              ),
            ],
          ),
          const SizedBox(height: 8),
          EditorToolRow(
            wrap: widget.isLandscape,
            children: [
              _ActionTile(
                icon: Icons.linear_scale_rounded,
                label: 'Extend',
                tooltip: widget.extendMode
                    ? 'Tap a note or rest to extend the selection to it'
                    : 'Then tap a note or rest to select everything up to it (Shift + tap)',
                selected: widget.extendMode,
                onPressed: _wrapAction(widget.onToggleExtend),
              ),
              _ActionTile(
                icon: Icons.select_all_rounded,
                label: 'Select bar',
                tooltip: 'Select every note and rest in this bar',
                onPressed: _wrapAction(widget.onSelectBar),
              ),
              _ActionTile(
                icon: Icons.copy_rounded,
                label: 'Copy',
                tooltip: 'Copy the selection (Ctrl/Cmd + C)',
                onPressed: _wrapAction(widget.onCopy),
              ),
              _ActionTile(
                icon: Icons.content_cut_rounded,
                label: 'Cut',
                tooltip: 'Copy the selection, then delete it (Ctrl/Cmd + X)',
                onPressed: _wrapAction(widget.onCut),
              ),
              _ActionTile(
                icon: Icons.content_paste_rounded,
                label: 'Paste',
                tooltip:
                    'Paste after the selection, or over a range (Ctrl/Cmd + V)',
                onPressed: _wrapAction(widget.onPaste),
              ),
            ],
          ),
          const SizedBox(height: 8),
          EditorToolRow(
            wrap: widget.isLandscape,
            children: [
              for (final (mark, icon, label, keys) in const [
                (
                  Articulation.staccato,
                  Icons.fiber_manual_record,
                  'Staccato',
                  'Shift + S',
                ),
                (
                  Articulation.staccatissimo,
                  Icons.change_history,
                  'Staccatiss.',
                  null,
                ),
                (
                  Articulation.tenuto,
                  Icons.horizontal_rule,
                  'Tenuto',
                  'Shift + N',
                ),
                (
                  Articulation.accent,
                  Icons.chevron_right,
                  'Accent',
                  'Shift + V',
                ),
                (
                  Articulation.marcato,
                  Icons.keyboard_arrow_up,
                  'Marcato',
                  'Shift + O',
                ),
                (
                  Articulation.fermata,
                  Icons.remove_red_eye_outlined,
                  'Fermata',
                  null,
                ),
                (Articulation.trill, Icons.waves, 'Trill', null),
                (Articulation.mordent, Icons.show_chart, 'Mordent', null),
                (Articulation.turn, Icons.all_inclusive, 'Turn', null),
              ])
                _ActionTile(
                  icon: icon,
                  label: label,
                  tooltip: keys == null ? label : '$label ($keys)',
                  selected: widget.markStates[mark] ?? false,
                  onPressed: widget.markStates[mark] == null
                      ? null
                      : _wrapAction(() => widget.onToggleMark(mark)),
                ),
            ],
          ),
          const SizedBox(height: 8),
          EditorToolRow(
            wrap: widget.isLandscape,
            children: [
              _ActionTile(
                icon: Icons.text_fields,
                label: 'Text & tempo',
                tooltip: 'Text, tempo and chord symbols in this bar',
                onPressed: _wrapAction(widget.onAnnotations),
              ),
              _ActionTile(
                icon: Icons.lyrics_outlined,
                label: 'Lyrics',
                tooltip: 'Lyrics on the selected note (Ctrl/Cmd + L)',
                onPressed: _wrapAction(widget.onLyrics),
              ),
              for (final mark in editorDynamics)
                ChoiceChip(
                  label: Text(
                    mark,
                    style: const TextStyle(
                      fontStyle: FontStyle.italic,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  tooltip: 'Dynamic $mark on the first selected note',
                  showCheckmark: false,
                  selected: widget.dynamicMark == mark,
                  onSelected:
                      widget.onDynamic == null || widget.isPlaybackActive
                      ? null
                      : (_) => widget.onDynamic!(mark),
                ),
              _ActionTile(
                icon: Icons.trending_up_rounded,
                label: 'Cresc.',
                tooltip: 'Crescendo hairpin over the selection (<)',
                onPressed: _wrapAction(
                  widget.onHairpin == null
                      ? null
                      : () => widget.onHairpin!(SpannerKind.crescendo),
                ),
              ),
              _ActionTile(
                icon: Icons.trending_down_rounded,
                label: 'Dim.',
                tooltip: 'Diminuendo hairpin over the selection (>)',
                onPressed: _wrapAction(
                  widget.onHairpin == null
                      ? null
                      : () => widget.onHairpin!(SpannerKind.diminuendo),
                ),
              ),
            ],
          ),
        ],
      );
    }
    return EditorToolDock(
      mode: mode,
      disabled: widget.isPlaybackActive,
      onModeChanged: (next) {
        if ((next == EditorToolMode.insert) != widget.insertMode) {
          widget.onToggleInsertMode();
        }
        setState(() => _barTools = next == EditorToolMode.measure);
      },
      title: title,
      subtitle: switch (mode) {
        EditorToolMode.insert =>
          'Tap the staff or type A–G · hold a symbol to drag',
        EditorToolMode.measure => 'Structure and staff settings',
        EditorToolMode.edit =>
          widget.rangeCount > 1
              ? '${widget.rangeCount} symbols selected · pitch moves apply to all'
              : widget.hasSelection
              ? '${dots > 0 ? 'Dotted ' : ''}$duration ${selected is Note ? 'note' : 'rest'} · Bar ${widget.selectedMeasureNumber}'
              : 'Tap the score to select a symbol',
      },
      showSymbolNavigation: mode == EditorToolMode.edit,
      onPreviousSymbol: widget.onPreviousSymbol,
      onNextSymbol: widget.onNextSymbol,
      onDeleteSymbol: widget.hasSelection ? widget.onDeleteSymbol : null,
      child: content,
    );
  }
}

class _ActionGroup {
  const _ActionGroup({required this.label, required this.children});
  final String label;
  final List<Widget> children;
}

// Drag-to-delete target, available while a symbol is held.

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

// ---------------------------------------------------------------------------
// Selection card
// ---------------------------------------------------------------------------

class _PageOverviewSheet extends StatelessWidget {
  const _PageOverviewSheet({
    required this.score,
    required this.currentPageIndex,
    required this.totalPages,
  });

  final Score score;
  final int currentPageIndex;
  final int totalPages;

  @override
  Widget build(BuildContext context) {
    final sheetHeight = MediaQuery.sizeOf(context).height * 0.72;
    final pageCount = math.max(1, totalPages);

    return SafeArea(
      top: false,
      child: Align(
        alignment: Alignment.bottomCenter,
        child: Material(
          color: AppColors.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(18)),
          child: SizedBox(
            height: sheetHeight,
            child: Column(
              children: [
                const SizedBox(height: 10),
                Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: AppColors.border,
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),
                Expanded(
                  child: GridView.builder(
                    padding: const EdgeInsets.fromLTRB(16, 18, 16, 24),
                    gridDelegate:
                        const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 2,
                          crossAxisSpacing: 12,
                          mainAxisSpacing: 14,
                          childAspectRatio: 0.64,
                        ),
                    itemCount: pageCount,
                    itemBuilder: (context, index) => _PageOverviewCard(
                      score: score,
                      pageIndex: index,
                      isActive: index == currentPageIndex,
                      onTap: () => Navigator.of(context).pop(index),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _PageOverviewCard extends StatelessWidget {
  const _PageOverviewCard({
    required this.score,
    required this.pageIndex,
    required this.isActive,
    required this.onTap,
  });

  final Score score;
  final int pageIndex;
  final bool isActive;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 140),
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: AppColors.background,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: isActive ? AppColors.accent : AppColors.border,
            width: isActive ? 2 : 1,
          ),
        ),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final previewWidth = math.max(1.0, constraints.maxWidth);
            final previewHeight = math.max(1.0, constraints.maxHeight - 28);

            return Column(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(5),
                  child: ScorePageThumbnail(
                    score: score,
                    pageIndex: pageIndex,
                    cardWidth: previewWidth,
                    height: previewHeight,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Page ${pageIndex + 1}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: isActive ? AppColors.accent : AppColors.textPrimary,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
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

class _PageNav extends StatelessWidget {
  const _PageNav({
    required this.currentPageIndex,
    required this.totalPages,
    required this.onPrev,
    required this.onNext,
    required this.onPageOverviewTap,
  });

  final int currentPageIndex;
  final int totalPages;
  final VoidCallback? onPrev;
  final VoidCallback? onNext;
  final VoidCallback onPageOverviewTap;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 132,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          _NavBtn(icon: Icons.chevron_left_rounded, onPressed: onPrev),
          _PageButton(
            label: totalPages <= 9
                ? '${currentPageIndex + 1} / $totalPages'
                : '${currentPageIndex + 1}',
            onTap: onPageOverviewTap,
          ),
          _NavBtn(icon: Icons.chevron_right_rounded, onPressed: onNext),
        ],
      ),
    );
  }
}

class _PageButton extends StatelessWidget {
  const _PageButton({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: 'Pages',
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: SizedBox.square(
          dimension: 44,
          child: Container(
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: AppColors.accent.withValues(alpha: 0.18),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: AppColors.accent.withValues(alpha: 0.75),
              ),
            ),
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                label,
                maxLines: 1,
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: AppColors.accent,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _NavBtn extends StatelessWidget {
  const _NavBtn({required this.icon, required this.onPressed});

  final IconData icon;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: icon == Icons.chevron_left_rounded
          ? 'Previous page'
          : 'Next page',
      child: SizedBox.square(
        dimension: 44,
        child: IconButton(
          onPressed: onPressed,
          icon: Icon(icon, size: 22),
          padding: EdgeInsets.zero,
          color: onPressed != null
              ? AppColors.textPrimary
              : AppColors.textSecondary.withValues(alpha: 0.3),
          visualDensity: VisualDensity.compact,
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Action tiles
// ---------------------------------------------------------------------------

double _toolTileWidth(
  BuildContext context,
  String label, {
  double minimum = 48,
  double fontSize = 10,
}) {
  final painter = TextPainter(
    text: TextSpan(
      text: label,
      style: DefaultTextStyle.of(
        context,
      ).style.copyWith(fontSize: fontSize, fontWeight: FontWeight.w600),
    ),
    textScaler: MediaQuery.textScalerOf(context),
    textDirection: Directionality.of(context),
  )..layout();
  final width = math.max(minimum, (painter.width + 16).ceilToDouble());
  painter.dispose();
  return width;
}

/// MuseScore Studio's voice colours: blue, green, orange, purple.
const _voiceColors = [
  Color(0xFF0065BF),
  Color(0xFF007F00),
  Color(0xFFC53F00),
  Color(0xFFC31989),
];

/// The dynamics the Edit dock and search offer.
const editorDynamics = ['pp', 'p', 'mp', 'mf', 'f', 'ff', 'sfz'];

class _ActionTile extends StatelessWidget {
  const _ActionTile({
    required this.icon,
    required this.label,
    required this.onPressed,
    this.tooltip,
    this.danger = false,
    this.selected,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onPressed;
  final String? tooltip;
  final bool danger;

  /// Non-null for a toggle; true draws it switched on.
  final bool? selected;

  @override
  Widget build(BuildContext context) {
    final enabled = onPressed != null;
    final activeColor = danger
        ? const Color(0xFFEF4444)
        : AppColors.textPrimary;
    final iconColor = enabled
        ? (danger ? const Color(0xFFEF4444) : AppColors.textPrimary)
        : AppColors.textSecondary.withValues(alpha: 0.35);

    final on = selected ?? false;
    return Tooltip(
      message: tooltip ?? label,
      child: Semantics(
        toggled: selected,
        child: InkWell(
          onTap: onPressed,
          borderRadius: BorderRadius.circular(8),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 120),
            width: _toolTileWidth(context, label, minimum: 52),
            constraints: const BoxConstraints(minHeight: 48),
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
            decoration: BoxDecoration(
              color: on
                  ? AppColors.accent.withValues(alpha: 0.18)
                  : enabled
                  ? AppColors.surfaceAlt
                  : AppColors.background,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: on
                    ? AppColors.accent
                    : enabled
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
                    fontSize: 10,
                    color: enabled
                        ? activeColor
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

    return Semantics(
      button: true,
      selected: isActive,
      enabled: enabled,
      label: '$sublabel accidental',
      onTap: onPressed,
      excludeSemantics: true,
      child: Tooltip(
        message: sublabel,
        child: InkWell(
          onTap: onPressed,
          borderRadius: BorderRadius.circular(8),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 120),
            width: math.max(
              _toolTileWidth(context, sublabel),
              _toolTileWidth(context, label, fontSize: 15),
            ),
            constraints: const BoxConstraints(minHeight: 48),
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
                    fontFamilyFallback: const ['NotoMusic'],
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
                    fontSize: 10,
                    color: isActive
                        ? _accent
                        : enabled
                        ? AppColors.textSecondary
                        : AppColors.textSecondary.withValues(alpha: 0.3),
                    fontWeight: FontWeight.w500,
                  ),
                  maxLines: 1,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ClefTile extends StatelessWidget {
  const _ClefTile({
    required this.shortLabel,
    required this.label,
    required this.isActive,
    required this.onPressed,
    this.semanticLabel,
  });

  final String shortLabel;
  final String label;
  final String? semanticLabel;
  final bool isActive;
  final VoidCallback? onPressed;

  static const _accent = Color(0xFFD4A96A);

  @override
  Widget build(BuildContext context) {
    final enabled = onPressed != null;

    return Semantics(
      button: true,
      selected: isActive,
      enabled: enabled,
      label:
          semanticLabel ??
          (shortLabel.contains('/')
              ? '$shortLabel time signature'
              : '$label clef'),
      onTap: onPressed,
      excludeSemantics: true,
      child: Tooltip(
        message: label,
        child: InkWell(
          onTap: onPressed,
          borderRadius: BorderRadius.circular(8),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 120),
            width: _toolTileWidth(context, label),
            constraints: const BoxConstraints(minHeight: 48),
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
                  shortLabel,
                  style: TextStyle(
                    fontSize: 13,
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
                  label,
                  style: TextStyle(
                    fontSize: 10,
                    color: isActive
                        ? _accent
                        : enabled
                        ? AppColors.textSecondary
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
      ),
    );
  }
}

class _MetadataSheet extends StatefulWidget {
  const _MetadataSheet({
    required this.initialTitle,
    required this.initialComposer,
  });

  final String initialTitle;
  final String initialComposer;

  @override
  State<_MetadataSheet> createState() => _MetadataSheetState();
}

class _MetadataSheetState extends State<_MetadataSheet> {
  late final TextEditingController _titleCtrl;
  late final TextEditingController _composerCtrl;

  @override
  void initState() {
    super.initState();
    _titleCtrl = TextEditingController(text: widget.initialTitle);
    _composerCtrl = TextEditingController(text: widget.initialComposer);
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    _composerCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(
        20,
        20,
        20,
        MediaQuery.viewInsetsOf(context).bottom + 24,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Expanded(
                child: Text(
                  'Score Metadata',
                  style: TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              IconButton(
                onPressed: () => Navigator.of(context).pop(),
                icon: const Icon(
                  Icons.close_rounded,
                  color: AppColors.textSecondary,
                ),
                visualDensity: VisualDensity.compact,
              ),
            ],
          ),
          const SizedBox(height: 16),
          _MetadataField(
            label: 'Title',
            controller: _titleCtrl,
            maxLength: 100,
          ),
          const SizedBox(height: 12),
          _MetadataField(
            label: 'Composer',
            controller: _composerCtrl,
            maxLength: 100,
          ),
          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: () => Navigator.of(context).pop((
                title: _titleCtrl.text.trim(),
                composer: _composerCtrl.text.trim(),
              )),
              child: const Text('Save'),
            ),
          ),
        ],
      ),
    );
  }
}

class _MetadataField extends StatefulWidget {
  const _MetadataField({
    required this.label,
    required this.controller,
    this.maxLength,
  });

  final String label;
  final TextEditingController controller;
  final int? maxLength;

  @override
  State<_MetadataField> createState() => _MetadataFieldState();
}

class _MetadataFieldState extends State<_MetadataField> {
  String? _emojiError;
  Timer? _emojiTimer;

  @override
  void dispose() {
    _emojiTimer?.cancel();
    super.dispose();
  }

  void _onEmojiBlocked() {
    _emojiTimer?.cancel();
    setState(() => _emojiError = 'Emoji not allowed');
    _emojiTimer = Timer(const Duration(seconds: 2), () {
      if (mounted) setState(() => _emojiError = null);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          widget.label,
          style: const TextStyle(
            color: AppColors.textSecondary,
            fontSize: 12,
            fontWeight: FontWeight.w500,
          ),
        ),
        const SizedBox(height: 6),
        TextField(
          controller: widget.controller,
          maxLength: widget.maxLength,
          inputFormatters: [EmojiBlockingFormatter(onBlocked: _onEmojiBlocked)],
          buildCounter:
              (_, {required currentLength, required isFocused, maxLength}) {
                if (maxLength == null || currentLength <= maxLength - 20) {
                  return null;
                }
                return Text(
                  '$currentLength / $maxLength',
                  style: TextStyle(
                    color: currentLength >= maxLength
                        ? const Color(0xFFE05252)
                        : AppColors.textSecondary,
                    fontSize: 11,
                  ),
                );
              },
          style: const TextStyle(color: AppColors.textPrimary, fontSize: 14),
          cursorColor: AppColors.accent,
          decoration: InputDecoration(
            errorText: _emojiError,
            filled: true,
            fillColor: AppColors.background,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: const BorderSide(color: AppColors.border),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: const BorderSide(color: AppColors.border),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: const BorderSide(color: AppColors.accent),
            ),
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 12,
              vertical: 10,
            ),
          ),
        ),
      ],
    );
  }
}

class _DurTile extends StatelessWidget {
  const _DurTile({
    required this.label,
    this.isRest = false,
    required this.sublabel,
    required this.isActive,
    required this.onPressed,
  });

  final String label;
  final bool isRest;
  final String sublabel;
  final bool isActive;
  final VoidCallback? onPressed;

  static const _accent = Color(0xFFD4A96A);

  @override
  Widget build(BuildContext context) {
    final enabled = onPressed != null;

    return Semantics(
      button: true,
      selected: isActive,
      enabled: enabled,
      label: sublabel == 'Dot' ? 'Dotted duration' : '$sublabel duration',
      onTap: onPressed,
      excludeSemantics: true,
      child: Tooltip(
        message: sublabel,
        child: InkWell(
          onTap: onPressed,
          borderRadius: BorderRadius.circular(8),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 120),
            width: math.max(
              _toolTileWidth(context, sublabel),
              _toolTileWidth(context, label, fontSize: 15),
            ),
            constraints: const BoxConstraints(minHeight: 48),
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
                if (label != '.')
                  CustomPaint(
                    size: const Size(22, 22),
                    painter: PaletteSymbolPainter(
                      type:
                          PaletteSymbolType.values[(isRest ? 5 : 0) +
                              switch (label) {
                                'W' => 0,
                                'H' => 1,
                                '♩' => 2,
                                '♪' => 3,
                                _ => 4,
                              }],
                      color: isActive
                          ? _accent
                          : enabled
                          ? AppColors.textPrimary
                          : AppColors.textSecondary.withValues(alpha: .35),
                    ),
                  )
                else
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
                    fontSize: 10,
                    color: isActive
                        ? _accent
                        : enabled
                        ? AppColors.textSecondary
                        : AppColors.textSecondary.withValues(alpha: 0.3),
                    fontWeight: FontWeight.w500,
                  ),
                  maxLines: 1,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Save error overlay
// ---------------------------------------------------------------------------

// ---------------------------------------------------------------------------
// Drag ghost overlay — floats above all UI during symbol reorder drag
// ---------------------------------------------------------------------------

class _DragGhostOverlay extends StatefulWidget {
  const _DragGhostOverlay({required this.positionNotifier, required this.type});

  final ValueNotifier<Offset> positionNotifier;
  final PaletteSymbolType type;

  @override
  State<_DragGhostOverlay> createState() => _DragGhostOverlayState();
}

class _DragGhostOverlayState extends State<_DragGhostOverlay>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _scale;
  Offset _position = Offset.zero;

  @override
  void initState() {
    super.initState();
    _position = widget.positionNotifier.value;
    widget.positionNotifier.addListener(_onPositionChanged);
    _controller = AnimationController(
      duration: const Duration(milliseconds: 200),
      vsync: this,
    );
    _scale = Tween<double>(
      begin: 0.4,
      end: 1.5,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOutBack));
    _controller.forward();
  }

  @override
  void dispose() {
    widget.positionNotifier.removeListener(_onPositionChanged);
    _controller.dispose();
    super.dispose();
  }

  void _onPositionChanged() {
    setState(() => _position = widget.positionNotifier.value);
  }

  @override
  Widget build(BuildContext context) {
    const ghostSize = Size(34, 40);
    return Positioned(
      left: _position.dx - ghostSize.width / 2,
      top: _position.dy - ghostSize.height * 1.9,
      child: IgnorePointer(
        child: AnimatedBuilder(
          animation: _scale,
          builder: (_, child) =>
              Transform.scale(scale: _scale.value, child: child),
          child: Material(
            color: Colors.transparent,
            child: CustomPaint(
              size: ghostSize,
              painter: PaletteSymbolPainter(
                type: widget.type,
                color: AppColors.accent,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
