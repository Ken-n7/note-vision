// lib/features/dev/detection_inspector/widgets/di_detection_summary.dart

import 'package:flutter/material.dart';
import '../controller/detection_inspector_controller.dart';
import 'di_section_card.dart';

class DiDetectionSummary extends StatelessWidget {
  final DetectionInspectorController controller;
  const DiDetectionSummary({super.key, required this.controller});

  @override
  Widget build(BuildContext context) {
    final mappedCount =
        controller.mappingResult?.confidenceSummary?.mappedSymbolCount;
    final droppedCount =
        controller.mappingResult?.confidenceSummary?.droppedSymbolCount;
    final avgConf =
        controller.mappingResult?.confidenceSummary?.averageDetectionConfidence;

    return DiSectionCard(
      label: 'DETECTION SUMMARY',
      child: Column(
        children: [
          // Input stats row
          Row(
            children: [
              _StatCell(
                label: 'Staffs',
                value: '${controller.staffCount}',
                icon: Icons.table_rows_outlined,
                color: const Color(0xFF4F8EF7),
              ),
              _Divider(),
              _StatCell(
                label: 'Barlines',
                value: '${controller.barlineCount}',
                icon: Icons.vertical_align_center,
                color: const Color(0xFFAB7EF7),
              ),
              _Divider(),
              _StatCell(
                label: 'Symbols',
                value: '${controller.symbolCount}',
                icon: Icons.music_note,
                color: const Color(0xFF4FCEF7),
              ),
            ],
          ),

          if (controller.mappingResult != null) ...[
            const SizedBox(height: 12),
            const Divider(height: 1, color: Color(0xFF252A3A)),
            const SizedBox(height: 12),

            // Mapping output row
            Row(
              children: [
                _StatCell(
                  label: 'Measures',
                  value: '${controller.measuresCreated}',
                  icon: Icons.grid_on_rounded,
                  color: const Color(0xFF3DD68C),
                ),
                _Divider(),
                _StatCell(
                  label: 'Notes',
                  value: '${controller.notesCreated}',
                  icon: Icons.music_note_rounded,
                  color: const Color(0xFF3DD68C),
                ),
                _Divider(),
                _StatCell(
                  label: 'Rests',
                  value: '${controller.restsCreated}',
                  icon: Icons.horizontal_rule_rounded,
                  color: const Color(0xFF3DD68C),
                ),
              ],
            ),

            if (mappedCount != null || avgConf != null) ...[
              const SizedBox(height: 12),
              const Divider(height: 1, color: Color(0xFF252A3A)),
              const SizedBox(height: 12),

              Row(
                children: [
                  if (mappedCount != null)
                    _StatCell(
                      label: 'Mapped',
                      value: '$mappedCount',
                      icon: Icons.check_rounded,
                      color: const Color(0xFF3DD68C),
                    ),
                  if (mappedCount != null) _Divider(),
                  if (droppedCount != null)
                    _StatCell(
                      label: 'Dropped',
                      value: '$droppedCount',
                      icon: Icons.cancel_outlined,
                      color: droppedCount > 0
                          ? const Color(0xFFF5A623)
                          : const Color(0xFF6B7390),
                    ),
                  if (droppedCount != null) _Divider(),
                  if (avgConf != null)
                    _StatCell(
                      label: 'Avg Conf',
                      value: '${(avgConf * 100).toStringAsFixed(0)}%',
                      icon: Icons.bar_chart_rounded,
                      color: avgConf > 0.8
                          ? const Color(0xFF3DD68C)
                          : const Color(0xFFF5A623),
                    ),
                ],
              ),
            ],
          ],
        ],
      ),
    );
  }
}

class _StatCell extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final Color color;

  const _StatCell({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 11, color: color.withValues(alpha: 0.7)),
              const SizedBox(width: 4),
              Text(
                label,
                style: const TextStyle(
                  fontSize: 10,
                  color: Color(0xFF6B7390),
                  letterSpacing: 0.5,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w700,
              color: color,
              height: 1.0,
            ),
          ),
        ],
      ),
    );
  }
}

class _Divider extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(width: 1, height: 36, color: const Color(0xFF252A3A));
  }
}
