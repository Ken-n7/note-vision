import 'package:flutter/material.dart';
import 'package:note_vision/core/theme/app_theme.dart';

class EditorHeaderPanel extends StatelessWidget {
  const EditorHeaderPanel({
    required this.title,
    required this.hasUnsavedChanges,
    required this.horizontalPadding,
    required this.onBack,
  });

  final String title;
  final bool hasUnsavedChanges;
  final double horizontalPadding;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(horizontalPadding, 12, horizontalPadding, 8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.border),
        ),
        child: Row(
          children: [
            IconButton(
              onPressed: onBack,
              icon: const Icon(Icons.arrow_back_ios_new, size: 16),
              color: AppColors.textPrimary,
              tooltip: 'Back',
            ),
            const SizedBox(width: 4),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    hasUnsavedChanges ? '$title *' : title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 2),
                  const Text(
                    'Editor Workspace',
                    style: TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
            FilledButton.icon(
              onPressed: () {},
              icon: const Icon(Icons.save_outlined, size: 18),
              label: const Text('Save'),
            ),
            const SizedBox(width: 8),
            OutlinedButton.icon(
              onPressed: () {},
              icon: const Icon(Icons.ios_share_outlined, size: 16),
              label: const Text('Export'),
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.textPrimary,
                side: const BorderSide(color: AppColors.border),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class EditorStatusStrip extends StatelessWidget {
  const EditorStatusStrip({
    required this.horizontalPadding,
    required this.symbolType,
    required this.pitch,
    required this.durationType,
    required this.measure,
    required this.onPrevMeasure,
    required this.onNextMeasure,
  });

  final double horizontalPadding;
  final String symbolType;
  final String pitch;
  final String durationType;
  final String measure;
  final VoidCallback? onPrevMeasure;
  final VoidCallback? onNextMeasure;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: EdgeInsets.fromLTRB(horizontalPadding, 4, horizontalPadding, 4), // ↓ from 8
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6), // ↓ from 12 / 10
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(8), // ↓ from 12
        border: Border.all(color: AppColors.border, width: 0.8), // slightly thinner
      ),
      child: Wrap(
        spacing: 8, // ↓ from 12
        runSpacing: 4, // ↓ from 8
        children: [
          _StatusItem(label: 'Type', value: symbolType),
          _StatusItem(label: 'Pitch', value: pitch),
          _StatusItem(label: 'Duration', value: durationType),
          _StatusItem(label: 'Measure', value: measure),
          _StatusNavButton(
            icon: Icons.chevron_left_rounded,
            onPressed: onPrevMeasure,
          ),
          _StatusNavButton(
            icon: Icons.chevron_right_rounded,
            onPressed: onNextMeasure,
          ),
        ],
      ),
    );
  }
}

class _StatusNavButton extends StatelessWidget {
  const _StatusNavButton({required this.icon, required this.onPressed});

  final IconData icon;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return OutlinedButton(
      onPressed: onPressed,
      style: OutlinedButton.styleFrom(
        side: const BorderSide(color: AppColors.border),
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
        minimumSize: const Size(32, 32),
      ),
      child: Icon(icon, size: 18),
    );
  }
}

class _StatusItem extends StatelessWidget {
  const _StatusItem({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minWidth: 82),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: AppColors.surfaceAlt,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(fontSize: 10, color: AppColors.textSecondary),
          ),
          Text(
            value,
            style: const TextStyle(
              color: AppColors.textPrimary,
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// EDITOR ACTION BAR — restructured layout
// ─────────────────────────────────────────────────────────────────────────────

class EditorActionBarPanel extends StatelessWidget {
  const EditorActionBarPanel({
    required this.horizontalPadding,
    required this.hasSelection,
    required this.hasMeasureContext,
    required this.canUndo,
    required this.canRedo,
    required this.onMoveUp,
    required this.onMoveDown,
    required this.onWhole,
    required this.onHalf,
    required this.onQuarter,
    required this.onEighth,
    required this.onInsertNote,
    required this.onInsertRest,
    required this.onDelete,
    required this.onMoveToPrevMeasure,
    required this.onMoveToNextMeasure,
    required this.onUndo,
    required this.onRedo,
  });

  final double horizontalPadding;
  final bool hasSelection;
  final bool hasMeasureContext;
  final bool canUndo;
  final bool canRedo;
  final VoidCallback onMoveUp;
  final VoidCallback onMoveDown;
  final VoidCallback onWhole;
  final VoidCallback onHalf;
  final VoidCallback onQuarter;
  final VoidCallback onEighth;
  final VoidCallback onInsertNote;
  final VoidCallback onInsertRest;
  final VoidCallback onDelete;
  final VoidCallback onMoveToPrevMeasure;
  final VoidCallback onMoveToNextMeasure;
  final VoidCallback onUndo;
  final VoidCallback onRedo;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: AppColors.surfaceAlt,
      padding: EdgeInsets.fromLTRB(horizontalPadding, 10, horizontalPadding, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── INSERT ROW ────────────────────────────────────────────────────
          const _SectionLabel('INSERT'),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: _InsertDropdown(
                  label: 'Note',
                  icon: Icons.music_note_rounded,
                  enabled: hasMeasureContext,
                  items: const ['Whole', 'Half', 'Quarter', 'Eighth'],
                  onSelected: (value) {
                    // First insert, then set duration based on selection
                    onInsertNote();
                    switch (value) {
                      case 'Whole':
                        onWhole();
                      case 'Half':
                        onHalf();
                      case 'Quarter':
                        onQuarter();
                      case 'Eighth':
                        onEighth();
                    }
                  },
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _InsertDropdown(
                  label: 'Rest',
                  icon: Icons.pause_rounded,
                  enabled: hasMeasureContext,
                  items: const ['Whole', 'Half', 'Quarter', 'Eighth'],
                  onSelected: (value) {
                    // First insert, then set duration based on selection
                    onInsertRest();
                    switch (value) {
                      case 'Whole':
                        onWhole();
                      case 'Half':
                        onHalf();
                      case 'Quarter':
                        onQuarter();
                      case 'Eighth':
                        onEighth();
                    }
                  },
                ),
              ),
            ],
          ),

          const SizedBox(height: 14),

          // ── DURATION ROW ─────────────────────────────────────────────────
          const _SectionLabel('DURATION'),
          const SizedBox(height: 8),
          Row(
            children: [
              _DurationChip(label: 'Whole', onPressed: hasSelection ? onWhole : null),
              const SizedBox(width: 6),
              _DurationChip(label: 'Half', onPressed: hasSelection ? onHalf : null),
              const SizedBox(width: 6),
              _DurationChip(label: 'Quarter', onPressed: hasSelection ? onQuarter : null),
              const SizedBox(width: 6),
              _DurationChip(label: 'Eighth', onPressed: hasSelection ? onEighth : null),
            ],
          ),

          const SizedBox(height: 14),

          // ── CONTROLS ROW ─────────────────────────────────────────────────
          const _SectionLabel('CONTROLS'),
          const SizedBox(height: 8),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              _ControlButton(
                icon: Icons.arrow_upward_rounded,
                label: 'Move Up',
                onPressed: hasSelection ? onMoveUp : null,
              ),
              _ControlButton(
                icon: Icons.arrow_downward_rounded,
                label: 'Move Down',
                onPressed: hasSelection ? onMoveDown : null,
              ),
              _ControlButton(
                icon: Icons.skip_previous_rounded,
                label: 'Prev',
                onPressed: hasSelection ? onMoveToPrevMeasure : null,
              ),
              _ControlButton(
                icon: Icons.skip_next_rounded,
                label: 'Next',
                onPressed: hasSelection ? onMoveToNextMeasure : null,
              ),
              _ControlButton(
                icon: Icons.undo_rounded,
                label: 'Undo',
                onPressed: canUndo ? onUndo : null,
              ),
              _ControlButton(
                icon: Icons.redo_rounded,
                label: 'Redo',
                onPressed: canRedo ? onRedo : null,
              ),
              _ControlButton(
                icon: Icons.delete_outline_rounded,
                label: 'Delete',
                onPressed: hasSelection ? onDelete : null,
                isDestructive: true,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// SUB-WIDGETS
// ─────────────────────────────────────────────────────────────────────────────

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: const TextStyle(
        fontSize: 10,
        color: AppColors.textSecondary,
        letterSpacing: 1.2,
        fontWeight: FontWeight.w600,
      ),
    );
  }
}

/// Dropdown button for inserting notes or rests with duration selection.
class _InsertDropdown extends StatelessWidget {
  const _InsertDropdown({
    required this.label,
    required this.icon,
    required this.enabled,
    required this.items,
    required this.onSelected,
  });

  final String label;
  final IconData icon;
  final bool enabled;
  final List<String> items;
  final void Function(String value) onSelected;

  @override
  Widget build(BuildContext context) {
    return MenuAnchor(
      menuChildren: items.map((item) {
        return MenuItemButton(
          onPressed: enabled ? () => onSelected(item) : null,
          leadingIcon: Icon(
            _durationIcon(item),
            size: 16,
            color: AppColors.textSecondary,
          ),
          child: Text(
            item,
            style: const TextStyle(fontSize: 13, color: AppColors.textPrimary),
          ),
        );
      }).toList(),
      builder: (context, controller, child) {
        return OutlinedButton(
          onPressed: enabled
              ? () {
                  if (controller.isOpen) {
                    controller.close();
                  } else {
                    controller.open();
                  }
                }
              : null,
          child: Text(
            'Insert $label',
            overflow: TextOverflow.ellipsis,
          ),
          style: OutlinedButton.styleFrom(
            backgroundColor: enabled ? AppColors.surface : AppColors.surfaceAlt,
            foregroundColor: enabled ? AppColors.textPrimary : AppColors.textSecondary,
            side: BorderSide(
              color: enabled ? AppColors.accent.withValues(alpha: 0.6) : AppColors.border,
            ),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          ),
        );
      },
    );
  }

  IconData _durationIcon(String duration) {
    switch (duration) {
      case 'Whole':
        return Icons.radio_button_unchecked_rounded;
      case 'Half':
        return Icons.looks_two_outlined;
      case 'Quarter':
        return Icons.looks_one_outlined;
      case 'Eighth':
        return Icons.looks_3_outlined;
      default:
        return Icons.music_note_rounded;
    }
  }
}

/// Compact chip-style duration button (for the Duration row).
class _DurationChip extends StatelessWidget {
  const _DurationChip({required this.label, required this.onPressed});

  final String label;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final enabled = onPressed != null;
    return Expanded(
      child: OutlinedButton(
        onPressed: onPressed,
        style: OutlinedButton.styleFrom(
          backgroundColor: enabled ? AppColors.surface : AppColors.surfaceAlt,
          foregroundColor: enabled ? AppColors.textPrimary : AppColors.textSecondary,
          side: BorderSide(
            color: enabled ? AppColors.accent.withValues(alpha: 0.5) : AppColors.border,
          ),
          padding: const EdgeInsets.symmetric(vertical: 10),
          minimumSize: const Size(0, 36),
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        ),
        child: Text(label, style: const TextStyle(fontSize: 12)),
      ),
    );
  }
}

/// Icon + label control button used in the Controls section.
class _ControlButton extends StatelessWidget {
  const _ControlButton({
    required this.icon,
    required this.label,
    required this.onPressed,
    this.isDestructive = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onPressed;
  final bool isDestructive;

  @override
  Widget build(BuildContext context) {
    final enabled = onPressed != null;

    final Color fgColor;
    final Color borderColor;
    if (!enabled) {
      fgColor = AppColors.textSecondary;
      borderColor = AppColors.border;
    } else if (isDestructive) {
      fgColor = Colors.redAccent;
      borderColor = Colors.redAccent.withValues(alpha: 0.5);
    } else {
      fgColor = AppColors.textPrimary;
      borderColor = AppColors.accent.withValues(alpha: 0.5);
    }

    return OutlinedButton(
      onPressed: onPressed,
      style: OutlinedButton.styleFrom(
        backgroundColor: enabled ? AppColors.surface : AppColors.surfaceAlt,
        foregroundColor: fgColor,
        side: BorderSide(color: borderColor),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        minimumSize: const Size(0, 36),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 15),
          const SizedBox(width: 4),
          Text(label, style: const TextStyle(fontSize: 12)),
        ],
      ),
    );
  }
}
