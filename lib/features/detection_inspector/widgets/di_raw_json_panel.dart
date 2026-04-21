// lib/features/dev/detection_inspector/widgets/di_raw_json_panel.dart

import 'package:flutter/material.dart';
import 'di_section_card.dart';

class DiRawJsonPanel extends StatelessWidget {
  final String json;
  final bool expanded;
  final VoidCallback onToggle;

  const DiRawJsonPanel({
    super.key,
    required this.json,
    required this.expanded,
    required this.onToggle,
  });

  @override
  Widget build(BuildContext context) {
    return DiSectionCard(
      label: 'RAW MOCK JSON',
      trailing: _ToggleChip(expanded: expanded, onTap: onToggle),
      child: AnimatedSize(
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeInOut,
        child: expanded
            ? Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFF0B0E16),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: const Color(0xFF1E2235)),
                ),
                child: SelectableText(
                  json.length > 3000
                      ? '${json.substring(0, 3000)}\n\n… (truncated)'
                      : json,
                  style: const TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 10.5,
                    color: Color(0xFF7A8CAF),
                    height: 1.6,
                  ),
                ),
              )
            : const SizedBox(height: 0),
      ),
    );
  }
}

class _ToggleChip extends StatelessWidget {
  final bool expanded;
  final VoidCallback onTap;

  const _ToggleChip({required this.expanded, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: expanded
              ? const Color(0xFF4F8EF7).withValues(alpha: 0.12)
              : const Color(0xFF252A3A),
          borderRadius: BorderRadius.circular(5),
          border: Border.all(
            color: expanded
                ? const Color(0xFF4F8EF7).withValues(alpha: 0.4)
                : Colors.transparent,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              expanded ? Icons.expand_less_rounded : Icons.expand_more_rounded,
              size: 13,
              color: expanded
                  ? const Color(0xFF4F8EF7)
                  : const Color(0xFF6B7390),
            ),
            const SizedBox(width: 3),
            Text(
              expanded ? 'Hide' : 'Show',
              style: TextStyle(
                fontSize: 10,
                color: expanded
                    ? const Color(0xFF4F8EF7)
                    : const Color(0xFF6B7390),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
