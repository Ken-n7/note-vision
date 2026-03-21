// lib/features/dev/detection_inspector/widgets/di_section_card.dart

import 'package:flutter/material.dart';

class DiSectionCard extends StatelessWidget {
  final String label;
  final Widget child;
  final Widget? trailing;

  const DiSectionCard({
    super.key,
    required this.label,
    required this.child,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF181C27),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFF252A3A)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Header
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 12, 0),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    label,
                    style: const TextStyle(
                      fontSize: 9.5,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF6B7390),
                      letterSpacing: 1.4,
                    ),
                  ),
                ),
                if (trailing != null) trailing!,
              ],
            ),
          ),
          const SizedBox(height: 10),
          const Divider(height: 1, color: Color(0xFF252A3A)),
          // Content
          Padding(
            padding: const EdgeInsets.all(14),
            child: child,
          ),
        ],
      ),
    );
  }
}