import 'package:flutter/material.dart';
import 'package:note_vision/core/config/app_features.dart';
import 'package:note_vision/core/models/clef.dart';
import 'package:note_vision/core/theme/app_theme.dart';
import 'package:note_vision/features/editor/domain/editor_actions.dart';

/// Instruments offered when adding a staff, with their usual clef.
const staffInstruments = <(String, Clef)>[
  ('Piano', Clef(sign: 'G', line: 2)),
  ('Voice', Clef(sign: 'G', line: 2)),
  ('Soprano', Clef(sign: 'G', line: 2)),
  ('Alto', Clef(sign: 'G', line: 2)),
  ('Tenor', Clef(sign: 'G', line: 2, octave: -1)),
  ('Flute', Clef(sign: 'G', line: 2)),
  ('Oboe', Clef(sign: 'G', line: 2)),
  ('Violin', Clef(sign: 'G', line: 2)),
  ('Guitar', Clef(sign: 'G', line: 2, octave: -1)),
  ('Clarinet in Bb', Clef(sign: 'G', line: 2)),
  ('Alto Saxophone', Clef(sign: 'G', line: 2)),
  ('Tenor Saxophone', Clef(sign: 'G', line: 2)),
  ('Trumpet in Bb', Clef(sign: 'G', line: 2)),
  ('Horn in F', Clef(sign: 'G', line: 2)),
  ('Viola', Clef(sign: 'C', line: 3)),
  ('Cello', Clef(sign: 'F', line: 4)),
  ('Double bass', Clef(sign: 'F', line: 4)),
  ('Bassoon', Clef(sign: 'F', line: 4)),
  ('Drum Kit', Clef.percussion),
  ('Trombone', Clef(sign: 'F', line: 4)),
  ('Tuba', Clef(sign: 'F', line: 4)),
  ('Bass guitar', Clef(sign: 'F', line: 4)),
  ('Bass voice', Clef(sign: 'F', line: 4)),
];

String _clefName(Clef? clef) => switch (clef) {
  Clef(sign: 'F') => 'Bass clef',
  Clef(sign: 'C', line: 3) => 'Alto clef',
  Clef(sign: 'C') => 'Tenor clef',
  Clef(octave: -1) => 'Treble clef 8vb',
  Clef(isPercussion: true) => 'Percussion clef',
  _ => 'Treble clef',
};

/// MuseScore's Instruments panel, for one staff per part: add, rename,
/// reorder and remove staves. Pops the new order as a [StaffPlanEntry] list,
/// applied as one undo step.
class StavesSheet extends StatefulWidget {
  const StavesSheet({super.key, required this.staves, this.addBlockedReason});

  /// Each existing part's name, opening clef and whether it is a further
  /// staff of the part above, in order.
  final List<(String, Clef?, bool)> staves;

  /// Why staves cannot be added, if they cannot.
  final String? addBlockedReason;

  @override
  State<StavesSheet> createState() => _StavesSheetState();
}

class _StavesSheetState extends State<StavesSheet> {
  late final _plan = <StaffPlanEntry>[
    for (final (i, (name, clef, joins)) in widget.staves.indexed)
      (from: i, name: name, clef: clef, joinsPrevious: joins),
  ];

  bool get _changed =>
      _plan.length != widget.staves.length ||
      [
        for (final (i, e) in _plan.indexed)
          e.from != i || e.name != widget.staves[i].$1,
      ].any((c) => c);

  void _move(int index, int delta) => setState(() {
    final entry = _plan.removeAt(index);
    _plan.insert(index + delta, entry);
  });

  Future<void> _rename(int index) async {
    final controller = TextEditingController(text: _plan[index].name);
    final name = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: const Text('Staff name'),
        content: TextField(
          key: const ValueKey('staff-name-field'),
          controller: controller,
          autofocus: true,
          textCapitalization: TextCapitalization.sentences,
          onSubmitted: (v) => Navigator.pop(context, v),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text),
            child: const Text('Rename'),
          ),
        ],
      ),
    );
    controller.dispose();
    final trimmed = name?.trim();
    if (trimmed == null || trimmed.isEmpty || !mounted) return;
    setState(() {
      final e = _plan[index];
      _plan[index] = (
        from: e.from,
        name: trimmed,
        clef: e.clef,
        joinsPrevious: e.joinsPrevious,
      );
    });
  }

  Future<void> _add() async {
    final picked = await showDialog<(String, Clef)>(
      context: context,
      builder: (context) => SimpleDialog(
        backgroundColor: AppColors.surface,
        title: const Text('Add instrument'),
        children: [
          for (final (name, clef) in staffInstruments)
            // Alto and tenor clefs stay hidden while the scanner cannot read
            // them (AppFeatures.cClefs).
            if (clef.sign != 'C' || AppFeatures.cClefs)
              SimpleDialogOption(
                onPressed: () => Navigator.pop(context, (name, clef)),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: Text(
                    name == 'Piano'
                        ? 'Piano · grand staff'
                        : '$name · ${_clefName(clef)}',
                  ),
                ),
              ),
        ],
      ),
    );
    if (picked == null || !mounted) return;
    setState(() {
      _plan.add((
        from: null,
        name: picked.$1,
        clef: picked.$2,
        joinsPrevious: false,
      ));
      // A piano has a grand staff: treble above, bass below, braced.
      if (picked.$1 == 'Piano') {
        _plan.add((
          from: null,
          name: 'Piano',
          clef: const Clef(sign: 'F', line: 4),
          joinsPrevious: true,
        ));
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 0, 16, 4),
            child: Text(
              'Staves and instruments',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Text(
              widget.addBlockedReason ??
                  'Top to bottom as on the page. Tap a name to rename it. New staves start empty and play with the others.',
              style: const TextStyle(color: AppColors.textSecondary),
            ),
          ),
          Flexible(
            child: ListView(
              shrinkWrap: true,
              children: [
                for (final (i, entry) in _plan.indexed)
                  ListTile(
                    key: ValueKey('staff-row-$i'),
                    title: Text(
                      entry.name.isEmpty ? 'Staff ${i + 1}' : entry.name,
                    ),
                    subtitle: Text(
                      [
                        if (entry.from == null) 'New',
                        if (entry.joinsPrevious && i > 0) 'lower staff',
                        _clefName(entry.clef),
                      ].join(' · '),
                    ),
                    onTap: () => _rename(i),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          tooltip: 'Move up',
                          onPressed: i == 0 ? null : () => _move(i, -1),
                          icon: const Icon(Icons.arrow_upward_rounded),
                        ),
                        IconButton(
                          tooltip: 'Move down',
                          onPressed: i == _plan.length - 1
                              ? null
                              : () => _move(i, 1),
                          icon: const Icon(Icons.arrow_downward_rounded),
                        ),
                        IconButton(
                          tooltip: 'Remove staff',
                          onPressed: _plan.length == 1
                              ? null
                              : () => setState(() => _plan.removeAt(i)),
                          icon: const Icon(Icons.delete_outline_rounded),
                          color: AppColors.error,
                        ),
                      ],
                    ),
                  ),
                if (widget.addBlockedReason == null)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                    child: OutlinedButton.icon(
                      onPressed: _add,
                      icon: const Icon(Icons.add_rounded),
                      label: const Text('Add instrument'),
                      style: OutlinedButton.styleFrom(
                        minimumSize: const Size(48, 48),
                      ),
                    ),
                  ),
              ],
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
                    onPressed: _changed
                        ? () => Navigator.pop<List<StaffPlanEntry>>(
                            context,
                            List.of(_plan),
                          )
                        : null,
                    style: FilledButton.styleFrom(
                      minimumSize: const Size(48, 48),
                    ),
                    child: const Text('Done'),
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
