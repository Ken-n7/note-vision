import 'package:flutter/material.dart';

import '../../../core/widgets/inspector_shared_widgets.dart';
import '../model/inspector_state.dart';

class StatusSection extends StatelessWidget {
  final InspectorState state;

  const StatusSection({super.key, required this.state});

  @override
  Widget build(BuildContext context) {
    return SectionCard(
      label: 'STATUS',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              StatusDot(status: state.status),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  state.fileName ?? 'No file imported',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: state.status == ScreenState.empty
                        ? FontWeight.w400
                        : FontWeight.w500,
                    color: state.status == ScreenState.empty
                        ? const Color(0xFFAAAAAA)
                        : const Color(0xFF111111),
                    fontStyle: state.status == ScreenState.empty
                        ? FontStyle.italic
                        : FontStyle.normal,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              ParseBadge(status: state.status),
              const SizedBox(width: 6),
              ValidationBadge(status: state.status),
            ],
          ),
        ],
      ),
    );
  }
}

// ─── StatusDot ────────────────────────────────────────────────────────────────

class StatusDot extends StatelessWidget {
  final ScreenState status;

  const StatusDot({super.key, required this.status});

  @override
  Widget build(BuildContext context) {
    final color = switch (status) {
      ScreenState.empty => const Color(0xFFD1D1D1),
      ScreenState.success => const Color(0xFF22C55E),
      ScreenState.parseError => const Color(0xFFEF4444),
      ScreenState.validationError => const Color(0xFFF97316),
    };
    return Container(
      width: 8,
      height: 8,
      decoration: BoxDecoration(color: color, shape: BoxShape.circle),
    );
  }
}

// ─── ParseBadge ───────────────────────────────────────────────────────────────

class ParseBadge extends StatelessWidget {
  final ScreenState status;

  const ParseBadge({super.key, required this.status});

  @override
  Widget build(BuildContext context) {
    return switch (status) {
      ScreenState.empty => const InspectorBadge(
        label: 'Parse: —',
        style: BadgeStyle.neutral,
      ),
      ScreenState.success => const InspectorBadge(
        label: 'Parse: OK',
        style: BadgeStyle.success,
      ),
      ScreenState.parseError => const InspectorBadge(
        label: 'Parse: FAIL',
        style: BadgeStyle.fail,
      ),
      ScreenState.validationError => const InspectorBadge(
        label: 'Parse: OK',
        style: BadgeStyle.success,
      ),
    };
  }
}

// ─── ValidationBadge ─────────────────────────────────────────────────────────

class ValidationBadge extends StatelessWidget {
  final ScreenState status;

  const ValidationBadge({super.key, required this.status});

  @override
  Widget build(BuildContext context) {
    return switch (status) {
      ScreenState.empty => const InspectorBadge(
        label: 'Validation: —',
        style: BadgeStyle.neutral,
      ),
      ScreenState.success => const InspectorBadge(
        label: 'Validation: OK',
        style: BadgeStyle.success,
      ),
      ScreenState.parseError => const InspectorBadge(
        label: 'Validation: —',
        style: BadgeStyle.neutral,
      ),
      ScreenState.validationError => const InspectorBadge(
        label: 'Validation: INVALID',
        style: BadgeStyle.fail,
      ),
    };
  }
}
