import 'package:flutter/material.dart';
import 'package:note_vision/core/models/clef.dart';
import 'package:note_vision/core/models/key_signature.dart';
import 'package:note_vision/core/models/score.dart';
import 'package:note_vision/core/models/time_signature.dart';
import 'package:note_vision/core/theme/app_theme.dart';
import 'package:note_vision/core/utils/emoji_blocking_formatter.dart';
import 'package:note_vision/features/editor/presentation/widgets/staves_sheet.dart';
import 'package:note_vision/features/new_score/new_score.dart';

/// MuseScore Studio's New Score dialog for a phone: choose instruments (from
/// a template or one by one), then the title, key, time, pickup, bars and
/// tempo. Pops the new [Score], or null when cancelled.
class NewScoreWizard extends StatefulWidget {
  const NewScoreWizard({super.key});

  @override
  State<NewScoreWizard> createState() => _NewScoreWizardState();
}

const _times = <(TimeSignature, String)>[
  (TimeSignature(beats: 2, beatType: 4), '2/4'),
  (TimeSignature(beats: 3, beatType: 4), '3/4'),
  (TimeSignature(beats: 4, beatType: 4), '4/4'),
  (TimeSignature.common, 'C'),
  (TimeSignature(beats: 2, beatType: 2), '2/2'),
  (TimeSignature.cut, '¢'),
  (TimeSignature(beats: 3, beatType: 8), '3/8'),
  (TimeSignature(beats: 6, beatType: 8), '6/8'),
  (TimeSignature(beats: 9, beatType: 8), '9/8'),
  (TimeSignature(beats: 12, beatType: 8), '12/8'),
];

String _clefLabel(Clef clef) => switch (clef) {
  Clef(sign: 'F') => 'Bass clef',
  Clef(sign: 'C') => 'Alto clef',
  Clef(octave: -1) => 'Treble clef 8vb',
  Clef(isPercussion: true) => 'Percussion clef',
  _ => 'Treble clef',
};

String _keyLabel(int fifths) => fifths == 0
    ? 'C major · no sharps or flats'
    : '${KeySignature(fifths: fifths).name} · ${fifths.abs()} '
          '${fifths > 0 ? 'sharp' : 'flat'}${fifths.abs() == 1 ? '' : 's'}';

class _NewScoreWizardState extends State<NewScoreWizard> {
  var _step = 0;
  String? _template = scoreTemplates.first.name;
  var _staves = [...scoreTemplates.first.staves];
  final _title = TextEditingController();
  final _composer = TextEditingController();
  var _fifths = 0;
  var _time = const TimeSignature(beats: 4, beatType: 4);
  var _pickup = 0;
  var _bars = 32;
  var _useTempo = false;
  var _tempo = 120;
  String? _emojiError;

  @override
  void dispose() {
    _title.dispose();
    _composer.dispose();
    super.dispose();
  }

  NewScoreOptions get _options => NewScoreOptions(
    staves: _staves,
    title: _title.text.trim(),
    composer: _composer.text.trim(),
    fifths: _fifths,
    time: _time,
    bars: _bars,
    pickupBeats: _pickup,
    tempo: _useTempo ? _tempo.toDouble() : null,
  );

  void _setTime(TimeSignature time) => setState(() {
    _time = time;
    if (!_options.pickupChoices.contains(_pickup)) _pickup = 0;
  });

  Future<void> _addInstrument() async {
    final picked = await showModalBottomSheet<(String, Clef)>(
      context: context,
      backgroundColor: AppColors.surface,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            for (final (name, clef) in staffInstruments)
              ListTile(
                title: Text(
                  name,
                  style: const TextStyle(color: AppColors.textPrimary),
                ),
                subtitle: Text(
                  name == 'Piano' ? 'Grand staff' : _clefLabel(clef),
                  style: const TextStyle(color: AppColors.textSecondary),
                ),
                onTap: () => Navigator.pop(context, (name, clef)),
              ),
          ],
        ),
      ),
    );
    if (picked == null || !mounted) return;
    setState(() {
      _template = null;
      _staves = [
        ..._staves,
        (name: picked.$1, clef: picked.$2, grand: picked.$1 == 'Piano'),
      ];
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        foregroundColor: AppColors.textPrimary,
        leading: IconButton(
          tooltip: _step == 0 ? 'Cancel' : 'Back',
          icon: Icon(
            _step == 0 ? Icons.close_rounded : Icons.arrow_back_rounded,
          ),
          onPressed: () =>
              _step == 0 ? Navigator.pop(context) : setState(() => _step = 0),
        ),
        title: Text(
          _step == 0 ? 'Instruments' : 'Score details',
          style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
        ),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(3),
          child: Semantics(
            label: 'Step ${_step + 1} of 2',
            child: LinearProgressIndicator(
              value: (_step + 1) / 2,
              minHeight: 3,
              color: AppColors.accent,
              backgroundColor: AppColors.border,
            ),
          ),
        ),
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(child: _step == 0 ? _instruments() : _details()),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
              child: SizedBox(
                width: double.infinity,
                height: 52,
                child: FilledButton(
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.accent,
                    foregroundColor: Colors.black,
                  ),
                  onPressed: _staves.isEmpty
                      ? null
                      : () => _step == 0
                            ? setState(() => _step = 1)
                            : Navigator.pop(context, buildNewScore(_options)),
                  child: Text(
                    _step == 0 ? 'Next' : 'Create score',
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _heading(String text) => Padding(
    padding: const EdgeInsets.fromLTRB(0, 20, 0, 8),
    child: Text(
      text,
      style: const TextStyle(
        color: AppColors.textSecondary,
        fontSize: 11,
        letterSpacing: 1.2,
        fontWeight: FontWeight.w600,
      ),
    ),
  );

  Widget _instruments() {
    final groups = <String, List<ScoreTemplate>>{};
    for (final t in scoreTemplates) {
      groups.putIfAbsent(t.group, () => []).add(t);
    }
    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      children: [
        _heading('YOUR STAVES'),
        if (_staves.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 12),
            child: Text(
              'Choose a template or add an instrument.',
              style: TextStyle(color: AppColors.textSecondary),
            ),
          ),
        for (final (i, staff) in _staves.indexed)
          Container(
            margin: const EdgeInsets.only(bottom: 8),
            decoration: BoxDecoration(
              color: AppColors.surface,
              border: Border.all(color: AppColors.border),
              borderRadius: BorderRadius.circular(10),
            ),
            child: ListTile(
              title: Text(
                staff.name,
                style: const TextStyle(color: AppColors.textPrimary),
              ),
              subtitle: Text(
                staff.grand ? 'Grand staff' : _clefLabel(staff.clef),
                style: const TextStyle(color: AppColors.textSecondary),
              ),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    tooltip: 'Move ${staff.name} up',
                    icon: const Icon(Icons.arrow_upward_rounded),
                    color: AppColors.textSecondary,
                    onPressed: i == 0
                        ? null
                        : () => setState(() {
                            _template = null;
                            _staves.insert(i - 1, _staves.removeAt(i));
                          }),
                  ),
                  IconButton(
                    tooltip: 'Remove ${staff.name}',
                    icon: const Icon(Icons.close_rounded),
                    color: AppColors.textSecondary,
                    onPressed: () => setState(() {
                      _template = null;
                      _staves.removeAt(i);
                    }),
                  ),
                ],
              ),
            ),
          ),
        OutlinedButton.icon(
          style: OutlinedButton.styleFrom(
            foregroundColor: AppColors.accent,
            side: const BorderSide(color: AppColors.border),
            minimumSize: const Size.fromHeight(48),
          ),
          icon: const Icon(Icons.add_rounded),
          label: const Text('Add instrument'),
          onPressed: _addInstrument,
        ),
        _heading('OR START FROM A TEMPLATE'),
        for (final MapEntry(key: group, value: templates)
            in groups.entries) ...[
          _heading(group.toUpperCase()),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final t in templates)
                ChoiceChip(
                  label: Text(t.name),
                  selected: _template == t.name,
                  onSelected: (_) => setState(() {
                    _template = t.name;
                    _staves = [...t.staves];
                  }),
                ),
            ],
          ),
        ],
        const SizedBox(height: 16),
      ],
    );
  }

  Widget _field(TextEditingController controller, String label, int max) =>
      TextField(
        controller: controller,
        maxLength: max,
        style: const TextStyle(color: AppColors.textPrimary),
        inputFormatters: [
          EmojiBlockingFormatter(
            onBlocked: () => setState(() => _emojiError = label),
          ),
        ],
        onChanged: (_) {
          if (_emojiError != null) setState(() => _emojiError = null);
        },
        decoration: InputDecoration(
          labelText: label,
          errorText: _emojiError == label ? 'Emoji not allowed' : null,
          labelStyle: const TextStyle(color: AppColors.textSecondary),
        ),
      );

  Widget _details() {
    final pickups = _options.pickupChoices;
    final beat = switch (_time.beatType) {
      2 => 'half',
      8 => 'eighth',
      _ => 'quarter',
    };
    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      children: [
        const SizedBox(height: 8),
        _field(_title, 'Title', 60),
        _field(_composer, 'Composer', 100),
        _heading('KEY SIGNATURE'),
        DropdownButtonFormField<int>(
          initialValue: _fifths,
          isExpanded: true,
          dropdownColor: AppColors.surface,
          style: const TextStyle(color: AppColors.textPrimary),
          items: [
            for (var f = -7; f <= 7; f++)
              DropdownMenuItem(
                value: f,
                child: Text(_keyLabel(f), overflow: TextOverflow.ellipsis),
              ),
          ],
          onChanged: (f) => setState(() => _fifths = f ?? 0),
        ),
        _heading('TIME SIGNATURE'),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final (time, label) in _times)
              ChoiceChip(
                label: Text(label),
                tooltip:
                    '${time.beats}/${time.beatType}'
                    '${time.symbol == null ? '' : ' (${time.symbol!.name} time)'}',
                selected: _time == time,
                onSelected: (_) => _setTime(time),
              ),
          ],
        ),
        _heading('PICKUP BAR'),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            ChoiceChip(
              label: const Text('None'),
              selected: _pickup == 0,
              onSelected: (_) => setState(() => _pickup = 0),
            ),
            for (final n in pickups)
              ChoiceChip(
                label: Text('$n $beat${n == 1 ? '' : 's'}'),
                selected: _pickup == n,
                onSelected: (_) => setState(() => _pickup = n),
              ),
          ],
        ),
        _heading('BARS'),
        Row(
          children: [
            IconButton(
              tooltip: 'Fewer bars',
              icon: const Icon(Icons.remove_rounded),
              color: AppColors.textPrimary,
              onPressed: _bars > 1 ? () => setState(() => _bars--) : null,
            ),
            SizedBox(
              width: 56,
              child: Text(
                '$_bars',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            IconButton(
              tooltip: 'More bars',
              icon: const Icon(Icons.add_rounded),
              color: AppColors.textPrimary,
              onPressed: _bars < 500 ? () => setState(() => _bars++) : null,
            ),
            Expanded(
              child: Text(
                _pickup > 0 ? 'plus the pickup' : '',
                style: const TextStyle(color: AppColors.textSecondary),
              ),
            ),
          ],
        ),
        _heading('TEMPO'),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text(
            'Write a metronome mark',
            style: TextStyle(color: AppColors.textPrimary),
          ),
          value: _useTempo,
          onChanged: (v) => setState(() => _useTempo = v),
        ),
        if (_useTempo)
          Row(
            children: [
              Text(
                '${switch (_options.tempoUnit) {
                  ('quarter', 1) => 'Dotted quarter',
                  ('half', _) => 'Half',
                  _ => 'Quarter',
                }} =',
                style: const TextStyle(color: AppColors.textPrimary),
              ),
              Expanded(
                child: Slider(
                  value: _tempo.toDouble(),
                  min: 30,
                  max: 240,
                  divisions: 210,
                  label: '$_tempo',
                  onChanged: (v) => setState(() => _tempo = v.round()),
                ),
              ),
              SizedBox(
                width: 40,
                child: Text(
                  '$_tempo',
                  style: const TextStyle(color: AppColors.textPrimary),
                ),
              ),
            ],
          ),
        const SizedBox(height: 16),
      ],
    );
  }
}
