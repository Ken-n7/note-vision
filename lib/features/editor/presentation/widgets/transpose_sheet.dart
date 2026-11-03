import 'package:flutter/material.dart';
import 'package:note_vision/core/models/key_signature.dart';
import 'package:note_vision/core/services/transposer.dart';
import 'package:note_vision/core/theme/app_theme.dart';

typedef TransposeRequest = ({TransposeOptions options, bool selectionOnly});

/// MuseScore Studio's Transpose dialog: to a key, by an interval, or along
/// the scale. Pops a [TransposeRequest].
class TransposeSheet extends StatefulWidget {
  const TransposeSheet({
    super.key,
    required this.currentKey,
    this.selectionCount,
  });

  /// The opening key, in fifths; the default target.
  final int currentKey;

  /// Notes in a range selection, which can be transposed on its own.
  final int? selectionCount;

  @override
  State<TransposeSheet> createState() => _TransposeSheetState();
}

class _TransposeSheetState extends State<TransposeSheet> {
  var _mode = TransposeMode.toKey;
  var _direction = TransposeDirection.closest;
  late var _targetKey = widget.currentKey;
  var _interval = 4; // Major second
  var _steps = 1; // A second
  var _keySignatures = true;
  var _doubleAccidentals = false;
  late var _selectionOnly = widget.selectionCount != null;

  static const _degrees = [
    'Second',
    'Third',
    'Fourth',
    'Fifth',
    'Sixth',
    'Seventh',
    'Octave',
  ];

  static String _keyName(int fifths) {
    const minors = [
      'Ab',
      'Eb',
      'Bb',
      'F',
      'C',
      'G',
      'D',
      'A',
      'E',
      'B',
      'F#',
      'C#',
      'G#',
      'D#',
      'A#',
    ];
    return '${KeySignature(fifths: fifths).name} / ${minors[fifths + 7]} minor';
  }

  void _setMode(TransposeMode mode) => setState(() {
    _mode = mode;
    if (mode != TransposeMode.toKey &&
        _direction == TransposeDirection.closest) {
      _direction = TransposeDirection.up;
    }
  });

  TransposeOptions get _options => TransposeOptions(
    mode: _mode,
    direction: _direction,
    targetKey: _targetKey,
    interval: _mode == TransposeMode.diatonic ? _steps : _interval,
    keySignatures: _keySignatures,
    doubleAccidentals: _doubleAccidentals,
  );

  @override
  Widget build(BuildContext context) {
    final directions = [
      if (_mode == TransposeMode.toKey) TransposeDirection.closest,
      TransposeDirection.up,
      TransposeDirection.down,
    ];
    final unchanged =
        _mode == TransposeMode.toKey &&
        _targetKey == widget.currentKey &&
        _direction == TransposeDirection.closest;
    return SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Flexible(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text(
                    'Transpose',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    _selectionOnly
                        ? 'Moves the selected notes; key signatures stay. Undo restores them.'
                        : 'Moves every note in every staff. Undo restores it.',
                    style: const TextStyle(color: AppColors.textSecondary),
                  ),
                  if (widget.selectionCount case final count?) ...[
                    const SizedBox(height: 12),
                    SegmentedButton<bool>(
                      segments: [
                        ButtonSegment(
                          value: true,
                          label: Text(
                            '$count selected ${count == 1 ? 'note' : 'notes'}',
                          ),
                        ),
                        const ButtonSegment(
                          value: false,
                          label: Text('Whole score'),
                        ),
                      ],
                      selected: {_selectionOnly},
                      showSelectedIcon: false,
                      onSelectionChanged: (s) =>
                          setState(() => _selectionOnly = s.single),
                    ),
                  ],
                  const SizedBox(height: 16),
                  SegmentedButton<TransposeMode>(
                    segments: const [
                      ButtonSegment(
                        value: TransposeMode.toKey,
                        label: Text('To key'),
                      ),
                      ButtonSegment(
                        value: TransposeMode.byInterval,
                        label: Text('Interval'),
                      ),
                      ButtonSegment(
                        value: TransposeMode.diatonic,
                        label: Text('In key'),
                      ),
                    ],
                    selected: {_mode},
                    showSelectedIcon: false,
                    onSelectionChanged: (s) => _setMode(s.single),
                  ),
                  const SizedBox(height: 16),
                  switch (_mode) {
                    TransposeMode.toKey => DropdownButtonFormField<int>(
                      key: const ValueKey('transpose-key'),
                      initialValue: _targetKey,
                      isExpanded: true,
                      decoration: const InputDecoration(labelText: 'New key'),
                      items: [
                        for (var f = -7; f <= 7; f++)
                          DropdownMenuItem(value: f, child: Text(_keyName(f))),
                      ],
                      onChanged: (v) => setState(() => _targetKey = v!),
                    ),
                    TransposeMode.byInterval => DropdownButtonFormField<int>(
                      key: const ValueKey('transpose-interval'),
                      initialValue: _interval,
                      isExpanded: true,
                      decoration: const InputDecoration(labelText: 'Interval'),
                      items: [
                        for (var i = 1; i < transposeIntervals.length; i++)
                          DropdownMenuItem(
                            value: i,
                            child: Text(transposeIntervals[i].$1),
                          ),
                      ],
                      onChanged: (v) => setState(() => _interval = v!),
                    ),
                    TransposeMode.diatonic => DropdownButtonFormField<int>(
                      key: const ValueKey('transpose-degree'),
                      initialValue: _steps,
                      isExpanded: true,
                      decoration: const InputDecoration(
                        labelText: 'Scale steps',
                        helperText:
                            'Stays in the key; written accidentals move with their notes',
                        helperMaxLines: 2,
                      ),
                      items: [
                        for (var i = 1; i <= _degrees.length; i++)
                          DropdownMenuItem(
                            value: i,
                            child: Text(_degrees[i - 1]),
                          ),
                      ],
                      onChanged: (v) => setState(() => _steps = v!),
                    ),
                  },
                  const SizedBox(height: 16),
                  SegmentedButton<TransposeDirection>(
                    segments: [
                      for (final d in directions)
                        ButtonSegment(
                          value: d,
                          label: Text(switch (d) {
                            TransposeDirection.up => 'Up',
                            TransposeDirection.down => 'Down',
                            TransposeDirection.closest => 'Closest',
                          }),
                        ),
                    ],
                    selected: {_direction},
                    onSelectionChanged: (s) =>
                        setState(() => _direction = s.single),
                  ),
                  if (_mode == TransposeMode.byInterval && !_selectionOnly)
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Transpose key signatures'),
                      value: _keySignatures,
                      onChanged: (v) => setState(() => _keySignatures = v),
                    ),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Use double sharps and flats'),
                    value: _doubleAccidentals,
                    onChanged: (v) => setState(() => _doubleAccidentals = v),
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
                    onPressed: () => Navigator.pop(context),
                    style: TextButton.styleFrom(
                      minimumSize: const Size(48, 48),
                    ),
                    child: const Text('Cancel'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  flex: 2,
                  child: FilledButton(
                    onPressed: unchanged
                        ? null
                        : () => Navigator.pop<TransposeRequest>(context, (
                            options: _options,
                            selectionOnly: _selectionOnly,
                          )),
                    style: FilledButton.styleFrom(
                      minimumSize: const Size(48, 48),
                    ),
                    child: const Text('Transpose'),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
