import 'package:flutter/material.dart';

import '../../../../../core/theme/app_theme.dart';

class EditorHelpSheet extends StatelessWidget {
  const EditorHelpSheet({super.key});

  @override
  Widget build(BuildContext context) => SingleChildScrollView(
    padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            const Expanded(
              child: Text(
                'Make the score your own',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
              ),
            ),
            IconButton(
              tooltip: 'Close help',
              onPressed: () => Navigator.pop(context),
              icon: const Icon(Icons.close_rounded),
            ),
          ],
        ),
        for (final (icon, title, description) in const [
          (
            Icons.touch_app_outlined,
            'Edit a symbol',
            'Tap a note or rest. Change its duration, pitch or accidental in Edit. Use the arrows to select the next symbol.',
          ),
          (
            Icons.add_rounded,
            'Add notes and rests',
            'Choose Add notes, pick a value, then tap the staff where it belongs. You can also hold a palette symbol and drag it onto the score. Choose Edit to finish.',
          ),
          (
            Icons.view_week_outlined,
            'Work with bars',
            'Tap an empty area in a bar, then open Bar tools to add measures, change the time signature or set the staff clef.',
          ),
          (
            Icons.open_with_rounded,
            'Move around',
            'Drag blank space to pan and pinch to zoom. Fit page shows the whole page. Tap the page number to jump to another page.',
          ),
          (
            Icons.manage_search_rounded,
            'Find a command',
            'Open Score commands beside the page controls. Search for an action, then tap it. Unavailable actions explain what to select or change first.',
          ),
          (
            Icons.fact_check_outlined,
            'Review a scan',
            'Open Review to inspect possible recognition issues. Preview each suggested change before applying it.',
          ),
        ])
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 10),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(icon, color: AppColors.accent),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        description,
                        style: const TextStyle(
                          color: AppColors.textSecondary,
                          height: 1.5,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        const Divider(height: 24),
        const Text(
          'Keyboard shortcuts',
          style: TextStyle(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 8),
        for (final (keys, action) in const [
          ('↑ / ↓', 'Raise / lower pitch'),
          ('Ctrl / ⌘ + ↑ / ↓', 'Raise / lower an octave'),
          ('3 / 4 / 5 / 6 / 7', '16th / eighth / quarter / half / whole'),
          ('.', 'Toggle duration dot on the selection'),
          ('← / →', 'Previous / next symbol'),
          ('Delete / Backspace', 'Delete selection'),
          ('N / Esc', 'Toggle note entry / finish editing'),
          ('Space', 'Play / pause'),
          ('Ctrl / ⌘ + Z', 'Undo'),
          ('Ctrl / ⌘ + Shift + Z', 'Redo'),
          ('Ctrl / ⌘ + S', 'Save'),
          ('Ctrl / ⌘ + K', 'Find a score command'),
        ])
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Wrap(
              spacing: 16,
              runSpacing: 4,
              children: [
                Text(keys, style: const TextStyle(color: AppColors.accent)),
                Text(
                  action,
                  style: const TextStyle(color: AppColors.textSecondary),
                ),
              ],
            ),
          ),
      ],
    ),
  );
}
