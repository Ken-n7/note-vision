import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:note_vision/core/models/measure.dart';
import 'package:note_vision/core/models/part.dart';
import 'package:note_vision/core/models/score.dart';
import 'package:note_vision/core/services/image_storage_service.dart';
import 'package:note_vision/core/theme/app_theme.dart';
import 'package:note_vision/core/theme/responsive_layout.dart';
import 'package:note_vision/core/widgets/drawer.dart';
import 'package:note_vision/features/capture/presentation/capture_screen.dart';
import 'package:note_vision/features/editor/model/editor_state.dart';
import 'package:note_vision/features/editor/presentation/editor_shell_screen.dart';

import 'widgets/empty_collection.dart';
import 'widgets/score_card.dart';

class CollectionScreen extends StatefulWidget {
  final ImageStorageService? imageStorageService;

  const CollectionScreen({super.key, this.imageStorageService});

  @override
  State<CollectionScreen> createState() => _CollectionScreenState();
}

class _CollectionScreenState extends State<CollectionScreen>
    with SingleTickerProviderStateMixin {
  int _currentIndex = 0;
  List<String> _imagePaths = [];
  bool _isLoading = true;

  late final ImageStorageService _service;
  late AnimationController _fadeController;
  late Animation<double> _fadeIn;

  @override
  void initState() {
    super.initState();
    SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
    ));

    _service = widget.imageStorageService ?? ImageStorageService();

    _fadeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    );
    _fadeIn = CurvedAnimation(parent: _fadeController, curve: Curves.easeOut);

    _loadImages();
  }

  @override
  void dispose() {
    _fadeController.dispose();
    super.dispose();
  }

  Future<void> _loadImages() async {
    final paths = await _service.getSavedImages();
    if (mounted) {
      setState(() {
        _imagePaths = paths;
        _isLoading = false;
      });
      _fadeController.forward(from: 0);
    }
  }

  Future<void> _deleteImage(String imagePath) async {
    await _service.deleteImage(imagePath);
    if (mounted) {
      setState(() => _imagePaths.remove(imagePath));
      if (_imagePaths.isEmpty) {
        _fadeController.forward(from: 0);
      }
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
    ).then((_) => _loadImages());
  }

  void _openEditorForImport(String imagePath) {
    final importedScore = _buildImportedScore(imagePath);
    Navigator.pushNamed(
      context,
      EditorShellScreen.routeName,
      arguments: EditorShellArgs(
        score: importedScore,
        initialState: EditorState(score: importedScore),
      ),
    );
  }

  Score _buildImportedScore(String imagePath) {
    final segments = imagePath.split('/');
    final fileName = segments.isNotEmpty ? segments.last : 'Imported Score';
    final title = fileName.contains('.')
        ? fileName.substring(0, fileName.lastIndexOf('.'))
        : fileName;

    return Score(
      id: 'imported-${title.hashCode}',
      title: title,
      composer: 'Imported',
      parts: const [
        Part(
          id: 'P1',
          name: 'Part 1',
          measures: [Measure(number: 1, symbols: [])],
        ),
      ],
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return const Center(
        child: CircularProgressIndicator(color: AppColors.accent, strokeWidth: 2),
      );
    }

    if (_imagePaths.isEmpty) {
      return FadeTransition(
        opacity: _fadeIn,
        child: EmptyCollection(onAddPressed: _goToCapture),
      );
    }

    return FadeTransition(
      opacity: _fadeIn,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final orientation = MediaQuery.of(context).orientation;
          final horizontalPadding =
              ResponsiveLayout.horizontalPadding(constraints.maxWidth);
          final crossAxisCount = ResponsiveLayout.gridColumns(
            width: constraints.maxWidth,
            orientation: orientation,
          );

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
                        '${_imagePaths.length} ${_imagePaths.length == 1 ? 'sheet' : 'sheets'}',
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
                padding: EdgeInsets.symmetric(horizontal: horizontalPadding),
                sliver: SliverGrid(
                  gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: crossAxisCount,
                    crossAxisSpacing: 12,
                    mainAxisSpacing: 12,
                    childAspectRatio: orientation == Orientation.landscape
                        ? 0.95
                        : 0.78,
                  ),
                  delegate: SliverChildBuilderDelegate(
                    (context, index) => ScoreCard(
                      imagePath: _imagePaths[index],
                      onDelete: () => _deleteImage(_imagePaths[index]),
                      onOpen: () => _openEditorForImport(_imagePaths[index]),
                    ),
                    childCount: _imagePaths.length,
                  ),
                ),
              ),
              const SliverToBoxAdapter(child: SizedBox(height: 24)),
            ],
          );
        },
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
                          fontWeight:
                              isSelected ? FontWeight.w600 : FontWeight.w400,
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
    final horizontalPadding =
        ResponsiveLayout.horizontalPadding(MediaQuery.of(context).size.width);

    return Scaffold(
      key: const ValueKey('collectionAppBar'),
      backgroundColor: AppColors.background,
      endDrawer: const CollectionDrawer(),
      floatingActionButton: _imagePaths.isNotEmpty ? _buildFab() : null,
      appBar: AppBar(
        leading: Padding(
          padding: EdgeInsets.only(left: horizontalPadding),
          child: Image.asset(
            'assets/images/notevision.png',
            height: 28,
            colorBlendMode: BlendMode.srcIn,
          ),
        ),
        title: const Text(
          'Note Vision',
          style: TextStyle(
            fontFamily: 'MaturaMTScriptCapitals',
            fontSize: 22,
            color: AppColors.textPrimary,
            letterSpacing: 0.5,
          ),
        ),
        centerTitle: true,
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(48),
          child: Padding(
            padding: EdgeInsets.fromLTRB(horizontalPadding, 0, horizontalPadding, 12),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'MY COLLECTION',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textSecondary,
                    letterSpacing: 2.0,
                  ),
                ),
                if (!_isLoading && _imagePaths.isNotEmpty)
                  Text(
                    '${_imagePaths.length} items',
                    style: const TextStyle(
                      fontSize: 11,
                      color: AppColors.textSecondary,
                      letterSpacing: 0.3,
                    ),
                  ),
              ],
            ),
          ),
        ),
        actions: [
          Builder(
            builder: (context) => IconButton(
              icon: const Icon(Icons.menu, color: AppColors.textPrimary, size: 22),
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
