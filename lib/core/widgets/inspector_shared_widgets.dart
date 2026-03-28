import 'package:flutter/material.dart';

// ─── SectionCard ──────────────────────────────────────────────────────────────

class SectionCard extends StatelessWidget {
  final String label;
  final Widget child;

  const SectionCard({super.key, required this.label, required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1A1A),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFF2C2C2C), width: 0.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w600,
              color: Color(0xFF8A8A8A),
              letterSpacing: 0.8,
            ),
          ),
          const SizedBox(height: 8),
          child,
        ],
      ),
    );
  }
}

// ─── Badge ────────────────────────────────────────────────────────────────────

enum BadgeStyle { neutral, success, fail }

class InspectorBadge extends StatelessWidget {
  final String label;
  final BadgeStyle style;

  const InspectorBadge({super.key, required this.label, required this.style});

  @override
  Widget build(BuildContext context) {
    final (bg, fg) = switch (style) {
      BadgeStyle.success => (const Color(0xFFDCFCE7), const Color(0xFF15803D)),
      BadgeStyle.fail    => (const Color(0xFFFEE2E2), const Color(0xFFB91C1C)),
      BadgeStyle.neutral => (const Color(0xFF252525), const Color(0xFFAAAAAA)),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(20),
        border: style == BadgeStyle.neutral
            ? Border.all(color: const Color(0xFF3A3A3A), width: 0.5)
            : null,
      ),
      child: Text(
        label,
        style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: fg),
      ),
    );
  }
}

// ─── MonoPreview ──────────────────────────────────────────────────────────────

class MonoPreview extends StatelessWidget {
  final String text;

  const MonoPreview({super.key, required this.text});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      color: const Color(0xFF111111),
      child: Text(
        text,
        style: const TextStyle(
          fontFamily: 'monospace',
          fontSize: 10.5,
          color: Color(0xFFB8C4E0),
          height: 1.5,
        ),
      ),
    );
  }
}
