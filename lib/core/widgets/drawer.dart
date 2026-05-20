import 'package:flutter/material.dart';
import 'package:note_vision/core/config/app_features.dart';
import 'package:note_vision/core/services/debug_mode_service.dart';
import 'package:note_vision/core/services/user_profile_service.dart';
import 'package:note_vision/core/widgets/user_avatar.dart';
import 'package:note_vision/features/info/presentation/about_screen.dart';
import 'package:note_vision/features/info/presentation/instructions_screen.dart';
import 'package:note_vision/features/profile/presentation/profile_stats_screen.dart';

class CollectionDrawer extends StatelessWidget {
  const CollectionDrawer({super.key});

  static const _bg = Color(0xFF0D0D0D);
  static const _border = Color(0xFF2C2C2C);
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
              const _ProfileHeader(),

              Container(
                height: 0.5,
                margin: const EdgeInsets.symmetric(horizontal: 24),
                color: _border,
              ),

              const SizedBox(height: 12),

              // ── ACCOUNT section ───────────────────────────────────────
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 8, 24, 4),
                child: Text(
                  'ACCOUNT',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                    color: _textSecondary.withValues(alpha: 0.6),
                    letterSpacing: 2.0,
                  ),
                ),
              ),

              _DrawerItem(
                icon: Icons.person_outline_rounded,
                title: 'My Profile',
                onTap: () {
                  Navigator.pop(context);
                  Navigator.pushNamed(context, ProfileStatsScreen.routeName);
                },
              ),

              if (AppFeatures.classroomWorkflow)
                FutureBuilder<bool>(
                  future: DebugModeService.isEnabled(),
                  builder: (context, snapshot) {
                    if (snapshot.data == true) {
                      return const _TemporaryRoleSwitch();
                    }
                    return const SizedBox.shrink();
                  },
                ),

              const SizedBox(height: 4),

              Container(
                height: 0.5,
                margin: const EdgeInsets.symmetric(horizontal: 24),
                color: _border,
              ),

              const SizedBox(height: 4),

              // ── NAVIGATE section ──────────────────────────────────────
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

              _DrawerItem(
                icon: Icons.school_outlined,
                title: 'Instructions',
                onTap: () {
                  Navigator.pop(context);
                  Navigator.pushNamed(context, InstructionsScreen.routeName);
                },
              ),
              _DrawerItem(
                icon: Icons.info_outline,
                title: 'About',
                onTap: () {
                  Navigator.pop(context);
                  Navigator.pushNamed(context, AboutScreen.routeName);
                },
              ),

              const Spacer(),
            ],
          ),
        ),
      ),
    );
  }
}

// Temporary debug-only testing helper.
// Remove before presentation if presenting a debug build.
class _TemporaryRoleSwitch extends StatefulWidget {
  const _TemporaryRoleSwitch();

  @override
  State<_TemporaryRoleSwitch> createState() => _TemporaryRoleSwitchState();
}

class _TemporaryRoleSwitchState extends State<_TemporaryRoleSwitch> {
  static const _surface = Color(0xFF1A1A1A);
  static const _border = Color(0xFF2C2C2C);
  static const _textPrimary = Color(0xFFFFFFFF);
  static const _textSecondary = Color(0xFF8A8A8A);

  String _role = 'student';
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _loadRole();
  }

  Future<void> _loadRole() async {
    final role = await UserProfileService.loadRole();
    if (!mounted) return;
    setState(() {
      if (role == 'teacher' || role == 'student') _role = role!;
    });
  }

  Future<void> _setRole(String role) async {
    if (_isSaving || role == _role) return;
    setState(() => _isSaving = true);
    await UserProfileService.saveRole(role);
    if (!mounted) return;
    setState(() {
      _role = role;
      _isSaving = false;
    });
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 6, 12, 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: _surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'TEMP TESTING',
            style: TextStyle(
              color: _textSecondary,
              fontSize: 9,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.6,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'Developer Role Switch',
            style: TextStyle(
              color: _textPrimary,
              fontSize: 13,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: _RoleDebugButton(
                  label: 'Student',
                  selected: _role == 'student',
                  enabled: !_isSaving,
                  onTap: () => _setRole('student'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _RoleDebugButton(
                  label: 'Teacher',
                  selected: _role == 'teacher',
                  enabled: !_isSaving,
                  onTap: () => _setRole('teacher'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          const Text(
            'Remove before presentation unless using a release build.',
            style: TextStyle(color: _textSecondary, fontSize: 10, height: 1.3),
          ),
        ],
      ),
    );
  }
}

class _RoleDebugButton extends StatelessWidget {
  const _RoleDebugButton({
    required this.label,
    required this.selected,
    required this.enabled,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final bool enabled;
  final VoidCallback onTap;

  static const _surfaceAlt = Color(0xFF161616);
  static const _border = Color(0xFF2C2C2C);
  static const _accent = Color(0xFFD4A96A);
  static const _textSecondary = Color(0xFF8A8A8A);

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: enabled ? onTap : null,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 140),
        padding: const EdgeInsets.symmetric(vertical: 9),
        decoration: BoxDecoration(
          color: selected ? _accent.withValues(alpha: 0.16) : _surfaceAlt,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: selected ? _accent : _border),
        ),
        child: Center(
          child: Text(
            label,
            style: TextStyle(
              color: selected ? _accent : _textSecondary,
              fontSize: 12,
              fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
            ),
          ),
        ),
      ),
    );
  }
}

// ─── Profile header ───────────────────────────────────────────────────────────

class _ProfileHeader extends StatefulWidget {
  const _ProfileHeader();

  @override
  State<_ProfileHeader> createState() => _ProfileHeaderState();
}

class _ProfileHeaderState extends State<_ProfileHeader> {
  static const _textPrimary = Color(0xFFFFFFFF);
  static const _textSecondary = Color(0xFF8A8A8A);

  UserProfile? _profile;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  Future<void> _reload() async {
    final profile = await UserProfileService.loadProfile();
    if (mounted) setState(() => _profile = profile);
  }

  void _onAvatarTap() {
    Navigator.pop(context);
    Navigator.pushNamed(context, ProfileStatsScreen.routeName);
  }

  @override
  Widget build(BuildContext context) {
    final name = _profile?.name ?? '';
    final initial = _profile?.initial ?? '?';
    final photo = _profile?.photoPath;

    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 32, 24, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          GestureDetector(
            onTap: _onAvatarTap,
            child: Stack(
              children: [
                UserAvatar(
                  initial: initial,
                  photoPath: photo,
                  size: 56,
                  borderColor: const Color(0xFF2C2C2C),
                  borderWidth: 2,
                ),
                Positioned(
                  bottom: 0,
                  right: 0,
                  child: Container(
                    width: 18,
                    height: 18,
                    decoration: const BoxDecoration(
                      shape: BoxShape.circle,
                      color: Color(0xFFD4A96A),
                    ),
                    child: const Icon(
                      Icons.edit,
                      size: 10,
                      color: Color(0xFF0D0D0D),
                    ),
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 16),

          if (name.isNotEmpty) ...[
            Text(
              name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontFamily: 'PlayfairDisplay',
                fontSize: 20,
                color: _textPrimary,
                letterSpacing: 0.5,
              ),
            ),
            const SizedBox(height: 4),
          ],

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
  static const _accent = Color(0xFFD4A96A);
  static const _textPrimary = Color(0xFFFFFFFF);
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
            Expanded(
              child: Text(
                widget.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w400,
                  color: _hovered ? _textPrimary : _textSecondary,
                  letterSpacing: 0.2,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
