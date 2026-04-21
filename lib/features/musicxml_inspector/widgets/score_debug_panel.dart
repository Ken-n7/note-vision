import 'package:flutter/material.dart';
import 'package:note_vision/core/models/score.dart';

import '/features/musicxml_inspector/score_debug_serializer.dart';

/// Expandable tree panel that displays the full [Score] structure.
///
/// Each level (score → part → measure → symbol) is independently
/// collapsible so testers can drill into exactly what they need.
class ScoreDebugPanel extends StatefulWidget {
  final Score score;

  const ScoreDebugPanel({super.key, required this.score});

  @override
  State<ScoreDebugPanel> createState() => _ScoreDebugPanelState();
}

class _ScoreDebugPanelState extends State<ScoreDebugPanel> {
  static const _serializer = ScoreDebugSerializer();

  late Map<String, dynamic> _tree;

  // Tracks which nodes are expanded: key = "part-{i}", "measure-{i}-{j}"
  final Set<String> _expanded = {};

  @override
  void initState() {
    super.initState();
    _tree = _serializer.serialize(widget.score);
  }

  @override
  void didUpdateWidget(ScoreDebugPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.score != widget.score) {
      _tree = _serializer.serialize(widget.score);
      _expanded.clear();
    }
  }

  void _toggle(String key) => setState(
    () => _expanded.contains(key) ? _expanded.remove(key) : _expanded.add(key),
  );

  bool _isExpanded(String key) => _expanded.contains(key);

  @override
  Widget build(BuildContext context) {
    final parts = _tree['parts'] as List;

    return Container(
      color: const Color(0xFFF0F0F0),
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Score root ──────────────────────────────────────────────────
          _KeyValue('id', _tree['id']),
          _KeyValue('title', _tree['title']),
          _KeyValue('composer', _tree['composer']),
          _KeyValue('parts', '${parts.length}'),

          const SizedBox(height: 6),

          // ── Parts ───────────────────────────────────────────────────────
          ...List.generate(parts.length, (pi) {
            final part = parts[pi] as Map<String, dynamic>;
            final partKey = 'part-$pi';
            final partExpanded = _isExpanded(partKey);
            final measures = part['measures'] as List;

            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Part header
                _TreeNode(
                  depth: 0,
                  expanded: partExpanded,
                  onTap: () => _toggle(partKey),
                  label:
                      'Part [${pi + 1}] "${part['name']}"  ·  ${part['measureCount']} measures',
                  color: const Color(0xFF185FA5),
                ),

                if (partExpanded) ...[
                  _KeyValue('id', part['id'], depth: 1),

                  const SizedBox(height: 4),

                  // ── Measures ──────────────────────────────────────────
                  ...List.generate(measures.length, (mi) {
                    final measure = measures[mi] as Map<String, dynamic>;
                    final measureKey = 'measure-$pi-$mi';
                    final measureExpanded = _isExpanded(measureKey);
                    final symbols = measure['symbols'] as List;

                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _TreeNode(
                          depth: 1,
                          expanded: measureExpanded,
                          onTap: () => _toggle(measureKey),
                          label:
                              'Measure ${measure['number']}  ·  ${measure['symbolCount']} symbols',
                          color: const Color(0xFF6B7280),
                        ),

                        if (measureExpanded) ...[
                          // Measure attributes
                          if (measure.containsKey('clef'))
                            _KeyValue(
                              'clef',
                              '${(measure['clef'] as Map)['sign']} / line ${(measure['clef'] as Map)['line']}',
                              depth: 2,
                            ),
                          if (measure.containsKey('timeSignature'))
                            _KeyValue(
                              'time',
                              '${(measure['timeSignature'] as Map)['beats']}/${(measure['timeSignature'] as Map)['beatType']}',
                              depth: 2,
                            ),
                          if (measure.containsKey('keySignature'))
                            _KeyValue(
                              'key',
                              'fifths=${(measure['keySignature'] as Map)['fifths']}',
                              depth: 2,
                            ),

                          const SizedBox(height: 2),

                          // ── Symbols ─────────────────────────────────
                          ...List.generate(symbols.length, (si) {
                            final sym = symbols[si] as Map<String, dynamic>;
                            final isNote = sym['type'] == 'note';
                            final isRest = sym['type'] == 'rest';

                            return _SymbolRow(
                              index: si,
                              symbol: sym,
                              isNote: isNote,
                              isRest: isRest,
                            );
                          }),

                          const SizedBox(height: 4),
                        ],
                      ],
                    );
                  }),

                  const SizedBox(height: 6),
                ],
              ],
            );
          }),
        ],
      ),
    );
  }
}

// ─── Tree node (collapsible header) ──────────────────────────────────────────

class _TreeNode extends StatelessWidget {
  final int depth;
  final bool expanded;
  final VoidCallback onTap;
  final String label;
  final Color color;

  const _TreeNode({
    required this.depth,
    required this.expanded,
    required this.onTap,
    required this.label,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Padding(
        padding: EdgeInsets.only(left: depth * 16.0, top: 3, bottom: 3),
        child: Row(
          children: [
            Text(
              expanded ? '▼ ' : '▶ ',
              style: TextStyle(fontSize: 9, color: color),
            ),
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  fontSize: 11,
                  fontFamily: 'monospace',
                  fontWeight: FontWeight.w600,
                  color: color,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Symbol row (note / rest / unknown) ──────────────────────────────────────

class _SymbolRow extends StatelessWidget {
  final int index;
  final Map<String, dynamic> symbol;
  final bool isNote;
  final bool isRest;

  const _SymbolRow({
    required this.index,
    required this.symbol,
    required this.isNote,
    required this.isRest,
  });

  @override
  Widget build(BuildContext context) {
    final (typeLabel, typeColor, detail) = isNote
        ? (
            'NOTE',
            const Color(0xFF15803D),
            '${symbol['pitch']}  ${symbol['noteType']}  dur=${symbol['duration']}',
          )
        : isRest
        ? (
            'REST',
            const Color(0xFF6B7280),
            '${symbol['restType']}  dur=${symbol['duration']}',
          )
        : ('?', const Color(0xFFB91C1C), 'unknown symbol');

    final voice = symbol['voice'];
    final staff = symbol['staff'];
    final extra = [
      if (voice != null) 'v$voice',
      if (staff != null) 's$staff',
    ].join(' ');

    return Padding(
      padding: const EdgeInsets.only(left: 32, top: 1, bottom: 1),
      child: Row(
        children: [
          // Index
          SizedBox(
            width: 24,
            child: Text(
              '$index',
              style: const TextStyle(
                fontSize: 10,
                fontFamily: 'monospace',
                color: Color(0xFFBBBBBB),
              ),
            ),
          ),
          // Type badge
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
            decoration: BoxDecoration(
              color: typeColor.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(3),
            ),
            child: Text(
              typeLabel,
              style: TextStyle(
                fontSize: 9,
                fontWeight: FontWeight.w700,
                fontFamily: 'monospace',
                color: typeColor,
              ),
            ),
          ),
          const SizedBox(width: 6),
          // Detail
          Expanded(
            child: Text(
              detail,
              style: const TextStyle(
                fontSize: 10.5,
                fontFamily: 'monospace',
                color: Color(0xFF333333),
              ),
            ),
          ),
          // Voice/staff hint
          if (extra.isNotEmpty)
            Text(
              extra,
              style: const TextStyle(
                fontSize: 9,
                fontFamily: 'monospace',
                color: Color(0xFFAAAAAA),
              ),
            ),
        ],
      ),
    );
  }
}

// ─── Key-value row ────────────────────────────────────────────────────────────

class _KeyValue extends StatelessWidget {
  final String label;
  final dynamic value;
  final int depth;

  const _KeyValue(this.label, this.value, {this.depth = 0});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(left: depth * 16.0 + 14, top: 1, bottom: 1),
      child: Row(
        children: [
          Text(
            '$label: ',
            style: const TextStyle(
              fontSize: 10.5,
              fontFamily: 'monospace',
              color: Color(0xFF888888),
            ),
          ),
          Expanded(
            child: Text(
              '${value ?? '—'}',
              style: const TextStyle(
                fontSize: 10.5,
                fontFamily: 'monospace',
                color: Color(0xFF111111),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
