import 'package:flutter/material.dart';

import '../../../core/widgets/inspector_shared_widgets.dart';
import '../model/parsed_metadata.dart';

class MetadataSection extends StatelessWidget {
  final ParsedMetadata? metadata;

  const MetadataSection({super.key, required this.metadata});

  @override
  Widget build(BuildContext context) {
    return SectionCard(
      label: 'METADATA',
      child: Column(
        children: [
          MetaRow(label: 'Root tag', value: metadata?.rootTag, mono: true),
          MetaRow(label: 'Title',    value: metadata?.title),
          MetaRow(label: 'Composer', value: metadata?.composer),
        ],
      ),
    );
  }
}

// ─── MetaRow ──────────────────────────────────────────────────────────────────

class MetaRow extends StatelessWidget {
  final String label;
  final String? value;
  final bool mono;

  const MetaRow({super.key, required this.label, this.value, this.mono = false});

  @override
  Widget build(BuildContext context) {
    final isEmpty = value == null || value!.isEmpty;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          SizedBox(
            width: 90,
            child: Text(
              label,
              style: const TextStyle(fontSize: 12, color: Color(0xFF888888)),
            ),
          ),
          Expanded(
            child: Text(
              isEmpty ? '—' : value!,
              style: TextStyle(
                fontSize: mono ? 11 : 12,
                color: isEmpty ? const Color(0xFFBBBBBB) : const Color(0xFFFFFFFF),
                fontStyle: isEmpty ? FontStyle.italic : FontStyle.normal,
                fontFamily: mono ? 'monospace' : null,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}
