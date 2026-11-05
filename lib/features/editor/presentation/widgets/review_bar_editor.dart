import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:note_vision/core/models/clef.dart';
import 'package:note_vision/core/models/key_signature.dart';
import 'package:note_vision/core/models/measure.dart';
import 'package:note_vision/core/models/note.dart';
import 'package:note_vision/core/models/rest.dart';
import 'package:note_vision/core/models/score.dart';
import 'package:note_vision/core/models/time_signature.dart';
import 'package:note_vision/core/widgets/score_notation/engraving_layout.dart';
import 'package:note_vision/core/widgets/score_notation_viewer.dart';
import 'package:note_vision/features/editor/domain/editor_actions.dart';
import 'package:note_vision/features/editor/model/editor_state.dart';

/// Small, selection-scoped corrections without leaving the photo comparison.
class ReviewBarEditor extends StatelessWidget {
  const ReviewBarEditor({
    super.key,
    required this.score,
    required this.part,
    required this.measure,
    required this.selectedSymbol,
    required this.onSelect,
    required this.onCorrect,
    required this.canEdit,
    required this.setupOpen,
  });

  final Score score;
  final int part, measure;
  final int? selectedSymbol;
  final ValueChanged<int?> onSelect;
  final void Function(Score base, Score corrected, String label) onCorrect;
  final bool canEdit, setupOpen;

  Measure get bar => score.parts[part].measures[measure];
  EditorState get selection => EditorState(score: score).selectSymbolAt(
    partIndex: part,
    measureIndex: measure,
    symbolIndex: selectedSymbol!,
  );

  void _metadata(Measure changed, String label) {
    final parts = score.parts.toList();
    final bars = parts[part].measures.toList()..[measure] = changed;
    parts[part] = parts[part].copyWith(measures: bars);
    onCorrect(score, score.copyWith(parts: parts), label);
  }

  @override
  Widget build(BuildContext context) {
    Clef? clef;
    TimeSignature? meter;
    KeySignature? keySignature;
    for (final m in score.parts[part].measures.take(measure + 1)) {
      clef = m.clef ?? clef;
      meter = m.timeSignature ?? meter;
      keySignature = m.keySignature ?? keySignature;
    }
    final selected = selectedSymbol == null
        ? null
        : bar.symbols.elementAtOrNull(selectedSymbol!);
    final width = math.max(
      280.0,
      EngravingLayout.forScore(score).minimumBarWidth + 110,
    );
    final clefs = <Clef>{
      ?clef,
      const Clef(sign: 'G', line: 2),
      const Clef(sign: 'F', line: 4),
      const Clef(sign: 'C', line: 3),
      const Clef(sign: 'C', line: 4),
    };
    final meters = <TimeSignature>{
      ?meter,
      for (final (n, d) in [
        (2, 4),
        (3, 4),
        (4, 4),
        (6, 8),
        (3, 8),
        (2, 2),
        (9, 8),
        (12, 8),
      ])
        TimeSignature(beats: n, beatType: d),
    };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          '${score.isScannedMusic ? 'Scanned' : 'Current'} bar · Tap a note to correct it',
        ),
        const SizedBox(height: 6),
        SizedBox(
          height: 155,
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: ScoreNotationViewer(
              score: score.copyWith(parts: [score.parts[part]]),
              firstMeasureIndex: measure,
              pageMeasureCount: 1,
              measuresPerRow: 1,
              minMeasureWidth: width,
              rowHeight: 145,
              padding: const EdgeInsets.all(12),
              backgroundColor: Colors.white,
              selectedPartIndex: 0,
              selectedMeasureIndex: 0,
              selectedSymbolIndex: selectedSymbol,
              onSymbolTap: canEdit
                  ? (target) => onSelect(target?.symbolIndex)
                  : null,
            ),
          ),
        ),
        if (bar.symbols.any((s) => s is Note || s is Rest))
          Row(
            children: [
              IconButton(
                tooltip: 'Previous note in bar',
                onPressed: !canEdit
                    ? null
                    : () {
                        final before =
                            math.min(
                              selectedSymbol ?? bar.symbols.length,
                              bar.symbols.length,
                            ) -
                            1;
                        for (var i = before; i >= 0; i--) {
                          if (bar.symbols[i] is Note ||
                              bar.symbols[i] is Rest) {
                            onSelect(i);
                            return;
                          }
                        }
                      },
                icon: const Icon(Icons.chevron_left),
              ),
              Expanded(
                child: Text(switch (selected) {
                  Note(:final pitch, :final type) => '$pitch · $type note',
                  Rest(:final type) => '$type rest',
                  _ => 'Select a note or rest',
                }, textAlign: TextAlign.center),
              ),
              IconButton(
                tooltip: 'Next note in bar',
                onPressed: !canEdit
                    ? null
                    : () {
                        for (
                          var i = (selectedSymbol ?? -1) + 1;
                          i < bar.symbols.length;
                          i++
                        ) {
                          if (bar.symbols[i] is Note ||
                              bar.symbols[i] is Rest) {
                            onSelect(i);
                            return;
                          }
                        }
                      },
                icon: const Icon(Icons.chevron_right),
              ),
            ],
          ),
        if (selected is Note || selected is Rest) ...[
          if (selected is Note)
            Wrap(
              spacing: 8,
              children: [
                for (final (step, label, icon) in [
                  (1, 'Note up', Icons.arrow_upward),
                  (-1, 'Note down', Icons.arrow_downward),
                ])
                  OutlinedButton.icon(
                    onPressed: canEdit && selection.canMoveSelectedPitch(step)
                        ? () => onCorrect(
                            score,
                            selection.moveSelectedPitch(step).score,
                            label,
                          )
                        : null,
                    icon: Icon(icon),
                    label: Text(label),
                  ),
              ],
            ),
          Wrap(
            spacing: 6,
            children: [
              for (final (spec, glyph, label) in [
                (wholeDuration, '𝅝', 'Whole'),
                (halfDuration, '𝅗𝅥', 'Half'),
                (quarterDuration, '♩', 'Quarter'),
                (eighthDuration, '♪', 'Eighth'),
                (sixteenthDuration, '𝅘𝅥𝅯', 'Sixteenth'),
              ])
                Tooltip(
                  message: '$label note length',
                  child: ChoiceChip(
                    label: Text.rich(
                      TextSpan(
                        children: [
                          TextSpan(
                            text: glyph,
                            style: const TextStyle(fontFamily: 'NotoMusic'),
                          ),
                          TextSpan(text: ' $label'),
                        ],
                      ),
                    ),
                    selected: switch (selected) {
                      Note(:final type) ||
                      Rest(:final type) => type == spec.type,
                      _ => false,
                    },
                    onSelected:
                        canEdit &&
                            selection.canSetSelectedDuration(
                              spec,
                              allowOverfull: score.isScannedMusic,
                            )
                        ? (_) => onCorrect(
                            score,
                            selection
                                .setSelectedDuration(
                                  spec,
                                  allowOverfull: score.isScannedMusic,
                                )
                                .score,
                            'Set $label length',
                          )
                        : null,
                  ),
                ),
            ],
          ),
          const Text(
            'Use Undo to reverse a correction.',
            style: TextStyle(fontSize: 12),
          ),
        ],
        ExpansionTile(
          key: ValueKey(('setup', part, measure)),
          tilePadding: EdgeInsets.zero,
          initiallyExpanded: setupOpen,
          title: const Text('Clef, key and time signature'),
          children: [
            const Text(
              'Changes apply from this bar to the next written change on this staff.',
            ),
            const SizedBox(height: 8),
            DropdownButtonFormField<Clef>(
              initialValue: clef,
              decoration: const InputDecoration(labelText: 'Clef'),
              isExpanded: true,
              hint: const Text('Not read'),
              items: [
                for (final c in clefs)
                  DropdownMenuItem(
                    value: c,
                    child: Text(switch ((c.sign, c.line)) {
                      ('G', 2) => '𝄞 Treble',
                      ('F', 4) => '𝄢 Bass',
                      ('C', 3) => 'Alto',
                      ('C', 4) => 'Tenor',
                      _ => '${c.sign} · line ${c.line}',
                    }),
                  ),
              ],
              onChanged: canEdit
                  ? (v) {
                      if (v != null) {
                        _metadata(bar.copyWith(clef: v), 'Correct clef');
                      }
                    }
                  : null,
            ),
            const SizedBox(height: 8),
            DropdownButtonFormField<int>(
              initialValue: keySignature?.fifths,
              hint: const Text('Not shown / not read'),
              decoration: const InputDecoration(
                labelText: 'Sharps or flats at the start',
              ),
              isExpanded: true,
              items: [
                for (var n = -7; n <= 7; n++)
                  DropdownMenuItem(
                    value: n,
                    child: Text(
                      n == 0
                          ? 'No sharps or flats'
                          : '${n.abs()} ${n > 0 ? 'sharps ♯' : 'flats ♭'}',
                    ),
                  ),
              ],
              onChanged: canEdit
                  ? (v) {
                      if (v != null) {
                        _metadata(
                          bar.copyWith(keySignature: KeySignature(fifths: v)),
                          'Correct key signature',
                        );
                      }
                    }
                  : null,
            ),
            const SizedBox(height: 8),
            DropdownButtonFormField<TimeSignature>(
              initialValue: meter,
              decoration: const InputDecoration(labelText: 'Time signature'),
              isExpanded: true,
              hint: const Text('Not shown / not read'),
              items: [
                if (measure == 0)
                  const DropdownMenuItem(
                    value: null,
                    child: Text('Not shown on the photo'),
                  ),
                for (final t in meters)
                  DropdownMenuItem(
                    value: t,
                    child: Text('${t.beats}/${t.beatType}'),
                  ),
              ],
              onChanged: canEdit
                  ? (v) => _metadata(
                      bar.copyWith(timeSignature: v),
                      'Correct time signature',
                    )
                  : null,
            ),
            const SizedBox(height: 8),
            const Text(
              'Check the barlines and any stacked notes too. Use Edit manually for missing notes, barlines or chords.',
            ),
          ],
        ),
      ],
    );
  }
}
