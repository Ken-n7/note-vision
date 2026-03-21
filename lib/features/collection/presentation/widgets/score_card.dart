import 'dart:io';
import 'package:flutter/material.dart';

class ScoreCard extends StatelessWidget {
  final String imagePath;
  final ImageProvider? imageProvider;
  final VoidCallback? onDelete;

  const ScoreCard({
    super.key,
    required this.imagePath,
    this.imageProvider,
    this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(10),
      child: Stack(
        fit: StackFit.expand,
        children: [
          // ── Image ────────────────────────────────────────────────────
          Image(
            image: imageProvider ?? FileImage(File(imagePath)),
            fit: BoxFit.cover,
            errorBuilder: (_, __, ___) => Container(
              color: Colors.grey.shade200,
              child: const Icon(Icons.broken_image, color: Colors.grey),
            ),
          ),

          // ── Top gradient scrim for delete button visibility ───────────
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            height: 56,
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.black.withOpacity(0.55),
                    Colors.transparent,
                  ],
                ),
              ),
            ),
          ),

          // ── Delete button ────────────────────────────────────────────
          if (onDelete != null)
            Positioned(
              top: 6,
              right: 6,
              child: GestureDetector(
                onTap: () => _confirmDelete(context),
                child: Container(
                  width: 28,
                  height: 28,
                  decoration: BoxDecoration(
                    color: Colors.black.withOpacity(0.55),
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: Colors.white.withOpacity(0.15),
                      width: 0.5,
                    ),
                  ),
                  child: const Icon(
                    Icons.close_rounded,
                    size: 15,
                    color: Colors.white,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  void _confirmDelete(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => _DeleteConfirmSheet(onConfirm: onDelete!),
    );
  }
}

// ── Confirmation bottom sheet ──────────────────────────────────────────────

class _DeleteConfirmSheet extends StatelessWidget {
  final VoidCallback onConfirm;

  const _DeleteConfirmSheet({required this.onConfirm});

  static const _surface = Color(0xFF1A1A1A);
  static const _border  = Color(0xFF2C2C2C);
  static const _textPri = Color(0xFFFFFFFF);
  static const _textSec = Color(0xFF8A8A8A);

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 0, 12, 28),
      decoration: BoxDecoration(
        color: _surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _border),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Handle
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: _border,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),

          const SizedBox(height: 20),

          // Icon
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: const Color(0xFFFF4444).withOpacity(0.12),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.delete_outline_rounded,
              color: Color(0xFFFF4444),
              size: 22,
            ),
          ),

          const SizedBox(height: 14),

          const Text(
            'Delete Image',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: _textPri,
            ),
          ),

          const SizedBox(height: 6),

          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 32),
            child: Text(
              'This image will be permanently removed from your collection.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 13,
                color: _textSec,
                height: 1.4,
              ),
            ),
          ),

          const SizedBox(height: 24),

          // Buttons
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 0),
            child: Row(
              children: [
                // Cancel
                Expanded(
                  child: GestureDetector(
                    onTap: () => Navigator.pop(context),
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 13),
                      decoration: BoxDecoration(
                        color: const Color(0xFF2C2C2C),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Center(
                        child: Text(
                          'Cancel',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w500,
                            color: _textPri,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),

                const SizedBox(width: 10),

                // Delete
                Expanded(
                  child: GestureDetector(
                    onTap: () {
                      Navigator.pop(context);
                      onConfirm();
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 13),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFF4444).withOpacity(0.15),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: const Color(0xFFFF4444).withOpacity(0.4),
                        ),
                      ),
                      child: const Center(
                        child: Text(
                          'Delete',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: Color(0xFFFF4444),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 16),
        ],
      ),
    );
  }
}