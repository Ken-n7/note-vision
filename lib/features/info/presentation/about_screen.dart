import 'package:flutter/material.dart';
import 'package:note_vision/core/services/debug_mode_service.dart';
import 'package:note_vision/core/theme/app_theme.dart';
import 'package:note_vision/core/utils/app_reset.dart';
import 'package:note_vision/features/landing/presentation/onboarding_screen.dart';

class AboutScreen extends StatefulWidget {
  const AboutScreen({super.key});

  static const routeName = '/about';

  @override
  State<AboutScreen> createState() => _AboutScreenState();
}

class _AboutScreenState extends State<AboutScreen> {
  static const _appVersion = '1.0.0';

  static const _contributors = ['Ken Canete'];

  static const _techStack = [
    _Tech(label: 'Flutter', detail: 'Cross-platform UI framework'),
    _Tech(label: 'TFLite', detail: 'On-device ML inference'),
    _Tech(label: 'MIDI / FluidSynth', detail: 'Score playback via SF2 soundfonts'),
    _Tech(label: 'MusicXML', detail: 'Standard score interchange format'),
    _Tech(label: 'pdf', detail: 'PDF export'),
  ];

  bool _debugMode = false;
  bool _resetting = false;

  @override
  void initState() {
    super.initState();
    DebugModeService.isEnabled().then((v) {
      if (mounted) setState(() => _debugMode = v);
    });
  }

  Future<void> _onDebugToggle(bool value) async {
    final action = value ? 'Enable' : 'Disable';
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(
          '$action debug mode?',
          style: const TextStyle(
            color: AppColors.textPrimary,
            fontSize: 17,
            fontWeight: FontWeight.w700,
          ),
        ),
        content: const Text(
          'All app data will be cleared and the app will restart from the beginning.',
          style: TextStyle(color: AppColors.textSecondary, fontSize: 14, height: 1.5),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel', style: TextStyle(color: AppColors.textSecondary)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(
              action,
              style: const TextStyle(color: AppColors.accent, fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;
    setState(() => _resetting = true);

    await AppReset.clearAndSetDebugMode(debugMode: value);
    if (!mounted) return;

    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const OnboardingScreen()),
      (_) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        foregroundColor: AppColors.textPrimary,
        elevation: 0,
        title: const Text(
          'About',
          style: TextStyle(
            color: AppColors.textPrimary,
            fontSize: 18,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
        children: [
          _AppHeader(version: _appVersion),
          const SizedBox(height: 24),
          _Section(
            title: 'Credits',
            child: _ContributorList(names: _contributors),
          ),
          const SizedBox(height: 16),
          _Section(
            title: 'Tech Stack',
            child: _TechList(items: _techStack),
          ),
          const SizedBox(height: 16),
          _Section(
            title: 'Developer',
            child: _DebugModeToggle(
              enabled: _debugMode,
              resetting: _resetting,
              onChanged: _onDebugToggle,
            ),
          ),
        ],
      ),
    );
  }
}

class _DebugModeToggle extends StatelessWidget {
  const _DebugModeToggle({
    required this.enabled,
    required this.resetting,
    required this.onChanged,
  });

  final bool enabled;
  final bool resetting;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: (enabled ? AppColors.accent : AppColors.textSecondary)
                    .withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(
                Icons.bug_report_outlined,
                size: 18,
                color: enabled ? AppColors.accent : AppColors.textSecondary,
              ),
            ),
            const SizedBox(width: 12),
            const Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Debug Mode',
                    style: TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  SizedBox(height: 2),
                  Text(
                    'Enables role switcher. Clears all data on toggle.',
                    style: TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 11,
                      height: 1.4,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            if (resetting)
              const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: AppColors.accent,
                ),
              )
            else
              Switch(
                value: enabled,
                onChanged: onChanged,
                thumbColor: WidgetStateProperty.resolveWith(
                  (states) => states.contains(WidgetState.selected)
                      ? AppColors.accent
                      : AppColors.textSecondary,
                ),
                trackColor: WidgetStateProperty.resolveWith(
                  (states) => states.contains(WidgetState.selected)
                      ? AppColors.accent.withValues(alpha: 0.3)
                      : AppColors.border,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _Tech {
  final String label;
  final String detail;
  const _Tech({required this.label, required this.detail});
}

class _AppHeader extends StatelessWidget {
  const _AppHeader({required this.version});

  final String version;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        children: [
          Container(
            width: 72,
            height: 72,
            decoration: BoxDecoration(
              color: AppColors.accent.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: AppColors.accent.withValues(alpha: 0.3),
              ),
            ),
            child: const Icon(
              Icons.music_note_rounded,
              color: AppColors.accent,
              size: 36,
            ),
          ),
          const SizedBox(height: 14),
          const Text(
            'Note Vision',
            style: TextStyle(
              color: AppColors.textPrimary,
              fontSize: 22,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.3,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Version $version',
            style: const TextStyle(
              color: AppColors.textSecondary,
              fontSize: 13,
            ),
          ),
          const SizedBox(height: 14),
          const Text(
            'NoteVision turns photos of sheet music into editable, playable scores — scan, correct, play back, and export, all from your phone.',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: AppColors.textSecondary,
              fontSize: 13,
              height: 1.55,
            ),
          ),
        ],
      ),
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({required this.title, required this.child});

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title.toUpperCase(),
          style: TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.w600,
            color: AppColors.textSecondary.withValues(alpha: 0.6),
            letterSpacing: 2.0,
          ),
        ),
        const SizedBox(height: 10),
        child,
      ],
    );
  }
}

class _ContributorList extends StatelessWidget {
  const _ContributorList({required this.names});

  final List<String> names;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        children: [
          for (var i = 0; i < names.length; i++) ...[
            if (i > 0)
              const Divider(height: 1, color: AppColors.border, indent: 16, endIndent: 16),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              child: Row(
                children: [
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: AppColors.accent.withValues(alpha: 0.12),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.person_outline_rounded,
                      color: AppColors.accent,
                      size: 18,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Text(
                    names[i],
                    style: const TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _TechList extends StatelessWidget {
  const _TechList({required this.items});

  final List<_Tech> items;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        children: [
          for (var i = 0; i < items.length; i++) ...[
            if (i > 0)
              const Divider(height: 1, color: AppColors.border, indent: 16, endIndent: 16),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      items[i].label,
                      style: const TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                  Text(
                    items[i].detail,
                    style: const TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}
