import 'package:flutter/material.dart';
import 'package:note_vision/core/models/part_playback.dart';
import 'package:note_vision/core/services/playback_mix.dart';
import 'package:note_vision/core/theme/app_theme.dart';

/// Draft settings: Apply makes one undoable edit; dismissal is inert.
class MixerSheet extends StatefulWidget {
  const MixerSheet({
    super.key,
    required this.strips,
    this.scannedLines = false,
  });
  final List<PlaybackStrip> strips;
  final bool scannedLines;
  @override
  State<MixerSheet> createState() => _MixerSheetState();
}

class _MixerSheetState extends State<MixerSheet> {
  late final _settings = [for (final s in widget.strips) s.settings];
  int _selected = 0;
  void _change(PartPlayback value) =>
      setState(() => _settings[_selected] = value);

  @override
  Widget build(BuildContext context) {
    final setting = _settings[_selected];
    final solo = _settings.any((s) => s.solo);
    final strip = widget.strips[_selected];
    final pan = setting.pan == 0
        ? 'Center'
        : '${setting.pan.abs().round()}° ${setting.pan < 0 ? 'left' : 'right'}';
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SafeArea(
        child: SizedBox(
          height: MediaQuery.sizeOf(context).height * .8,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Padding(
                padding: EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: Text(
                  'Mixer',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
                ),
              ),
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        widget.scannedLines
                            ? 'All scanned lines share one sound and mix.'
                            : 'Choose an instrument to adjust its sound and mix. Linked staves share a strip.',
                        style: const TextStyle(color: AppColors.textSecondary),
                      ),
                      const SizedBox(height: 12),
                      Wrap(
                        spacing: 8,
                        runSpacing: 4,
                        children: [
                          for (final (i, s) in widget.strips.indexed)
                            ChoiceChip(
                              key: ValueKey('mixer-strip-$i'),
                              label: Text(
                                s.name.isEmpty ? 'Instrument ${i + 1}' : s.name,
                              ),
                              selected: i == _selected,
                              onSelected: (_) => setState(() => _selected = i),
                            ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Text(
                        strip.name.isEmpty
                            ? 'Instrument ${_selected + 1}'
                            : strip.name,
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 8),
                      const Text('Sound'),
                      DropdownButton<int>(
                        key: const ValueKey('mixer-sound'),
                        value: setting.program,
                        isExpanded: true,
                        menuMaxHeight: 360,
                        items: [
                          for (final (i, name) in gmSounds.indexed)
                            DropdownMenuItem(
                              value: i,
                              child: Text(
                                name,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                        ],
                        onChanged: (v) {
                          if (v != null) _change(setting.copyWith(program: v));
                        },
                      ),
                      const Text(
                        'Sound changes keep the written notes and clef.',
                        style: TextStyle(color: AppColors.textSecondary),
                      ),
                      const SizedBox(height: 16),
                      Text('Volume · ${setting.volume.round()}%'),
                      Slider(
                        key: const ValueKey('mixer-volume'),
                        value: setting.volume,
                        min: 0,
                        max: 100,
                        divisions: 100,
                        label: '${setting.volume.round()}%',
                        semanticFormatterCallback: (v) =>
                            'Volume ${v.round()} percent',
                        onChanged: (v) => _change(setting.copyWith(volume: v)),
                      ),
                      Text('Pan · $pan'),
                      Slider(
                        key: const ValueKey('mixer-pan'),
                        value: setting.pan,
                        min: -90,
                        max: 90,
                        divisions: 180,
                        label: pan,
                        semanticFormatterCallback: (v) => v == 0
                            ? 'Center'
                            : '${v.abs().round()} degrees ${v < 0 ? 'left' : 'right'}',
                        onChanged: (v) => _change(setting.copyWith(pan: v)),
                      ),
                      Align(
                        alignment: Alignment.centerRight,
                        child: TextButton(
                          onPressed: () => _change(setting.copyWith(pan: 0)),
                          child: const Text('Center pan'),
                        ),
                      ),
                      Wrap(
                        spacing: 12,
                        runSpacing: 8,
                        children: [
                          FilterChip(
                            key: const ValueKey('mixer-mute'),
                            label: const Text('Mute'),
                            selected: setting.mute,
                            onSelected: (v) =>
                                _change(setting.copyWith(mute: v)),
                          ),
                          FilterChip(
                            key: const ValueKey('mixer-solo'),
                            label: const Text('Solo'),
                            selected: setting.solo,
                            onSelected: (v) =>
                                _change(setting.copyWith(solo: v)),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        setting.mute
                            ? 'Muted'
                            : solo && !setting.solo
                            ? 'Silent while another instrument is soloed'
                            : setting.volume == 0
                            ? 'Silent at 0% volume'
                            : 'Audible',
                        style: const TextStyle(color: AppColors.textSecondary),
                      ),
                      const SizedBox(height: 12),
                      OutlinedButton(
                        onPressed: () => _change(const PartPlayback()),
                        child: const Text('Reset this instrument'),
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        'Apply, then play or resume to hear the mix. Mute and solo are saved in the project.',
                        style: TextStyle(color: AppColors.textSecondary),
                      ),
                      const SizedBox(height: 12),
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
                        child: const Text('Cancel'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: FilledButton(
                        key: const ValueKey('mixer-apply'),
                        onPressed: () => Navigator.pop(
                          context,
                          List<PartPlayback>.of(_settings),
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
      ),
    );
  }
}
