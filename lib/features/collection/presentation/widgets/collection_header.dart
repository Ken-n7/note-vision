import 'package:flutter/material.dart';

import '../../../../core/services/user_profile_service.dart';
import '../../../../core/widgets/user_avatar.dart';

/// The header block at the top of the Collection screen.
///
/// Shows the app title and, below it, the saved username + a small avatar.
/// Uses [FutureBuilder] so Sprint 8 profile edits are reflected on next
/// rebuild without any additional wiring.
class CollectionHeader extends StatefulWidget {
  const CollectionHeader({super.key});

  @override
  State<CollectionHeader> createState() => _CollectionHeaderState();
}

class _CollectionHeaderState extends State<CollectionHeader> {
  late Future<UserProfile?> _profileFuture;

  @override
  void initState() {
    super.initState();
    _profileFuture = UserProfileService.loadProfile();
  }

  /// Call to force a re-read from SharedPreferences — e.g. after Sprint 8
  /// profile edit completes.
  void refresh() {
    setState(() {
      _profileFuture = UserProfileService.loadProfile();
    });
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<UserProfile?>(
      future: _profileFuture,
      builder: (context, snapshot) {
        final profile = snapshot.data;

        return Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── App title ────────────────────────────────────────────────
              const Text(
                'My Collection',
                style: TextStyle(
                  color: Color(0xFFF5F5F5),
                  fontSize: 28,
                  fontWeight: FontWeight.w700,
                  letterSpacing: -0.8,
                  height: 1.1,
                ),
              ),

              if (profile != null) ...[
                const SizedBox(height: 10),

                // ── Username + avatar row ────────────────────────────────
                Row(
                  children: [
                    UserAvatar(
                      initial: profile.initial,
                      photoPath: profile.photoPath,
                      size: 28,
                      borderColor: const Color(0xFF2A2A2A),
                      borderWidth: 1.5,
                    ),
                    const SizedBox(width: 8),
                    Flexible(
                      child: Text(
                        profile.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Color(0xFF888888),
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                          letterSpacing: 0.1,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ],
          ),
        );
      },
    );
  }
}