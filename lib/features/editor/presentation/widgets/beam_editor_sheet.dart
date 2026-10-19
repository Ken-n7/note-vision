import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../../../core/models/beam_grouping.dart';
import '../../../../core/models/measure.dart';
import '../../../../core/models/note.dart';
import '../../../../core/models/part.dart';
import '../../../../core/models/rest.dart';
import '../../../../core/models/score.dart';
import '../../../../core/models/score_symbol.dart';
import '../../../../core/models/time_signature.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/widgets/score_notation_viewer.dart';

/// A measure-local preview. Dismissing the sheet never changes the score.
class BeamEditorSheet extends StatefulWidget {
  const BeamEditorSheet({
    super.key,
    required this.measure,
    this.selectedSymbolIndex,
    this.isPickup = false,
  });
  final Measure measure;
  final int? selectedSymbolIndex;
  final bool isPickup;

  @override
  State<BeamEditorSheet> createState() => _BeamEditorSheetState();
}

class _BeamEditorSheetState extends State<BeamEditorSheet> {
  late List<ScoreSymbol> _symbols;
  late int _anchor, _end, _focus;
  bool _choosingEnd = true;
  String? _notice;

  TimeSignature get _time =>
      widget.measure.timeSignature ??
      const TimeSignature(beats: 4, beatType: 4);
  int get _start => math.min(_anchor, _end);
  int get _last => math.max(_anchor, _end);
  bool get _dirty => !listEquals(_symbols, widget.measure.symbols);

  @override
  void initState() {
    super.initState();
    _symbols = widget.measure.symbols;
    final selected = widget.selectedSymbolIndex;
    _focus =
        selected != null &&
            selected >= 0 &&
            selected < _symbols.length &&
            BeamGrouping.eligible(_symbols[selected])
        ? selected
        : _symbols.indexWhere(BeamGrouping.eligible);
    _focus = math.max(0, _focus);
    final group = BeamGrouping.groupAt(_symbols, _focus);
    _anchor = group.length > 1 ? group.first : _focus;
    _end = group.length > 1 ? group.last : _focus;
    _choosingEnd = group.length < 2;
  }

  void _select(int index) {
    if (!BeamGrouping.eligible(_symbols[index])) return;
    setState(() {
      if (_choosingEnd) {
        _end = index;
        _choosingEnd = false;
      } else {
        _anchor = _end = index;
        _choosingEnd = true;
      }
      _focus = index;
      _notice = null;
    });
  }

  void _preview(List<ScoreSymbol> next, String notice) {
    if (identical(next, _symbols)) return;
    setState(() {
      _symbols = next;
      _notice = notice;
    });
  }

  Measure get _previewMeasure => Measure(
    number: widget.measure.number,
    clef: widget.measure.clef,
    keySignature: widget.measure.keySignature,
    timeSignature: _time,
    symbols: _symbols,
  );

  Widget _notation() => LayoutBuilder(
    builder: (context, constraints) {
      final score = Score(
        id: 'beam-preview',
        title: '',
        composer: '',
        parts: [
          Part(id: 'preview', name: '', measures: [_previewMeasure]),
        ],
      );
      final height = (MediaQuery.sizeOf(context).height * .21).clamp(
        96.0,
        156.0,
      );
      return Semantics(
        label:
            'Beam preview. Selected notes ${_start + 1} through ${_last + 1}.',
        image: true,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: ColoredBox(
            color: const Color(0xFFF9FAFB),
            child: SizedBox(
              width: constraints.maxWidth,
              height: height,
              child: FittedBox(
                fit: BoxFit.contain,
                child: SizedBox(
                  width: constraints.maxWidth,
                  height: 156,
                  child: ScoreNotationViewer(
                    key: const ValueKey('beam-preview'),
                    score: score,
                    measuresPerRow: 1,
                    minMeasureWidth: math.max(140, constraints.maxWidth - 102),
                    rowHeight: 140,
                    padding: const EdgeInsets.all(8),
                    selectedMeasureIndex: 0,
                    selectedSymbolIndices: {
                      for (var i = _start; i <= _last; i++)
                        if (BeamGrouping.eligible(_symbols[i])) i,
                    },
                    onSymbolTap: (target) {
                      if (target != null) _select(target.symbolIndex);
                    },
                  ),
                ),
              ),
            ),
          ),
        ),
      );
    },
  );

  Widget _noteChoice(int index) {
    final symbol = _symbols[index];
    final eligible = BeamGrouping.eligible(symbol);
    final selected = eligible && index >= _start && index <= _last;
    final label = symbol is Note
        ? '${index + 1} · ${symbol.pitch}'
        : symbol is Rest
        ? '${index + 1} · Rest'
        : '${index + 1}';
    final description = symbol is Note
        ? 'Note ${index + 1}, ${symbol.pitch}, ${symbol.type}'
        : 'Rest ${index + 1}';
    return Semantics(
      label: description,
      button: true,
      selected: selected,
      enabled: eligible,
      onTap: eligible ? () => _select(index) : null,
      excludeSemantics: true,
      child: ChoiceChip(
        key: ValueKey('beam-note-$index'),
        label: Text(label),
        selected: selected,
        showCheckmark: false,
        materialTapTargetSize: MaterialTapTargetSize.padded,
        onSelected: eligible ? (_) => _select(index) : null,
        side: BorderSide(color: selected ? AppColors.accent : AppColors.border),
        selectedColor: AppColors.accent.withValues(alpha: .18),
        labelStyle: TextStyle(
          color: selected
              ? AppColors.accent
              : eligible
              ? AppColors.textPrimary
              : AppColors.textSecondary,
          fontSize: 13,
        ),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final validRange = BeamGrouping.canJoin(_symbols, _start, _last);
    final joined = validRange
        ? BeamGrouping.join(_symbols, _start, _last)
        : _symbols;
    final canJoin = !identical(joined, _symbols);
    final canSeparate = _symbols.asMap().entries.any(
      (entry) =>
          entry.key >= _start &&
          entry.key <= _last &&
          BeamGrouping.eligible(entry.value) &&
          (entry.value as Note).beamed,
    );
    final group = BeamGrouping.groupAt(_symbols, _focus);
    final before = group.indexOf(_focus) > 0;
    final after =
        group.contains(_focus) && group.indexOf(_focus) < group.length - 1;
    final byBeat = BeamGrouping.byBeat(
      _symbols,
      _time,
      pickup: widget.isPickup,
    );
    final buttonStyle = OutlinedButton.styleFrom(
      minimumSize: const Size(48, 48),
    );

    return SizedBox(
      height: MediaQuery.sizeOf(context).height * .84,
      child: SafeArea(
        top: false,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 8, 8),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Beams',
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                        Text(
                          'Measure ${widget.measure.number} · ${_time.beats}/${_time.beatType}${widget.isPickup ? ' · Pickup' : ''}',
                          style: const TextStyle(
                            color: AppColors.textSecondary,
                            fontSize: 13,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: 'Cancel beam editing',
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close_rounded),
                    constraints: const BoxConstraints(
                      minWidth: 48,
                      minHeight: 48,
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              child: _notation(),
            ),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    OutlinedButton.icon(
                      style: buttonStyle,
                      onPressed: identical(byBeat, _symbols)
                          ? null
                          : () => _preview(
                              byBeat,
                              'Measure grouped by beat in preview.',
                            ),
                      icon: const Icon(Icons.auto_fix_high_rounded, size: 18),
                      label: const Text('Group by beat'),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      BeamGrouping.canGroupByBeat(_time)
                          ? 'Whole measure'
                          : 'Choose a custom range for this meter.',
                      style: TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 12,
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      _choosingEnd
                          ? 'Tap the last note to select a range.'
                          : 'Tap a first note, then a last note to choose another range.',
                      style: const TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 13,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 6,
                      runSpacing: 4,
                      children: [
                        for (var i = 0; i < _symbols.length; i++)
                          if (_symbols[i] is Note || _symbols[i] is Rest)
                            _noteChoice(i),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Semantics(
                      liveRegion: true,
                      child: Text(
                        _notice ??
                            (_start == _last
                                ? 'Note ${_start + 1} selected'
                                : 'Notes ${_start + 1}–${_last + 1} selected'),
                        style: const TextStyle(
                          color: AppColors.accent,
                          fontSize: 13,
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        OutlinedButton.icon(
                          style: buttonStyle,
                          onPressed: canJoin
                              ? () => _preview(
                                  joined,
                                  'Selected notes beamed together in preview.',
                                )
                              : null,
                          icon: const Icon(Icons.join_inner_rounded, size: 18),
                          label: const Text('Beam together'),
                        ),
                        OutlinedButton.icon(
                          style: buttonStyle,
                          onPressed: canSeparate
                              ? () => _preview(
                                  BeamGrouping.separate(
                                    _symbols,
                                    _start,
                                    _last,
                                  ),
                                  'Selected notes separated in preview.',
                                )
                              : null,
                          icon: const Icon(Icons.call_split_rounded, size: 18),
                          label: const Text('Separate notes'),
                        ),
                      ],
                    ),
                    if (!validRange && _start != _last)
                      Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: Text(
                          'Choose consecutive eighth or sixteenth notes in the same voice, without a rest between them.',
                          style: const TextStyle(
                            color: AppColors.textSecondary,
                            fontSize: 12,
                          ),
                        ),
                      ),
                    const SizedBox(height: 16),
                    Text(
                      'Split at note ${_focus + 1}',
                      style: const TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 13,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        OutlinedButton(
                          style: buttonStyle,
                          onPressed: before
                              ? () => _preview(
                                  BeamGrouping.split(
                                    _symbols,
                                    _focus,
                                    before: true,
                                  ),
                                  'Beam split before note ${_focus + 1}.',
                                )
                              : null,
                          child: const Text('Break before'),
                        ),
                        OutlinedButton(
                          style: buttonStyle,
                          onPressed: after
                              ? () => _preview(
                                  BeamGrouping.split(
                                    _symbols,
                                    _focus,
                                    before: false,
                                  ),
                                  'Beam split after note ${_focus + 1}.',
                                )
                              : null,
                          child: const Text('Break after'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  Expanded(
                    child: TextButton(
                      onPressed: _dirty
                          ? () => setState(() {
                              _symbols = widget.measure.symbols;
                              _notice = 'Original beaming restored in preview.';
                            })
                          : null,
                      style: TextButton.styleFrom(
                        minimumSize: const Size(48, 48),
                      ),
                      child: const Text('Reset'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    flex: 2,
                    child: FilledButton(
                      onPressed: _dirty
                          ? () => Navigator.pop(context, _symbols)
                          : null,
                      style: FilledButton.styleFrom(
                        minimumSize: const Size(48, 48),
                      ),
                      child: const Text('Apply'),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
