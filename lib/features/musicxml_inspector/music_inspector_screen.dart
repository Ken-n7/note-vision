import 'package:flutter/material.dart';
import 'package:note_vision/features/notation/score_notation_viewer.dart';

import '../../core/widgets/inspector_shared_widgets.dart';
import '../detection_inspector/detection_inspector_screen.dart';
import 'controller/musicxml_inspector_controller.dart';
import 'model/inspector_state.dart';
import 'widgets/collapsible_section.dart';
import 'widgets/counts_section.dart';
import 'widgets/error_block.dart';
import 'widgets/metadata_section.dart';
import 'widgets/status_section.dart';

// ── Dark theme color palette ──────────────────────────────────────────────────
class _Colors {
  static const bg          = Color(0xFF0D0F14);       // near-black canvas
  static const surface     = Color(0xFF151820);       // card surface
  static const surfaceAlt  = Color(0xFF1C1F2A);       // slightly lighter surface
  static const border      = Color(0xFF252836);       // subtle border
  static const accent      = Color(0xFF4F8EF7);       // electric blue
  static const accentDim   = Color(0xFF1E3A6E);       // muted accent bg
  static const accentGlow  = Color(0x334F8EF7);       // glow tint
  static const textPrimary = Color(0xFFE8EAF0);       // near-white
  static const textSecond  = Color(0xFF7A7F94);       // muted
  static const devBadge    = Color(0xFF0F2040);
  static const devText     = Color(0xFF4F8EF7);
  static const danger      = Color(0xFFFF5C5C);
  static const success     = Color(0xFF3DD68C);
}

class MusicXmlInspectorScreen extends StatefulWidget {
  const MusicXmlInspectorScreen({super.key});

  @override
  State<MusicXmlInspectorScreen> createState() =>
      _MusicXmlInspectorScreenState();
}

class _MusicXmlInspectorScreenState extends State<MusicXmlInspectorScreen>
    with SingleTickerProviderStateMixin {
  final _controller = MusicXmlInspectorController();
  late final AnimationController _fadeCtrl;
  late final Animation<double> _fadeAnim;

  bool _showRawXml    = false;
  bool _showScoreModel = false;

  @override
  void initState() {
    super.initState();
    _fadeCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    )..forward();
    _fadeAnim = CurvedAnimation(parent: _fadeCtrl, curve: Curves.easeOut);
  }

  @override
  void dispose() {
    _controller.dispose();
    _fadeCtrl.dispose();
    super.dispose();
  }

  Future<void> _onImportPressed() async {
    setState(() {
      _showRawXml    = false;
      _showScoreModel = false;
    });
    await _controller.onImportPressed();
    if (mounted) setState(() {});
  }

  void _goToDetectionInspector() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const DetectionInspectorScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    final state     = _controller.state;
    final isLoading = _controller.isLoading;

    return Theme(
      data: _darkTheme(),
      child: Scaffold(
        backgroundColor: _Colors.bg,
        appBar: _buildAppBar(),
        body: FadeTransition(
          opacity: _fadeAnim,
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 40),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // ── Divider line below app bar ──────────────────────────
                Container(
                  height: 1,
                  color: _Colors.border,
                  margin: const EdgeInsets.only(bottom: 24),
                ),

                // ── Action buttons ──────────────────────────────────────
                _ImportButton(
                  isLoading: isLoading,
                  onPressed: isLoading ? null : _onImportPressed,
                ),

                const SizedBox(height: 10),

                _DetectionButton(onPressed: _goToDetectionInspector),

                const SizedBox(height: 24),

                // ── Status ──────────────────────────────────────────────
                _DarkCard(
                  child: StatusSection(state: state),
                ),

                // ── Error block ─────────────────────────────────────────
                if (state.errorMessage != null) ...[
                  const SizedBox(height: 10),
                  _DarkCard(
                    accentLeft: _Colors.danger,
                    child: ErrorBlock(
                      message: state.errorMessage!,
                      isValidation:
                          state.status == ScreenState.validationError,
                    ),
                  ),
                ],

                // ── Warnings block ──────────────────────────────────────
                if (state.metadata?.warnings.isNotEmpty == true) ...[
                  const SizedBox(height: 10),
                  _DarkCard(
                    accentLeft: const Color(0xFFFFB84F),
                    child: WarningBlock(warnings: state.metadata!.warnings),
                  ),
                ],

                const SizedBox(height: 10),

                // ── Metadata ────────────────────────────────────────────
                _SectionLabel(label: 'METADATA'),
                const SizedBox(height: 6),
                _DarkCard(child: MetadataSection(metadata: state.metadata)),

                const SizedBox(height: 10),

                // ── Counts ──────────────────────────────────────────────
                _SectionLabel(label: 'ELEMENT COUNTS'),
                const SizedBox(height: 6),
                _DarkCard(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      CountsSection(metadata: state.metadata),
                      const SizedBox(height: 1),
                    ],
                  ),
                ),

                const SizedBox(height: 16),

                // ── Raw XML preview ─────────────────────────────────────
                _DarkCollapsible(
                  label: 'RAW XML PREVIEW',
                  icon: Icons.code_rounded,
                  enabled: state.rawXml != null,
                  expanded: _showRawXml,
                  onToggle: state.rawXml != null
                      ? () => setState(() => _showRawXml = !_showRawXml)
                      : null,
                  child: state.rawXml != null
                      ? MonoPreview(
                          text: state.rawXml!.length > 2000
                              ? '${state.rawXml!.substring(0, 2000)}\n\n… (truncated)'
                              : state.rawXml!,
                        )
                      : null,
                ),

                const SizedBox(height: 10),

                // ── ScoreModel debug ────────────────────────────────────
                _DarkCollapsible(
                  label: 'SCOREMODEL DEBUG',
                  icon: Icons.music_note_rounded,
                  enabled: state.score != null,
                  expanded: _showScoreModel,
                  onToggle: state.score != null
                      ? () => setState(
                            () => _showScoreModel = !_showScoreModel)
                      : null,
                  child: state.score != null
                      ? SizedBox(
                          height: 300,
                          child: ScoreNotationViewer(score: state.score!),
                        )
                      : null,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  PreferredSizeWidget _buildAppBar() {
    return AppBar(
      backgroundColor: _Colors.bg,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      centerTitle: true,
      title: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(
            Icons.queue_music_rounded,
            size: 16,
            color: _Colors.accent,
          ),
          const SizedBox(width: 8),
          const Text(
            'MusicXML Inspector',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: _Colors.textPrimary,
              letterSpacing: 0.3,
            ),
          ),
        ],
      ),
      actions: [
        Container(
          margin: const EdgeInsets.only(right: 16, top: 11, bottom: 11),
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          decoration: BoxDecoration(
            color: _Colors.devBadge,
            borderRadius: BorderRadius.circular(4),
            border: Border.all(color: _Colors.accentDim, width: 1),
          ),
          child: const Text(
            'DEV',
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w700,
              color: _Colors.devText,
              letterSpacing: 1.0,
            ),
          ),
        ),
      ],
    );
  }

  ThemeData _darkTheme() {
    return ThemeData.dark().copyWith(
      scaffoldBackgroundColor: _Colors.bg,
      colorScheme: const ColorScheme.dark(
        primary: _Colors.accent,
        surface: _Colors.surface,
      ),
    );
  }
}

// ── Import button ─────────────────────────────────────────────────────────────
class _ImportButton extends StatelessWidget {
  const _ImportButton({required this.isLoading, this.onPressed});
  final bool isLoading;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 50,
      child: ElevatedButton(
        onPressed: onPressed,
        style: ElevatedButton.styleFrom(
          backgroundColor: _Colors.accent,
          foregroundColor: Colors.white,
          disabledBackgroundColor: _Colors.accentDim,
          disabledForegroundColor: _Colors.accent.withValues(alpha: 0.5),
          elevation: 0,
          shadowColor: _Colors.accentGlow,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
        ).copyWith(
          overlayColor: WidgetStateProperty.resolveWith(
            (s) => s.contains(WidgetState.pressed)
                ? Colors.white.withValues(alpha: 0.1)
                : null,
          ),
        ),
        child: isLoading
            ? const SizedBox(
                height: 16,
                width: 16,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Colors.white,
                ),
              )
            : Row(
                mainAxisSize: MainAxisSize.min,
                children: const [
                  Icon(Icons.upload_file_rounded, size: 16),
                  SizedBox(width: 8),
                  Text(
                    'Import MusicXML',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 0.2,
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}

// ── Detection inspector button ────────────────────────────────────────────────
class _DetectionButton extends StatelessWidget {
  const _DetectionButton({required this.onPressed});
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 46,
      child: OutlinedButton.icon(
        onPressed: onPressed,
        icon: const Icon(Icons.biotech_outlined, size: 15),
        label: const Text(
          'Detection Inspector',
          style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
        ),
        style: OutlinedButton.styleFrom(
          foregroundColor: _Colors.textSecond,
          side: const BorderSide(color: _Colors.border, width: 1.5),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
        ).copyWith(
          overlayColor: WidgetStateProperty.all(
            _Colors.accent.withValues(alpha: 0.06),
          ),
        ),
      ),
    );
  }
}

// ── Reusable dark card ────────────────────────────────────────────────────────
class _DarkCard extends StatelessWidget {
  const _DarkCard({required this.child, this.accentLeft});
  final Widget child;
  final Color? accentLeft;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: _Colors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _Colors.border, width: 1),
      ),
      clipBehavior: Clip.hardEdge,
      child: accentLeft != null
          ? IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Container(width: 3, color: accentLeft),
                  Expanded(child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: child,
                  )),
                ],
              ),
            )
          : Padding(
              padding: const EdgeInsets.all(16),
              child: child,
            ),
    );
  }
}

// ── Section label ─────────────────────────────────────────────────────────────
class _SectionLabel extends StatelessWidget {
  const _SectionLabel({required this.label});
  final String label;

  @override
  Widget build(BuildContext context) {
    return Text(
      label,
      style: const TextStyle(
        fontSize: 10,
        fontWeight: FontWeight.w700,
        color: _Colors.textSecond,
        letterSpacing: 1.4,
      ),
    );
  }
}

// ── Dark-themed collapsible section ──────────────────────────────────────────
class _DarkCollapsible extends StatelessWidget {
  const _DarkCollapsible({
    required this.label,
    required this.icon,
    required this.enabled,
    required this.expanded,
    this.onToggle,
    this.child,
  });

  final String label;
  final IconData icon;
  final bool enabled;
  final bool expanded;
  final VoidCallback? onToggle;
  final Widget? child;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: _Colors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _Colors.border, width: 1),
      ),
      clipBehavior: Clip.hardEdge,
      child: Column(
        children: [
          // Header row
          Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: onToggle,
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 14,
                ),
                child: Row(
                  children: [
                    Icon(
                      icon,
                      size: 14,
                      color: enabled ? _Colors.accent : _Colors.textSecond,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        label,
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 1.4,
                          color: enabled
                              ? _Colors.textPrimary
                              : _Colors.textSecond,
                        ),
                      ),
                    ),
                    if (!enabled)
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: _Colors.surfaceAlt,
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: const Text(
                          'NO DATA',
                          style: TextStyle(
                            fontSize: 9,
                            fontWeight: FontWeight.w600,
                            color: _Colors.textSecond,
                            letterSpacing: 0.8,
                          ),
                        ),
                      )
                    else
                      AnimatedRotation(
                        turns: expanded ? 0.5 : 0,
                        duration: const Duration(milliseconds: 200),
                        child: const Icon(
                          Icons.keyboard_arrow_down_rounded,
                          size: 18,
                          color: _Colors.textSecond,
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),

          // Expandable content
          AnimatedSize(
            duration: const Duration(milliseconds: 250),
            curve: Curves.easeInOut,
            child: expanded && child != null
                ? Column(
                    children: [
                      Container(height: 1, color: _Colors.border),
                      Padding(
                        padding: const EdgeInsets.all(16),
                        child: child!,
                      ),
                    ],
                  )
                : const SizedBox.shrink(),
          ),
        ],
      ),
    );
  }
}