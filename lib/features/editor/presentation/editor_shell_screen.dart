import 'package:note_vision/core/models/score_review.dart';
import 'package:note_vision/core/services/notation_review_service.dart';
import 'package:note_vision/features/editor/presentation/widgets/notation_review_panel.dart';
import 'dart:async' show StreamSubscription, Timer, unawaited;
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:note_vision/core/config/app_features.dart';
import 'package:note_vision/core/models/clef.dart';
import 'package:note_vision/core/models/note.dart';
import 'package:note_vision/core/models/project.dart';
import 'package:note_vision/core/models/rest.dart';
import 'package:note_vision/core/models/score.dart';
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
import 'package:note_vision/core/services/score_classifier.dart';
import 'package:note_vision/core/services/user_profile_service.dart';
import 'package:note_vision/core/widgets/score_notation/notation_layout.dart';
import 'package:note_vision/core/widgets/score_notation/score_notation_painter.dart';
import 'package:note_vision/core/theme/app_theme.dart';
import 'package:note_vision/core/widgets/score_notation_viewer.dart';
import 'package:note_vision/core/widgets/score_page_thumbnail.dart';
import 'package:note_vision/features/editor/domain/editor_actions.dart';
import 'package:note_vision/features/editor/model/editor_state.dart';
import 'package:note_vision/features/editor/model/editor_state_history.dart';
import 'package:note_vision/features/editor/presentation/editor_layout_policy.dart';
import 'package:note_vision/features/editor/presentation/widgets/notation_check_sheet.dart';
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
  bool _isSubmitting = false;
  String? _role;
  _EditorBannerData? _banner;

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
      EditorLayoutPolicy.forPartCount(_editorState.score.parts.length);

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
    _editorState = _withDefaultMeasureContext(
      widget.args.initialState.copyWith(
        score: NotationReviewService.ensureIdentity(widget.args.score),
      ),
    );
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
        const _EditorBannerData.error(
          'Could not export the score. Try again.',
          duration: Duration(seconds: 6),
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
          _editorState = _editorState.copyWith(hasUnsavedChanges: false);
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
          _editorState = _editorState.copyWith(hasUnsavedChanges: false);
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
    _showEditorBanner(_EditorBannerData.success('Saved as $name'));
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
    setState(() => _banner = banner);
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
    await _playback.play(
      _editorState.score,
      fromMeasureIndex: fromMeasureIndex,
      fromPartIndex: partIndex,
    );
    if (!mounted) return;
    if (_playback.status != PlaybackStatus.playing) {
      setState(() {
        _playheadEpoch = 0;
        _playheadSymbolIndex = 0;
        _playheadNoteDurationMs = 0;
      });
    }
  }

  void _stopVisualPlayback() {
    setState(() {
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
      _editorState = nextState.copyWith(
        score: NotationReviewService.ensureIdentity(nextState.score),
      );
      if (!identical(prevScore, _editorState.score)) {
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

  void _onNotationSymbolTap(int partIndex, int measureIndex, int symbolIndex) {
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
    final isPlaybackActive =
        _playbackStatus == PlaybackStatus.playing || _reviewListening;
    final isReadOnly = _isReviewMode;
    final selected = _editorState.selectedSymbol;
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

    return PopScope(
      canPop: isReadOnly || !_editorState.hasUnsavedChanges,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _handlePopAttempt();
      },
      child: Scaffold(
        backgroundColor: AppColors.background,
        body: SafeArea(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final isLandscape = constraints.maxWidth > constraints.maxHeight;

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
                // In portrait the selection card floats over the top of the
                // canvas; the zoom controls float over its bottom edge.
                fitInsets: EdgeInsets.only(
                  top: isLandscape ? 0 : _kSelectionCardReserve,
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
                onToggleInsertMode: _toggleInsertMode,
                onPaletteTypeTap: _onPaletteTypeTap,
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
                      isPlaybackActive: isPlaybackActive,
                      selected: selected,
                      hasSelection: hasSelection,
                      hasMeasureContext: hasMeasureContext,
                      selectedMeasureNumber: selectedMeasureNumber,
                      currentPageIndex: _currentPageIndex,
                      totalPages: _pageMetrics.totalPages,
                      onPrevPage: onPrevPage,
                      onNextPage: onNextPage,
                      onPageOverviewTap: _showPageOverview,
                      onMoveUp: () =>
                          _updateState((s) => s.moveSelectedSymbolUp()),
                      onMoveDown: () =>
                          _updateState((s) => s.moveSelectedSymbolDown()),
                      onWhole: () => _updateState(
                        (s) => s.setSelectedDuration(wholeDuration),
                      ),
                      onHalf: () => _updateState(
                        (s) => s.setSelectedDuration(halfDuration),
                      ),
                      onQuarter: () => _updateState(
                        (s) => s.setSelectedDuration(quarterDuration),
                      ),
                      onEighth: () => _updateState(
                        (s) => s.setSelectedDuration(eighthDuration),
                      ),
                      onSixteenth: () => _updateState(
                        (s) => s.setSelectedDuration(sixteenthDuration),
                      ),
                      onSetAccidental: (alter) => _updateState(
                        (s) => s.setSelectedNoteAccidental(alter),
                      ),
                      currentMeasureClef: currentMeasureClef,
                      currentTimeSignature:
                          _editorState.selectedMeasureTimeSignature,
                      onSetTimeSignature: (timeSignature) => _updateState(
                        (s) =>
                            s.setTimeSignatureAtSelectedMeasure(timeSignature),
                      ),
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
                          _updateState((s) => s.deleteSelectedSymbol()),
                      onToggleDot: () =>
                          _updateState((s) => s.toggleSelectedDot()),
                    );

              final scoreIsEmpty =
                  _editorState.score.parts.isEmpty ||
                  _editorState.score.parts.every(
                    (p) => p.measures.every((m) => m.symbols.isEmpty),
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
                  onSave: isReadOnly ? null : _onSave,
                  showSubmitButton: _isStudent && !isReadOnly,
                  onSubmit:
                      _isStudent &&
                          !isReadOnly &&
                          !isPlaybackActive &&
                          !_isSubmitting
                      ? _onSubmit
                      : null,
                  onMetadataTap: isReadOnly ? null : _showMetadataSheet,
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
                  isEmpty: scoreIsEmpty,
                  // The scrubber covers every staff in reading order.
                  measuresPerPart: measuresPerPart,
                  totalMeasures:
                      measuresPerPart * _editorState.score.parts.length,
                  onPlay: () => unawaited(
                    _playFromMeasure(
                      _editorState.selectedMeasureIndex ?? 0,
                      partIndex: _editorState.selectedPartIndex ?? 0,
                    ),
                  ),
                  onResume: () {
                    _playback.resume();
                  },
                  onPause: () {
                    _playback.pause();
                  },
                  onStop: () {
                    _stopVisualPlayback();
                    _playback.stop();
                  },
                  onTempoChanged: _setPlaybackTempo,
                  onSeek: (step) => unawaited(
                    _playFromMeasure(
                      step % measuresPerPart,
                      partIndex: step ~/ measuresPerPart,
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }
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
                      : Stack(
                          children: [
                            Positioned.fill(
                              child: Padding(
                                padding: const EdgeInsets.fromLTRB(
                                  12,
                                  0,
                                  12,
                                  _kInspectorBarHeight,
                                ),
                                child: notationArea,
                              ),
                            ),
                            Positioned.fill(child: inspectorPanel),
                            if (isDraggingNote)
                              Positioned(
                                left: 0,
                                right: 0,
                                bottom: 0,
                                height: _kInspectorBarHeight,
                                child: Center(
                                  child: _TrashZone(
                                    key: trashZoneKey,
                                    isHovered: () {
                                      if (dragGlobal == Offset.zero) {
                                        return false;
                                      }
                                      final box =
                                          trashZoneKey.currentContext
                                                  ?.findRenderObject()
                                              as RenderBox?;
                                      if (box == null) return false;
                                      return (box.localToGlobal(Offset.zero) &
                                              box.size)
                                          .contains(dragGlobal);
                                    }(),
                                  ),
                                ),
                              ),
                          ],
                        ),
                ),
                if (reviewPanel == null) playbackControls,
              ],
            ),
            Positioned(
              top: 64,
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

enum _HeaderMenuAction { scanPage, checkNotation, exportXml, exportPdf }

class _HeaderMenuItem extends StatelessWidget {
  const _HeaderMenuItem({required this.icon, required this.label});

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

  static final ButtonStyle _compactIconButtonStyle = IconButton.styleFrom(
    visualDensity: VisualDensity.compact,
    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
    minimumSize: const Size(36, 36),
    padding: const EdgeInsets.all(6),
  );

  @override
  Widget build(BuildContext context) {
    return Container(
      height:
          56 +
          (MediaQuery.textScalerOf(context).scale(15) - 15) +
          (MediaQuery.textScalerOf(context).scale(10) - 10),
      decoration: const BoxDecoration(
        color: AppColors.surface,
        border: Border(bottom: BorderSide(color: AppColors.border)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 6),
      child: Row(
        children: [
          IconButton(
            onPressed: onBack,
            icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 16),
            color: AppColors.textPrimary,
            tooltip: 'Back',
            style: _compactIconButtonStyle,
          ),
          const SizedBox(width: 2),
          Flexible(
            fit: FlexFit.tight,
            child: ConstrainedBox(
              constraints: const BoxConstraints(minWidth: 120),
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
                                color: AppColors.accent.withValues(alpha: 0.18),
                                borderRadius: BorderRadius.circular(4),
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
                              isReviewMode ? reviewModeLabel : 'Score Editor',
                              if (scoreLabel != null) scoreLabel!.displayName,
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
          IconButton(
            onPressed: onCheckNotation,
            icon: const Icon(Icons.fact_check_outlined, size: 18),
            color: AppColors.accent,
            tooltip: 'Review & Correct',
            style: _compactIconButtonStyle,
          ),
          IconButton(
            onPressed: canUndo ? onUndo : null,
            icon: const Icon(Icons.undo_rounded, size: 18),
            color: canUndo
                ? AppColors.textPrimary
                : AppColors.textSecondary.withValues(alpha: 0.3),
            tooltip: 'Undo',
            style: _compactIconButtonStyle,
          ),
          IconButton(
            onPressed: canRedo ? onRedo : null,
            icon: const Icon(Icons.redo_rounded, size: 18),
            color: canRedo
                ? AppColors.textPrimary
                : AppColors.textSecondary.withValues(alpha: 0.3),
            tooltip: 'Redo',
            style: _compactIconButtonStyle,
          ),
          const SizedBox(width: 4),
          if (showSubmitButton)
            IconButton(
              onPressed: onSubmit,
              icon: const Icon(Icons.upload_rounded, size: 18),
              color: onSubmit == null
                  ? AppColors.textSecondary.withValues(alpha: 0.35)
                  : AppColors.accent,
              tooltip: 'Submit',
              style: _compactIconButtonStyle,
            ),
          if (onSave != null)
            FilledButton.icon(
              onPressed: onSave,
              icon: const Icon(Icons.save_rounded, size: 15),
              label: const Text('Save', style: TextStyle(fontSize: 13)),
              style: FilledButton.styleFrom(
                minimumSize: const Size(60, 34),
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                padding: const EdgeInsets.symmetric(horizontal: 10),
              ),
            ),
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
            ],
          ),
          const SizedBox(width: 2),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Notation area — A4-like canvas with InteractiveViewer for pan/zoom
// ---------------------------------------------------------------------------

// Inspector bar height (portrait bottom action bar, sits above PlaybackControlsBar).
const double _kInspectorBarHeight = 56.0;

/// Canvas height hidden by the selection card in portrait (8 px gap, the
/// compact card, 8 px gap) and by the floating zoom controls at the bottom.
/// The page is fitted between them so its first and last staves show.
const double _kSelectionCardReserve = 64.0;
const double _kFloatingControlsReserve = 46.0;

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
    required this.onToggleInsertMode,
    required this.onPaletteTypeTap,
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
  final VoidCallback onToggleInsertMode;
  final ValueChanged<PaletteSymbolType> onPaletteTypeTap;
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
        math.min(viewport.width / content.width, freeHeight / content.height) *
        0.90;

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
    final scale = math
        .min(
          viewport.width / (policy.minMeasureWidth * 1.7),
          viewport.height / (policy.rowHeight * 1.6),
        )
        .clamp(.2, 2.5);
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
        viewport.height / 2 - (y + policy.rowHeight / 2) * scale,
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
    final newScale = currentScale * delta;
    final newTx = cx + delta * (translation.x - cx);
    final newTy = cy + delta * (translation.y - cy);

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
    return Size(
      widget.layoutPolicy.pageWidth,
      math.max(widget.layoutPolicy.pageHeight, layout.size.height),
    );
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
      onMeasureTap: widget.isReadOnly && !widget.isPlaybackActive
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
                    if (viewportChanged && widget.reviewFocusMeasure != null) {
                      WidgetsBinding.instance.addPostFrameCallback((_) {
                        if (mounted && widget.reviewFocusMeasure != null) {
                          focusMeasure(
                            widget.reviewFocusPart,
                            widget.reviewFocusMeasure!,
                          );
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

              // Insert mode banner
              if (widget.insertMode)
                Positioned(
                  top: 8,
                  left: 0,
                  right: 0,
                  child: Center(
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 5,
                      ),
                      decoration: BoxDecoration(
                        color: AppColors.accent.withValues(alpha: 0.18),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                          color: AppColors.accent.withValues(alpha: 0.5),
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(
                            Icons.edit_rounded,
                            size: 12,
                            color: AppColors.accent,
                          ),
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
                right: 8,
                bottom: 8,
                // Only the zoom readout follows pan and zoom; rebuilding the
                // page on every frame would repaint the whole score.
                child: ValueListenableBuilder<Matrix4>(
                  valueListenable: _transformController,
                  builder: (context, transform, _) => _FloatingControls(
                    zoomPercent: (transform.entry(0, 0) * 100).round(),
                    insertMode: widget.insertMode && !widget.isPlaybackActive,
                    showInsertToggle: !widget.isReadOnly,
                    onZoomIn: _zoomIn,
                    onZoomOut: _zoomOut,
                    onFitToScreen: _fitToScreen,
                    onToggleInsertMode: widget.isPlaybackActive
                        ? () {}
                        : widget.onToggleInsertMode,
                  ),
                ),
              ),
            ],
          ),
        ),
        if (!widget.isReadOnly)
          IgnorePointer(
            ignoring: widget.isPlaybackActive,
            child: SymbolPalette(
              selectedType: widget.insertMode && !widget.isPlaybackActive
                  ? widget.insertSymbolType
                  : null,
              onTypeTap: widget.onPaletteTypeTap,
            ),
          ),
      ],
    );
  }

  String _typeLabel(PaletteSymbolType t) => switch (t) {
    PaletteSymbolType.wholeNote => 'whole note',
    PaletteSymbolType.halfNote => 'half note',
    PaletteSymbolType.quarterNote => 'quarter note',
    PaletteSymbolType.eighthNote => 'eighth note',
    PaletteSymbolType.sixteenthNote => 'sixteenth note',
    PaletteSymbolType.wholeRest => 'whole rest',
    PaletteSymbolType.halfRest => 'half rest',
    PaletteSymbolType.quarterRest => 'quarter rest',
    PaletteSymbolType.eighthRest => 'eighth rest',
    PaletteSymbolType.sixteenthRest => 'sixteenth rest',
  };

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
    required this.insertMode,
    required this.showInsertToggle,
    required this.onZoomIn,
    required this.onZoomOut,
    required this.onFitToScreen,
    required this.onToggleInsertMode,
  });

  final int zoomPercent;
  final bool insertMode;
  final bool showInsertToggle;
  final VoidCallback onZoomIn;
  final VoidCallback onZoomOut;
  final VoidCallback onFitToScreen;
  final VoidCallback onToggleInsertMode;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (showInsertToggle) ...[
          Semantics(
            button: true,
            toggled: insertMode,
            label: insertMode
                ? 'Insert mode on. Tap to switch to select mode'
                : 'Select mode. Tap to switch to insert mode',
            excludeSemantics: true,
            child: GestureDetector(
              onTap: onToggleInsertMode,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 6,
                ),
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
                      color: insertMode
                          ? AppColors.accent
                          : AppColors.textSecondary,
                    ),
                    const SizedBox(width: 5),
                    Text(
                      insertMode ? 'Insert' : 'Select',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: insertMode
                            ? AppColors.accent
                            : AppColors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(width: 6),
        ],
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
      width: 36,
      height: 36,
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
              height: _kInspectorBarHeight,
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
    required this.isPlaybackActive,
    required this.selected,
    required this.hasSelection,
    required this.hasMeasureContext,
    required this.selectedMeasureNumber,
    required this.currentPageIndex,
    required this.totalPages,
    required this.onPrevPage,
    required this.onNextPage,
    required this.onPageOverviewTap,
    required this.onMoveUp,
    required this.onMoveDown,
    required this.onWhole,
    required this.onHalf,
    required this.onQuarter,
    required this.onEighth,
    required this.onSixteenth,
    required this.onSetAccidental,
    required this.currentMeasureClef,
    required this.currentTimeSignature,
    required this.onSetTimeSignature,
    required this.onSetClef,
    required this.onMoveToPrev,
    required this.onMoveToNext,
    required this.onAddMeasure,
    required this.onAddPage,
    required this.canDeleteMeasure,
    required this.onDeleteMeasure,
    required this.onDeleteSymbol,
    required this.onToggleDot,
  });

  final bool isLandscape;
  final bool isPlaybackActive;
  final ScoreSymbol? selected;
  final bool hasSelection;
  final bool hasMeasureContext;
  final int? selectedMeasureNumber;
  final int currentPageIndex;
  final int totalPages;
  final VoidCallback? onPrevPage;
  final VoidCallback? onNextPage;
  final VoidCallback onPageOverviewTap;
  final VoidCallback onMoveUp;
  final VoidCallback onMoveDown;
  final VoidCallback onWhole;
  final VoidCallback onHalf;
  final VoidCallback onQuarter;
  final VoidCallback onEighth;
  final VoidCallback onSixteenth;
  final void Function(int? alter) onSetAccidental;
  final Clef? currentMeasureClef;
  final TimeSignature? currentTimeSignature;
  final ValueChanged<TimeSignature> onSetTimeSignature;
  final ValueChanged<Clef?> onSetClef;
  final VoidCallback onMoveToPrev;
  final VoidCallback onMoveToNext;
  final VoidCallback onAddMeasure;
  final VoidCallback onAddPage;
  final bool canDeleteMeasure;
  final VoidCallback onDeleteMeasure;
  final VoidCallback onDeleteSymbol;
  final VoidCallback onToggleDot;

  @override
  State<_InspectorPanel> createState() => _InspectorPanelState();
}

class _InspectorPanelState extends State<_InspectorPanel> {
  int? _activeGroupIndex;

  static const _groupIcons = [
    Icons.unfold_more_rounded,
    Icons.tag_rounded,
    Icons.music_note_rounded,
    Icons.av_timer_rounded,
    Icons.hourglass_empty_rounded,
    Icons.grid_on_rounded,
  ];

  @override
  void didUpdateWidget(_InspectorPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isPlaybackActive &&
        !oldWidget.isPlaybackActive &&
        _activeGroupIndex != null) {
      // Use post-frame to avoid calling setState during a build cycle.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) setState(() => _activeGroupIndex = null);
      });
    }
  }

  VoidCallback? _wrapAction(VoidCallback? action) =>
      widget.isPlaybackActive ? null : action;

  List<_ActionGroup> _buildGroups() {
    final isNoteSelected = widget.selected is Note;
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
            onPressed: _wrapAction(
              widget.hasSelection ? widget.onMoveUp : null,
            ),
          ),
          _ActionTile(
            icon: Icons.keyboard_arrow_down_rounded,
            label: 'Down',
            onPressed: _wrapAction(
              widget.hasSelection ? widget.onMoveDown : null,
            ),
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
          _DurTile(
            label: 'W',
            sublabel: 'Whole',
            isActive: currentType == 'whole',
            onPressed: _wrapAction(widget.hasSelection ? widget.onWhole : null),
          ),
          _DurTile(
            label: 'H',
            sublabel: 'Half',
            isActive: currentType == 'half',
            onPressed: _wrapAction(widget.hasSelection ? widget.onHalf : null),
          ),
          _DurTile(
            label: '♩',
            sublabel: 'Qtr',
            isActive: currentType == 'quarter',
            onPressed: _wrapAction(
              widget.hasSelection ? widget.onQuarter : null,
            ),
          ),
          _DurTile(
            label: '♪',
            sublabel: '8th',
            isActive: currentType == 'eighth',
            onPressed: _wrapAction(
              widget.hasSelection ? widget.onEighth : null,
            ),
          ),
          _DurTile(
            label: '♬',
            sublabel: '16th',
            isActive: currentType == 'sixteenth' || currentType == '16th',
            onPressed: _wrapAction(
              widget.hasSelection ? widget.onSixteenth : null,
            ),
          ),
          _DurTile(
            label: '.',
            sublabel: 'Dot',
            isActive: isDotted,
            onPressed: _wrapAction(
              canDot && widget.hasSelection ? widget.onToggleDot : null,
            ),
          ),
        ],
      ),
      _ActionGroup(
        label: 'MEASURE',
        children: [
          _ActionTile(
            icon: Icons.skip_previous_rounded,
            label: 'Prev',
            onPressed: _wrapAction(
              widget.hasSelection ? widget.onMoveToPrev : null,
            ),
          ),
          _ActionTile(
            icon: Icons.skip_next_rounded,
            label: 'Next',
            onPressed: _wrapAction(
              widget.hasSelection ? widget.onMoveToNext : null,
            ),
          ),
          _ActionTile(
            icon: Icons.add_rounded,
            label: 'Add',
            onPressed: _wrapAction(widget.onAddMeasure),
          ),
          _ActionTile(
            icon: Icons.add_box_rounded,
            label: 'Page',
            onPressed: _wrapAction(widget.onAddPage),
          ),
          _ActionTile(
            icon: Icons.remove_rounded,
            label: 'Del',
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

    final selectionCard = _SelectionCard(
      selected: widget.selected,
      hasSelection: widget.hasSelection,
      hasMeasureContext: widget.hasMeasureContext,
      selectedMeasureNumber: widget.selectedMeasureNumber,
      currentPageIndex: widget.currentPageIndex,
      totalPages: widget.totalPages,
      onPrevPage: widget.onPrevPage,
      onNextPage: widget.onNextPage,
      onPageOverviewTap: widget.onPageOverviewTap,
      compact: !widget.isLandscape,
    );

    if (widget.isLandscape) {
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
              ...groups.map(
                (g) => Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: _LandscapeGroup(group: g),
                ),
              ),
            ],
          ),
        ),
      );
    }

    // ── Portrait: bottom inspector bar ────────────────────────────────────
    return Stack(
      children: [
        // Barrier — tapping canvas dismisses the open popup
        if (_activeGroupIndex != null)
          Positioned.fill(
            child: GestureDetector(
              behavior: HitTestBehavior.translucent,
              onTap: () => setState(() => _activeGroupIndex = null),
            ),
          ),
        // Selection card — top of canvas
        Positioned(top: 8, left: 8, right: 8, child: selectionCard),
        // Active group popup — floats above the bottom bar
        if (_activeGroupIndex != null && !widget.isPlaybackActive)
          Positioned(
            left: 0,
            right: 0,
            bottom: _kInspectorBarHeight + 8,
            child: Center(
              child: _ToolGroupPopup(group: groups[_activeGroupIndex!]),
            ),
          ),
        // Bottom inspector bar
        Positioned(
          left: 0,
          right: 0,
          bottom: 0,
          child: _BottomInspectorBar(
            groups: groups,
            icons: _groupIcons,
            activeIndex: _activeGroupIndex,
            disabled: widget.isPlaybackActive,
            onGroupTap: (i) => setState(() {
              _activeGroupIndex = _activeGroupIndex == i ? null : i;
            }),
          ),
        ),
      ],
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

// ---------------------------------------------------------------------------
// Bottom inspector bar (portrait)
// ---------------------------------------------------------------------------

class _BottomInspectorBar extends StatelessWidget {
  const _BottomInspectorBar({
    required this.groups,
    required this.icons,
    required this.activeIndex,
    required this.onGroupTap,
    this.disabled = false,
  });

  final List<_ActionGroup> groups;
  final List<IconData> icons;
  final int? activeIndex;
  final ValueChanged<int> onGroupTap;
  final bool disabled;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: _kInspectorBarHeight,
      decoration: const BoxDecoration(
        color: AppColors.surface,
        border: Border(top: BorderSide(color: AppColors.border)),
        boxShadow: [
          BoxShadow(
            color: Color(0x33000000),
            blurRadius: 8,
            offset: Offset(0, -2),
          ),
        ],
      ),
      child: Row(
        children: List.generate(groups.length, (i) {
          final isActive = activeIndex == i;
          final iconColor = disabled
              ? AppColors.textSecondary.withValues(alpha: 0.3)
              : isActive
              ? AppColors.accent
              : AppColors.textSecondary;
          final label = groups[i].label;
          return Expanded(
            child: Semantics(
              button: true,
              selected: isActive,
              enabled: !disabled,
              label: '${label[0]}${label.substring(1).toLowerCase()} tools',
              excludeSemantics: true,
              child: GestureDetector(
                onTap: disabled ? null : () => onGroupTap(i),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 150),
                  decoration: BoxDecoration(
                    color: isActive && !disabled
                        ? AppColors.accent.withValues(alpha: 0.10)
                        : Colors.transparent,
                    border: Border(
                      top: BorderSide(
                        color: isActive && !disabled
                            ? AppColors.accent
                            : Colors.transparent,
                        width: 2,
                      ),
                    ),
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(icons[i], size: 20, color: iconColor),
                      const SizedBox(height: 2),
                      Text(
                        // Title case fits the narrow tabs at a readable size.
                        '${label[0]}${label.substring(1).toLowerCase()}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w600,
                          color: iconColor,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
        }),
      ),
    );
  }
}

class _ToolGroupPopup extends StatelessWidget {
  const _ToolGroupPopup({required this.group});

  final _ActionGroup group;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(maxWidth: 220),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.35),
            blurRadius: 14,
            offset: const Offset(-4, 0),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            group.label,
            style: const TextStyle(
              fontSize: 10,
              color: AppColors.textSecondary,
              letterSpacing: 1.0,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 8),
          Wrap(spacing: 4, runSpacing: 4, children: group.children),
        ],
      ),
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

// ---------------------------------------------------------------------------
// Selection card
// ---------------------------------------------------------------------------

class _SelectionCard extends StatelessWidget {
  const _SelectionCard({
    required this.selected,
    required this.hasSelection,
    required this.hasMeasureContext,
    required this.selectedMeasureNumber,
    required this.currentPageIndex,
    required this.totalPages,
    required this.onPrevPage,
    required this.onNextPage,
    required this.onPageOverviewTap,
    this.compact = false,
  });

  final ScoreSymbol? selected;
  final bool hasSelection;
  final bool hasMeasureContext;
  final int? selectedMeasureNumber;
  final int currentPageIndex;
  final int totalPages;
  final VoidCallback? onPrevPage;
  final VoidCallback? onNextPage;
  final VoidCallback onPageOverviewTap;
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
    final pageNav = _PageNav(
      currentPageIndex: currentPageIndex,
      totalPages: totalPages,
      onPrev: onPrevPage,
      onNext: onNextPage,
      onPageOverviewTap: onPageOverviewTap,
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
                        _isNote
                            ? Icons.music_note_rounded
                            : Icons.horizontal_rule_rounded,
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
                        style: const TextStyle(
                          color: AppColors.textSecondary,
                          fontSize: 11,
                        ),
                      ),
                    ),
                  ] else
                    Expanded(
                      child: Text(
                        hasMeasureContext && selectedMeasureNumber != null
                            ? 'Measure $selectedMeasureNumber selected'
                            : 'Tap a symbol to select',
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: AppColors.textSecondary,
                          fontSize: 12,
                        ),
                      ),
                    ),
                ],
              ),
            ),
            pageNav,
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
              pageNav,
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
                    _isNote
                        ? Icons.music_note_rounded
                        : Icons.horizontal_rule_rounded,
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
                      style: const TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
              ],
            )
          else
            Text(
              hasMeasureContext && selectedMeasureNumber != null
                  ? 'Measure $selectedMeasureNumber selected. Tap a note or rest to edit a symbol.'
                  : 'Tap a note or rest to select it',
              style: TextStyle(color: AppColors.textSecondary, fontSize: 12),
            ),
        ],
      ),
    );
  }
}

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
    final activeColor = danger
        ? const Color(0xFFEF4444)
        : AppColors.textPrimary;
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
    );
  }
}

class _ClefTile extends StatelessWidget {
  const _ClefTile({
    required this.shortLabel,
    required this.label,
    required this.isActive,
    required this.onPressed,
  });

  final String shortLabel;
  final String label;
  final bool isActive;
  final VoidCallback? onPressed;

  static const _accent = Color(0xFFD4A96A);

  @override
  Widget build(BuildContext context) {
    final enabled = onPressed != null;

    return Tooltip(
      message: label,
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(8),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          width: 48,
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
