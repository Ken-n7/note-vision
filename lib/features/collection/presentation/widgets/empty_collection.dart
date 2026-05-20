import 'package:flutter/material.dart';

class EmptyCollection extends StatefulWidget {
  final VoidCallback onAddPressed;
  final VoidCallback? onImportPressed;
  final VoidCallback? onNewScorePressed;

  const EmptyCollection({
    super.key,
    required this.onAddPressed,
    this.onImportPressed,
    this.onNewScorePressed,
  });

  @override
  State<EmptyCollection> createState() => _EmptyCollectionState();
}

class _EmptyCollectionState extends State<EmptyCollection>
    with SingleTickerProviderStateMixin {
  late AnimationController _pulse;
  late Animation<double> _scale;
  late Animation<double> _glow;

  static const _accent = Color(0xFFD4A96A);
  static const _surface = Color(0xFF1A1A1A);
  static const _border = Color(0xFF2C2C2C);
  static const _textPri = Color(0xFFFFFFFF);
  static const _textSec = Color(0xFF8A8A8A);

  @override
  void initState() {
    super.initState();
    _pulse = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2200),
    )..repeat(reverse: true);

    _scale = Tween<double>(
      begin: 1.0,
      end: 1.06,
    ).animate(CurvedAnimation(parent: _pulse, curve: Curves.easeInOut));
    _glow = Tween<double>(
      begin: 0.25,
      end: 0.55,
    ).animate(CurvedAnimation(parent: _pulse, curve: Curves.easeInOut));
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isLandscape =
        MediaQuery.of(context).orientation == Orientation.landscape;

    return LayoutBuilder(
      builder: (context, constraints) => SingleChildScrollView(
        padding: const EdgeInsets.symmetric(vertical: 16),
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: constraints.maxHeight - 16),
          child: Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 40),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  AnimatedBuilder(
                    animation: _pulse,
                    builder: (_, _) => Transform.scale(
                      scale: _scale.value,
                      child: Container(
                        width: 96,
                        height: 96,
                        decoration: BoxDecoration(
                          color: _surface,
                          shape: BoxShape.circle,
                          border: Border.all(color: _border, width: 1),
                          boxShadow: [
                            BoxShadow(
                              color: _accent.withValues(alpha: _glow.value),
                              blurRadius: 32,
                              spreadRadius: 2,
                            ),
                          ],
                        ),
                        child: const Icon(
                          Icons.music_note_rounded,
                          size: 38,
                          color: _accent,
                        ),
                      ),
                    ),
                  ),

                  SizedBox(height: isLandscape ? 18 : 32),

                  Text(
                    'Your collection\nis empty',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: isLandscape ? 22 : 26,
                      fontWeight: FontWeight.w700,
                      color: _textPri,
                      height: 1.2,
                    ),
                  ),

                  const SizedBox(height: 10),

                  const Text(
                    'Scan, import, or start with a blank score.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 14,
                      color: _textSec,
                      height: 1.55,
                      letterSpacing: 0.1,
                    ),
                  ),

                  SizedBox(height: isLandscape ? 20 : 36),

                  _PrimaryEmptyAction(
                    key: const ValueKey('scanImageButton'),
                    icon: Icons.document_scanner_rounded,
                    label: 'Scan Image',
                    onTap: widget.onAddPressed,
                  ),

                  if (widget.onImportPressed != null ||
                      widget.onNewScorePressed != null) ...[
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        if (widget.onImportPressed != null)
                          Expanded(
                            child: _SecondaryEmptyAction(
                              key: const ValueKey('importMusicXmlButton'),
                              icon: Icons.upload_file_rounded,
                              label: 'Import',
                              onTap: widget.onImportPressed!,
                            ),
                          ),
                        if (widget.onImportPressed != null &&
                            widget.onNewScorePressed != null)
                          const SizedBox(width: 10),
                        if (widget.onNewScorePressed != null)
                          Expanded(
                            child: _SecondaryEmptyAction(
                              key: const ValueKey('newScoreButton'),
                              icon: Icons.note_add_rounded,
                              label: 'New Score',
                              onTap: widget.onNewScorePressed!,
                            ),
                          ),
                      ],
                    ),
                  ],

                  const SizedBox(height: 10),

                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(
                        Icons.camera_alt_outlined,
                        size: 13,
                        color: _textSec,
                      ),
                      const SizedBox(width: 5),
                      Text(
                        'Camera scan, file import, or blank score',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 12,
                          color: _textSec.withValues(alpha: 0.7),
                          letterSpacing: 0.1,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _PrimaryEmptyAction extends StatelessWidget {
  const _PrimaryEmptyAction({
    super.key,
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  static const _bg = Color(0xFF0D0D0D);
  static const _accent = Color(0xFFD4A96A);

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 16),
        decoration: BoxDecoration(
          color: _accent,
          borderRadius: BorderRadius.circular(14),
          boxShadow: [
            BoxShadow(
              color: _accent.withValues(alpha: 0.28),
              blurRadius: 20,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 20, color: _bg),
            const SizedBox(width: 8),
            Text(
              label,
              style: const TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w700,
                color: _bg,
                letterSpacing: 0.3,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SecondaryEmptyAction extends StatelessWidget {
  const _SecondaryEmptyAction({
    super.key,
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  static const _surface = Color(0xFF1A1A1A);
  static const _border = Color(0xFF2C2C2C);
  static const _accent = Color(0xFFD4A96A);
  static const _textPri = Color(0xFFFFFFFF);

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 48,
        decoration: BoxDecoration(
          color: _surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: _border),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 18, color: _accent),
            const SizedBox(width: 7),
            Flexible(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: _textPri,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
