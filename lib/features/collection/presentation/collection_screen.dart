import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:note_vision/core/widgets/drawer.dart';
import 'package:note_vision/core/services/image_storage_service.dart';
import 'package:note_vision/features/capture/presentation/capture_screen.dart';
import 'widgets/empty_collection.dart';
import 'widgets/score_card.dart';

class CollectionScreen extends StatefulWidget {
  final ImageStorageService? imageStorageService;

  const CollectionScreen({
    super.key,
    this.imageStorageService,
  });

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

  // ── Design tokens ──────────────────────────────────────────────────────────
  static const _bg            = Color(0xFF0D0D0D);
  static const _surface       = Color(0xFF1A1A1A);
  static const _border        = Color(0xFF2C2C2C);
  static const _accent        = Color(0xFFD4A96A);
  static const _textPrimary   = Color(0xFFFFFFFF);
  static const _textSecondary = Color(0xFF8A8A8A);

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
      // If the last image was removed, re-trigger the fade for empty state
      if (_imagePaths.isEmpty) {
        _fadeController.forward(from: 0);
      }
    }
  }

  void _goToCapture() {
    Navigator.push(
      context,
      PageRouteBuilder(
        pageBuilder: (_, __, ___) => const CaptureScreen(),
        transitionsBuilder: (_, animation, __, child) =>
            FadeTransition(opacity: animation, child: child),
        transitionDuration: const Duration(milliseconds: 400),
      ),
    ).then((_) => _loadImages());
  }

  // ── Body ───────────────────────────────────────────────────────────────────

  Widget _buildBody() {
    if (_isLoading) {
      return const Center(
        child: CircularProgressIndicator(
          color: _accent,
          strokeWidth: 2,
        ),
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
      child: CustomScrollView(
        slivers: [
          // ── Count header ───────────────────────────────────────────────
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    '${_imagePaths.length} ${_imagePaths.length == 1 ? 'sheet' : 'sheets'}',
                    style: const TextStyle(
                      fontSize: 13,
                      color: _textSecondary,
                      letterSpacing: 0.3,
                    ),
                  ),
                  // Sort/filter placeholder
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(
                      color: _surface,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: _border),
                    ),
                    child: const Row(
                      children: [
                        Icon(Icons.sort, size: 13, color: _textSecondary),
                        SizedBox(width: 4),
                        Text(
                          'Recent',
                          style: TextStyle(
                            fontSize: 12,
                            color: _textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),

          // ── Grid ───────────────────────────────────────────────────────
          SliverPadding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            sliver: SliverGrid(
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2,
                crossAxisSpacing: 12,
                mainAxisSpacing: 12,
                childAspectRatio: 0.78,
              ),
              delegate: SliverChildBuilderDelegate(
                (context, index) => ScoreCard(
                  imagePath: _imagePaths[index],
                  onDelete: () => _deleteImage(_imagePaths[index]),
                ),
                childCount: _imagePaths.length,
              ),
            ),
          ),

          const SliverToBoxAdapter(child: SizedBox(height: 24)),
        ],
      ),
    );
  }

  // ── Bottom nav ─────────────────────────────────────────────────────────────

  Widget _buildBottomNav() {
    final items = [
      (Icons.add_circle_outline, 'Add Files'),
      (Icons.info_outline, 'Info'),
      (Icons.edit_outlined, 'Edit'),
      (Icons.check_circle_outline, 'Result'),
    ];

    return Container(
      decoration: const BoxDecoration(
        color: _surface,
        border: Border(top: BorderSide(color: _border, width: 0.5)),
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
                        color: isSelected ? _accent : _textSecondary,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        label,
                        style: TextStyle(
                          fontSize: 10,
                          color: isSelected ? _accent : _textSecondary,
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

  // ── FAB ────────────────────────────────────────────────────────────────────

  Widget _buildFab() {
    return GestureDetector(
      onTap: _goToCapture,
      child: Container(
        width: 52,
        height: 52,
        decoration: BoxDecoration(
          color: _textPrimary,
          shape: BoxShape.circle,
          boxShadow: [
            BoxShadow(
              color: _accent.withOpacity(0.2),
              blurRadius: 16,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: const Icon(Icons.add, color: _bg, size: 24),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      key: const ValueKey('collectionAppBar'),
      backgroundColor: _bg,
      endDrawer: const CollectionDrawer(),
      floatingActionButton: _imagePaths.isNotEmpty ? _buildFab() : null,
      appBar: AppBar(
        backgroundColor: _bg,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        leading: Padding(
          padding: const EdgeInsets.only(left: 16),
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
            color: _textPrimary,
            letterSpacing: 0.5,
          ),
        ),
        centerTitle: true,
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(48),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'MY COLLECTION',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: _textSecondary,
                    letterSpacing: 2.0,
                  ),
                ),
                if (!_isLoading && _imagePaths.isNotEmpty)
                  Text(
                    '${_imagePaths.length} items',
                    style: const TextStyle(
                      fontSize: 11,
                      color: _textSecondary,
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
              icon: const Icon(Icons.menu, color: _textPrimary, size: 22),
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