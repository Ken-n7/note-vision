import 'package:flutter/material.dart';

// ─── ErrorBlock ───────────────────────────────────────────────────────────────

class ErrorBlock extends StatelessWidget {
  final String message;
  final bool isValidation;

  const ErrorBlock({
    super.key,
    required this.message,
    this.isValidation = false,
  });

  @override
  Widget build(BuildContext context) {
    // Validation errors use orange; hard parse errors use red.
    final (bg, border, labelColor, textColor) = isValidation
        ? (
            const Color(0xFFFFF7ED),
            const Color(0xFFFED7AA),
            const Color(0xFFC2410C),
            const Color(0xFF7C2D12),
          )
        : (
            const Color(0xFFFFF5F5),
            const Color(0xFFFCA5A5),
            const Color(0xFFB91C1C),
            const Color(0xFF7F1D1D),
          );

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: border, width: 0.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            isValidation ? 'VALIDATION ERROR' : 'ERROR',
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w600,
              color: labelColor,
              letterSpacing: 0.8,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            message,
            style: TextStyle(
              fontSize: 11.5,
              color: textColor,
              fontFamily: 'monospace',
              height: 1.55,
            ),
          ),
        ],
      ),
    );
  }
}

// ─── WarningBlock ─────────────────────────────────────────────────────────────

class WarningBlock extends StatelessWidget {
  final List<String> warnings;

  const WarningBlock({super.key, required this.warnings});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFFFFBEB),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFFDE68A), width: 0.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'WARNINGS',
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w600,
              color: Color(0xFFB45309),
              letterSpacing: 0.8,
            ),
          ),
          const SizedBox(height: 6),
          ...warnings.map(
            (w) => Padding(
              padding: const EdgeInsets.only(bottom: 2),
              child: Text(
                '• $w',
                style: const TextStyle(
                  fontSize: 11.5,
                  color: Color(0xFF78350F),
                  height: 1.55,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
