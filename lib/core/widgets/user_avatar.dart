import 'dart:io';
import 'package:flutter/material.dart';

// No internal imports needed — this is the base widget other files depend on.

/// A circular avatar that shows a profile [photoPath] when available, or falls
/// back to displaying [initial] on a dark background.
///
/// Used in both CollectionHeader and AppDrawerHeader so rendering logic
/// lives in exactly one place.
class UserAvatar extends StatelessWidget {
  /// Absolute path to the saved profile photo. May be null if no photo chosen.
  final String? photoPath;

  /// First letter of the username — shown when [photoPath] is absent.
  final String initial;

  /// Diameter of the circular avatar.
  final double size;

  /// Border colour. Defaults to a subtle dark ring.
  final Color? borderColor;

  /// Border thickness. Set to 0 to remove the border.
  final double borderWidth;

  const UserAvatar({
    super.key,
    required this.initial,
    this.photoPath,
    this.size = 40,
    this.borderColor,
    this.borderWidth = 1.5,
  });

  @override
  Widget build(BuildContext context) {
    final File? photoFile = _resolvePhoto();

    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: const Color(0xFF1A1A1A),
        border: borderWidth > 0
            ? Border.all(
                color: borderColor ?? const Color(0xFF2A2A2A),
                width: borderWidth,
              )
            : null,
      ),
      child: ClipOval(
        child: photoFile != null
            ? Image.file(
                photoFile,
                fit: BoxFit.cover,
                width: size,
                height: size,
                errorBuilder: (_, __, ___) => _buildInitial(),
              )
            : _buildInitial(),
      ),
    );
  }

  File? _resolvePhoto() {
    if (photoPath == null) return null;
    final file = File(photoPath!);
    return file.existsSync() ? file : null;
  }

  Widget _buildInitial() {
    return Container(
      color: const Color(0xFF1A1A1A),
      alignment: Alignment.center,
      child: Text(
        initial.isNotEmpty ? initial : '?',
        style: TextStyle(
          color: const Color(0xFFE8C547),
          fontSize: size * 0.42,
          fontWeight: FontWeight.w700,
          height: 1,
        ),
      ),
    );
  }
}