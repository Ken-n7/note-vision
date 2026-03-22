// lib/features/dev/detection_inspector/widgets/di_status_badge.dart

import 'package:flutter/material.dart';
import '../controller/detection_inspector_controller.dart';

class DiStatusBadge extends StatelessWidget {
  final DetectionInspectorController controller;
  const DiStatusBadge({super.key, required this.controller});

  @override
  Widget build(BuildContext context) {
    final status = controller.status;

    final (label, detail, color, icon) = switch (status) {
      InspectorStatus.idle => (
          'Idle',
          'Select a mock case to begin',
          const Color(0xFF6B7390),
          Icons.radio_button_unchecked,
        ),
      InspectorStatus.loaded => (
          'Detection Loaded',
          controller.loadedCase?.label ?? '',
          const Color(0xFFF5A623),
          Icons.download_done_rounded,
        ),
      InspectorStatus.mapped => (
          'Mapping Complete',
          '${controller.measuresCreated} measures · ${controller.notesCreated} notes · ${controller.restsCreated} rests',
          const Color(0xFF3DD68C),
          Icons.check_circle_rounded,
        ),
      InspectorStatus.error => (
          'Error',
          controller.errorMessage ?? 'Unknown error',
          const Color(0xFFFF5757),
          Icons.error_rounded,
        ),
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          Icon(icon, size: 18, color: color),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: color,
                    letterSpacing: 0.1,
                  ),
                ),
                if (detail.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    detail,
                    style: const TextStyle(
                      fontSize: 11,
                      color: Color(0xFF6B7390),
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}