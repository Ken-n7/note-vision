// lib/features/dev/detection_inspector/widgets/di_issues_section.dart

import 'package:flutter/material.dart';
import '../controller/detection_inspector_controller.dart';
import 'di_section_card.dart';

class DiIssuesSection extends StatelessWidget {
  final DetectionInspectorController controller;
  const DiIssuesSection({super.key, required this.controller});

  @override
  Widget build(BuildContext context) {
    final warnings = controller.warnings;
    final errors = controller.errors;
    final errorMessage = controller.errorMessage;

    final hasContent =
        warnings.isNotEmpty || errors.isNotEmpty || errorMessage != null;

    if (!hasContent) {
      return DiSectionCard(
        label: 'WARNINGS / ERRORS',
        child: const _EmptyIssues(),
      );
    }

    return DiSectionCard(
      label: 'WARNINGS / ERRORS',
      trailing: _IssueBadge(
        warnings: warnings.length,
        errors: errors.length + (errorMessage != null ? 1 : 0),
      ),
      child: Column(
        children: [
          if (errorMessage != null)
            _IssueRow(
              message: errorMessage,
              isError: true,
            ),
          ...errors.map((e) => _IssueRow(message: e, isError: true)),
          ...warnings.map((w) => _IssueRow(message: w, isError: false)),
        ],
      ),
    );
  }
}

class _EmptyIssues extends StatelessWidget {
  const _EmptyIssues();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          const Icon(
            Icons.check_circle_outline,
            size: 14,
            color: Color(0xFF3DD68C),
          ),
          const SizedBox(width: 8),
          const Text(
            'No warnings or errors',
            style: TextStyle(
              fontSize: 12,
              color: Color(0xFF3DD68C),
            ),
          ),
        ],
      ),
    );
  }
}

class _IssueBadge extends StatelessWidget {
  final int warnings;
  final int errors;
  const _IssueBadge({required this.warnings, required this.errors});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (errors > 0) ...[
          _Chip(count: errors, color: const Color(0xFFFF5757)),
          if (warnings > 0) const SizedBox(width: 4),
        ],
        if (warnings > 0)
          _Chip(count: warnings, color: const Color(0xFFF5A623)),
      ],
    );
  }
}

class _Chip extends StatelessWidget {
  final int count;
  final Color color;
  const _Chip({required this.count, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withOpacity(0.15),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        '$count',
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w700,
          color: color,
        ),
      ),
    );
  }
}

class _IssueRow extends StatelessWidget {
  final String message;
  final bool isError;
  const _IssueRow({required this.message, required this.isError});

  @override
  Widget build(BuildContext context) {
    final color = isError ? const Color(0xFFFF5757) : const Color(0xFFF5A623);
    final icon = isError ? Icons.error_outline : Icons.warning_amber_rounded;

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 1),
            child: Icon(icon, size: 13, color: color),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: TextStyle(
                fontSize: 12,
                color: color.withOpacity(0.9),
                height: 1.5,
              ),
            ),
          ),
        ],
      ),
    );
  }
}