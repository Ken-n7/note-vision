import 'package:flutter/material.dart';
import 'package:note_vision/core/models/key_signature.dart';
import 'package:note_vision/core/models/score.dart';
import 'package:note_vision/core/models/score_review.dart';
import 'package:note_vision/core/services/notation_review_service.dart';
import 'package:note_vision/core/widgets/score_notation_viewer.dart';
import 'package:note_vision/features/editor/domain/scan_key_correction.dart';
import 'scan_comparison_view.dart';

class ScanKeyCorrectionSheet extends StatefulWidget {
  const ScanKeyCorrectionSheet({
    super.key,
    required this.score,
    required this.row,
  });
  final Score score;
  final int row;

  static Future<ScanKeyCorrection?> show(
    BuildContext context,
    Score score,
    int row,
  ) => showModalBottomSheet<ScanKeyCorrection>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (_) => ScanKeyCorrectionSheet(score: score, row: row),
  );

  @override
  State<ScanKeyCorrectionSheet> createState() => _ScanKeyCorrectionSheetState();
}

class _ScanKeyCorrectionSheetState extends State<ScanKeyCorrectionSheet> {
  final _scroll = ScrollController();
  late final _rows = {widget.row};
  late int _fifths =
      (widget.score.parts[widget.row].measures.first.keySignature?.fifths ?? 0)
          .clamp(-7, 7);
  late int _focus = widget.row;
  bool _preview = false, _proposed = true;

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  Widget _photo() {
    final measure = widget.score.parts[_focus].measures.first;
    final source = NotationReviewService.measureSource(measure);
    final page = widget.score.sourcePages
        .where((p) => p.id == source?.pageId)
        .firstOrNull;
    if (source == null || page == null) {
      return const Text(
        'No photo attached to this row. Compare with your original sheet.',
      );
    }
    return ScanComparisonView(
      key: ValueKey(('key-photo', _focus)),
      page: page,
      height: 120,
      region: SourceRegion(
        pageId: source.pageId,
        x: 0,
        y: (source.y - .025).clamp(0, 1),
        width: (source.x + source.width).clamp(.2, 1),
        height: (source.height + .05).clamp(.05, 1),
      ),
      semanticsLabel: 'Original key signature on row ${_focus + 1}',
    );
  }

  @override
  Widget build(BuildContext context) {
    final plan = ScanKeyCorrection.prepare(widget.score, _rows, _fifths);
    final display = _proposed ? plan.preview : widget.score;
    final target = ScanKeyCorrection.keyLabel(KeySignature(fifths: _fifths));
    return SizedBox(
      height: MediaQuery.sizeOf(context).height * .9,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                const Expanded(
                  child: Text(
                    'Correct key across rows',
                    style: TextStyle(fontSize: 19, fontWeight: FontWeight.w600),
                  ),
                ),
                IconButton(
                  tooltip: 'Cancel key correction',
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close),
                ),
              ],
            ),
            Expanded(
              child: ListView(
                controller: _scroll,
                children: [
                  const Text(
                    'Set the opening key on the rows you choose. Later different keys stay in place. Written accidentals stay; playback follows the corrected key.',
                  ),
                  const SizedBox(height: 12),
                  if (!_preview) ...[
                    DropdownButtonFormField<int>(
                      initialValue: _fifths,
                      isExpanded: true,
                      decoration: const InputDecoration(
                        labelText: 'Correct key signature',
                      ),
                      items: [
                        for (var n = -7; n <= 7; n++)
                          DropdownMenuItem(
                            value: n,
                            child: Text(
                              ScanKeyCorrection.keyLabel(
                                KeySignature(fifths: n),
                              ),
                            ),
                          ),
                      ],
                      onChanged: (v) {
                        if (v != null) setState(() => _fifths = v);
                      },
                    ),
                    Wrap(
                      spacing: 8,
                      children: [
                        TextButton(
                          onPressed: () => setState(
                            () => _rows.addAll(
                              List.generate(
                                widget.score.parts.length,
                                (i) => i,
                              ),
                            ),
                          ),
                          child: const Text('Select all rows'),
                        ),
                        TextButton(
                          onPressed: () => setState(_rows.clear),
                          child: const Text('Clear selection'),
                        ),
                      ],
                    ),
                    for (var p = 0; p < widget.score.parts.length; p++)
                      CheckboxListTile(
                        contentPadding: EdgeInsets.zero,
                        title: Text('Row ${p + 1}'),
                        subtitle: Text(
                          ScanKeyCorrection.keyLabel(
                            widget.score.parts[p].measures.first.keySignature,
                          ),
                        ),
                        value: _rows.contains(p),
                        onChanged: (v) => setState(() {
                          v == true ? _rows.add(p) : _rows.remove(p);
                          _focus = p;
                        }),
                      ),
                  ] else ...[
                    Text(
                      '${plan.changes.length} ${plan.changes.length == 1 ? 'row' : 'rows'} will change to $target',
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                    DropdownButtonFormField<int>(
                      key: const ValueKey('preview-row'),
                      initialValue: _focus,
                      isExpanded: true,
                      decoration: const InputDecoration(
                        labelText: 'Preview row',
                      ),
                      items: [
                        for (final c in plan.changes)
                          DropdownMenuItem(
                            value: c.row,
                            child: Text('Row ${c.row + 1}'),
                          ),
                      ],
                      onChanged: (v) {
                        if (v != null) setState(() => _focus = v);
                      },
                    ),
                  ],
                  const Divider(),
                  Text('Original photo · Row ${_focus + 1}'),
                  _photo(),
                  if (_preview) ...[
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      children: [
                        ChoiceChip(
                          label: const Text('Current key'),
                          selected: !_proposed,
                          onSelected: (_) => setState(() => _proposed = false),
                        ),
                        ChoiceChip(
                          label: const Text('Proposed key'),
                          selected: _proposed,
                          onSelected: (_) => setState(() => _proposed = true),
                        ),
                      ],
                    ),
                    SizedBox(
                      height: 165,
                      child: SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: ScoreNotationViewer(
                          score: display.copyWith(
                            parts: [display.parts[_focus]],
                          ),
                          firstMeasureIndex: 0,
                          pageMeasureCount: 1,
                          measuresPerRow: 1,
                          minMeasureWidth: 380,
                          rowHeight: 155,
                          padding: const EdgeInsets.all(12),
                          backgroundColor: Colors.white,
                        ),
                      ),
                    ),
                    const Text(
                      'This changes the key signature, not the written notes. Check the photo before applying.',
                    ),
                    const Divider(),
                    const Text('Affected bars'),
                    for (final change in plan.changes)
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        title: Text(
                          'Row ${change.row + 1}: ${ScanKeyCorrection.keyLabel(change.before)} → $target',
                        ),
                        subtitle: Text(
                          'Bars 1–${change.end}${change.end < widget.score.parts[change.row].measures.length ? ' · later key change kept' : ''}',
                        ),
                      ),
                    if (_rows.length > plan.changes.length)
                      Text(
                        '${_rows.length - plan.changes.length} selected rows already match.',
                      ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 8),
            Wrap(
              alignment: WrapAlignment.end,
              spacing: 8,
              children: [
                if (_preview)
                  TextButton(
                    onPressed: () {
                      setState(() => _preview = false);
                      _scroll.jumpTo(0);
                    },
                    child: const Text('Change selection'),
                  ),
                FilledButton(
                  onPressed: !plan.hasChanges
                      ? null
                      : () {
                          if (_preview) {
                            Navigator.pop(context, plan);
                          } else {
                            setState(() {
                              _preview = true;
                              _focus = plan.changes.first.row;
                            });
                            _scroll.jumpTo(0);
                          }
                        },
                  child: Text(
                    _preview
                        ? 'Apply key correction'
                        : 'Preview key correction',
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
