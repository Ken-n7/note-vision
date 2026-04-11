import 'package:flutter/material.dart';
import 'package:note_vision/core/models/project.dart';
import 'package:note_vision/core/models/score.dart';
import 'package:note_vision/core/services/project_storage_service.dart';
import 'package:note_vision/core/theme/app_theme.dart';
import 'package:note_vision/features/editor/model/editor_state.dart';
import 'package:note_vision/features/editor/presentation/editor_shell_screen.dart';

class ProjectListScreen extends StatefulWidget {
  const ProjectListScreen({super.key});

  static const routeName = '/projects';

  @override
  State<ProjectListScreen> createState() => _ProjectListScreenState();
}

class _ProjectListScreenState extends State<ProjectListScreen> {
  final _storage = ProjectStorageService();
  List<Project> _projects = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final projects = await _storage.loadAllProjects();
      if (mounted) setState(() { _projects = projects; _isLoading = false; });
    } catch (e) {
      debugPrint('ProjectListScreen: failed to load: $e');
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
    // Reload in case the user re-saved with a different name.
    if (mounted) _load();
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
    if (mounted) setState(() => _projects.removeWhere((p) => p.id == project.id));
  }

  String _formatDate(DateTime dt) {
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    return '${months[dt.month - 1]} ${dt.day}, ${dt.year}';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.surface,
        elevation: 0,
        centerTitle: false,
        title: const Text(
          'Saved Projects',
          style: TextStyle(
            color: AppColors.textPrimary,
            fontSize: 17,
            fontWeight: FontWeight.w600,
          ),
        ),
        leading: IconButton(
          icon: const Icon(
            Icons.arrow_back_ios_new_rounded,
            size: 16,
            color: AppColors.textPrimary,
          ),
          onPressed: () => Navigator.of(context).pop(),
        ),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(height: 1, color: AppColors.border),
        ),
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return const Center(
        child: CircularProgressIndicator(color: AppColors.accent, strokeWidth: 2),
      );
    }

    if (_projects.isEmpty) {
      return const _EmptyState();
    }

    return ListView.separated(
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: _projects.length,
      separatorBuilder: (_, _x) => const Divider(
        height: 1,
        color: AppColors.border,
        indent: 76,
        endIndent: 16,
      ),
      itemBuilder: (context, index) {
        final project = _projects[index];
        return _ProjectTile(
          project: project,
          formattedDate: _formatDate(project.updatedAt),
          onTap: () => _openProject(project),
          onLongPress: () => _confirmDelete(project),
        );
      },
    );
  }
}

// ── Empty state ───────────────────────────────────────────────────────────────

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.save_outlined, size: 56, color: AppColors.textSecondary),
          const SizedBox(height: 16),
          const Text(
            'No saved projects yet',
            style: TextStyle(
              color: AppColors.textSecondary,
              fontSize: 16,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Save a score from the editor to see it here.',
            style: TextStyle(
              color: AppColors.textSecondary.withValues(alpha: 0.5),
              fontSize: 13,
            ),
          ),
        ],
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
    return InkWell(
      onTap: onTap,
      onLongPress: onLongPress,
      splashColor: AppColors.accent.withValues(alpha: 0.06),
      highlightColor: AppColors.accent.withValues(alpha: 0.04),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          children: [
            // Thumbnail placeholder
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
