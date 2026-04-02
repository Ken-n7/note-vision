import 'dart:io';
import 'package:flutter/material.dart';

class UserAvatar extends StatelessWidget {
  final String? photoPath;
  final String initial;
  final double size;
  final Color? borderColor;
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
                key: ValueKey(
                  photoFile.existsSync()
                      ? photoFile.lastModifiedSync().millisecondsSinceEpoch
                      : photoPath,
                ),
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