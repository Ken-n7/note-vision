// lib/features/dev/detection_inspector/widgets/di_action_bar.dart

import 'package:flutter/material.dart';

import '../controller/detection_inspector_controller.dart';

class DiActionBar extends StatelessWidget {
  final DetectionInspectorController controller;

  const DiActionBar({super.key, required this.controller});

  @override
  Widget build(BuildContext context) {
    final canRunMapping = controller.detection != null &&
        !controller.isRunningMapping &&
        controller.status != InspectorStatus.error;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // ── Load mock case picker ────────────────────────────────────────
        _SectionLabel(label: 'LOAD MOCK DETECTION'),
        const SizedBox(height: 8),
        ...DetectionInspectorController.availableCases.map((c) {
          final isActive = controller.loadedCase?.label == c.label;
          return Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: _CaseButton(
              mockCase: c,
              isActive: isActive,
              onTap: () => controller.loadMockCase(c),
            ),
          );
        }),

        const SizedBox(height: 12),

        // ── Run mapping ──────────────────────────────────────────────────
        _SectionLabel(label: 'ACTIONS'),
        const SizedBox(height: 8),
        _RunButton(
          canRun: canRunMapping,
          isRunning: controller.isRunningMapping,
          onTap: () => controller.runMapping(),
        ),
      ],
    );
  }
}

class _SectionLabel extends StatelessWidget {
  final String label;
  const _SectionLabel({required this.label});

  @override
  Widget build(BuildContext context) {
    return Text(
      label,
      style: const TextStyle(
        fontSize: 10,
        fontWeight: FontWeight.w600,
        color: Color(0xFF6B7390),
        letterSpacing: 1.4,
      ),
    );
  }
}

class _CaseButton extends StatelessWidget {
  final MockCase mockCase;
  final bool isActive;
  final VoidCallback onTap;

  const _CaseButton({
    required this.mockCase,
    required this.isActive,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: isActive
              ? const Color(0xFF4F8EF7).withOpacity(0.1)
              : const Color(0xFF181C27),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: isActive
                ? const Color(0xFF4F8EF7).withOpacity(0.6)
                : const Color(0xFF252A3A),
            width: isActive ? 1.5 : 1,
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 28,
              height: 28,
              decoration: BoxDecoration(
                color: isActive
                    ? const Color(0xFF4F8EF7).withOpacity(0.18)
                    : const Color(0xFF252A3A),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Icon(
                isActive ? Icons.check_circle_rounded : Icons.data_object,
                size: 15,
                color: isActive
                    ? const Color(0xFF4F8EF7)
                    : const Color(0xFF6B7390),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    mockCase.label,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: isActive
                          ? const Color(0xFF4F8EF7)
                          : const Color(0xFFE8ECF4),
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    mockCase.description,
                    style: const TextStyle(
                      fontSize: 11,
                      color: Color(0xFF6B7390),
                    ),
                  ),
                ],
              ),
            ),
            if (isActive)
              const Icon(
                Icons.arrow_forward_ios_rounded,
                size: 12,
                color: Color(0xFF4F8EF7),
              ),
          ],
        ),
      ),
    );
  }
}

class _RunButton extends StatelessWidget {
  final bool canRun;
  final bool isRunning;
  final VoidCallback onTap;

  const _RunButton({
    required this.canRun,
    required this.isRunning,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: canRun ? onTap : null,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        padding: const EdgeInsets.symmetric(vertical: 14),
        decoration: BoxDecoration(
          color: canRun
              ? const Color(0xFF3DD68C).withOpacity(0.12)
              : const Color(0xFF181C27),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: canRun
                ? const Color(0xFF3DD68C).withOpacity(0.5)
                : const Color(0xFF252A3A),
          ),
        ),
        child: Center(
          child: isRunning
              ? const SizedBox(
                  height: 16,
                  width: 16,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Color(0xFF3DD68C),
                  ),
                )
              : Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.play_arrow_rounded,
                      size: 18,
                      color: canRun
                          ? const Color(0xFF3DD68C)
                          : const Color(0xFF6B7390),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      'Run Mapping',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: canRun
                            ? const Color(0xFF3DD68C)
                            : const Color(0xFF6B7390),
                        letterSpacing: 0.3,
                      ),
                    ),
                  ],
                ),
        ),
      ),
    );
  }
}