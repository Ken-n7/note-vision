import 'package:flutter/material.dart';
import 'package:note_vision/core/services/notation_checker.dart';
import 'package:note_vision/core/theme/app_theme.dart';

Color notationIssueColor(NotationIssueKind kind) =>
    kind == NotationIssueKind.lowConfidence
    ? const Color(0xFFF59E0B)
    : AppColors.error;

/// A quiet entry point after a scan or while editing a reviewed score.
class NotationCheckBar extends StatelessWidget {
  const NotationCheckBar({
    super.key,
    required this.issueCount,
    required this.onReview,
    required this.onClose,
    this.appliedCount = 0,
    this.keptCount = 0,
  });

  final int issueCount, appliedCount, keptCount;
  final VoidCallback onReview, onClose;

  @override
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.fromLTRB(12, 4, 12, 6),
    padding: const EdgeInsets.only(left: 12),
    decoration: BoxDecoration(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(10),
      border: Border.all(color: AppColors.border),
    ),
    child: Row(
      children: [
        Icon(
          issueCount == 0 ? Icons.task_alt_rounded : Icons.fact_check_outlined,
          size: 18,
          color: AppColors.accent,
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            issueCount > 0
                ? '$issueCount ${issueCount == 1 ? 'place' : 'places'} to review'
                : appliedCount + keptCount > 0
                ? 'Review complete · $appliedCount applied · $keptCount kept'
                : 'No issues detected',
            style: const TextStyle(color: AppColors.textPrimary, fontSize: 12),
          ),
        ),
        TextButton(onPressed: onReview, child: const Text('Review')),
        IconButton(
          onPressed: onClose,
          tooltip: 'Hide review reminder',
          icon: const Icon(Icons.close_rounded, size: 18),
          color: AppColors.textSecondary,
        ),
      ],
    ),
  );
}
