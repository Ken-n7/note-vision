import 'package:flutter/material.dart';
import 'package:note_vision/core/services/playback_display_preferences_service.dart';
import 'package:note_vision/core/services/scan_preferences_service.dart';
import 'package:note_vision/core/services/usage_stats_service.dart';
import 'package:note_vision/core/services/user_profile_service.dart';
import 'package:note_vision/core/theme/app_theme.dart';
import 'package:note_vision/core/widgets/user_avatar.dart';
import 'package:note_vision/features/profile/presentation/edit_profile_sheet.dart';

class ProfileStatsScreen extends StatefulWidget {
  const ProfileStatsScreen({super.key});

  static const routeName = '/profile';

  @override
  State<ProfileStatsScreen> createState() => _ProfileStatsScreenState();
}

class _ProfileStatsScreenState extends State<ProfileStatsScreen> {
  late Future<List<Object?>> _dataFuture;

  @override
  void initState() {
    super.initState();
    _dataFuture = _loadData();
  }

  Future<List<Object?>> _loadData() => Future.wait([
    UserProfileService.loadProfile(),
    UsageStatsService.loadStats(),
  ]);

  Future<void> _onEditTap(UserProfile? current) async {
    await showModalBottomSheet<UserProfile>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => EditProfileSheet(profile: current),
    );
    if (!mounted) return;
    final refreshed = _loadData();
    setState(() {
      _dataFuture = refreshed;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 18),
          color: AppColors.textPrimary,
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: const Text(
          'My Profile',
          style: TextStyle(
            color: AppColors.textPrimary,
            fontSize: 17,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
      body: FutureBuilder<List<Object?>>(
        future: _dataFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(
              child: CircularProgressIndicator(
                color: AppColors.accent,
                strokeWidth: 2,
              ),
            );
          }

          final data = snapshot.data;
          final profile = (data != null && data.isNotEmpty)
              ? data[0] as UserProfile?
              : null;
          final stats = (data != null && data.length > 1)
              ? data[1] as UsageStats? ??
                    const UsageStats(scans: 0, exports: 0, playbacks: 0)
              : const UsageStats(scans: 0, exports: 0, playbacks: 0);

          return SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _ProfileSection(
                  profile: profile,
                  onEditTap: () => _onEditTap(profile),
                ),
                const SizedBox(height: 28),
                _StatsSection(stats: stats),
                const SizedBox(height: 28),
                const _ScanSettingsSection(),
                const SizedBox(height: 28),
                const _PlaybackSettingsSection(),
              ],
            ),
          );
        },
      ),
    );
  }
}

// ─── Profile section ──────────────────────────────────────────────────────────

class _ProfileSection extends StatelessWidget {
  const _ProfileSection({required this.profile, required this.onEditTap});

  final UserProfile? profile;
  final VoidCallback onEditTap;

  @override
  Widget build(BuildContext context) {
    final name = profile?.name ?? '';
    final initial = profile?.initial ?? '?';
    final photo = profile?.photoPath;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          UserAvatar(
            initial: initial,
            photoPath: photo,
            size: 64,
            borderColor: AppColors.border,
            borderWidth: 2,
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name.isNotEmpty ? name : 'No name set',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontFamily: 'PlayfairDisplay',
                    fontSize: 20,
                    color: AppColors.textPrimary,
                    letterSpacing: 0.5,
                  ),
                ),
                const SizedBox(height: 2),
                const Text(
                  'Music sheet scanner',
                  style: TextStyle(
                    fontSize: 12,
                    color: AppColors.textSecondary,
                    letterSpacing: 0.2,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          OutlinedButton(
            onPressed: onEditTap,
            style: OutlinedButton.styleFrom(
              foregroundColor: AppColors.accent,
              side: const BorderSide(color: AppColors.accent),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              minimumSize: Size.zero,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            child: const Text(
              'Edit',
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Stats section ────────────────────────────────────────────────────────────

class _StatsSection extends StatelessWidget {
  const _StatsSection({required this.stats});

  final UsageStats stats;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'YOUR STATS',
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w600,
            color: AppColors.textSecondary,
            letterSpacing: 2.0,
          ),
        ),
        const SizedBox(height: 14),
        GridView.count(
          crossAxisCount: 2,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          mainAxisSpacing: 12,
          crossAxisSpacing: 12,
          childAspectRatio: 1.4,
          children: [
            _StatCard(
              icon: Icons.camera_alt_outlined,
              label: 'Scans',
              count: stats.scans,
            ),
            _StatCard(
              icon: Icons.ios_share_rounded,
              label: 'Exports',
              count: stats.exports,
            ),
            _StatCard(
              icon: Icons.play_circle_outline_rounded,
              label: 'Playbacks',
              count: stats.playbacks,
            ),
          ],
        ),
      ],
    );
  }
}

class _StatCard extends StatelessWidget {
  const _StatCard({
    required this.icon,
    required this.label,
    required this.count,
  });

  final IconData icon;
  final String label;
  final int count;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: AppColors.accent.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, size: 16, color: AppColors.accent),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '$count',
                style: const TextStyle(
                  fontSize: 26,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textPrimary,
                  height: 1.0,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                label,
                style: const TextStyle(
                  fontSize: 11,
                  color: AppColors.textSecondary,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ─── Playback settings section ────────────────────────────────────────────────

class _PlaybackSettingsSection extends StatefulWidget {
  const _PlaybackSettingsSection();

  @override
  State<_PlaybackSettingsSection> createState() =>
      _PlaybackSettingsSectionState();
}

class _PlaybackSettingsSectionState extends State<_PlaybackSettingsSection> {
  bool _showSymbolGlow =
      PlaybackDisplayPreferencesService.showSymbolGlowNotifier.value;

  @override
  void initState() {
    super.initState();
    PlaybackDisplayPreferencesService.showSymbolGlowNotifier.addListener(
      _onPreferenceChanged,
    );
    _load();
  }

  @override
  void dispose() {
    PlaybackDisplayPreferencesService.showSymbolGlowNotifier.removeListener(
      _onPreferenceChanged,
    );
    super.dispose();
  }

  Future<void> _load() async {
    final value = await PlaybackDisplayPreferencesService.getShowSymbolGlow();
    if (!mounted) return;
    setState(() => _showSymbolGlow = value);
  }

  void _onPreferenceChanged() {
    if (!mounted) return;
    setState(() {
      _showSymbolGlow =
          PlaybackDisplayPreferencesService.showSymbolGlowNotifier.value;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'PLAYBACK SETTINGS',
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w600,
            color: AppColors.textSecondary,
            letterSpacing: 2.0,
          ),
        ),
        const SizedBox(height: 14),
        Container(
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: AppColors.border),
          ),
          child: _buildToggle(
            icon: Icons.graphic_eq_rounded,
            title: 'Show symbol glow',
            subtitle: 'Keep the gold note/rest glow during playback',
            value: _showSymbolGlow,
            onChanged: (v) async {
              setState(() => _showSymbolGlow = v);
              await PlaybackDisplayPreferencesService.setShowSymbolGlow(v);
            },
          ),
        ),
      ],
    );
  }

  Widget _buildToggle({
    required IconData icon,
    required String title,
    required String subtitle,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      leading: Container(
        padding: const EdgeInsets.all(6),
        decoration: BoxDecoration(
          color: AppColors.accent.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Icon(icon, size: 16, color: AppColors.accent),
      ),
      title: Text(
        title,
        style: const TextStyle(
          color: AppColors.textPrimary,
          fontSize: 14,
          fontWeight: FontWeight.w500,
        ),
      ),
      subtitle: Text(
        subtitle,
        style: const TextStyle(color: AppColors.textSecondary, fontSize: 12),
      ),
      trailing: Switch(
        value: value,
        onChanged: onChanged,
        activeThumbColor: AppColors.accent,
        activeTrackColor: AppColors.accent.withValues(alpha: 0.4),
        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),
    );
  }
}

// ─── Scan settings section ────────────────────────────────────────────────────

class _ScanSettingsSection extends StatefulWidget {
  const _ScanSettingsSection();

  @override
  State<_ScanSettingsSection> createState() => _ScanSettingsSectionState();
}

class _ScanSettingsSectionState extends State<_ScanSettingsSection> {
  bool _skipPreview = false;
  bool _skipReview = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final results = await Future.wait([
      ScanPreferencesService.getSkipPreview(),
      ScanPreferencesService.getSkipReview(),
    ]);
    if (!mounted) return;
    setState(() {
      _skipPreview = results[0];
      _skipReview = results[1];
    });
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'SCAN SETTINGS',
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w600,
            color: AppColors.textSecondary,
            letterSpacing: 2.0,
          ),
        ),
        const SizedBox(height: 14),
        Container(
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: AppColors.border),
          ),
          child: Column(
            children: [
              _buildToggle(
                icon: Icons.hide_image_outlined,
                title: 'Skip image preview',
                subtitle: 'Go straight to scanning when an image is selected',
                value: _skipPreview,
                onChanged: (v) async {
                  setState(() => _skipPreview = v);
                  await ScanPreferencesService.setSkipPreview(v);
                },
              ),
              const Divider(
                color: AppColors.border,
                height: 1,
                indent: 16,
                endIndent: 16,
              ),
              _buildToggle(
                icon: Icons.skip_next_rounded,
                title: 'Skip scan review',
                subtitle: 'Auto-proceed to editor when detection completes',
                value: _skipReview,
                onChanged: (v) async {
                  setState(() => _skipReview = v);
                  await ScanPreferencesService.setSkipReview(v);
                },
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildToggle({
    required IconData icon,
    required String title,
    required String subtitle,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      leading: Container(
        padding: const EdgeInsets.all(6),
        decoration: BoxDecoration(
          color: AppColors.accent.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Icon(icon, size: 16, color: AppColors.accent),
      ),
      title: Text(
        title,
        style: const TextStyle(
          color: AppColors.textPrimary,
          fontSize: 14,
          fontWeight: FontWeight.w500,
        ),
      ),
      subtitle: Text(
        subtitle,
        style: const TextStyle(color: AppColors.textSecondary, fontSize: 12),
      ),
      trailing: Switch(
        value: value,
        onChanged: onChanged,
        activeThumbColor: AppColors.accent,
        activeTrackColor: AppColors.accent.withValues(alpha: 0.4),
        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),
    );
  }
}
