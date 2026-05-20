import 'dart:io';

import 'package:flutter/material.dart';
import 'package:note_vision/core/models/score.dart';
import 'package:note_vision/core/theme/app_theme.dart';
import 'package:note_vision/core/widgets/score_page_thumbnail.dart';

class ScoreCard extends StatelessWidget {
  final String imagePath;
  final ImageProvider? imageProvider;
  final Score? score;
  final String? title;
  final String? composer;
  final String? scoreLabel;
  final String? updatedLabel;
  final VoidCallback? onDelete;
  final VoidCallback? onOpen;
  final VoidCallback? onRename;
  final VoidCallback? onExport;

  const ScoreCard({
    super.key,
    required this.imagePath,
    this.imageProvider,
    this.score,
    this.title,
    this.composer,
    this.scoreLabel,
    this.updatedLabel,
    this.onDelete,
    this.onOpen,
    this.onRename,
    this.onExport,
  });

  bool get _hasScorePreview =>
      score != null &&
      score!.parts.isNotEmpty &&
      score!.parts.first.measures.isNotEmpty;

  bool get _hasImageFallback =>
      imageProvider != null || imagePath.trim().isNotEmpty;

  bool get _hasMenu => onRename != null || onExport != null || onDelete != null;

  @override
  Widget build(BuildContext context) {
    final displayTitle = _clean(title) ?? _clean(score?.title) ?? 'Untitled';
    final displayComposer = _clean(composer) ?? _clean(score?.composer);

    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: Material(
        color: AppColors.surface,
        child: InkWell(
          onTap: onOpen,
          child: Stack(
            fit: StackFit.expand,
            children: [
              Column(
                children: [
                  Expanded(
                    flex: 65,
                    child: LayoutBuilder(
                      builder: (context, constraints) => _buildPreview(
                        width: constraints.maxWidth,
                        height: constraints.maxHeight,
                      ),
                    ),
                  ),
                  Expanded(
                    flex: 35,
                    child: _ScoreCardFooter(
                      title: displayTitle,
                      composer: displayComposer,
                      scoreLabel: scoreLabel,
                      updatedLabel: updatedLabel,
                    ),
                  ),
                ],
              ),
              if (_hasMenu)
                Positioned(
                  top: 8,
                  right: 8,
                  child: _ScoreCardMenu(
                    onRename: onRename,
                    onExport: onExport,
                    onDelete: onDelete == null
                        ? null
                        : () => _confirmDelete(context),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPreview({required double width, required double height}) {
    if (_hasScorePreview) {
      return ScorePageThumbnail(
        score: score!,
        pageIndex: 0,
        cardWidth: width,
        height: height,
      );
    }

    if (_hasImageFallback) {
      return Image(
        image: imageProvider ?? FileImage(File(imagePath)),
        fit: BoxFit.cover,
        width: width,
        height: height,
        errorBuilder: (_, _, _) => const _ScoreCardPlaceholder(),
      );
    }

    return const _ScoreCardShimmer();
  }

  void _confirmDelete(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => _DeleteConfirmSheet(onConfirm: onDelete!),
    );
  }

  String? _clean(String? value) {
    final trimmed = value?.trim();
    if (trimmed == null || trimmed.isEmpty) return null;
    return trimmed;
  }
}

class _ScoreCardFooter extends StatelessWidget {
  const _ScoreCardFooter({
    required this.title,
    required this.composer,
    required this.scoreLabel,
    required this.updatedLabel,
  });

  final String title;
  final String? composer;
  final String? scoreLabel;
  final String? updatedLabel;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      color: AppColors.surface,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: AppColors.textPrimary,
              fontSize: 14,
              fontWeight: FontWeight.w700,
            ),
          ),
          if (composer != null) ...[
            const SizedBox(height: 2),
            Text(
              composer!,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: AppColors.textSecondary,
                fontSize: 11,
              ),
            ),
          ],
          const Spacer(),
          Row(
            children: [
              if (scoreLabel != null)
                Flexible(child: _ScoreCardLabelBadge(label: scoreLabel!)),
              if (updatedLabel != null) ...[
                if (scoreLabel != null) const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    updatedLabel!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.right,
                    style: const TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 10,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

class _ScoreCardLabelBadge extends StatelessWidget {
  const _ScoreCardLabelBadge({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: AppColors.accent.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: AppColors.accent.withValues(alpha: 0.22)),
      ),
      child: Text(
        label,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(
          color: AppColors.accent,
          fontSize: 11,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

enum _ScoreCardAction { rename, export, delete }

class _ScoreCardMenu extends StatelessWidget {
  const _ScoreCardMenu({
    required this.onRename,
    required this.onExport,
    required this.onDelete,
  });

  final VoidCallback? onRename;
  final VoidCallback? onExport;
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<_ScoreCardAction>(
      tooltip: 'Project actions',
      color: AppColors.surface,
      onSelected: (action) {
        switch (action) {
          case _ScoreCardAction.rename:
            onRename?.call();
          case _ScoreCardAction.export:
            onExport?.call();
          case _ScoreCardAction.delete:
            onDelete?.call();
        }
      },
      itemBuilder: (_) => [
        if (onRename != null)
          const PopupMenuItem(
            value: _ScoreCardAction.rename,
            child: _ScoreCardActionRow(
              icon: Icons.drive_file_rename_outline_rounded,
              label: 'Rename',
            ),
          ),
        if (onExport != null)
          const PopupMenuItem(
            value: _ScoreCardAction.export,
            child: _ScoreCardActionRow(
              icon: Icons.ios_share_rounded,
              label: 'Export',
            ),
          ),
        if (onDelete != null)
          const PopupMenuItem(
            value: _ScoreCardAction.delete,
            child: _ScoreCardActionRow(
              icon: Icons.delete_outline_rounded,
              label: 'Delete',
              color: Color(0xFFE05252),
            ),
          ),
      ],
      child: Container(
        width: 34,
        height: 34,
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.56),
          shape: BoxShape.circle,
          border: Border.all(
            color: Colors.white.withValues(alpha: 0.15),
            width: 0.5,
          ),
        ),
        child: const Icon(
          Icons.more_vert_rounded,
          size: 18,
          color: Colors.white,
        ),
      ),
    );
  }
}

class _ScoreCardActionRow extends StatelessWidget {
  const _ScoreCardActionRow({
    required this.icon,
    required this.label,
    this.color = AppColors.textPrimary,
  });

  final IconData icon;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 18, color: color),
        const SizedBox(width: 10),
        Text(
          label,
          style: TextStyle(
            color: color,
            fontSize: 13,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }
}

class _ScoreCardPlaceholder extends StatelessWidget {
  const _ScoreCardPlaceholder();

  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color(0xFFE5E7EB),
      child: const Icon(Icons.broken_image, color: Color(0xFF9CA3AF)),
    );
  }
}

class _ScoreCardShimmer extends StatefulWidget {
  const _ScoreCardShimmer();

  @override
  State<_ScoreCardShimmer> createState() => _ScoreCardShimmerState();
}

class _ScoreCardShimmerState extends State<_ScoreCardShimmer>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        final value = 0.35 + (_controller.value * 0.25);
        return Container(
          color: Color.lerp(
            const Color(0xFF2A2A2A),
            const Color(0xFF3A3A3A),
            value,
          ),
        );
      },
    );
  }
}

class _DeleteConfirmSheet extends StatelessWidget {
  final VoidCallback onConfirm;

  const _DeleteConfirmSheet({required this.onConfirm});

  static const _surface = AppColors.surface;
  static const _border = AppColors.border;
  static const _textPri = AppColors.textPrimary;
  static const _textSec = AppColors.textSecondary;

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
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: const Color(0xFFFF4444).withValues(alpha: 0.12),
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
            'Delete Score',
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
              'This score will be permanently removed from your collection.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13, color: _textSec, height: 1.4),
            ),
          ),
          const SizedBox(height: 24),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 0),
            child: Row(
              children: [
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
                Expanded(
                  child: GestureDetector(
                    onTap: () {
                      Navigator.pop(context);
                      onConfirm();
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 13),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFF4444).withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: const Color(0xFFFF4444).withValues(alpha: 0.4),
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
