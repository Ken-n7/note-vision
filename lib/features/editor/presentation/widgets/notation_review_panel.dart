import 'package:flutter/material.dart';
import 'package:note_vision/core/models/note.dart';
import 'package:note_vision/core/models/note_value.dart';
import 'package:note_vision/core/models/rest.dart';
import 'package:note_vision/core/models/score.dart';
import 'package:note_vision/core/models/score_review.dart';
import 'package:note_vision/core/models/time_signature.dart';
import 'package:note_vision/core/services/notation_checker.dart';
import 'package:note_vision/core/services/notation_review_service.dart';
import 'package:note_vision/core/theme/app_theme.dart';
import 'package:note_vision/core/widgets/score_notation_viewer.dart';
import 'notation_check_sheet.dart' show notationIssueColor;
import 'scan_comparison_view.dart';

enum _ReviewTab { focused, overview, batch, history }

class NotationReviewPanel extends StatefulWidget {
  const NotationReviewPanel({
    super.key,
    required this.score,
    required this.issues,
    required this.focusedKey,
    required this.onFocus,
    required this.onApply,
    required this.onKeep,
    required this.onPlanChanged,
    required this.onPreviewChanged,
    required this.onClose,
    required this.onEditManually,
    required this.onListen,
    required this.onRestore,
    required this.previewing,
    required this.canEdit,
    required this.listening,
    required this.onStopListening,
  });

  final Score score;
  final List<NotationIssue> issues;
  final String? focusedKey;
  final ValueChanged<NotationIssue> onFocus, onKeep;
  final ValueChanged<NotationReviewPlan?> onPlanChanged;
  final ValueChanged<bool> onPreviewChanged;
  final ValueChanged<NotationReviewPlan> onApply;
  final ValueChanged<ScoreReviewEntry> onRestore;
  final VoidCallback onClose, onEditManually, onStopListening;
  final void Function(Score score, int part, int first, int last) onListen;
  final bool previewing, canEdit, listening;

  @override
  State<NotationReviewPanel> createState() => _NotationReviewPanelState();
}

class _NotationReviewPanelState extends State<NotationReviewPanel> {
  _ReviewTab _tab = _ReviewTab.focused;
  final Set<String> _selected = {};
  NotationReviewPlan? _plan;
  bool _compareScan = false;
  int _comparisonIndex = 0;
  final ScrollController _scroll = ScrollController();
  final GlobalKey _scanKey = GlobalKey();

  @override
  void didUpdateWidget(covariant NotationReviewPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.score, widget.score)) {
      _plan = null;
      _selected.clear();
    }
    if (oldWidget.focusedKey != widget.focusedKey && _scroll.hasClients) {
      _scroll.jumpTo(0);
    }
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  NotationIssue? get _focused =>
      widget.issues
          .where(
            (i) =>
                NotationReviewService.key(widget.score, i) == widget.focusedKey,
          )
          .firstOrNull ??
      widget.issues.firstOrNull;

  void _prepare(Set<String> keys) {
    final plan = NotationReviewService.prepare(widget.score, keys);
    setState(() {
      _plan = plan;
      _comparisonIndex = 0;
    });
    widget.onPlanChanged(plan);
    widget.onPreviewChanged(true);
  }

  void _switchTab(_ReviewTab tab) {
    setState(() {
      _tab = tab;
      _plan = null;
    });
    widget.onPlanChanged(null);
    widget.onPreviewChanged(false);
  }

  @override
  Widget build(BuildContext context) {
    final applied = widget.score.reviewHistory
        .where((e) => e.disposition == ReviewDisposition.applied)
        .length;
    final kept = widget.score.reviewHistory
        .where((e) => e.disposition == ReviewDisposition.kept)
        .length;
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact =
            constraints.maxHeight < 340 ||
            MediaQuery.textScalerOf(context).scale(1) > 1.5;
        return Material(
          color: AppColors.surface,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: const BorderSide(color: AppColors.border),
          ),
          clipBehavior: Clip.antiAlias,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 4, 0),
                child: Row(
                  children: [
                    const Icon(
                      Icons.fact_check_outlined,
                      color: AppColors.accent,
                      size: 20,
                    ),
                    const SizedBox(width: 8),
                    const Expanded(
                      child: Text(
                        'Review & Correct',
                        style: TextStyle(
                          color: AppColors.textPrimary,
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    TextButton(
                      onPressed: widget.onClose,
                      child: const Text('Done'),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
                child: Semantics(
                  liveRegion: true,
                  child: Text(
                    '${widget.issues.length} remaining · $applied applied · $kept kept original',
                    style: const TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 12,
                    ),
                  ),
                ),
              ),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  child: Row(
                    children: [
                      _tabButton(
                        'Review',
                        _ReviewTab.focused,
                        Icons.tune_rounded,
                      ),
                      _tabButton(
                        'All (${widget.issues.length})',
                        _ReviewTab.overview,
                        Icons.list_rounded,
                      ),
                      _tabButton(
                        'Batch',
                        _ReviewTab.batch,
                        Icons.checklist_rounded,
                      ),
                      _tabButton(
                        'History',
                        _ReviewTab.history,
                        Icons.history_rounded,
                      ),
                    ],
                  ),
                ),
              ),
              if (_plan != null)
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
                  child: _versionToggle(),
                ),
              const Divider(height: 1, color: AppColors.border),
              Expanded(
                child: SingleChildScrollView(
                  controller: _scroll,
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      switch (_tab) {
                        _ReviewTab.focused =>
                          _focused == null
                              ? _complete(applied, kept)
                              : _issue(_focused!),
                        _ReviewTab.overview => _overview(),
                        _ReviewTab.batch => _batch(),
                        _ReviewTab.history => _history(),
                      },
                      if (compact &&
                          _tab == _ReviewTab.focused &&
                          _focused != null)
                        _actions(_focused!),
                      if (compact && _tab == _ReviewTab.batch && _plan != null)
                        _batchActions(),
                    ],
                  ),
                ),
              ),
              if (!compact && _tab == _ReviewTab.focused && _focused != null)
                _actions(_focused!),
              if (!compact && _tab == _ReviewTab.batch && _plan != null)
                _batchActions(),
            ],
          ),
        );
      },
    );
  }

  Widget _tabButton(String label, _ReviewTab tab, IconData icon) =>
      TextButton.icon(
        onPressed: () => _switchTab(tab),
        style: TextButton.styleFrom(
          foregroundColor: _tab == tab
              ? AppColors.accent
              : AppColors.textSecondary,
        ),
        icon: Icon(icon, size: 16),
        label: Text(label),
      );

  Widget _complete(int applied, int kept) => Column(
    children: [
      const Icon(Icons.task_alt_rounded, color: AppColors.accent, size: 36),
      const SizedBox(height: 12),
      Text(
        applied + kept == 0 ? 'No issues detected' : 'Review complete',
        style: const TextStyle(
          color: AppColors.textPrimary,
          fontSize: 18,
          fontWeight: FontWeight.w600,
        ),
      ),
      const SizedBox(height: 8),
      Text(
        '$applied changes applied · $kept kept original',
        textAlign: TextAlign.center,
        style: const TextStyle(color: AppColors.textSecondary),
      ),
      const SizedBox(height: 8),
      const Text(
        'You can revisit decisions in History or keep editing your score.',
        textAlign: TextAlign.center,
        style: TextStyle(color: AppColors.textSecondary),
      ),
    ],
  );

  Widget _issue(NotationIssue issue) {
    final index = widget.issues.indexOf(issue);
    final measures = widget.score.parts[issue.partIndex].measures;
    final measure = measures[issue.measureIndex];
    final symbol = issue.symbolIndex == null
        ? null
        : measure.symbols[issue.symbolIndex!];
    final source =
        NotationReviewService.sourceOf(symbol) ??
        NotationReviewService.measureSource(measure);
    final page = widget.score.sourcePages
        .where((p) => p.id == source?.pageId)
        .firstOrNull;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            IconButton(
              tooltip: 'Previous suggestion',
              onPressed: index > 0
                  ? () => _focus(widget.issues[index - 1])
                  : null,
              icon: const Icon(Icons.chevron_left_rounded),
            ),
            Expanded(
              child: Text(
                '${NotationReviewService.location(widget.score, issue)}\n${index + 1} of ${widget.issues.length}',
                textAlign: TextAlign.center,
                style: const TextStyle(color: AppColors.textSecondary),
              ),
            ),
            IconButton(
              tooltip: 'Next suggestion',
              onPressed: index + 1 < widget.issues.length
                  ? () => _focus(widget.issues[index + 1])
                  : null,
              icon: const Icon(Icons.chevron_right_rounded),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Icon(
              issue.kind == NotationIssueKind.lowConfidence
                  ? Icons.help_outline_rounded
                  : Icons.info_outline_rounded,
              color: notationIssueColor(issue.kind),
              size: 20,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                NotationReviewService.title(issue.kind),
                style: const TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Text(
          issue.kind == NotationIssueKind.lowConfidence
              ? 'Check this symbol against the original scan. Recognition was uncertain.'
              : issue.message,
          style: const TextStyle(color: AppColors.textPrimary, height: 1.5),
        ),
        if (issue.hasFix) ...[
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppColors.surfaceAlt,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: AppColors.border),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'SUGGESTED CHANGE',
                  style: TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 10,
                    letterSpacing: 1.2,
                  ),
                ),
                const SizedBox(height: 5),
                Text(
                  issue.fixLabel!,
                  style: const TextStyle(
                    color: AppColors.textPrimary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 5),
                const Text(
                  'Compare with the music before applying.',
                  style: TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
        ],
        if (issue.kind == NotationIssueKind.beatTotal) ...[
          const SizedBox(height: 12),
          _beatBreakdown(issue),
        ],
        const SizedBox(height: 10),
        if (page != null && source != null) ...[
          TextButton.icon(
            onPressed: _toggleScan,
            icon: Icon(
              _compareScan
                  ? Icons.expand_less
                  : Icons.document_scanner_outlined,
            ),
            label: Text(
              _compareScan ? 'Hide original scan' : 'Compare original scan',
            ),
          ),
          if (_compareScan)
            ScanComparisonView(
              key: _scanKey,
              page: page,
              region:
                  NotationReviewService.measureSource(
                    measure,
                    pageId: source.pageId,
                  ) ??
                  source,
              highlight: NotationReviewService.sourceOf(symbol),
            ),
        ] else
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 8),
            child: Text(
              'No source scan is attached. You can still compare the current and proposed notation.',
              style: TextStyle(
                color: AppColors.textSecondary,
                fontSize: 12,
                height: 1.4,
              ),
            ),
          ),
        if (_plan == null)
          OutlinedButton.icon(
            onPressed: widget.listening
                ? widget.onStopListening
                : () => widget.onListen(
                    widget.score,
                    issue.partIndex,
                    (issue.measureIndex - 1).clamp(0, issue.measureIndex),
                    issue.measureIndex + 1,
                  ),
            icon: Icon(
              widget.listening ? Icons.stop_rounded : Icons.play_arrow_rounded,
            ),
            label: Text(
              widget.listening ? 'Stop listening' : 'Listen to passage',
            ),
          ),
        if (_plan != null) ...[_previewControls(), _changeDetails(_plan!)],
      ],
    );
  }

  void _toggleScan() {
    setState(() => _compareScan = !_compareScan);
    if (!_compareScan) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final context = _scanKey.currentContext;
      if (mounted && context != null) {
        Scrollable.ensureVisible(
          context,
          alignment: .5,
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOut,
        );
      }
    });
  }

  Widget _beatBreakdown(NotationIssue issue) {
    final part = widget.score.parts[issue.partIndex];
    final measure = part.measures[issue.measureIndex];
    TimeSignature? meter;
    for (var i = 0; i <= issue.measureIndex; i++) {
      meter = part.measures[i].timeSignature ?? meter;
    }
    final beats = measure.symbols
        .map(
          (s) => switch (s) {
            Note(isChordTone: true) => 0.0,
            Note(:final type, :final dots, :final duration) ||
            Rest(
              :final type,
              :final dots,
              :final duration,
            ) => quarterLength(type, dots, duration),
            _ => 0.0,
          },
        )
        .toList();
    final total = beats.fold(0.0, (a, b) => a + b) * (meter?.beatType ?? 4) / 4;
    String number(double n) =>
        n == n.roundToDouble() ? n.toInt().toString() : n.toStringAsFixed(2);
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: AppColors.surfaceAlt,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        '${number(total)} counted beats / ${meter?.beats ?? '?'} expected'
        '${meter == null ? '' : ' · ${meter.beats}/${meter.beatType}'}',
        style: const TextStyle(color: AppColors.textPrimary, fontSize: 12),
      ),
    );
  }

  void _focus(NotationIssue issue) {
    setState(() {
      _tab = _ReviewTab.focused;
      _plan = null;
    });
    widget.onPlanChanged(null);
    widget.onPreviewChanged(false);
    widget.onFocus(issue);
  }

  Widget _actions(NotationIssue issue) => Padding(
    padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: OutlinedButton(
                onPressed: widget.canEdit ? () => widget.onKeep(issue) : null,
                child: const Text('Keep original'),
              ),
            ),
            const SizedBox(width: 8),
            if (issue.hasFix)
              Expanded(
                child: FilledButton(
                  onPressed:
                      !widget.canEdit || (_plan != null && !_plan!.hasChanges)
                      ? null
                      : () {
                          if (_plan == null) {
                            _prepare({
                              NotationReviewService.key(widget.score, issue),
                            });
                          } else {
                            widget.onApply(_plan!);
                          }
                        },
                  child: Text(
                    _plan == null ? 'Preview change' : 'Apply change',
                  ),
                ),
              ),
          ],
        ),
        TextButton(
          onPressed: widget.canEdit ? widget.onEditManually : null,
          child: const Text('Edit manually'),
        ),
        if (!widget.canEdit)
          const Text(
            'Stop playback to make changes.',
            textAlign: TextAlign.center,
            style: TextStyle(color: AppColors.textSecondary, fontSize: 12),
          ),
      ],
    ),
  );

  Widget _versionToggle() => SegmentedButton<bool>(
    segments: const [
      ButtonSegment(
        value: false,
        label: Text('Current'),
        icon: Icon(Icons.music_note_outlined, size: 16),
      ),
      ButtonSegment(
        value: true,
        label: Text('Proposed'),
        icon: Icon(Icons.auto_fix_high_outlined, size: 16),
      ),
    ],
    selected: {widget.previewing},
    onSelectionChanged: widget.listening
        ? null
        : (v) => widget.onPreviewChanged(v.first),
  );

  Widget _previewControls() => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      const SizedBox(height: 8),
      OutlinedButton.icon(
        onPressed: widget.listening
            ? widget.onStopListening
            : () {
                final issue = _focused;
                if (issue == null) return;
                final part =
                    _tab == _ReviewTab.batch && _plan!.changes.isNotEmpty
                    ? _plan!
                          .changes[_comparisonIndex.clamp(
                            0,
                            _plan!.changes.length - 1,
                          )]
                          .partIndex
                    : issue.partIndex;
                final bounds = _plan!.passageBounds(
                  part,
                  proposed: widget.previewing,
                );
                widget.onListen(
                  widget.previewing ? _plan!.preview : widget.score,
                  part,
                  bounds.$1,
                  bounds.$2,
                );
              },
        icon: Icon(
          widget.listening ? Icons.stop_rounded : Icons.play_arrow_rounded,
        ),
        label: Text(
          widget.listening
              ? 'Stop listening'
              : 'Listen to ${widget.previewing ? 'proposed' : 'current'}',
        ),
      ),
    ],
  );

  Widget _changeDetails(NotationReviewPlan plan) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      const SizedBox(height: 10),
      Text(
        plan.scopeDescription,
        style: const TextStyle(color: AppColors.textSecondary, fontSize: 12),
      ),
      if (plan.skipped > 0)
        Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Text(
            '${plan.skipped} dependent suggestions were left out. Review them again after applying.',
            style: const TextStyle(color: AppColors.accent, fontSize: 12),
          ),
        ),
      const SizedBox(height: 8),
      const Text(
        'Outlined notation shows the affected measures. Compare both versions below.',
        style: TextStyle(color: AppColors.textSecondary, fontSize: 12),
      ),
      if (plan.changes.length > 1)
        Row(
          children: [
            IconButton(
              tooltip: 'Previous affected measure',
              onPressed: _comparisonIndex > 0
                  ? () => setState(() => _comparisonIndex--)
                  : null,
              icon: const Icon(Icons.chevron_left_rounded),
            ),
            Expanded(
              child: Text(
                'Affected measure ${_comparisonIndex + 1} of ${plan.changes.length}',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 12,
                ),
              ),
            ),
            IconButton(
              tooltip: 'Next affected measure',
              onPressed: _comparisonIndex + 1 < plan.changes.length
                  ? () => setState(() => _comparisonIndex++)
                  : null,
              icon: const Icon(Icons.chevron_right_rounded),
            ),
          ],
        ),
      for (final change in plan.changes.skip(_comparisonIndex).take(1)) ...[
        const SizedBox(height: 12),
        Text(
          'Measure ${change.after?.number ?? change.before!.number} · Staff ${change.partIndex + 1}',
          style: const TextStyle(
            color: AppColors.textPrimary,
            fontSize: 12,
            fontWeight: FontWeight.w600,
          ),
        ),
        for (final description in plan.describe(change))
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(
                  Icons.change_circle_outlined,
                  color: AppColors.accent,
                  size: 16,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    description,
                    style: const TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: 12,
                      height: 1.4,
                    ),
                  ),
                ),
              ],
            ),
          ),
        if (change.before == null)
          const Text(
            'Current: measure does not exist',
            style: TextStyle(color: AppColors.textSecondary, fontSize: 12),
          )
        else
          _measurePreview(
            plan.base,
            change.partIndex,
            plan.base.parts[change.partIndex].measures.indexWhere(
              (m) => m.reviewId == change.before!.reviewId,
            ),
            'Current',
          ),
        _measurePreview(
          plan.preview,
          change.partIndex,
          change.measureIndex,
          'Proposed',
        ),
      ],
    ],
  );

  Widget _measurePreview(Score score, int part, int measure, String label) {
    if (part >= score.parts.length ||
        measure < 0 ||
        measure >= score.parts[part].measures.length) {
      return Text(
        '$label: measure added or removed',
        style: const TextStyle(color: AppColors.textSecondary),
      );
    }
    return Padding(
      padding: const EdgeInsets.only(top: 5),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(
              color: AppColors.textSecondary,
              fontSize: 11,
            ),
          ),
          const SizedBox(height: 4),
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: SizedBox(
              height: 145,
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: ScoreNotationViewer(
                  score: Score(
                    id: score.id,
                    title: '',
                    composer: '',
                    parts: [score.parts[part]],
                  ),
                  firstMeasureIndex: measure,
                  pageMeasureCount: 1,
                  measuresPerRow: 1,
                  minMeasureWidth: 240,
                  rowHeight: 140,
                  padding: const EdgeInsets.all(12),
                  backgroundColor: Colors.white,
                  issueMarks: {'0:0': AppColors.accent},
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _overview() => widget.issues.isEmpty
      ? _complete(
          widget.score.reviewHistory
              .where((e) => e.disposition == ReviewDisposition.applied)
              .length,
          widget.score.reviewHistory
              .where((e) => e.disposition == ReviewDisposition.kept)
              .length,
        )
      : Column(
          children: [
            for (final issue in widget.issues)
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Icon(
                  Icons.info_outline_rounded,
                  color: notationIssueColor(issue.kind),
                ),
                title: Text(
                  NotationReviewService.title(issue.kind),
                  style: const TextStyle(color: AppColors.textPrimary),
                ),
                subtitle: Text(
                  NotationReviewService.location(widget.score, issue),
                  style: const TextStyle(color: AppColors.textSecondary),
                ),
                trailing: const Icon(
                  Icons.chevron_right_rounded,
                  color: AppColors.textSecondary,
                ),
                onTap: () => _focus(issue),
              ),
          ],
        );

  Widget _batch() => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      const Text(
        'Choose changes to preview',
        style: TextStyle(
          color: AppColors.textPrimary,
          fontSize: 16,
          fontWeight: FontWeight.w600,
        ),
      ),
      const SizedBox(height: 8),
      const Text(
        'Select the suggestions you want to apply. Rhythm, pitch and meter changes need your musical judgment.',
        style: TextStyle(color: AppColors.textSecondary, height: 1.4),
      ),
      const SizedBox(height: 8),
      for (final issue in widget.issues.where((i) => i.hasFix))
        CheckboxListTile(
          contentPadding: EdgeInsets.zero,
          controlAffinity: ListTileControlAffinity.leading,
          value: _selected.contains(
            NotationReviewService.key(widget.score, issue),
          ),
          onChanged: !widget.canEdit
              ? null
              : (value) {
                  setState(() {
                    final key = NotationReviewService.key(widget.score, issue);
                    value == true ? _selected.add(key) : _selected.remove(key);
                    _plan = null;
                  });
                  widget.onPlanChanged(null);
                  widget.onPreviewChanged(false);
                },
          title: Text(
            issue.fixLabel!,
            style: const TextStyle(color: AppColors.textPrimary, fontSize: 13),
          ),
          subtitle: Text(
            NotationReviewService.location(widget.score, issue),
            style: const TextStyle(
              color: AppColors.textSecondary,
              fontSize: 11,
            ),
          ),
        ),
      if (!widget.issues.any((i) => i.hasFix))
        const Text(
          'These suggestions need a manual review.',
          style: TextStyle(color: AppColors.textSecondary),
        ),
      if (_plan == null)
        FilledButton.tonal(
          onPressed: _selected.isEmpty || !widget.canEdit
              ? null
              : () => _prepare(_selected),
          child: Text('Preview selected (${_selected.length})'),
        ),
      if (_plan != null) ...[_previewControls(), _changeDetails(_plan!)],
    ],
  );

  Widget _batchActions() => Padding(
    padding: const EdgeInsets.all(12),
    child: FilledButton(
      onPressed: !widget.canEdit || !_plan!.hasChanges
          ? null
          : () => widget.onApply(_plan!),
      child: Text('Apply selected (${_plan!.entries.length})'),
    ),
  );

  Widget _history() => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      if (widget.score.reviewHistory.isEmpty)
        const Text(
          'Your review decisions will appear here.',
          style: TextStyle(color: AppColors.textSecondary),
        ),
      for (final entry in widget.score.reviewHistory.reversed)
        Padding(
          padding: const EdgeInsets.only(bottom: 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Icon(
                    entry.disposition == ReviewDisposition.applied
                        ? Icons.check_circle_outline_rounded
                        : Icons.push_pin_outlined,
                    color: AppColors.accent,
                    size: 18,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      entry.disposition == ReviewDisposition.applied
                          ? 'Applied · ${entry.change}'
                          : 'Kept original',
                      style: const TextStyle(
                        color: AppColors.textPrimary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 5),
              Text(
                entry.location,
                style: const TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 12,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                entry.message,
                style: const TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 12,
                ),
              ),
              if (NotationReviewService.canRestore(widget.score, entry))
                TextButton(
                  onPressed: widget.canEdit
                      ? () {
                          widget.onRestore(entry);
                          _switchTab(_ReviewTab.focused);
                        }
                      : null,
                  child: Text(
                    entry.disposition == ReviewDisposition.kept
                        ? 'Review again'
                        : 'Restore original',
                  ),
                )
              else
                const Padding(
                  padding: EdgeInsets.only(top: 6),
                  child: Text(
                    'This passage changed after review. Use the editor’s undo history to revisit it.',
                    style: TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 11,
                    ),
                  ),
                ),
            ],
          ),
        ),
    ],
  );
}
