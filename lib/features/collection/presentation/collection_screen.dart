import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:note_vision/core/models/clef.dart';
import 'package:note_vision/core/models/key_signature.dart';
import 'package:note_vision/core/models/measure.dart';
import 'package:note_vision/core/models/part.dart';
import 'package:note_vision/core/models/project.dart';
import 'package:note_vision/core/models/score.dart';
import 'package:note_vision/core/models/time_signature.dart';
import 'package:note_vision/core/services/project_storage_service.dart';
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

  late final ProjectStorageService _storage;
  late AnimationController _fadeController;
  late Animation<double> _fadeIn;

  @override
  void initState() {
    super.initState();
    SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
    ));

    _storage = widget.storageService ?? ProjectStorageService();

    _fadeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    );
    _fadeIn = CurvedAnimation(parent: _fadeController, curve: Curves.easeOut);

    _loadProjects();
    _loadProfile();
  }

  @override
  void dispose() {
    _fadeController.dispose();
    super.dispose();
  }

  Future<void> _loadProfile() async {
    final profile = await UserProfileService.loadProfile();
    if (mounted) setState(() => _userProfile = profile);
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

  Future<void> _openProject(Project project) async {
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
      ),
    );
    if (mounted) _loadProjects();
  }

  Future<void> _confirmDelete(Project project) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: const Text(
          'Delete project?',
          style: TextStyle(color: AppColors.textPrimary),
        ),
        content: Text(
          '"${project.name}" will be permanently deleted.',
          style: const TextStyle(color: AppColors.textSecondary),
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
              'Delete',
              style: TextStyle(color: Color(0xFFE05252)),
            ),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;
    await _storage.deleteProject(project.id);
    if (mounted) {
      setState(() => _projects.removeWhere((p) => p.id == project.id));
    }
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
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    return '${months[dt.month - 1]} ${dt.day}, ${dt.year}';
  }

  Widget _buildBody() {
    if (_isLoading) {
      return const Center(
        child: CircularProgressIndicator(color: AppColors.accent, strokeWidth: 2),
      );
    }

    if (_projects.isEmpty) {
      return FadeTransition(
        opacity: _fadeIn,
        child: EmptyCollection(onAddPressed: _goToCapture),
      );
    }

    return FadeTransition(
      opacity: _fadeIn,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final horizontalPadding =
              ResponsiveLayout.horizontalPadding(constraints.maxWidth);

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
                        '${_projects.length} ${_projects.length == 1 ? 'project' : 'projects'}',
                        style: const TextStyle(
                          fontSize: 13,
                          color: AppColors.textSecondary,
                          letterSpacing: 0.3,
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 5,
                        ),
                        decoration: BoxDecoration(
                          color: AppColors.surface,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: AppColors.border),
                        ),
                        child: const Row(
                          children: [
                            Icon(
                              Icons.sort,
                              size: 13,
                              color: AppColors.textSecondary,
                            ),
                            SizedBox(width: 4),
                            Text(
                              'Recent',
                              style: TextStyle(
                                fontSize: 12,
                                color: AppColors.textSecondary,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              SliverPadding(
                padding: EdgeInsets.only(
                  left: horizontalPadding,
                  right: horizontalPadding,
                  bottom: 24,
                ),
                sliver: SliverList(
                  delegate: SliverChildBuilderDelegate(
                    (context, index) {
                      final project = _projects[index];
                      return Column(
                        children: [
                          _ProjectTile(
                            project: project,
                            formattedDate: _formatDate(project.updatedAt),
                            onTap: () => _openProject(project),
                            onLongPress: () => _confirmDelete(project),
                          ),
                          if (index < _projects.length - 1)
                            const Divider(
                              height: 1,
                              color: AppColors.border,
                              indent: 76,
                            ),
                        ],
                      );
                    },
                    childCount: _projects.length,
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  PreferredSizeWidget _buildAppBarBottom(
      bool isLandscape, double horizontalPadding) {
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
    final horizontalPadding =
        ResponsiveLayout.horizontalPadding(MediaQuery.of(context).size.width);

    return Scaffold(
      key: const ValueKey('collectionAppBar'),
      backgroundColor: AppColors.background,
      onEndDrawerChanged: (isOpen) {
        if (!isOpen) _loadProfile();
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
            fontFamily: 'MaturaMTScriptCapitals',
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
                    : const Icon(Icons.person_rounded,
                        color: AppColors.textPrimary, size: 24),
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
        // Mini FABs fan upward — top item shown first
        for (final item in items)
          AnimatedSlide(
            offset: isOpen ? Offset.zero : const Offset(0, 0.4),
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeOut,
            child: AnimatedOpacity(
              opacity: isOpen ? 1.0 : 0.0,
              duration: const Duration(milliseconds: 180),
              child: Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: _MiniFabRow(item: item),
              ),
            ),
          ),
        // Main FAB
        FloatingActionButton(
          heroTag: 'main_fab',
          onPressed: onToggle,
          backgroundColor: AppColors.accent,
          elevation: 4,
          child: AnimatedRotation(
            turns: isOpen ? 0.125 : 0,
            duration: const Duration(milliseconds: 200),
            child: const Icon(Icons.add_rounded, color: AppColors.background, size: 28),
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
              BoxShadow(color: Color(0x40000000), blurRadius: 8, offset: Offset(0, 2)),
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
          ),
          const SizedBox(height: 16),
          _DialogTextField(
            controller: _composerController,
            label: 'Composer',
            hint: 'Unknown',
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

class _DialogTextField extends StatelessWidget {
  const _DialogTextField({
    required this.controller,
    required this.label,
    required this.hint,
    this.autofocus = false,
  });

  final TextEditingController controller;
  final String label;
  final String hint;
  final bool autofocus;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      autofocus: autofocus,
      style: const TextStyle(color: AppColors.textPrimary),
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        labelStyle: const TextStyle(color: AppColors.textSecondary, fontSize: 13),
        hintStyle: TextStyle(color: AppColors.textSecondary.withValues(alpha: 0.5)),
        enabledBorder: const UnderlineInputBorder(
          borderSide: BorderSide(color: AppColors.border),
        ),
        focusedBorder: const UnderlineInputBorder(
          borderSide: BorderSide(color: AppColors.accent),
        ),
      ),
    );
  }
}

// ── Project tile ──────────────────────────────────────────────────────────────

class _ProjectTile extends StatelessWidget {
  const _ProjectTile({
    required this.project,
    required this.formattedDate,
    required this.onTap,
    required this.onLongPress,
  });

  final Project project;
  final String formattedDate;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  @override
  Widget build(BuildContext context) {
    final scoreLabel = _projectLabel(project);

    return InkWell(
      onTap: onTap,
      onLongPress: onLongPress,
      splashColor: AppColors.accent.withValues(alpha: 0.06),
      highlightColor: AppColors.accent.withValues(alpha: 0.04),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: AppColors.surfaceAlt,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: AppColors.border),
              ),
              child: const Icon(
                Icons.music_note_rounded,
                color: AppColors.accent,
                size: 20,
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    project.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 6),
                  _ScoreLabelBadge(label: scoreLabel.displayName),
                  const SizedBox(height: 3),
                  Text(
                    'Last modified $formattedDate',
                    style: const TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            const Icon(
              Icons.chevron_right_rounded,
              color: AppColors.textSecondary,
              size: 20,
            ),
          ],
        ),
      ),
    );
  }

  ScoreLabel _projectLabel(Project project) {
    try {
      return ScoreClassifier.classify(project.decodeScore());
    } catch (_) {
      return ScoreLabel.generalPiece;
    }
  }
}

class _ScoreLabelBadge extends StatelessWidget {
  const _ScoreLabelBadge({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: AppColors.accent.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color: AppColors.accent.withValues(alpha: 0.22),
        ),
      ),
      child: Text(
        label,
        style: const TextStyle(
          color: AppColors.accent,
          fontSize: 11,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}
