import 'package:flutter/material.dart';

import '../services/user_profile_service.dart';
import 'user_avatar.dart';

/// The header section of the app's navigation [Drawer].
///
/// Lives at: lib/core/widgets/header_drawer.dart
///
/// Displays:
/// - A 64px circular profile avatar (photo or initial fallback)
/// - The user's display name
/// - A subtle divider below
///
/// Rebuilds from SharedPreferences via [FutureBuilder] so edits made in the
/// stats/profile screen (Sprint 8) are reflected next time the drawer opens.
class HeaderDrawer extends StatelessWidget {
  const HeaderDrawer({super.key});

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<UserProfile?>(
      future: UserProfileService.loadProfile(),
      builder: (context, snapshot) {
        final profile = snapshot.data;
        final name = profile?.name ?? '';
        final initial = profile?.initial ?? '?';
        final photoPath = profile?.photoPath;

        return Container(
          width: double.infinity,
          color: const Color(0xFF111111),
          padding: EdgeInsets.fromLTRB(
            20,
            MediaQuery.of(context).padding.top + 24, // respect status bar
            20,
            20,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── Avatar ──────────────────────────────────────────────────
              UserAvatar(
                initial: initial,
                photoPath: photoPath,
                size: 64,
                borderColor: const Color(0xFF2C2C2C),
                borderWidth: 2,
              ),

              const SizedBox(height: 14),

              // ── Name ────────────────────────────────────────────────────
              if (name.isNotEmpty)
                Text(
                  name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Color(0xFFF5F5F5),
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                    letterSpacing: -0.3,
                  ),
                ),

              const SizedBox(height: 16),

              // ── Divider ─────────────────────────────────────────────────
              Container(height: 1, color: const Color(0xFF222222)),
            ],
          ),
        );
      },
    );
  }
}
