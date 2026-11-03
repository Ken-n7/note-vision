import 'package:flutter/material.dart';
import '../../../../../core/models/measure.dart';
import '../../../../../core/models/musical_time.dart';

/// Draft editing of beat-attached text/tempo/harmony in one staff's bar.
class AnnotationsSheet extends StatefulWidget {
  const AnnotationsSheet({
    super.key,
    required this.annotations,
    required this.offset,
    required this.beatType,
    this.initialIndex,
    this.initialKind,
  });
  final List<ScoreAnnotation> annotations;
  final MusicalTime offset;
  final int beatType;
  final int? initialIndex;
  final AnnotationKind? initialKind;
  @override
  State<AnnotationsSheet> createState() => _AnnotationsSheetState();
}

class _AnnotationsSheetState extends State<AnnotationsSheet> {
  late final List<ScoreAnnotation> _items = [...widget.annotations];
  int? _index;
  AnnotationKind _kind = AnnotationKind.staffText;
  final _text = TextEditingController(),
      _beat = TextEditingController(),
      _bpm = TextEditingController();
  String _unit = 'quarter';
  int _dots = 0;
  bool _below = false;
  String? _error;
  static const names = {
    AnnotationKind.staffText: 'Staff text',
    AnnotationKind.systemText: 'System text',
    AnnotationKind.rehearsal: 'Rehearsal mark',
    AnnotationKind.tempo: 'Tempo',
    AnnotationKind.chord: 'Chord symbol',
  };
  MusicalTime get _beatLength => MusicalTime(4, widget.beatType);
  @override
  void initState() {
    super.initState();
    _load(widget.initialIndex, kind: widget.initialKind);
  }

  @override
  void dispose() {
    _text.dispose();
    _beat.dispose();
    _bpm.dispose();
    super.dispose();
  }

  MusicalTime? _parseBeat(String s) {
    try {
      final pieces = s.trim().split('/');
      return pieces.length == 2
          ? MusicalTime(int.parse(pieces[0]), int.parse(pieces[1]))
          : MusicalTime.decimal(s);
    } on Object {
      return null;
    }
  }

  void _load(int? index, {AnnotationKind? kind}) {
    _index = index;
    final a = index == null ? null : _items[index];
    _kind = a?.kind ?? kind ?? AnnotationKind.staffText;
    _text.text = _kind == AnnotationKind.chord
        ? a?.chord?.label ?? ''
        : a?.text ?? '';
    _beat.text = ((a?.offset ?? widget.offset) / _beatLength + MusicalTime.one)
        .toString();
    _bpm.text = ScoreAnnotation.number(a?.perMinute ?? a?.tempo ?? 120);
    _unit = a?.beatUnit ?? 'quarter';
    _dots = a?.beatDots ?? 0;
    _below = a?.below ?? false;
    _error = null;
  }

  double _quarters(String unit, int dots) {
    var base =
        const {
          'whole': 4.0,
          'half': 2.0,
          'quarter': 1.0,
          'eighth': 0.5,
          '16th': 0.25,
        }[unit] ??
        1;
    var extra = base / 2;
    for (var i = 0; i < dots; i++) {
      base += extra;
      extra /= 2;
    }
    return base;
  }

  bool _store({bool allowBlank = false}) {
    if (_index == null &&
        _text.text.isEmpty &&
        _kind != AnnotationKind.tempo &&
        allowBlank) {
      return true;
    }
    final beat = _parseBeat(_beat.text);
    final bpm = double.tryParse(_bpm.text);
    final old = _index == null ? null : _items[_index!];
    final chord = _kind != AnnotationKind.chord
        ? null
        : (_text.text == old?.chord?.label
              ? old?.chord
              : ChordSymbol.parse(_text.text));
    if (old != null &&
        _text.text ==
            (_kind == AnnotationKind.chord ? old.chord?.label : old.text) &&
        beat == (old.offset / _beatLength + MusicalTime.one) &&
        bpm == (old.perMinute ?? old.tempo ?? 120) &&
        _unit == old.beatUnit &&
        _dots == old.beatDots &&
        _below == old.below) {
      return true;
    }
    String? error;
    if (beat == null || beat.compareTo(MusicalTime.one) < 0) {
      error = 'Enter a beat of 1 or greater.';
    } else if (_kind == AnnotationKind.tempo &&
        (bpm == null || !bpm.isFinite || bpm < 1 || bpm > 1000)) {
      error = 'Enter a tempo between 1 and 1000.';
    } else if (_kind == AnnotationKind.chord && chord == null) {
      error = 'Use a chord such as C, Am7, Bbmaj7 or F/A.';
    } else if (_kind != AnnotationKind.tempo && _text.text.trim().isEmpty) {
      error = 'Enter the marking’s text.';
    }
    if (error != null) {
      setState(() => _error = error);
      return false;
    }
    final keepTempo =
        old != null &&
        old.perMinute == bpm &&
        old.beatUnit == _unit &&
        old.beatDots == _dots;
    final a = ScoreAnnotation(
      kind: _kind,
      text: _kind == AnnotationKind.chord ? '' : _text.text,
      offset: (beat! - MusicalTime.one) * _beatLength,
      chord: chord,
      tempo: _kind == AnnotationKind.tempo
          ? (keepTempo ? old.tempo : bpm! * _quarters(_unit, _dots))
          : null,
      perMinute: _kind == AnnotationKind.tempo ? bpm : null,
      beatUnit: _unit,
      beatDots: _dots,
      staff: old?.staff ?? 1,
      below: _below,
      hidden: old?.hidden ?? false,
      sourceIndex: old?.sourceIndex,
      sourceXml: old?.sourceXml,
    );
    if (_index == null) {
      _items.add(a);
      _index = _items.length - 1;
    } else {
      _items[_index!] = a;
    }
    _error = null;
    return true;
  }

  @override
  Widget build(BuildContext context) => Padding(
    padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
    child: SizedBox(
      height: MediaQuery.sizeOf(context).height * .86,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  'Text, tempo & chords',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
                ),
                Row(
                  children: [
                    Expanded(
                      child: TextButton(
                        onPressed: () => Navigator.pop(context),
                        child: const Text('Cancel'),
                      ),
                    ),
                    Expanded(
                      child: FilledButton(
                        key: const ValueKey('annotations-apply'),
                        onPressed: () {
                          if (_store(allowBlank: true)) {
                            Navigator.pop(context, _items);
                          }
                        },
                        child: const Text('Apply'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (_items.isNotEmpty) ...[
                    for (final (i, a) in _items.indexed)
                      ListTile(
                        key: ValueKey('annotation-item-$i'),
                        selected: _index == i,
                        title: Text(a.label.isEmpty ? names[a.kind]! : a.label),
                        subtitle: Text(
                          '${names[a.kind]} · beat ${((a.offset / _beatLength) + MusicalTime.one)}',
                        ),
                        onTap: () {
                          if (_store(allowBlank: true)) {
                            setState(() => _load(i));
                          }
                        },
                        trailing: IconButton(
                          tooltip: 'Remove marking',
                          icon: const Icon(Icons.delete_outline),
                          onPressed: () {
                            if (_index != i && !_store(allowBlank: true)) {
                              return;
                            }
                            setState(() {
                              _items.removeAt(i);
                              _load(null);
                            });
                          },
                        ),
                      ),
                    const Divider(),
                  ],
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final kind in AnnotationKind.values)
                        ActionChip(
                          label: Text('Add ${names[kind]}'),
                          onPressed: () {
                            if (_store(allowBlank: true)) {
                              setState(() => _load(null, kind: kind));
                            }
                          },
                        ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Text(
                    names[_kind]!,
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  TextField(
                    key: const ValueKey('annotation-text'),
                    controller: _text,
                    decoration: InputDecoration(
                      labelText: _kind == AnnotationKind.chord
                          ? 'Chord symbol'
                          : 'Text',
                      hintText: _kind == AnnotationKind.chord
                          ? 'C, Am7, Bbmaj7, F/A'
                          : _kind == AnnotationKind.tempo
                          ? 'Allegro (optional)'
                          : 'dolce, A…',
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    key: const ValueKey('annotation-beat'),
                    controller: _beat,
                    decoration: const InputDecoration(
                      labelText: 'Beat',
                      helperText: '1 = start of bar; fractions allowed',
                    ),
                  ),
                  if (_kind == AnnotationKind.tempo) ...[
                    const SizedBox(height: 12),
                    TextField(
                      key: const ValueKey('annotation-bpm'),
                      controller: _bpm,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      decoration: const InputDecoration(
                        labelText: 'Beats per minute',
                      ),
                    ),
                    DropdownButtonFormField<String>(
                      key: ValueKey('tempo-unit-$_index-$_unit'),
                      initialValue: _unit,
                      isExpanded: true,
                      decoration: const InputDecoration(labelText: 'Beat unit'),
                      items: [
                        for (final unit in <String>{
                          'whole',
                          'half',
                          'quarter',
                          'eighth',
                          '16th',
                          _unit,
                        })
                          DropdownMenuItem(value: unit, child: Text(unit)),
                      ],
                      onChanged: (v) => setState(() => _unit = v ?? 'quarter'),
                    ),
                    DropdownButtonFormField<int>(
                      key: ValueKey('tempo-dots-$_index-$_dots'),
                      initialValue: _dots,
                      isExpanded: true,
                      decoration: const InputDecoration(labelText: 'Dots'),
                      items: [
                        for (var i = 0; i <= (_dots > 2 ? _dots : 2); i++)
                          DropdownMenuItem(value: i, child: Text('$i')),
                      ],
                      onChanged: (v) => setState(() => _dots = v ?? 0),
                    ),
                  ],
                  if (_kind != AnnotationKind.tempo &&
                      _kind != AnnotationKind.rehearsal)
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Below staff'),
                      value: _below,
                      onChanged: (v) => setState(() => _below = v),
                    ),
                  if (_error != null)
                    Text(
                      _error!,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  const SizedBox(height: 12),
                  const Text(
                    'Apply saves all changes in one undo step. Tempo changes affect every staff; chord symbols play supported chord voicings.',
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    ),
  );
}
