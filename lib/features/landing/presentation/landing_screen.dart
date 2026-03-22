import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:note_vision/features/musicxml_inspector/music_inspector_screen.dart';
import '../../../features/collection/presentation/collection_screen.dart';

class LandingScreen extends StatefulWidget {
  const LandingScreen({super.key});

  @override
  State<LandingScreen> createState() => _LandingScreenState();
}

class _LandingScreenState extends State<LandingScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _fadeIn;
  late Animation<Offset> _slideUp;

  @override
  void initState() {
    super.initState();

    SystemChrome.setSystemUIOverlayStyle(
      const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.light,
      ),
    );

    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    );

    _fadeIn = CurvedAnimation(
      parent: _controller,
      curve: const Interval(0.0, 0.7, curve: Curves.easeOut),
    );

    _slideUp = Tween<Offset>(
      begin: const Offset(0, 0.08),
      end: Offset.zero,
    ).animate(CurvedAnimation(
      parent: _controller,
      curve: const Interval(0.0, 0.7, curve: Curves.easeOut),
    ));

    _controller.forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;

    return Scaffold(
      backgroundColor: const Color.fromARGB(255, 0, 0, 0),
      body: Stack(
        children: [
          // ── Ambient glow background ────────────────────────────────────
          Positioned(
            top: -size.height * 0.1,
            left: -size.width * 0.2,
            child: Container(
              width: size.width * 1.4,
              height: size.height * 0.55,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
              ),
            ),
          ),

          // ── Main content ───────────────────────────────────────────────
          SafeArea(
            child: FadeTransition(
              opacity: _fadeIn,
              child: SlideTransition(
                position: _slideUp,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 32),
                  child: Column(
                    children: [
                      const Spacer(flex: 3),

                      // ── Title ──────────────────────────────────────────
                      Text(
                        'Note Vision',
                        style: TextStyle(
                          fontFamily: 'MaturaMTScriptCapitals',
                          fontSize: 50,
                          color: Colors.white,
                          letterSpacing: 1.5,
                        ),
                      ),

                      const Spacer(flex: 1),

                      // ── Logo with glow ─────────────────────────────────
                      Container(
                        width: 160,
                        height: 160,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                        ),
                        child: Image.asset(
                          'assets/images/notevision.png',
                          width: 160,
                          height: 160,
                          colorBlendMode: BlendMode.srcIn,
                        ),
                      ),

                      const Spacer(flex: 1),

                      // ── Tagline ────────────────────────────────────────
                      Text(
                        'Read music. Understand it.',
                        style: TextStyle(
                          fontSize: 13,
                          color: Colors.white.withOpacity(0.35),
                          letterSpacing: 2.0,
                          fontWeight: FontWeight.w300,
                        ),
                      ),

                      const Spacer(flex: 3),

                      // ── Get Started (primary) ──────────────────────────
                      _PrimaryButton(
                        label: 'Get Started',
                        onPressed: () => Navigator.push(
                          context,
                          _fadeRoute(const CollectionScreen()),
                        ),
                      ),

                      const SizedBox(height: 14),

                      // ── Dev's Workbench (ghost) ────────────────────────
                      _GhostButton(
                        label: "Dev's Workbench",
                        onPressed: () => Navigator.push(
                          context,
                          _fadeRoute(const MusicXmlInspectorScreen()),
                        ),
                      ),

                      const Spacer(flex: 2),
                      const SizedBox(height: 16),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  PageRoute _fadeRoute(Widget page) {
    return PageRouteBuilder(
      pageBuilder: (_, __, ___) => page,
      transitionsBuilder: (_, animation, __, child) =>
          FadeTransition(opacity: animation, child: child),
      transitionDuration: const Duration(milliseconds: 400),
    );
  }
}

// ─── Primary button ───────────────────────────────────────────────────────────

class _PrimaryButton extends StatefulWidget {
  final String label;
  final VoidCallback onPressed;

  const _PrimaryButton({required this.label, required this.onPressed});

  @override
  State<_PrimaryButton> createState() => _PrimaryButtonState();
}

class _PrimaryButtonState extends State<_PrimaryButton> {
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
        child: Container(
          width: double.infinity,
          height: 54,
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(14),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFFD4A96A).withOpacity(0.2),
                blurRadius: 20,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          alignment: Alignment.center,
          child: Text(
            widget.label,
            style: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w600,
              color: Color(0xFF0D0D0D),
              letterSpacing: 0.5,
            ),
          ),
        ),
      ),
    );
  }
}

// ─── Ghost button ─────────────────────────────────────────────────────────────

class _GhostButton extends StatefulWidget {
  final String label;
  final VoidCallback onPressed;

  const _GhostButton({required this.label, required this.onPressed});

  @override
  State<_GhostButton> createState() => _GhostButtonState();
}

class _GhostButtonState extends State<_GhostButton> {
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
          opacity: _pressed ? 0.6 : 1.0,
          duration: const Duration(milliseconds: 100),
          child: Container(
            width: double.infinity,
            height: 54,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: Colors.white.withOpacity(0.15),
                width: 1,
              ),
            ),
            alignment: Alignment.center,
            child: Text(
              widget.label,
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w400,
                color: Colors.white.withOpacity(0.5),
                letterSpacing: 0.5,
              ),
            ),
          ),
        ),
      ),
    );
  }
}