import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:note_vision/core/models/project.dart';
import 'package:note_vision/core/models/score.dart';
import 'package:note_vision/core/services/project_storage_service.dart';
import 'package:note_vision/core/services/user_profile_service.dart';
import 'package:note_vision/core/theme/app_theme.dart';
import 'package:note_vision/core/theme/responsive_layout.dart';
import 'package:note_vision/core/widgets/drawer.dart';
import 'package:note_vision/core/widgets/user_avatar.dart';
import 'package:note_vision/features/capture/presentation/capture_screen.dart';
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
  int _currentIndex = 0;
  List<Project> _projects = [];
  bool _isLoading = true;
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
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'MY COLLECTION',
              style: TextStyle(
                fontSize: isLandscape ? 10 : 11,
                fontWeight: FontWeight.w600,
                color: AppColors.textSecondary,
                letterSpacing: 2.0,
              ),
            ),
            if (_userProfile != null)
              Row(
                children: [
                  Text(
                    _userProfile!.name,
                    style: TextStyle(
                      fontSize: isLandscape ? 10 : 11,
                      color: AppColors.textSecondary,
                      letterSpacing: 0.3,
                    ),
                  ),
                  const SizedBox(width: 8),
                  UserAvatar(
                    initial: _userProfile!.initial,
                    photoPath: _userProfile!.photoPath,
                    size: 24,
                    borderColor: const Color(0xFF2A2A2A),
                    borderWidth: 1.5,
                  ),
                ],
              )
            else if (!_isLoading && _projects.isNotEmpty)
              Text(
                '${_projects.length} items',
                style: TextStyle(
                  fontSize: isLandscape ? 10 : 11,
                  color: AppColors.textSecondary,
                  letterSpacing: 0.3,
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildBottomNav() {
    final items = [
      (Icons.add_circle_outline, 'Add Files'),
      (Icons.info_outline, 'Info'),
      (Icons.edit_outlined, 'Edit'),
      (Icons.check_circle_outline, 'Result'),
    ];

    return Container(
      decoration: const BoxDecoration(
        color: AppColors.surface,
        border: Border(top: BorderSide(color: AppColors.border, width: 0.5)),
      ),
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: 60,
          child: Row(
            children: List.generate(items.length, (i) {
              final (icon, label) = items[i];
              final isSelected = _currentIndex == i;
              return Expanded(
                child: GestureDetector(
                  onTap: () {
                    setState(() => _currentIndex = i);
                    if (i == 0) _goToCapture();
                  },
                  behavior: HitTestBehavior.opaque,
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        icon,
                        size: 22,
                        color: isSelected
                            ? AppColors.accent
                            : AppColors.textSecondary,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        label,
                        style: TextStyle(
                          fontSize: 10,
                          color: isSelected
                              ? AppColors.accent
                              : AppColors.textSecondary,
                          fontWeight: isSelected
                              ? FontWeight.w600
                              : FontWeight.w400,
                          letterSpacing: 0.2,
                        ),
                      ),
                    ],
                  ),
                ),
              );
            }),
          ),
        ),
      ),
    );
  }

  Widget _buildFab() {
    return GestureDetector(
      onTap: _goToCapture,
      child: Container(
        width: 52,
        height: 52,
        decoration: BoxDecoration(
          color: AppColors.textPrimary,
          shape: BoxShape.circle,
          boxShadow: [
            BoxShadow(
              color: AppColors.accent.withValues(alpha: 0.2),
              blurRadius: 16,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: const Icon(Icons.add, color: AppColors.background, size: 24),
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
      floatingActionButton: _projects.isNotEmpty ? _buildFab() : null,
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
            builder: (context) => IconButton(
              icon: const Icon(Icons.menu,
                  color: AppColors.textPrimary, size: 22),
              onPressed: () => Scaffold.of(context).openEndDrawer(),
            ),
          ),
        ],
      ),
      body: _buildBody(),
      bottomNavigationBar: _buildBottomNav(),
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
}
