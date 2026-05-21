import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:note_vision/core/utils/emoji_blocking_formatter.dart';
import 'package:note_vision/core/config/app_features.dart';
import 'package:note_vision/core/models/clef.dart';
import 'package:note_vision/core/models/key_signature.dart';
import 'package:note_vision/core/models/measure.dart';
import 'package:note_vision/core/models/part.dart';
import 'package:note_vision/core/models/project.dart';
import 'package:note_vision/core/models/score.dart';
import 'package:note_vision/core/models/time_signature.dart';
import 'package:note_vision/core/services/project_storage_service.dart';
import 'package:note_vision/core/services/nvscore_export_service.dart';
import 'package:note_vision/core/services/incoming_file_service.dart';
import 'package:note_vision/core/services/nvscore_import_service.dart';
import 'package:note_vision/core/services/score_classifier.dart';
import 'package:note_vision/core/services/user_profile_service.dart';
import 'package:note_vision/core/theme/app_theme.dart';
import 'package:note_vision/core/theme/responsive_layout.dart';
import 'package:note_vision/core/widgets/drawer.dart';
import 'package:note_vision/core/widgets/user_avatar.dart';
import 'package:note_vision/features/capture/presentation/capture_screen.dart';
import 'package:note_vision/features/capture/presentation/import_score_screen.dart';
import 'package:note_vision/features/editor/model/editor_state.dart';
import 'package:note_vision/features/editor/presentation/editor_shell_screen.dart';

import 'widgets/empty_collection.dart';
import 'widgets/score_card.dart';

enum _CollectionFilter { recent, myScores, submissions, feedback }

class CollectionScreen extends StatefulWidget {
  final ProjectStorageService? storageService;

  const CollectionScreen({super.key, this.storageService});

  @override
  State<CollectionScreen> createState() => _CollectionScreenState();
}

class _CollectionScreenState extends State<CollectionScreen>
    with SingleTickerProviderStateMixin {
  List<Project> _projects = [];
  bool _isLoading = true;
  bool _fabOpen = false;
  UserProfile? _userProfile;
  String? _role;
  _CollectionFilter _filter = _CollectionFilter.recent;

  late final ProjectStorageService _storage;
  late AnimationController _fadeController;
  late Animation<double> _fadeIn;
  StreamSubscription<String>? _incomingFileSub;

  @override
  void initState() {
    super.initState();
    SystemChrome.setSystemUIOverlayStyle(
      const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.light,
      ),
    );

    _storage = widget.storageService ?? ProjectStorageService();

    _fadeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    );
    _fadeIn = CurvedAnimation(parent: _fadeController, curve: Curves.easeOut);

    _loadProjects();
    _loadProfile();

    if (AppFeatures.classroomWorkflow) {
      _incomingFileSub = IncomingFileService.instance.filePathStream
          .listen(_handleIncomingFile);
    }
  }

  @override
  void dispose() {
    _incomingFileSub?.cancel();
    _fadeController.dispose();
    super.dispose();
  }

  Future<void> _loadProfile() async {
    final profile = await UserProfileService.loadProfile();
    final role = AppFeatures.classroomWorkflow
        ? await UserProfileService.loadRole()
        : null;
    if (mounted) {
      final availableFilters = !AppFeatures.classroomWorkflow
          ? const [_CollectionFilter.recent]
          : role == 'teacher'
          ? const [
              _CollectionFilter.recent,
              _CollectionFilter.myScores,
              _CollectionFilter.submissions,
            ]
          : const [
              _CollectionFilter.recent,
              _CollectionFilter.myScores,
              _CollectionFilter.feedback,
            ];
      setState(() {
        _userProfile = profile;
        _role = role;
        if (!availableFilters.contains(_filter)) {
          _filter = _CollectionFilter.recent;
        }
      });
    }
  }

  Future<void> _handleIncomingFile(String path) async {
    try {
      final imported = await NvscoreImportService(storageService: _storage)
          .importFromPath(path, beforeSave: _isTeacher ? null : _copyForStudentImport);
      if (!mounted || imported == null) return;
      setState(() => _projects.insert(0, imported));
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('"${imported.name}" imported.')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not import file.')),
      );
    }
  }

  Future<void> _loadProjects() async {
    try {
      final projects = await _storage.loadAllProjects();
      if (mounted) {
        setState(() {
          _projects = projects;
          _isLoading = false;
        });
        _fadeController.forward(from: 0);
      }
    } catch (e) {
      debugPrint('CollectionScreen: failed to load projects: $e');
      if (mounted) setState(() => _isLoading = false);
    }
  }

  bool get _isTeacher => AppFeatures.classroomWorkflow && _role == 'teacher';

  bool _isSubmission(Project project) =>
      AppFeatures.classroomWorkflow &&
      (project.submittedBy?.trim().isNotEmpty ?? false);

  bool _hasTeacherComments(Project project) =>
      AppFeatures.classroomWorkflow &&
      (project.teacherComments?.isNotEmpty ?? false);

  List<Project> get _teacherScores =>
      _projects.where((project) => !_isSubmission(project)).toList();

  List<Project> get _studentSubmissions =>
      _projects.where(_isSubmission).toList();

  List<Project> get _studentScores =>
      _projects.where((project) => !_hasTeacherComments(project)).toList();

  List<Project> get _studentFeedback =>
      _projects.where(_hasTeacherComments).toList();

  List<Project> get _filteredStudentProjects {
    if (!AppFeatures.classroomWorkflow) return _projects;
    return switch (_filter) {
      _CollectionFilter.feedback => _studentFeedback,
      _CollectionFilter.myScores => _studentScores,
      _ => _projects,
    };
  }

  List<Project> get _exportableProjects {
    if (!AppFeatures.classroomWorkflow) return _projects;
    if (_isTeacher) {
      return switch (_filter) {
        _CollectionFilter.myScores => _teacherScores,
        _CollectionFilter.submissions => _studentSubmissions,
        _ => _projects,
      };
    }
    return _filteredStudentProjects;
  }

  String get _filterLabel => switch (_filter) {
    _CollectionFilter.recent => 'Recent',
    _CollectionFilter.myScores => 'My Scores',
    _CollectionFilter.submissions => 'Submissions',
    _CollectionFilter.feedback => 'Feedback',
  };

  List<_CollectionFilter> get _availableFilters {
    if (!AppFeatures.classroomWorkflow) {
      return const [_CollectionFilter.recent];
    }
    return _isTeacher
        ? const [
            _CollectionFilter.recent,
            _CollectionFilter.myScores,
            _CollectionFilter.submissions,
          ]
        : const [
            _CollectionFilter.recent,
            _CollectionFilter.myScores,
            _CollectionFilter.feedback,
          ];
  }

  Future<void> _openProject(
    Project project, {
    bool reviewMode = false,
    bool canEditTeacherComments = true,
  }) async {
    final Score score;
    try {
      score = project.decodeScore();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Could not open project — file may be corrupted.'),
        ),
      );
      return;
    }

    if (!mounted) return;
    await Navigator.pushNamed(
      context,
      EditorShellScreen.routeName,
      arguments: EditorShellArgs(
        score: score,
        initialState: EditorState(score: score),
        existingProject: project,
        reviewMode: reviewMode,
        canEditTeacherComments: canEditTeacherComments,
      ),
    );
    if (mounted) _loadProjects();
  }

  Future<Project> _copyForStudentImport(Project project) async {
    final currentUserId = await UserProfileService.loadOrCreateUserId();
    final submittedById = project.submittedById?.trim();
    if (submittedById != null &&
        submittedById.isNotEmpty &&
        submittedById != currentUserId) {
      throw const FormatException(
        'This score was submitted by another student.',
      );
    }

    final now = DateTime.now();
    final feedbackName = _hasTeacherComments(project)
        ? '${project.name} Feedback'
        : project.name;
    return Project(
      id: '${now.microsecondsSinceEpoch}_${project.id}',
      name: feedbackName,
      createdAt: now,
      updatedAt: now,
      scoreJson: project.scoreJson,
      submittedBy: project.submittedBy,
      submittedById: project.submittedById,
      teacherComments: project.teacherComments,
    );
  }

  Future<void> _importNvscoreProject() async {
    setState(() => _fabOpen = false);

    try {
      final imported = await NvscoreImportService(
        storageService: _storage,
      ).importProject(beforeSave: _isTeacher ? null : _copyForStudentImport);
      if (!mounted || imported == null) return;

      await _loadProjects();
      if (!mounted) return;
      final destination = !_isTeacher && _hasTeacherComments(imported)
          ? 'Teacher Feedback'
          : _isSubmission(imported)
          ? 'Student Submissions'
          : 'My Scores';
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Imported to $destination.')));
    } catch (e) {
      debugPrint('CollectionScreen: failed to import .nvscore: $e');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not import that score file.')),
      );
    }
  }

  Future<void> _exportAllNvscoreProjects() async {
    setState(() => _fabOpen = false);
    final projects = _exportableProjects;
    if (projects.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _isTeacher
                ? 'There are no $_filterLabel projects to export.'
                : 'There are no $_filterLabel scores to export.',
          ),
        ),
      );
      return;
    }

    try {
      final path = await const NvscoreExportService().exportAllProjects(
        projects,
        fileName: NvscoreExportService.collectionZipFileName(
          role: _isTeacher ? 'teacher' : 'student',
          filter: _filterLabel,
        ),
      );
      if (!mounted || path == null) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Scores exported as a ZIP file.')),
      );
    } catch (e) {
      debugPrint('CollectionScreen: failed to export all scores: $e');
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Could not export scores.')));
    }
  }

  Future<void> _deleteProject(Project project) async {
    await _storage.deleteProject(project.id);
    if (mounted) {
      setState(() => _projects.removeWhere((p) => p.id == project.id));
    }
  }

  Future<void> _renameProject(Project project) async {
    final newName = await showDialog<String>(
      context: context,
      builder: (_) => _RenameProjectDialog(initialName: project.name),
    );

    if (newName == null || newName.isEmpty || newName == project.name) return;

    final renamed = project.copyWithUpdated(name: newName);
    await _storage.saveProject(renamed);
    if (!mounted) return;
    setState(() {
      final index = _projects.indexWhere((p) => p.id == project.id);
      if (index >= 0) _projects[index] = renamed;
    });
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Project renamed.')));
  }

  Future<void> _exportProject(Project project) async {
    try {
      final path = await const NvscoreExportService().exportProject(
        project,
        fileName: await _exportFileNameFor(project),
      );
      if (!mounted || path == null) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Score exported.')));
    } catch (e) {
      debugPrint('CollectionScreen: failed to export score: $e');
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Could not export score.')));
    }
  }

  Future<String> _exportFileNameFor(Project project) async {
    if (!AppFeatures.classroomWorkflow) return project.name;
    if (_hasTeacherComments(project)) {
      return NvscoreExportService.feedbackFileName(project);
    }
    if (_isTeacher) return project.name;

    final profile = _userProfile ?? await UserProfileService.loadProfile();
    final studentName = profile?.name.trim();
    if (studentName == null || studentName.isEmpty) return project.name;

    return NvscoreExportService.submissionFileName(
      project: project,
      studentName: studentName,
      studentId: await UserProfileService.loadOrCreateUserId(),
    );
  }

  void _goToCapture() {
    setState(() => _fabOpen = false);
    Navigator.push(
      context,
      PageRouteBuilder(
        pageBuilder: (_, _, _) => const CaptureScreen(),
        transitionsBuilder: (_, animation, _, child) =>
            FadeTransition(opacity: animation, child: child),
        transitionDuration: const Duration(milliseconds: 400),
      ),
    ).then((_) => _loadProjects());
  }

  void _goToImport() {
    setState(() => _fabOpen = false);
    Navigator.push(
      context,
      PageRouteBuilder(
        pageBuilder: (_, _, _) => const ImportScoreScreen(),
        transitionsBuilder: (_, animation, _, child) =>
            FadeTransition(opacity: animation, child: child),
        transitionDuration: const Duration(milliseconds: 400),
      ),
    ).then((_) => _loadProjects());
  }

  Future<void> _showNewScoreDialog() async {
    setState(() => _fabOpen = false);
    final result = await showDialog<Map<String, String>>(
      context: context,
      builder: (_) => const _NewScoreDialog(),
    );
    if (result == null || !mounted) return;
    final score = _createBlankScore(
      title: result['title']!,
      composer: result['composer']!,
    );
    await Navigator.pushNamed(
      context,
      EditorShellScreen.routeName,
      arguments: EditorShellArgs(
        score: score,
        initialState: EditorState(score: score),
      ),
    );
    if (mounted) _loadProjects();
  }

  Score _createBlankScore({required String title, required String composer}) {
    const trebleClef = Clef(sign: 'G', line: 2);
    const commonTime = TimeSignature(beats: 4, beatType: 4);
    const cMajor = KeySignature(fifths: 0);
    return Score(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      title: title.isEmpty ? 'Untitled' : title,
      composer: composer,
      parts: [
        Part(
          id: 'P1',
          name: 'Part 1',
          measures: [
            const Measure(
              number: 1,
              clef: trebleClef,
              timeSignature: commonTime,
              keySignature: cMajor,
              symbols: [],
            ),
            const Measure(number: 2, symbols: []),
            const Measure(number: 3, symbols: []),
            const Measure(number: 4, symbols: []),
          ],
        ),
      ],
    );
  }

  String _formatDate(DateTime dt) {
    const months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    return '${months[dt.month - 1]} ${dt.day}, ${dt.year}';
  }

  String _labelForFilter(_CollectionFilter filter) => switch (filter) {
    _CollectionFilter.recent => 'Recent',
    _CollectionFilter.myScores => 'My Scores',
    _CollectionFilter.submissions => 'Student Submissions',
    _CollectionFilter.feedback => 'Teacher Feedback',
  };

  Widget _buildBody() {
    if (_isLoading) {
      return const Center(
        child: CircularProgressIndicator(
          color: AppColors.accent,
          strokeWidth: 2,
        ),
      );
    }

    if (_projects.isEmpty && !_isTeacher) {
      return FadeTransition(
        opacity: _fadeIn,
        child: EmptyCollection(
          onAddPressed: _goToCapture,
          onImportPressed: _goToImport,
          onNewScorePressed: _showNewScoreDialog,
        ),
      );
    }

    return FadeTransition(
      opacity: _fadeIn,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final horizontalPadding = ResponsiveLayout.horizontalPadding(
            constraints.maxWidth,
          );

          if (_isTeacher) {
            return _buildTeacherBody(horizontalPadding);
          }

          final displayedProjects = _filteredStudentProjects;

          return CustomScrollView(
            slivers: [
              SliverToBoxAdapter(
                child: Padding(
                  padding: EdgeInsets.fromLTRB(
                    horizontalPadding,
                    20,
                    horizontalPadding,
                    12,
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        '${displayedProjects.length} ${displayedProjects.length == 1 ? 'project' : 'projects'}',
                        style: const TextStyle(
                          fontSize: 13,
                          color: AppColors.textSecondary,
                          letterSpacing: 0.3,
                        ),
                      ),
                      if (_availableFilters.length > 1)
                        _CollectionFilterButton(
                          label: _filterLabel,
                          filters: _availableFilters,
                          activeFilter: _filter,
                          labelFor: _labelForFilter,
                          onSelected: (filter) => setState(() {
                            _filter = filter;
                          }),
                        ),
                    ],
                  ),
                ),
              ),
              if (displayedProjects.isEmpty)
                _SectionPlaceholderSliver(
                  horizontalPadding: horizontalPadding,
                  text: _filter == _CollectionFilter.feedback
                      ? 'Imported teacher feedback appears here.'
                      : 'No scores match this filter.',
                )
              else
                _ProjectListSliver(
                  horizontalPadding: horizontalPadding,
                  projects: displayedProjects,
                  formatDate: _formatDate,
                  onOpen: (project) => _openProject(
                    project,
                    reviewMode:
                        AppFeatures.classroomWorkflow &&
                        _hasTeacherComments(project),
                    canEditTeacherComments: false,
                  ),
                  onRename: _renameProject,
                  onExport: _exportProject,
                  onDelete: _deleteProject,
                ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildTeacherBody(double horizontalPadding) {
    final myScores = _teacherScores;
    final submissions = _studentSubmissions;
    final showMyScores =
        _filter == _CollectionFilter.recent ||
        _filter == _CollectionFilter.myScores;
    final showSubmissions =
        _filter == _CollectionFilter.recent ||
        _filter == _CollectionFilter.submissions;
    final groupedSubmissions = <String, List<Project>>{};
    for (final project in submissions) {
      final studentName = project.submittedBy!.trim();
      groupedSubmissions.putIfAbsent(studentName, () => []).add(project);
    }

    return CustomScrollView(
      slivers: [
        SliverToBoxAdapter(
          child: Padding(
            padding: EdgeInsets.fromLTRB(
              horizontalPadding,
              20,
              horizontalPadding,
              12,
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    '${myScores.length} ${myScores.length == 1 ? 'score' : 'scores'} · '
                    '${submissions.length} ${submissions.length == 1 ? 'submission' : 'submissions'}',
                    style: const TextStyle(
                      fontSize: 13,
                      color: AppColors.textSecondary,
                      letterSpacing: 0.3,
                    ),
                  ),
                ),
                _CollectionFilterButton(
                  label: _filterLabel,
                  filters: _availableFilters,
                  activeFilter: _filter,
                  labelFor: _labelForFilter,
                  onSelected: (filter) => setState(() {
                    _filter = filter;
                  }),
                ),
              ],
            ),
          ),
        ),
        if (showMyScores) ...[
          _SectionHeaderSliver(
            horizontalPadding: horizontalPadding,
            title: 'My Scores',
            count: myScores.length,
          ),
          if (myScores.isEmpty)
            _SectionPlaceholderSliver(
              horizontalPadding: horizontalPadding,
              text: 'Create or import a score to start your collection.',
            )
          else
            _ProjectListSliver(
              horizontalPadding: horizontalPadding,
              projects: myScores,
              formatDate: _formatDate,
              onOpen: (project) => _openProject(project),
              onRename: _renameProject,
              onExport: _exportProject,
              onDelete: _deleteProject,
            ),
        ],
        if (showSubmissions) ...[
          _SectionHeaderSliver(
            horizontalPadding: horizontalPadding,
            title: 'Student Submissions',
            count: submissions.length,
          ),
          if (submissions.isEmpty)
            _SectionPlaceholderSliver(
              horizontalPadding: horizontalPadding,
              text: 'Imported student files appear here automatically.',
            )
          else
            for (final entry in groupedSubmissions.entries) ...[
              SliverToBoxAdapter(
                child: Padding(
                  padding: EdgeInsets.fromLTRB(
                    horizontalPadding + 16,
                    8,
                    horizontalPadding + 16,
                    4,
                  ),
                  child: Text(
                    entry.key,
                    style: const TextStyle(
                      color: AppColors.accent,
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
              _ProjectListSliver(
                horizontalPadding: horizontalPadding,
                projects: entry.value,
                formatDate: _formatDate,
                onOpen: (project) => _openProject(
                  project,
                  reviewMode: true,
                  canEditTeacherComments: true,
                ),
                onRename: _renameProject,
                onExport: _exportProject,
                onDelete: _deleteProject,
              ),
            ],
        ],
        const SliverToBoxAdapter(child: SizedBox(height: 24)),
      ],
    );
  }

  PreferredSizeWidget _buildAppBarBottom(
    bool isLandscape,
    double horizontalPadding,
  ) {
    return PreferredSize(
      preferredSize: Size.fromHeight(isLandscape ? 42 : 48),
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          horizontalPadding,
          0,
          horizontalPadding,
          isLandscape ? 8 : 12,
        ),
        child: Text(
          'MY COLLECTION',
          style: TextStyle(
            fontSize: isLandscape ? 10 : 11,
            fontWeight: FontWeight.w600,
            color: AppColors.textSecondary,
            letterSpacing: 2.0,
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final orientation = MediaQuery.of(context).orientation;
    final isLandscape = orientation == Orientation.landscape;
    final horizontalPadding = ResponsiveLayout.horizontalPadding(
      MediaQuery.of(context).size.width,
    );

    return Scaffold(
      key: const ValueKey('collectionAppBar'),
      backgroundColor: AppColors.background,
      onEndDrawerChanged: (isOpen) {
        if (!isOpen) {
          _loadProfile();
          _loadProjects();
        }
      },
      endDrawer: const CollectionDrawer(),
      appBar: AppBar(
        leading: Padding(
          padding: EdgeInsets.only(left: horizontalPadding),
          child: Image.asset(
            'assets/images/notevision.png',
            height: 28,
            colorBlendMode: BlendMode.srcIn,
          ),
        ),
        title: Text(
          'Note Vision',
          style: TextStyle(
            fontFamily: 'PlayfairDisplay',
            fontSize: isLandscape ? 20 : 22,
            color: AppColors.textPrimary,
            letterSpacing: 0.5,
          ),
        ),
        centerTitle: true,
        bottom: _buildAppBarBottom(isLandscape, horizontalPadding),
        actions: [
          Builder(
            builder: (context) => Padding(
              padding: const EdgeInsets.only(right: 12),
              child: GestureDetector(
                onTap: () => Scaffold.of(context).openEndDrawer(),
                child: _userProfile != null
                    ? UserAvatar(
                        initial: _userProfile!.initial,
                        photoPath: _userProfile!.photoPath,
                        size: 28,
                        borderColor: AppColors.accent.withValues(alpha: 0.5),
                        borderWidth: 1.5,
                      )
                    : const Icon(
                        Icons.person_rounded,
                        color: AppColors.textPrimary,
                        size: 24,
                      ),
              ),
            ),
          ),
        ],
      ),
      body: Stack(
        children: [
          _buildBody(),
          if (_fabOpen)
            Positioned.fill(
              child: GestureDetector(
                onTap: () => setState(() => _fabOpen = false),
                child: const ColoredBox(color: Colors.transparent),
              ),
            ),
        ],
      ),
      floatingActionButton: _SpeedDialFab(
        isOpen: _fabOpen,
        onToggle: () => setState(() => _fabOpen = !_fabOpen),
        items: [
          if (AppFeatures.classroomWorkflow && _isTeacher)
            _SpeedDialItem(
              icon: Icons.file_open_rounded,
              label: 'Import Score',
              onTap: _importNvscoreProject,
            ),
          if (AppFeatures.classroomWorkflow && !_isTeacher)
            _SpeedDialItem(
              icon: Icons.rate_review_rounded,
              label: 'Import Feedback',
              onTap: _importNvscoreProject,
            ),
          if (AppFeatures.classroomWorkflow)
            _SpeedDialItem(
              icon: Icons.archive_rounded,
              label: 'Export All',
              onTap: _exportAllNvscoreProjects,
            ),
          _SpeedDialItem(
            icon: Icons.note_add_rounded,
            label: 'New Score',
            onTap: _showNewScoreDialog,
          ),
          _SpeedDialItem(
            icon: Icons.upload_file_outlined,
            label: 'Import MusicXML',
            onTap: _goToImport,
          ),
          _SpeedDialItem(
            icon: Icons.camera_alt_rounded,
            label: 'Scan Image',
            onTap: _goToCapture,
          ),
        ],
      ),
    );
  }
}

class _CollectionFilterButton extends StatelessWidget {
  const _CollectionFilterButton({
    required this.label,
    required this.filters,
    required this.activeFilter,
    required this.labelFor,
    required this.onSelected,
  });

  final String label;
  final List<_CollectionFilter> filters;
  final _CollectionFilter activeFilter;
  final String Function(_CollectionFilter filter) labelFor;
  final ValueChanged<_CollectionFilter> onSelected;

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<_CollectionFilter>(
      onSelected: onSelected,
      tooltip: 'Filter',
      color: AppColors.surface,
      itemBuilder: (_) => filters
          .map(
            (filter) => PopupMenuItem(
              value: filter,
              child: Row(
                children: [
                  Icon(
                    filter == activeFilter
                        ? Icons.radio_button_checked_rounded
                        : Icons.radio_button_unchecked_rounded,
                    size: 15,
                    color: filter == activeFilter
                        ? AppColors.accent
                        : AppColors.textSecondary,
                  ),
                  const SizedBox(width: 9),
                  Text(
                    labelFor(filter),
                    style: TextStyle(
                      color: filter == activeFilter
                          ? AppColors.accent
                          : AppColors.textPrimary,
                      fontSize: 13,
                    ),
                  ),
                ],
              ),
            ),
          )
          .toList(),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: AppColors.border),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.filter_list_rounded,
              size: 13,
              color: AppColors.textSecondary,
            ),
            const SizedBox(width: 4),
            Text(
              label,
              style: const TextStyle(
                fontSize: 12,
                color: AppColors.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SectionHeaderSliver extends StatelessWidget {
  const _SectionHeaderSliver({
    required this.horizontalPadding,
    required this.title,
    required this.count,
  });

  final double horizontalPadding;
  final String title;
  final int count;

  @override
  Widget build(BuildContext context) {
    return SliverToBoxAdapter(
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          horizontalPadding + 16,
          18,
          horizontalPadding + 16,
          8,
        ),
        child: Row(
          children: [
            Text(
              title,
              style: const TextStyle(
                color: AppColors.textPrimary,
                fontSize: 16,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
              decoration: BoxDecoration(
                color: AppColors.accent.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(999),
              ),
              child: Text(
                '$count',
                style: const TextStyle(
                  color: AppColors.accent,
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SectionPlaceholderSliver extends StatelessWidget {
  const _SectionPlaceholderSliver({
    required this.horizontalPadding,
    required this.text,
  });

  final double horizontalPadding;
  final String text;

  @override
  Widget build(BuildContext context) {
    return SliverToBoxAdapter(
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          horizontalPadding + 16,
          8,
          horizontalPadding + 16,
          8,
        ),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 16),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: AppColors.border),
          ),
          child: Text(
            text,
            style: const TextStyle(
              color: AppColors.textSecondary,
              fontSize: 13,
            ),
          ),
        ),
      ),
    );
  }
}

class _ProjectListSliver extends StatelessWidget {
  const _ProjectListSliver({
    required this.horizontalPadding,
    required this.projects,
    required this.formatDate,
    required this.onOpen,
    required this.onRename,
    required this.onExport,
    required this.onDelete,
  });

  final double horizontalPadding;
  final List<Project> projects;
  final String Function(DateTime) formatDate;
  final ValueChanged<Project> onOpen;
  final ValueChanged<Project> onRename;
  final ValueChanged<Project> onExport;
  final ValueChanged<Project> onDelete;

  @override
  Widget build(BuildContext context) {
    return SliverPadding(
      padding: EdgeInsets.only(
        left: horizontalPadding,
        right: horizontalPadding,
        bottom: 16,
      ),
      sliver: SliverGrid(
        gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
          maxCrossAxisExtent: 320,
          mainAxisSpacing: 14,
          crossAxisSpacing: 14,
          childAspectRatio: 0.76,
        ),
        delegate: SliverChildBuilderDelegate((context, index) {
          final project = projects[index];
          final score = _decodeScore(project);
          final scoreLabel = score == null
              ? ScoreLabel.generalPiece
              : ScoreClassifier.classify(score);

          return ScoreCard(
            imagePath: '',
            score: score,
            title: project.name,
            composer: score?.composer,
            scoreLabel: scoreLabel.displayName,
            updatedLabel: formatDate(project.updatedAt),
            onOpen: () => onOpen(project),
            onRename: () => onRename(project),
            onExport: () => onExport(project),
            onDelete: () => onDelete(project),
          );
        }, childCount: projects.length),
      ),
    );
  }

  Score? _decodeScore(Project project) {
    try {
      return project.decodeScore();
    } catch (_) {
      return null;
    }
  }
}

// ── Speed dial FAB ────────────────────────────────────────────────────────────

class _SpeedDialItem {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _SpeedDialItem({
    required this.icon,
    required this.label,
    required this.onTap,
  });
}

class _SpeedDialFab extends StatelessWidget {
  const _SpeedDialFab({
    required this.isOpen,
    required this.onToggle,
    required this.items,
  });

  final bool isOpen;
  final VoidCallback onToggle;
  final List<_SpeedDialItem> items;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        AnimatedSize(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOut,
          alignment: Alignment.bottomRight,
          child: isOpen
              ? Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    for (final item in items)
                      AnimatedSlide(
                        offset: Offset.zero,
                        duration: const Duration(milliseconds: 200),
                        curve: Curves.easeOut,
                        child: AnimatedOpacity(
                          opacity: 1,
                          duration: const Duration(milliseconds: 180),
                          child: Padding(
                            padding: const EdgeInsets.only(bottom: 10),
                            child: _MiniFabRow(item: item),
                          ),
                        ),
                      ),
                  ],
                )
              : const SizedBox.shrink(),
        ),
        FloatingActionButton(
          heroTag: 'main_fab',
          onPressed: onToggle,
          backgroundColor: AppColors.accent,
          elevation: 4,
          child: AnimatedRotation(
            turns: isOpen ? 0.125 : 0,
            duration: const Duration(milliseconds: 200),
            child: const Icon(
              Icons.add_rounded,
              color: AppColors.background,
              size: 28,
            ),
          ),
        ),
      ],
    );
  }
}

class _MiniFabRow extends StatelessWidget {
  const _MiniFabRow({required this.item});

  final _SpeedDialItem item;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: AppColors.border),
            boxShadow: const [
              BoxShadow(
                color: Color(0x40000000),
                blurRadius: 8,
                offset: Offset(0, 2),
              ),
            ],
          ),
          child: Text(
            item.label,
            style: const TextStyle(
              color: AppColors.textPrimary,
              fontSize: 13,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
        const SizedBox(width: 10),
        FloatingActionButton.small(
          heroTag: item.label,
          onPressed: item.onTap,
          backgroundColor: AppColors.surface,
          elevation: 2,
          child: Icon(item.icon, size: 20, color: AppColors.accent),
        ),
      ],
    );
  }
}

class _RenameProjectDialog extends StatefulWidget {
  const _RenameProjectDialog({required this.initialName});

  final String initialName;

  @override
  State<_RenameProjectDialog> createState() => _RenameProjectDialogState();
}

class _RenameProjectDialogState extends State<_RenameProjectDialog> {
  late final TextEditingController _controller;
  String? _errorText;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialName);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    final trimmed = _controller.text.trim();
    if (trimmed.isEmpty) {
      setState(() => _errorText = 'Name cannot be empty');
      return;
    }
    Navigator.of(context).pop(trimmed);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: AppColors.surface,
      title: const Text(
        'Rename project',
        style: TextStyle(color: AppColors.textPrimary),
      ),
      content: TextField(
        controller: _controller,
        autofocus: true,
        maxLength: 60,
        style: const TextStyle(color: AppColors.textPrimary),
        inputFormatters: [
          EmojiBlockingFormatter(onBlocked: () {
            setState(() => _errorText = 'Emoji not allowed');
          }),
        ],
        buildCounter: (_, {required currentLength, required isFocused, maxLength}) {
          if (maxLength == null || currentLength <= maxLength - 20) return null;
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
        onChanged: (_) {
          if (_errorText != null) setState(() => _errorText = null);
        },
        onSubmitted: (_) => _submit(),
        decoration: InputDecoration(
          labelText: 'Project name',
          errorText: _errorText,
          labelStyle: const TextStyle(color: AppColors.textSecondary),
          enabledBorder: const UnderlineInputBorder(
            borderSide: BorderSide(color: AppColors.border),
          ),
          focusedBorder: const UnderlineInputBorder(
            borderSide: BorderSide(color: AppColors.accent),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text(
            'Cancel',
            style: TextStyle(color: AppColors.textSecondary),
          ),
        ),
        TextButton(
          onPressed: _submit,
          child: const Text(
            'Rename',
            style: TextStyle(
              color: AppColors.accent,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    );
  }
}

// ── New Score dialog ──────────────────────────────────────────────────────────

class _NewScoreDialog extends StatefulWidget {
  const _NewScoreDialog();

  @override
  State<_NewScoreDialog> createState() => _NewScoreDialogState();
}

class _NewScoreDialogState extends State<_NewScoreDialog> {
  final _titleController = TextEditingController();
  final _composerController = TextEditingController();

  @override
  void dispose() {
    _titleController.dispose();
    _composerController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: AppColors.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: const Text(
        'New Score',
        style: TextStyle(
          color: AppColors.textPrimary,
          fontWeight: FontWeight.w600,
          fontSize: 17,
        ),
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _DialogTextField(
            controller: _titleController,
            label: 'Title',
            hint: 'Untitled',
            autofocus: true,
            maxLength: 100,
          ),
          const SizedBox(height: 16),
          _DialogTextField(
            controller: _composerController,
            label: 'Composer',
            hint: 'Unknown',
            maxLength: 100,
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text(
            'Cancel',
            style: TextStyle(color: AppColors.textSecondary),
          ),
        ),
        TextButton(
          onPressed: () => Navigator.of(context).pop({
            'title': _titleController.text.trim(),
            'composer': _composerController.text.trim(),
          }),
          child: const Text(
            'Create',
            style: TextStyle(
              color: AppColors.accent,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    );
  }
}

class _DialogTextField extends StatefulWidget {
  const _DialogTextField({
    required this.controller,
    required this.label,
    required this.hint,
    this.autofocus = false,
    this.maxLength,
  });

  final TextEditingController controller;
  final String label;
  final String hint;
  final bool autofocus;
  final int? maxLength;

  @override
  State<_DialogTextField> createState() => _DialogTextFieldState();
}

class _DialogTextFieldState extends State<_DialogTextField> {
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
      mainAxisSize: MainAxisSize.min,
      children: [
        TextField(
          controller: widget.controller,
          autofocus: widget.autofocus,
          maxLength: widget.maxLength,
          inputFormatters: [
            EmojiBlockingFormatter(onBlocked: _onEmojiBlocked),
          ],
          buildCounter: (_, {required currentLength, required isFocused, maxLength}) {
            if (maxLength == null || currentLength <= maxLength - 20) return null;
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
            labelText: widget.label,
            hintText: widget.hint,
            labelStyle: const TextStyle(
              color: AppColors.textSecondary,
              fontSize: 13,
            ),
            hintStyle: TextStyle(
              color: AppColors.textSecondary.withValues(alpha: 0.5),
            ),
            errorText: _emojiError,
            enabledBorder: const UnderlineInputBorder(
              borderSide: BorderSide(color: AppColors.border),
            ),
            focusedBorder: const UnderlineInputBorder(
              borderSide: BorderSide(color: AppColors.accent),
            ),
          ),
        ),
      ],
    );
  }
}
