import 'package:flutter/material.dart';

class CollectionDrawer extends StatelessWidget {
  const CollectionDrawer({super.key});

  // ── Design tokens ──────────────────────────────────────────────────────────
  static const _bg            = Color(0xFF0D0D0D);
  // static const _surface       = Color(0xFF1A1A1A);
  static const _border        = Color(0xFF2C2C2C);
  // static const _accent        = Color(0xFFD4A96A);
  static const _textPrimary   = Color(0xFFFFFFFF);
  static const _textSecondary = Color(0xFF8A8A8A);

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 260,
      child: Drawer(
        backgroundColor: _bg,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.only(
            topLeft: Radius.circular(20),
            bottomLeft: Radius.circular(20),
          ),
        ),
        child: SafeArea(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── Header ───────────────────────────────────────────────
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 32, 24, 24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Image.asset(
                      'assets/images/notevision.png',
                      height: 32,
                      colorBlendMode: BlendMode.srcIn,
                    ),
                    const SizedBox(height: 16),
                    const Text(
                      'Note Vision',
                      style: TextStyle(
                        fontFamily: 'MaturaMTScriptCapitals',
                        fontSize: 20,
                        color: _textPrimary,
                        letterSpacing: 0.5,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Music sheet scanner',
                      style: TextStyle(
                        fontSize: 12,
                        color: _textSecondary.withValues(alpha: 0.6),
                        letterSpacing: 0.3,
                      ),
                    ),
                  ],
                ),
              ),

              // ── Divider ──────────────────────────────────────────────
              Container(
                height: 0.5,
                margin: const EdgeInsets.symmetric(horizontal: 24),
                color: _border,
              ),

              const SizedBox(height: 12),

              // ── Section label ────────────────────────────────────────
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 8, 24, 4),
                child: Text(
                  'NAVIGATE',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                    color: _textSecondary.withValues(alpha: 0.6),
                    letterSpacing: 2.0,
                  ),
                ),
              ),

              // ── Menu items ───────────────────────────────────────────
              _DrawerItem(
                icon: Icons.edit_outlined,
                title: 'Digital Writing',
                onTap: () => Navigator.pop(context),
              ),
              _DrawerItem(
                icon: Icons.school_outlined,
                title: 'Instruction',
                onTap: () => Navigator.pop(context),
              ),
              _DrawerItem(
                icon: Icons.info_outline,
                title: 'About',
                onTap: () => Navigator.pop(context),
              ),

              const Spacer(),
            ],
          ),
        ),
      ),
    );
  }
}

// ─── Drawer item ──────────────────────────────────────────────────────────────

class _DrawerItem extends StatefulWidget {
  final IconData icon;
  final String title;
  final VoidCallback onTap;

  const _DrawerItem({
    required this.icon,
    required this.title,
    required this.onTap,
  });

  @override
  State<_DrawerItem> createState() => _DrawerItemState();
}

class _DrawerItemState extends State<_DrawerItem> {
  bool _hovered = false;

  static const _surface = Color(0xFF1A1A1A);
  static const _accent  = Color(0xFFD4A96A);
  static const _textPrimary   = Color(0xFFFFFFFF);
  static const _textSecondary = Color(0xFF8A8A8A);

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => setState(() => _hovered = true),
      onTapUp: (_) {
        setState(() => _hovered = false);
        widget.onTap();
      },
      onTapCancel: () => setState(() => _hovered = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 13),
        decoration: BoxDecoration(
          color: _hovered ? _surface : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: _hovered
                    ? _accent.withValues(alpha: 0.15)
                    : const Color(0xFF1A1A1A),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(
                widget.icon,
                size: 18,
                color: _hovered ? _accent : _textSecondary,
              ),
            ),
            const SizedBox(width: 14),
            Text(
              widget.title,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w400,
                color: _hovered ? _textPrimary : _textSecondary,
                letterSpacing: 0.2,
              ),
            ),
          ],
        ),
      ),
    );
  }
}