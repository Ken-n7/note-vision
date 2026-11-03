import 'package:flutter/material.dart';

import '../../../../../core/theme/app_theme.dart';

enum EditorToolMode { edit, insert, measure }

/// A stable home for editing controls, beside or below the score.
/// Its contents scroll independently so large text never covers the canvas.
class EditorToolDock extends StatelessWidget {
  const EditorToolDock({
    super.key,
    required this.mode,
    required this.onModeChanged,
    required this.title,
    required this.subtitle,
    required this.child,
    this.onPreviousSymbol,
    this.onNextSymbol,
    this.onDeleteSymbol,
    this.showSymbolNavigation = false,
    this.disabled = false,
  });

  final EditorToolMode mode;
  final ValueChanged<EditorToolMode> onModeChanged;
  final String title, subtitle;
  final Widget child;
  final VoidCallback? onPreviousSymbol, onNextSymbol, onDeleteSymbol;
  final bool showSymbolNavigation, disabled;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      color: AppColors.surface,
      border: Border.all(color: AppColors.border),
      borderRadius: BorderRadius.circular(12),
    ),
    child: Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(6, 6, 6, 0),
          child: Row(
            children: [
              for (final (value, icon, label) in const [
                (EditorToolMode.edit, Icons.touch_app_outlined, 'Edit'),
                (EditorToolMode.insert, Icons.add_rounded, 'Add notes'),
                (EditorToolMode.measure, Icons.view_week_outlined, 'Bar tools'),
              ])
                Expanded(
                  child: Semantics(
                    button: true,
                    selected: mode == value,
                    enabled: !disabled,
                    label: label,
                    onTap: disabled ? null : () => onModeChanged(value),
                    excludeSemantics: true,
                    child: TextButton(
                      key: ValueKey('editor-mode-${value.name}'),
                      onPressed: disabled ? null : () => onModeChanged(value),
                      style: TextButton.styleFrom(
                        minimumSize: const Size(44, 44),
                        padding: const EdgeInsets.symmetric(horizontal: 4),
                        foregroundColor: mode == value
                            ? AppColors.accent
                            : AppColors.textSecondary,
                        backgroundColor: mode == value
                            ? AppColors.accent.withValues(alpha: .12)
                            : Colors.transparent,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(icon, size: 17),
                          const SizedBox(width: 4),
                          Flexible(
                            child: Text(
                              MediaQuery.textScalerOf(context).scale(12) > 18
                                  ? switch (value) {
                                      EditorToolMode.insert => 'Add',
                                      EditorToolMode.measure => 'Bars',
                                      EditorToolMode.edit => label,
                                    }
                                  : label,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontSize: 12),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
        const Divider(height: 12),
        Expanded(
          child: SingleChildScrollView(
            key: const ValueKey('editor-dock-scroll'),
            padding: const EdgeInsets.fromLTRB(10, 0, 10, 10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            title,
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          Text(
                            disabled ? 'Pause playback to edit' : subtitle,
                            style: const TextStyle(
                              color: AppColors.textSecondary,
                              fontSize: 11,
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (showSymbolNavigation) ...[
                      IconButton(
                        tooltip: 'Delete symbol',
                        onPressed: disabled ? null : onDeleteSymbol,
                        color: AppColors.error,
                        icon: const Icon(
                          Icons.delete_outline_rounded,
                          size: 20,
                        ),
                        constraints: const BoxConstraints.tightFor(
                          width: 44,
                          height: 44,
                        ),
                      ),
                      IconButton(
                        tooltip: 'Previous symbol',
                        onPressed: disabled ? null : onPreviousSymbol,
                        icon: const Icon(Icons.chevron_left_rounded),
                        constraints: const BoxConstraints.tightFor(
                          width: 44,
                          height: 44,
                        ),
                      ),
                      IconButton(
                        tooltip: 'Next symbol',
                        onPressed: disabled ? null : onNextSymbol,
                        icon: const Icon(Icons.chevron_right_rounded),
                        constraints: const BoxConstraints.tightFor(
                          width: 44,
                          height: 44,
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 8),
                child,
              ],
            ),
          ),
        ),
      ],
    ),
  );
}

class EditorToolRow extends StatelessWidget {
  const EditorToolRow({super.key, required this.children, this.wrap = false});

  final List<Widget> children;
  final bool wrap;

  @override
  Widget build(BuildContext context) => wrap
      ? Wrap(spacing: 6, runSpacing: 6, children: children)
      : SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              for (var i = 0; i < children.length; i++) ...[
                if (i > 0) const SizedBox(width: 6),
                children[i],
              ],
            ],
          ),
        );
}
