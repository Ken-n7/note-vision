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
import 'review_bar_editor.dart';

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
    required this.onDefer,
    required this.onResume,
    required this.onCorrect,
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
  final ValueChanged<NotationIssue> onFocus, onKeep, onDefer, onResume;
  final void Function(Score base, Score corrected, String label) onCorrect;
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
  bool _compareScan = true;
  bool _fullScan = false, _showLater = false;
  int? _selectedSymbol;
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
    final oldBar = oldWidget.issues
        .where(
          (i) =>
              NotationReviewService.key(oldWidget.score, i) ==
              oldWidget.focusedKey,
        )
        .firstOrNull;
    final newBar = widget.issues
        .where(
          (i) =>
              NotationReviewService.key(widget.score, i) == widget.focusedKey,
        )
        .firstOrNull;
    if (oldBar?.partIndex != newBar?.partIndex ||
        oldBar?.measureIndex != newBar?.measureIndex) {
      _selectedSymbol = newBar?.symbolIndex;
      _compareScan = true;
      _fullScan = false;
      if (_scroll.hasClients) _scroll.jumpTo(0);
    }
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  List<NotationIssue> get _visibleIssues => widget.issues
      .where(
        (i) => _showLater || !NotationReviewService.isDeferred(widget.score, i),
      )
      .toList();
  List<List<NotationIssue>> get _bars {
    final groups = <(int, int), List<NotationIssue>>{};
    for (final issue in _visibleIssues) {
      groups
          .putIfAbsent((issue.partIndex, issue.measureIndex), () => [])
          .add(issue);
    }
    return groups.values.toList();
  }

  int get _laterCount => widget.issues
      .where((i) => NotationReviewService.isDeferred(widget.score, i))
      .map((i) => (i.partIndex, i.measureIndex))
      .toSet()
      .length;
  NotationIssue? get _focused =>
      _visibleIssues
          .where(
            (i) =>
                NotationReviewService.key(widget.score, i) == widget.focusedKey,
          )
          .firstOrNull ??
      _visibleIssues.firstOrNull;

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
            constraints.maxHeight < 520 ||
            MediaQuery.textScalerOf(context).scale(1) > 1.5;
        final chrome = <Widget>[
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
                Flexible(
                  child: TextButton(
                    onPressed: widget.onClose,
                    child: const Text('Save & close'),
                  ),
                ),

                PopupMenuButton<_ReviewTab>(
                  tooltip: 'More review options',
                  onSelected: _switchTab,
                  icon: const Icon(Icons.more_horiz),
                  itemBuilder: (_) => const [
                    PopupMenuItem(
                      value: _ReviewTab.focused,
                      child: Text('Review bars'),
                    ),
                    PopupMenuItem(
                      value: _ReviewTab.overview,
                      child: Text('All bars'),
                    ),
                    PopupMenuItem(
                      value: _ReviewTab.batch,
                      child: Text('Batch'),
                    ),
                    PopupMenuItem(
                      value: _ReviewTab.history,
                      child: Text('History'),
                    ),
                  ],
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
            child: Semantics(
              liveRegion: true,
              child: Text(
                '${_bars.length} ${_bars.length == 1 ? 'bar' : 'bars'} to check · $_laterCount for later',
                style: const TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 12,
                ),
              ),
            ),
          ),
          if (_plan != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
              child: _versionToggle(),
            ),
          const Divider(height: 1, color: AppColors.border),
        ];
        final details = Padding(
          padding: const EdgeInsets.all(16),
          child: switch (_tab) {
            _ReviewTab.focused =>
              _focused == null ? _complete(applied, kept) : _issue(_focused!),
            _ReviewTab.overview => _overview(),
            _ReviewTab.batch => _batch(),
            _ReviewTab.history => _history(),
          },
        );
        final actions = <Widget>[
          if (_tab == _ReviewTab.focused && _focused != null)
            _actions(_focused!),
          if (_tab == _ReviewTab.batch && _plan != null) _batchActions(),
        ];
        return Material(
          color: AppColors.surface,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: const BorderSide(color: AppColors.border),
          ),
          clipBehavior: Clip.antiAlias,
          child: compact
              ? SingleChildScrollView(
                  controller: _scroll,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [...chrome, details, ...actions],
                  ),
                )
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    ...chrome,
                    Expanded(
                      child: SingleChildScrollView(
                        controller: _scroll,
                        child: details,
                      ),
                    ),
                    ...actions,
                  ],
                ),
        );
      },
    );
  }

  Widget _complete(int applied, int kept) => Column(
    children: [
      Icon(
        _laterCount > 0 ? Icons.schedule : Icons.task_alt_rounded,
        color: AppColors.accent,
        size: 36,
      ),
      const SizedBox(height: 12),
      Text(
        _laterCount > 0 ? 'Saved for later' : 'No more checks in this review',
        style: const TextStyle(
          color: AppColors.textPrimary,
          fontSize: 18,
          fontWeight: FontWeight.w600,
        ),
      ),
      const SizedBox(height: 8),
      Text(
        '$applied corrections · $kept confirmed',
        textAlign: TextAlign.center,
        style: const TextStyle(color: AppColors.textSecondary),
      ),
      if (_laterCount > 0)
        FilledButton.tonal(
          onPressed: () {
            setState(() => _showLater = true);
            final next = widget.issues
                .where((i) => NotationReviewService.isDeferred(widget.score, i))
                .firstOrNull;
            if (next != null) _focus(next);
          },
          child: const Text('Review saved bars'),
        ),
      const SizedBox(height: 8),
      const Text(
        'The checker can miss wrong notes, bars and chords. Compare the music with the photo before using it.',
        textAlign: TextAlign.center,
        style: TextStyle(color: AppColors.textSecondary),
      ),
    ],
  );

  Widget _issue(NotationIssue issue) {
    final bars = _bars;
    final index = bars.indexWhere(
      (b) =>
          b.first.partIndex == issue.partIndex &&
          b.first.measureIndex == issue.measureIndex,
    );
    final currentBar = bars[index];
    final measures = widget.score.parts[issue.partIndex].measures;
    final measure = measures[issue.measureIndex];
    final selected = _selectedSymbol ?? issue.symbolIndex;
    final symbol = selected == null
        ? null
        : measure.symbols.elementAtOrNull(selected);
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
              tooltip: 'Previous bar to review',
              onPressed: index > 0 ? () => _focus(bars[index - 1].first) : null,
              icon: const Icon(Icons.chevron_left_rounded),
            ),
            Expanded(
              child: Text(
                '${NotationReviewService.location(widget.score, issue)}\nBar ${index + 1} of ${bars.length}',
                textAlign: TextAlign.center,
                style: const TextStyle(color: AppColors.textSecondary),
              ),
            ),
            IconButton(
              tooltip: 'Next bar to review',
              onPressed: index + 1 < bars.length
                  ? () => _focus(bars[index + 1].first)
                  : null,
              icon: const Icon(Icons.chevron_right_rounded),
            ),
          ],
        ),
        if (NotationReviewService.isDeferred(widget.score, issue))
          TextButton.icon(
            onPressed: widget.canEdit
                ? () {
                    _showLater = false;
                    widget.onResume(issue);
                  }
                : null,
            icon: const Icon(Icons.playlist_add_check),
            label: const Text('Resume this bar'),
          ),
        if (page != null && source != null) ...[
          Row(
            children: [
              const Expanded(
                child: Text(
                  'Original photo',
                  style: TextStyle(fontWeight: FontWeight.w600),
                ),
              ),
              TextButton(
                onPressed: () => setState(() => _fullScan = !_fullScan),
                child: Text(_fullScan ? 'Bar crop' : 'Full page'),
              ),
              IconButton(
                tooltip: _compareScan ? 'Hide photo' : 'Show photo',
                onPressed: _toggleScan,
                icon: Icon(
                  _compareScan ? Icons.expand_less : Icons.expand_more,
                ),
              ),
            ],
          ),
          if (_compareScan)
            ScanComparisonView(
              height: _fullScan ? 170 : 124,
              key: _scanKey,
              page: page,
              region: _fullScan
                  ? SourceRegion(
                      pageId: page.id,
                      x: 0,
                      y: 0,
                      width: 1,
                      height: 1,
                    )
                  : () {
                      final crop =
                          NotationReviewService.measureSource(
                            measure,
                            pageId: source.pageId,
                          ) ??
                          source;
                      // The first bar's clef/signatures lie left of its notes.
                      return issue.measureIndex == 0 ||
                              issue.kind == NotationIssueKind.scanContext
                          ? SourceRegion(
                              pageId: crop.pageId,
                              x: 0,
                              y: crop.y,
                              width: crop.x + crop.width,
                              height: crop.height,
                            )
                          : crop;
                    }(),
              highlight:
                  NotationReviewService.sourceOf(symbol) ??
                  NotationReviewService.measureSource(measure),
            ),
        ] else
          const Text('No photo is attached. Compare with your original sheet.'),
        const SizedBox(height: 10),
        if (_plan == null)
          ReviewBarEditor(
            score: widget.score,
            part: issue.partIndex,
            measure: issue.measureIndex,
            selectedSymbol: selected,
            onSelect: (i) => setState(() => _selectedSymbol = i),
            canEdit: widget.canEdit,
            onCorrect: widget.onCorrect,
            setupOpen: issue.kind == NotationIssueKind.scanContext,
          ),
        if (currentBar.length > 1) ...[
          const SizedBox(height: 12),
          Text('${currentBar.length} checks in this bar'),
          Wrap(
            spacing: 6,
            children: [
              for (final (n, check) in currentBar.indexed)
                ChoiceChip(
                  label: Text(
                    check.kind == NotationIssueKind.scanContext
                        ? 'Bar setup'
                        : '${n + 1}. ${NotationReviewService.title(check.kind)}',
                  ),
                  selected: identical(issue, check),
                  onSelected: (_) => _focus(check),
                ),
            ],
          ),
        ],
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
        if (_plan == null)
          OutlinedButton.icon(
            onPressed: widget.listening
                ? widget.onStopListening
                : () => widget.onListen(
                    widget.score,
                    issue.partIndex,
                    issue.measureIndex,
                    issue.measureIndex,
                  ),
            icon: Icon(
              widget.listening ? Icons.stop_rounded : Icons.play_arrow_rounded,
            ),
            label: Text(
              widget.listening ? 'Stop listening' : 'Listen to this bar',
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
            Note() || Rest() => symbolQuarters(s),
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
    _selectedSymbol = issue.symbolIndex;
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
                child: Text(
                  issue.kind == NotationIssueKind.scanContext
                      ? 'Setup matches photo'
                      : 'Keep original',
                ),
              ),
            ),
            const SizedBox(width: 8),
            if (issue.hasFix)
              Expanded(
                child: FilledButton(
                  onPressed:
                      !widget.canEdit ||
                          (_plan != null && !_plan!.hasChanges) ||
                          (!NotationReviewService.setupChecked(
                            widget.score,
                            issue.partIndex,
                            issue.measureIndex,
                          ))
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
        if (issue.hasFix &&
            !NotationReviewService.setupChecked(
              widget.score,
              issue.partIndex,
              issue.measureIndex,
            ))
          const Text(
            'Check this bar’s setup against the photo before trying a suggested change.',
          ),
        Wrap(
          alignment: WrapAlignment.center,
          spacing: 8,
          children: [
            TextButton(
              onPressed: widget.canEdit
                  ? () {
                      _showLater = false;
                      widget.onDefer(issue);
                    }
                  : null,
              child: const Text('Not sure · Review later'),
            ),
            TextButton(
              onPressed: widget.canEdit ? widget.onEditManually : null,
              child: const Text('Edit manually'),
            ),
          ],
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

  Widget _versionToggle() => Wrap(
    spacing: 8,
    runSpacing: 4,
    children: [
      for (final (proposed, label) in [(false, 'Current'), (true, 'Proposed')])
        ChoiceChip(
          label: Text(label),
          selected: widget.previewing == proposed,
          onSelected: widget.listening
              ? null
              : (_) => widget.onPreviewChanged(proposed),
        ),
    ],
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
                  surrounding: false,
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
            '${plan.skipped} suggestions need another check. For rhythm changes, check the setup of each affected bar first.',
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
                  score: score.copyWith(
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

  Widget _overview() {
    final groups = <(int, int), List<NotationIssue>>{};
    for (final i in widget.issues) {
      groups.putIfAbsent((i.partIndex, i.measureIndex), () => []).add(i);
    }
    if (groups.isEmpty) return _complete(0, 0);
    return Column(
      children: [
        for (final bar in groups.values)
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.music_note),
            title: Text(
              NotationReviewService.location(widget.score, bar.first),
            ),
            subtitle: Text(
              '${bar.length} checks${bar.every((i) => NotationReviewService.isDeferred(widget.score, i)) ? ' · Saved for later' : ''}',
            ),
            trailing: const Icon(Icons.chevron_right),
            onTap: () {
              _showLater = true;
              _focus(bar.first);
            },
          ),
      ],
    );
  }

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
                          : entry.disposition == ReviewDisposition.deferred
                          ? 'Saved for later'
                          : entry.issueKey.startsWith('scanContext:')
                          ? 'Bar setup checked'
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
                    entry.disposition != ReviewDisposition.applied
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
