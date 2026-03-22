import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:io';

import 'package:note_vision/core/utils/image_picker_helper.dart';
import 'package:note_vision/core/widgets/drawer.dart';
import 'package:note_vision/features/scan/presentation/scan_screen.dart';

class CaptureScreen extends StatefulWidget {
  const CaptureScreen({super.key});

  @override
  State<CaptureScreen> createState() => _CaptureScreenState();
}

class _CaptureScreenState extends State<CaptureScreen>
    with SingleTickerProviderStateMixin {
  File? _selectedImage;

  late AnimationController _previewController;
  late Animation<double> _previewFade;
  late Animation<double> _previewScale;

  // ── Design tokens ──────────────────────────────────────────────────────────
  static const _bg         = Color(0xFF0D0D0D);
  static const _surface    = Color(0xFF1A1A1A);
  static const _border     = Color(0xFF2C2C2C);
  static const _accent     = Color(0xFFD4A96A);
  static const _textPrimary   = Color(0xFFFFFFFF);
  static const _textSecondary = Color(0xFF8A8A8A);

  @override
  void initState() {
    super.initState();
    SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
    ));

    _previewController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    );
    _previewFade = CurvedAnimation(
      parent: _previewController,
      curve: Curves.easeOut,
    );
    _previewScale = Tween<double>(begin: 0.96, end: 1.0).animate(
      CurvedAnimation(parent: _previewController, curve: Curves.easeOut),
    );
  }

  @override
  void dispose() {
    _previewController.dispose();
    super.dispose();
  }

  Future<void> _openCameraAndShowPreview() async {
    final file = await ImagePickerHelper.pickFromCamera(context);
    if (file == null || !mounted) return;
    setState(() => _selectedImage = file);
    _previewController.forward(from: 0);
  }

  Future<void> _pickFromGallery() async {
    final file = await ImagePickerHelper.pickFromGallery(context);
    if (file != null && mounted) {
      setState(() => _selectedImage = file);
      _previewController.forward(from: 0);
    }
  }

  void _cancelSelection() {
    setState(() => _selectedImage = null);
    _previewController.reset();
  }

  // ── Widgets ────────────────────────────────────────────────────────────────

  Widget _buildPreviewArea() {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: _surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _border),
      ),
      clipBehavior: Clip.antiAlias,
      child: AspectRatio(
        aspectRatio: 3 / 4,
        child: _selectedImage != null
            ? ScaleTransition(
                scale: _previewScale,
                child: FadeTransition(
                  opacity: _previewFade,
                  child: Image.file(_selectedImage!, fit: BoxFit.cover),
                ),
              )
            : _buildEmptyPreview(),
      ),
    );
  }

  Widget _buildEmptyPreview() {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Container(
          width: 64,
          height: 64,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(color: _border, width: 1.5),
          ),
          child: const Icon(
            Icons.camera_alt_outlined,
            color: _textSecondary,
            size: 28,
          ),
        ),
        const SizedBox(height: 16),
        const Text(
          'No image selected',
          style: TextStyle(
            fontSize: 14,
            color: _textSecondary,
            letterSpacing: 0.3,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          'Scan or upload a music sheet below',
          style: TextStyle(
            fontSize: 12,
            color: _textSecondary.withOpacity(0.5),
          ),
        ),
      ],
    );
  }

  Widget _buildHint() {
    return Row(
      children: [
        Icon(
          Icons.lightbulb_outline,
          size: 15,
          color: _accent.withOpacity(0.8),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            'Ensure the sheet is well-lit and fully visible for best accuracy.',
            style: TextStyle(
              fontSize: 12,
              color: _textSecondary,
              height: 1.5,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildPrimaryButton({
    required String label,
    required IconData icon,
    required VoidCallback onPressed,
  }) {
    return Expanded(
      child: _TappableButton(
        onPressed: onPressed,
        child: Container(
          height: 52,
          decoration: BoxDecoration(
            color: _textPrimary,
            borderRadius: BorderRadius.circular(14),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 18, color: _bg),
              const SizedBox(width: 8),
              Text(
                label,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: _bg,
                  letterSpacing: 0.3,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildGhostButton({
    required String label,
    required IconData icon,
    required VoidCallback onPressed,
  }) {
    return Expanded(
      child: _TappableButton(
        onPressed: onPressed,
        child: Container(
          height: 52,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: _border, width: 1),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 18, color: _textSecondary),
              const SizedBox(width: 8),
              Text(
                label,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w400,
                  color: _textSecondary,
                  letterSpacing: 0.3,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildContinueButton() {
    return _TappableButton(
      onPressed: () async {
        final bytes = await _selectedImage!.readAsBytes();
        if (!mounted) return;
        Navigator.push(
          context,
          PageRouteBuilder(
            pageBuilder: (_, __, ___) => ScanScreenProvider(imageBytes: bytes),
            transitionsBuilder: (_, animation, __, child) =>
                FadeTransition(opacity: animation, child: child),
            transitionDuration: const Duration(milliseconds: 400),
          ),
        );
      },
      child: Container(
        width: double.infinity,
        height: 52,
        decoration: BoxDecoration(
          color: _textPrimary,
          borderRadius: BorderRadius.circular(14),
          boxShadow: [
            BoxShadow(
              color: _accent.withOpacity(0.15),
              blurRadius: 20,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: const Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              'Continue',
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: _bg,
                letterSpacing: 0.4,
              ),
            ),
            SizedBox(width: 8),
            Icon(Icons.arrow_forward, size: 18, color: _bg),
          ],
        ),
      ),
    );
  }

  Widget _buildActionRow() {
    if (_selectedImage == null) {
      return Row(
        children: [
          _buildPrimaryButton(
            label: 'Scan Sheet',
            icon: Icons.camera_alt_outlined,
            onPressed: _openCameraAndShowPreview,
          ),
          const SizedBox(width: 12),
          _buildGhostButton(
            label: 'Upload',
            icon: Icons.upload_file_outlined,
            onPressed: _pickFromGallery,
          ),
        ],
      );
    }

    return Column(
      children: [
        _buildContinueButton(),
        const SizedBox(height: 10),
        _TappableButton(
          onPressed: _cancelSelection,
          child: SizedBox(
            width: double.infinity,
            height: 44,
            child: Center(
              child: Text(
                'Cancel',
                style: TextStyle(
                  fontSize: 13,
                  color: const Color.fromARGB(255, 255, 255, 255).withOpacity(0.7),
                  letterSpacing: 0.3,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      endDrawer: const CollectionDrawer(),
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
        actions: [
          Builder(
            builder: (context) => IconButton(
              icon: const Icon(Icons.menu, color: _textPrimary, size: 22),
              onPressed: () => Scaffold.of(context).openEndDrawer(),
            ),
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Section label ────────────────────────────────────────────
            const Text(
              'CAPTURE MUSIC SHEET',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: _textSecondary,
                letterSpacing: 2.0,
              ),
            ),

            const SizedBox(height: 6),

            // ── Description ──────────────────────────────────────────────
            const Text(
              'Scan printed music sheets and convert them into digital notation.',
              style: TextStyle(
                fontSize: 14,
                color: _textSecondary,
                height: 1.5,
              ),
            ),

            const SizedBox(height: 16),

            // ── Hint ─────────────────────────────────────────────────────
            _buildHint(),

            const SizedBox(height: 20),

            // ── Preview area ─────────────────────────────────────────────
            Expanded(child: _buildPreviewArea()),

            const SizedBox(height: 16),

            // ── Action buttons ───────────────────────────────────────────
            _buildActionRow(),

            const SizedBox(height: 20),
          ],
        ),
      ),
      bottomNavigationBar: _buildBottomNav(),
    );
  }

  Widget _buildBottomNav() {
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
            children: [
              _BottomNavItem(
                icon: Icons.camera_alt_outlined,
                label: 'Scan',
                isSelected: true,
                onTap: _openCameraAndShowPreview,
              ),
              _BottomNavItem(
                icon: Icons.upload_file_outlined,
                label: 'Import',
                isSelected: false,
                onTap: _pickFromGallery,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─── Bottom nav item ──────────────────────────────────────────────────────────

class _BottomNavItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool isSelected;
  final VoidCallback onTap;

  const _BottomNavItem({
    required this.icon,
    required this.label,
    required this.isSelected,
    required this.onTap,
  });

  static const _accent = Color(0xFFD4A96A);
  static const _textSecondary = Color(0xFF8A8A8A);

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
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
                fontSize: 11,
                color: isSelected ? _accent : _textSecondary,
                fontWeight:
                    isSelected ? FontWeight.w600 : FontWeight.w400,
                letterSpacing: 0.3,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Tappable button wrapper ──────────────────────────────────────────────────

class _TappableButton extends StatefulWidget {
  final Widget child;
  final VoidCallback onPressed;

  const _TappableButton({required this.child, required this.onPressed});

  @override
  State<_TappableButton> createState() => _TappableButtonState();
}

class _TappableButtonState extends State<_TappableButton> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => setState(() => _pressed = true),
      onTapUp: (_) {
        setState(() => _pressed = false);
        widget.onPressed();
      },
      onTapCancel: () => setState(() => _pressed = false),
      child: AnimatedScale(
        scale: _pressed ? 0.97 : 1.0,
        duration: const Duration(milliseconds: 100),
        child: AnimatedOpacity(
          opacity: _pressed ? 0.85 : 1.0,
          duration: const Duration(milliseconds: 100),
          child: widget.child,
        ),
      ),
    );
  }
}