import 'package:flutter/material.dart';

import '../model/parsed_metadata.dart';

class CountsSection extends StatelessWidget {
  final ParsedMetadata? metadata;

  const CountsSection({super.key, required this.metadata});

  @override
  Widget build(BuildContext context) {
    final hasData = metadata != null;
    return GridView.count(
      crossAxisCount: 2,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      crossAxisSpacing: 8,
      mainAxisSpacing: 8,
      childAspectRatio: 2.4,
      children: [
        CountCard(
          label: 'Parts',
          value: hasData ? '${metadata!.partCount}' : '—',
          dimmed: !hasData,
        ),
        CountCard(
          label: 'Measures',
          value: hasData ? '${metadata!.measureCount}' : '—',
          dimmed: !hasData,
        ),
        CountCard(
          label: 'Notes',
          value: hasData ? _formatNumber(metadata!.noteCount) : '—',
          dimmed: !hasData,
        ),
        CountCard(
          label: 'Rests',
          value: hasData ? _formatNumber(metadata!.restCount) : '—',
          dimmed: !hasData,
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
