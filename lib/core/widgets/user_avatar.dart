import 'dart:io';
import 'package:flutter/material.dart';
import 'package:note_vision/core/theme/app_theme.dart';

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
        color: AppColors.surface,
        border: borderWidth > 0
            ? Border.all(
                color: borderColor ?? AppColors.border,
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
                errorBuilder: (_, _, _) => _buildInitial(),
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
      color: AppColors.surface,
      alignment: Alignment.center,
      child: Text(
        initial.isNotEmpty ? initial : '?',
        style: TextStyle(
          color: AppColors.accent,
          fontSize: size * 0.42,
          fontWeight: FontWeight.w700,
          height: 1,
        ),
      ),
    );
  }
}