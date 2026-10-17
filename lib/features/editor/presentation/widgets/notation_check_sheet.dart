import 'package:flutter/material.dart';
import 'package:note_vision/core/services/notation_checker.dart';
import 'package:note_vision/core/theme/app_theme.dart';

/// Colour of an issue's highlight in the score and its icon in the list:
/// amber for symbols to double-check, red for notation that is wrong.
Color notationIssueColor(NotationIssueKind kind) =>
    kind == NotationIssueKind.lowConfidence
    ? const Color(0xFFF59E0B)
    : AppColors.error;

IconData _iconFor(NotationIssueKind kind) => switch (kind) {
  NotationIssueKind.lowConfidence => Icons.help_outline_rounded,
  NotationIssueKind.missingComponent => Icons.extension_off_rounded,
  NotationIssueKind.misplacedAccidental => Icons.tag_rounded,
  NotationIssueKind.beatTotal => Icons.straighten_rounded,
  NotationIssueKind.timeSignature => Icons.av_timer_rounded,
};

/// Slim bar under the editor header while the notation check is on.
class NotationCheckBar extends StatelessWidget {
  const NotationCheckBar({
    super.key,
    required this.issueCount,
    required this.onReview,
    required this.onClose,
  });

  final int issueCount;
  final VoidCallback onReview;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final ok = issueCount == 0;
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 0, 12, 6),
      padding: const EdgeInsets.only(left: 12),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          Icon(
            ok ? Icons.check_circle_rounded : Icons.fact_check_rounded,
            size: 16,
            color: ok ? const Color(0xFF4ADE80) : AppColors.accent,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              ok
                  ? 'Notation check: no issues'
                  : 'Notation check: $issueCount '
                        '${issueCount == 1 ? 'issue' : 'issues'}',
              style: const TextStyle(
                color: AppColors.textPrimary,
                fontSize: 13,
              ),
            ),
          ),
          if (!ok) TextButton(onPressed: onReview, child: const Text('Review')),
          IconButton(
            onPressed: onClose,
            tooltip: 'Turn off notation check',
            icon: const Icon(Icons.close_rounded, size: 18),
            color: AppColors.textSecondary,
            visualDensity: VisualDensity.compact,
          ),
        ],
      ),
    );
  }
}

/// The list of issues with accept / reject per issue and for all at once.
/// Reads the issues through [issues] after every action, since accepting a
/// fix changes the score and so the issues.
class NotationCheckSheet extends StatefulWidget {
  const NotationCheckSheet({
    super.key,
    required this.issues,
    required this.checkMicros,
    required this.onFix,
    required this.onIgnore,
    required this.onFixAll,
    required this.onIgnoreAll,
    required this.onShow,
  });

  final List<NotationIssue> Function() issues;
  final int Function() checkMicros;
  final ValueChanged<NotationIssue> onFix;
  final ValueChanged<NotationIssue> onIgnore;
  final VoidCallback onFixAll;
  final VoidCallback onIgnoreAll;
  final ValueChanged<NotationIssue> onShow;

  @override
  State<NotationCheckSheet> createState() => _NotationCheckSheetState();
}

class _NotationCheckSheetState extends State<NotationCheckSheet> {
  void _run(VoidCallback action) {
    action();
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final issues = widget.issues();
    final fixable = issues.where((i) => i.hasFix).length;
    final ms = widget.checkMicros() / 1000;
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.5,
      minChildSize: 0.25,
      maxChildSize: 0.9,
      builder: (context, scroll) => Column(
        children: [
          Container(
            margin: const EdgeInsets.only(top: 8, bottom: 4),
            width: 36,
            height: 4,
            decoration: BoxDecoration(
              color: AppColors.border,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 12, 4),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  issues.isEmpty
                      ? 'No issues found'
                      : '${issues.length} '
                            '${issues.length == 1 ? 'issue' : 'issues'}',
                  style: const TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Text(
                  'Checked in '
                  '${ms < 1 ? ms.toStringAsFixed(2) : ms.round()} ms. '
                  'Nothing changes until you accept a fix.',
                  style: const TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 12,
                  ),
                ),
                if (issues.isNotEmpty)
                  Align(
                    alignment: Alignment.centerRight,
                    child: Wrap(
                      spacing: 4,
                      children: [
                        TextButton(
                          onPressed: () => _run(widget.onIgnoreAll),
                          child: const Text('Ignore all'),
                        ),
                        if (fixable > 0)
                          FilledButton(
                            onPressed: () => _run(widget.onFixAll),
                            child: Text('Fix all ($fixable)'),
                          ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
          const Divider(height: 1, color: AppColors.border),
          Expanded(
            child: ListView.separated(
              controller: scroll,
              itemCount: issues.length,
              separatorBuilder: (_, _) =>
                  const Divider(height: 1, color: AppColors.border),
              itemBuilder: (context, index) => _IssueTile(
                issue: issues[index],
                onFix: () => _run(() => widget.onFix(issues[index])),
                onIgnore: () => _run(() => widget.onIgnore(issues[index])),
                onShow: () => widget.onShow(issues[index]),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _IssueTile extends StatelessWidget {
  const _IssueTile({
    required this.issue,
    required this.onFix,
    required this.onIgnore,
    required this.onShow,
  });

  final NotationIssue issue;
  final VoidCallback onFix;
  final VoidCallback onIgnore;
  final VoidCallback onShow;

  @override
  Widget build(BuildContext context) {
    final color = notationIssueColor(issue.kind);
    final unsure = issue.kind == NotationIssueKind.lowConfidence;
    return InkWell(
      onTap: onShow,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 10, 12, 6),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(_iconFor(issue.kind), size: 18, color: color),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Staff ${issue.partIndex + 1} · Bar '
                        '${issue.measureIndex + 1}',
                        style: const TextStyle(
                          color: AppColors.textSecondary,
                          fontSize: 11,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        issue.message,
                        style: const TextStyle(
                          color: AppColors.textPrimary,
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            Wrap(
              alignment: WrapAlignment.end,
              spacing: 4,
              children: [
                TextButton(onPressed: onShow, child: const Text('Show')),
                TextButton(
                  onPressed: onIgnore,
                  child: Text(unsure ? 'Keep' : 'Ignore'),
                ),
                if (issue.hasFix)
                  FilledButton.tonal(
                    onPressed: onFix,
                    child: Text(issue.fixLabel ?? 'Fix'),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
