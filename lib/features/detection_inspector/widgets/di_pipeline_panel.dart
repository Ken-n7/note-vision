// lib/features/dev/detection_inspector/widgets/di_pipeline_panel.dart
//
// Renders all four intermediate mapping stages in collapsible sections:
//   Stage 1 – Raw Symbols
//   Stage 2 – Staff Assignments
//   Stage 3 – Measure Grouping
//   Stage 4 – Mapped Score Summary

import 'package:flutter/material.dart';

import 'package:note_vision/core/models/note.dart';
import 'package:note_vision/core/models/rest.dart';
import 'package:note_vision/features/detection_inspector/model/mapping_pipeline_state.dart';

class DiPipelinePanel extends StatefulWidget {
  final MappingPipelineState pipeline;

  const DiPipelinePanel({super.key, required this.pipeline});

  @override
  State<DiPipelinePanel> createState() => _DiPipelinePanelState();
}

class _DiPipelinePanelState extends State<DiPipelinePanel> {
  final _expanded = <int, bool>{0: true, 1: false, 2: false, 3: false};

  void _toggle(int index) =>
      setState(() => _expanded[index] = !(_expanded[index] ?? false));

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Header label
        const Padding(
          padding: EdgeInsets.only(bottom: 8),
          child: Text(
            'PIPELINE STAGES',
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w600,
              color: Color(0xFF6B7390),
              letterSpacing: 1.4,
            ),
          ),
        ),

        _StageBlock(
          index: 0,
          label: 'STAGE 1',
          title: 'Raw Symbols',
          icon: Icons.scatter_plot_rounded,
          color: const Color(0xFF4FCEF7),
          count: widget.pipeline.detection.symbols.length,
          countLabel: 'symbols',
          expanded: _expanded[0] ?? false,
          onToggle: () => _toggle(0),
          child: _RawSymbolsView(pipeline: widget.pipeline),
        ),

        const SizedBox(height: 8),

        _StageBlock(
          index: 1,
          label: 'STAGE 2',
          title: 'Staff Assignments',
          icon: Icons.table_rows_rounded,
          color: const Color(0xFFAB7EF7),
          count: widget.pipeline.assignments.length,
          countLabel: 'assigned',
          expanded: _expanded[1] ?? false,
          onToggle: () => _toggle(1),
          child: _AssignmentsView(pipeline: widget.pipeline),
        ),

        const SizedBox(height: 8),

        _StageBlock(
          index: 2,
          label: 'STAGE 3',
          title: 'Measure Grouping',
          icon: Icons.grid_on_rounded,
          color: const Color(0xFFF5A623),
          count: widget.pipeline.measures.length,
          countLabel: 'measures',
          expanded: _expanded[2] ?? false,
          onToggle: () => _toggle(2),
          child: _MeasureGroupingView(pipeline: widget.pipeline),
        ),

        const SizedBox(height: 8),

        _StageBlock(
          index: 3,
          label: 'STAGE 4',
          title: 'Mapped Score Summary',
          icon: Icons.music_note_rounded,
          color: const Color(0xFF3DD68C),
          count: widget.pipeline.result.score.totalMeasures,
          countLabel: 'measures out',
          expanded: _expanded[3] ?? false,
          onToggle: () => _toggle(3),
          child: _ScoreSummaryView(pipeline: widget.pipeline),
        ),
      ],
    );
  }
}

// ── Stage block shell ──────────────────────────────────────────────────────

class _StageBlock extends StatelessWidget {
  final int index;
  final String label;
  final String title;
  final IconData icon;
  final Color color;
  final int count;
  final String countLabel;
  final bool expanded;
  final VoidCallback onToggle;
  final Widget child;

  const _StageBlock({
    required this.index,
    required this.label,
    required this.title,
    required this.icon,
    required this.color,
    required this.count,
    required this.countLabel,
    required this.expanded,
    required this.onToggle,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF181C27),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: expanded
              ? color.withValues(alpha: 0.35)
              : const Color(0xFF252A3A),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // ── Header ────────────────────────────────────────────────────
          GestureDetector(
            onTap: onToggle,
            behavior: HitTestBehavior.opaque,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(14, 12, 12, 12),
              child: Row(
                children: [
                  Container(
                    width: 30,
                    height: 30,
                    decoration: BoxDecoration(
                      color: color.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(7),
                    ),
                    child: Icon(icon, size: 15, color: color),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          label,
                          style: TextStyle(
                            fontSize: 9,
                            fontWeight: FontWeight.w700,
                            color: color.withValues(alpha: 0.7),
                            letterSpacing: 1.2,
                          ),
                        ),
                        Text(
                          title,
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: Color(0xFFE8ECF4),
                          ),
                        ),
                      ],
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      color: color.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(5),
                    ),
                    child: Text(
                      '$count $countLabel',
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                        color: color,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Icon(
                    expanded
                        ? Icons.keyboard_arrow_up_rounded
                        : Icons.keyboard_arrow_down_rounded,
                    size: 18,
                    color: const Color(0xFF6B7390),
                  ),
                ],
              ),
            ),
          ),

          // ── Body ─────────────────────────────────────────────────────
          AnimatedSize(
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeInOut,
            child: expanded
                ? Column(
                    children: [
                      const Divider(height: 1, color: Color(0xFF252A3A)),
                      Padding(padding: const EdgeInsets.all(14), child: child),
                    ],
                  )
                : const SizedBox(height: 0),
          ),
        ],
      ),
    );
  }
}

// ── Stage 1: Raw symbols ───────────────────────────────────────────────────

class _RawSymbolsView extends StatelessWidget {
  final MappingPipelineState pipeline;
  const _RawSymbolsView({required this.pipeline});

  @override
  Widget build(BuildContext context) {
    final symbols = pipeline.detection.symbols;
    if (symbols.isEmpty) {
      return const _EmptyHint(message: 'No symbols in detection input.');
    }

    // Group by type for a compact summary
    final typeCounts = <String, int>{};
    for (final s in symbols) {
      typeCounts[s.type] = (typeCounts[s.type] ?? 0) + 1;
    }
    final sorted = typeCounts.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Type breakdown
        _SubLabel(label: 'TYPE BREAKDOWN'),
        const SizedBox(height: 8),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: sorted
              .map((e) => _TypeChip(type: e.key, count: e.value))
              .toList(),
        ),
        const SizedBox(height: 12),
        const Divider(height: 1, color: Color(0xFF252A3A)),
        const SizedBox(height: 12),

        // Symbol table
        _SubLabel(label: 'ALL SYMBOLS (${symbols.length})'),
        const SizedBox(height: 8),
        _MonoTable(
          headers: const ['id', 'type', 'x', 'y', 'conf'],
          rows: symbols
              .map(
                (s) => [
                  s.id,
                  s.type,
                  s.x.toStringAsFixed(1),
                  s.y.toStringAsFixed(1),
                  s.confidence != null
                      ? '${(s.confidence! * 100).toStringAsFixed(0)}%'
                      : '—',
                ],
              )
              .toList(),
        ),
      ],
    );
  }
}

// ── Stage 2: Staff assignments ─────────────────────────────────────────────

class _AssignmentsView extends StatelessWidget {
  final MappingPipelineState pipeline;
  const _AssignmentsView({required this.pipeline});

  @override
  Widget build(BuildContext context) {
    final assignments = pipeline.assignments;
    if (assignments.isEmpty) {
      return const _EmptyHint(message: 'No assignments — no staffs detected.');
    }

    // Group by staff id
    final byStaff = <String, List<_AssignmentRow>>{};
    for (final a in assignments) {
      byStaff
          .putIfAbsent(a.staff.id, () => [])
          .add(
            _AssignmentRow(
              symbolId: a.symbol.id,
              type: a.symbol.type,
              cx: a.symbolCenterX,
              staffId: a.staff.id,
              staffTop: a.staff.topY,
              staffBottom: a.staff.bottomY,
            ),
          );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: byStaff.entries.map((entry) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _SubLabel(
              label: 'STAFF ${entry.key} (${entry.value.length} symbols)',
            ),
            const SizedBox(height: 8),
            _MonoTable(
              headers: const ['symbol id', 'type', 'center-x'],
              rows: entry.value
                  .map((r) => [r.symbolId, r.type, r.cx.toStringAsFixed(1)])
                  .toList(),
            ),
            const SizedBox(height: 12),
          ],
        );
      }).toList(),
    );
  }
}

class _AssignmentRow {
  final String symbolId, type, staffId;
  final double cx, staffTop, staffBottom;
  const _AssignmentRow({
    required this.symbolId,
    required this.type,
    required this.cx,
    required this.staffId,
    required this.staffTop,
    required this.staffBottom,
  });
}

// ── Stage 3: Measure grouping ──────────────────────────────────────────────

class _MeasureGroupingView extends StatelessWidget {
  final MappingPipelineState pipeline;
  const _MeasureGroupingView({required this.pipeline});

  @override
  Widget build(BuildContext context) {
    final measures = pipeline.measures;
    final barlines = pipeline.detection.barlines;
    final stemLinks = pipeline.stemLinks;

    if (measures.isEmpty) {
      return const _EmptyHint(message: 'No measures grouped.');
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Barline list
        _SubLabel(label: 'BARLINES (${barlines.length})'),
        const SizedBox(height: 6),
        barlines.isEmpty
            ? const _EmptyHint(message: 'No barlines detected.')
            : Wrap(
                spacing: 6,
                runSpacing: 6,
                children: barlines
                    .map(
                      (b) => _InlineTag(
                        label: 'x=${b.x.toStringAsFixed(1)}',
                        color: const Color(0xFFAB7EF7),
                      ),
                    )
                    .toList(),
              ),

        const SizedBox(height: 12),
        const Divider(height: 1, color: Color(0xFF252A3A)),
        const SizedBox(height: 12),

        // Per-measure breakdown
        ...measures.map((m) {
          final noteheads = m.symbols
              .where((e) => e.symbol.type.toLowerCase().contains('notehead'))
              .toList();
          final rests = m.symbols
              .where((e) => e.symbol.type.toLowerCase().contains('rest'))
              .toList();
          final other = m.symbols
              .where(
                (e) =>
                    !e.symbol.type.toLowerCase().contains('notehead') &&
                    !e.symbol.type.toLowerCase().contains('rest'),
              )
              .toList();

          return Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Container(
              decoration: BoxDecoration(
                color: const Color(0xFF0F1117),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: const Color(0xFF1E2235)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Measure header
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                    decoration: const BoxDecoration(
                      border: Border(
                        bottom: BorderSide(color: Color(0xFF1E2235)),
                      ),
                    ),
                    child: Row(
                      children: [
                        Text(
                          'Measure ${m.number}',
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: Color(0xFFF5A623),
                          ),
                        ),
                        const Spacer(),
                        _InlineTag(
                          label: '${m.symbols.length} sym',
                          color: const Color(0xFF6B7390),
                        ),
                      ],
                    ),
                  ),

                  // Symbol rows
                  Padding(
                    padding: const EdgeInsets.all(10),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        if (noteheads.isNotEmpty) ...[
                          _MiniGroupLabel(
                            label: 'Noteheads (${noteheads.length})',
                          ),
                          ...noteheads.map((e) {
                            final link = stemLinks[e.symbol.id];
                            final stemInfo = link?.stem != null
                                ? ' + stem'
                                : ' (no stem)';
                            final flagInfo = link?.flag != null
                                ? ' + flag'
                                : '';
                            return _SymRow(
                              type: e.symbol.type,
                              detail:
                                  'x=${e.symbolCenterX.toStringAsFixed(1)}$stemInfo$flagInfo',
                              color: const Color(0xFF4FCEF7),
                            );
                          }),
                        ],
                        if (rests.isNotEmpty) ...[
                          const SizedBox(height: 6),
                          _MiniGroupLabel(label: 'Rests (${rests.length})'),
                          ...rests.map(
                            (e) => _SymRow(
                              type: e.symbol.type,
                              detail: 'x=${e.symbolCenterX.toStringAsFixed(1)}',
                              color: const Color(0xFFAB7EF7),
                            ),
                          ),
                        ],
                        if (other.isNotEmpty) ...[
                          const SizedBox(height: 6),
                          _MiniGroupLabel(label: 'Other (${other.length})'),
                          ...other.map(
                            (e) => _SymRow(
                              type: e.symbol.type,
                              detail: 'x=${e.symbolCenterX.toStringAsFixed(1)}',
                              color: const Color(0xFF6B7390),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            ),
          );
        }),
      ],
    );
  }
}

// ── Stage 4: Mapped score summary ─────────────────────────────────────────

class _ScoreSummaryView extends StatelessWidget {
  final MappingPipelineState pipeline;
  const _ScoreSummaryView({required this.pipeline});

  @override
  Widget build(BuildContext context) {
    final score = pipeline.result.score;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: score.parts.expand((part) {
        return [
          _SubLabel(
            label: 'PART "${part.name}" · ${part.measures.length} measure(s)',
          ),
          const SizedBox(height: 8),
          ...part.measures.map((m) {
            return Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Container(
                decoration: BoxDecoration(
                  color: const Color(0xFF0F1117),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: const Color(0xFF1E2235)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Measure header row
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 8,
                      ),
                      decoration: const BoxDecoration(
                        border: Border(
                          bottom: BorderSide(color: Color(0xFF1E2235)),
                        ),
                      ),
                      child: Wrap(
                        spacing: 8,
                        runSpacing: 4,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          Text(
                            'Measure ${m.number}',
                            style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              color: Color(0xFF3DD68C),
                            ),
                          ),
                          if (m.clef != null)
                            _InlineTag(
                              label: '${m.clef!.sign}-clef',
                              color: const Color(0xFF4F8EF7),
                            ),
                          if (m.timeSignature != null)
                            _InlineTag(
                              label:
                                  '${m.timeSignature!.beats}/${m.timeSignature!.beatType}',
                              color: const Color(0xFFF5A623),
                            ),
                          if (m.keySignature != null)
                            _InlineTag(
                              label: m.keySignature!.name,
                              color: const Color(0xFFAB7EF7),
                            ),
                          _InlineTag(
                            label: '${m.symbolCount} sym',
                            color: const Color(0xFF6B7390),
                          ),
                        ],
                      ),
                    ),

                    // Symbols
                    if (m.symbols.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.all(10),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: m.symbols.map((sym) {
                            if (sym is Note) {
                              return _SymRow(
                                type: '♩ Note',
                                detail:
                                    '${sym.pitch}  ${sym.type}  dur:${sym.duration}',
                                color: const Color(0xFF3DD68C),
                              );
                            } else if (sym is Rest) {
                              return _SymRow(
                                type: '𝄽 Rest',
                                detail: '${sym.type}  dur:${sym.duration}',
                                color: const Color(0xFFAB7EF7),
                              );
                            }
                            return _SymRow(
                              type: sym.runtimeType.toString(),
                              detail: sym.toString(),
                              color: const Color(0xFF6B7390),
                            );
                          }).toList(),
                        ),
                      )
                    else
                      const Padding(
                        padding: EdgeInsets.all(10),
                        child: _EmptyHint(message: 'Empty measure.'),
                      ),
                  ],
                ),
              ),
            );
          }),
          const SizedBox(height: 12),
        ];
      }).toList(),
    );
  }
}

// ── Shared micro-widgets ───────────────────────────────────────────────────

class _SubLabel extends StatelessWidget {
  final String label;
  const _SubLabel({required this.label});

  @override
  Widget build(BuildContext context) {
    return Text(
      label,
      style: const TextStyle(
        fontSize: 9.5,
        fontWeight: FontWeight.w600,
        color: Color(0xFF4A5270),
        letterSpacing: 1.2,
      ),
    );
  }
}

class _MiniGroupLabel extends StatelessWidget {
  final String label;
  const _MiniGroupLabel({required this.label});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Text(
        label,
        style: const TextStyle(
          fontSize: 9,
          fontWeight: FontWeight.w600,
          color: Color(0xFF4A5270),
          letterSpacing: 1.0,
        ),
      ),
    );
  }
}

class _InlineTag extends StatelessWidget {
  final String label;
  final Color color;
  const _InlineTag({required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w600,
          color: color,
        ),
      ),
    );
  }
}

class _TypeChip extends StatelessWidget {
  final String type;
  final int count;
  const _TypeChip({required this.type, required this.count});

  Color get _color {
    if (type.contains('notehead')) return const Color(0xFF4FCEF7);
    if (type.contains('rest')) return const Color(0xFFAB7EF7);
    if (type.contains('Clef') || type.contains('clef'))
      return const Color(0xFF4F8EF7);
    if (type.contains('timeSig')) return const Color(0xFFF5A623);
    if (type.contains('stem') || type.contains('flag'))
      return const Color(0xFF6B7390);
    return const Color(0xFF3DD68C);
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: _color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: _color.withValues(alpha: 0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            type,
            style: TextStyle(
              fontSize: 11,
              color: _color,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(width: 5),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
            decoration: BoxDecoration(
              color: _color.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(3),
            ),
            child: Text(
              '$count',
              style: TextStyle(
                fontSize: 9,
                fontWeight: FontWeight.w700,
                color: _color,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SymRow extends StatelessWidget {
  final String type;
  final String detail;
  final Color color;
  const _SymRow({
    required this.type,
    required this.detail,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 6,
            height: 6,
            margin: const EdgeInsets.only(top: 4, right: 8),
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          SizedBox(
            width: 120,
            child: Text(
              type,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: color,
              ),
            ),
          ),
          Expanded(
            child: Text(
              detail,
              style: const TextStyle(
                fontSize: 11,
                color: Color(0xFF7A8CAF),
                fontFamily: 'monospace',
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _EmptyHint extends StatelessWidget {
  final String message;
  const _EmptyHint({required this.message});

  @override
  Widget build(BuildContext context) {
    return Text(
      message,
      style: const TextStyle(fontSize: 12, color: Color(0xFF4A5270)),
    );
  }
}

// ── Mono table ─────────────────────────────────────────────────────────────

class _MonoTable extends StatelessWidget {
  final List<String> headers;
  final List<List<String>> rows;

  const _MonoTable({required this.headers, required this.rows});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF0B0E16),
        borderRadius: BorderRadius.circular(7),
        border: Border.all(color: const Color(0xFF1E2235)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Header row
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: const BoxDecoration(
              border: Border(bottom: BorderSide(color: Color(0xFF1E2235))),
            ),
            child: Row(
              children: headers
                  .map(
                    (h) => Expanded(
                      child: Text(
                        h.toUpperCase(),
                        style: const TextStyle(
                          fontSize: 9,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFF4A5270),
                          letterSpacing: 0.8,
                        ),
                      ),
                    ),
                  )
                  .toList(),
            ),
          ),

          // Data rows
          ...rows.asMap().entries.map((entry) {
            final isEven = entry.key.isEven;
            return Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              color: isEven ? Colors.transparent : const Color(0xFF0F1320),
              child: Row(
                children: entry.value
                    .map(
                      (cell) => Expanded(
                        child: Text(
                          cell,
                          style: const TextStyle(
                            fontSize: 10.5,
                            color: Color(0xFF8A9BB8),
                            fontFamily: 'monospace',
                          ),
                        ),
                      ),
                    )
                    .toList(),
              ),
            );
          }),
        ],
      ),
    );
  }
}
