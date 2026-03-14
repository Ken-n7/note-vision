import 'package:flutter/material.dart';

import '../model/parsed_metadata.dart';

class CountsSection extends StatelessWidget {
  final ParsedMetadata? metadata;

  const CountsSection({super.key, required this.metadata});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: CountCard(
            label: 'Parts',
            value: metadata != null ? '${metadata!.partCount}' : '—',
            dimmed: metadata == null,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: CountCard(
            label: 'Measures',
            value: metadata != null ? '${metadata!.measureCount}' : '—',
            dimmed: metadata == null,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: CountCard(
            label: 'Notes',
            value: metadata != null ? _formatNumber(metadata!.noteCount) : '—',
            dimmed: metadata == null,
          ),
        ),
      ],
    );
  }

  String _formatNumber(int n) {
    return n.toString().replaceAllMapped(
          RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'),
          (m) => '${m[1]},',
        );
  }
}

// ─── CountCard ────────────────────────────────────────────────────────────────

class CountCard extends StatelessWidget {
  final String label;
  final String value;
  final bool dimmed;

  const CountCard({
    super.key,
    required this.label,
    required this.value,
    this.dimmed = false,
  });

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: dimmed ? 0.4 : 1.0,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          color: const Color(0xFFF7F7F7),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Column(
          children: [
            Text(
              value,
              style: const TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w600,
                color: Color(0xFF111111),
              ),
            ),
            const SizedBox(height: 2),
            Text(
              label,
              style: const TextStyle(fontSize: 10, color: Color(0xFF999999)),
            ),
          ],
        ),
      ),
    );
  }
}