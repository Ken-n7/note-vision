import 'package:flutter/material.dart';
import 'package:note_vision/core/models/note.dart';
import 'package:note_vision/core/models/score.dart';
import 'package:note_vision/core/theme/app_theme.dart';
import 'package:note_vision/core/widgets/score_notation_viewer.dart';
import 'package:note_vision/features/editor/domain/editor_actions.dart';
import 'package:note_vision/features/editor/model/editor_state.dart';

/// Draft lyric entry: Apply commits the whole session as one editor edit;
/// Cancel, Back and dismissal leave the score untouched.
class LyricsSheet extends StatefulWidget {
  const LyricsSheet({super.key, required this.initialState});
  final EditorState initialState;
  @override
  State<LyricsSheet> createState() => _LyricsSheetState();
}

class _LyricsSheetState extends State<LyricsSheet> {
  late EditorState _draft;
  final _text = TextEditingController();
  final _verse = TextEditingController(text: '1');
  final _focus = FocusNode();
  Syllabic _syllabic = Syllabic.single;
  LyricExtend? _extend;
  String? _message;
  String _activeVerse = '1';
  String get verse => _activeVerse;
  bool get _validVerse =>
      _verse.text.trim().isNotEmpty &&
      !RegExp(r'\s').hasMatch(_verse.text.trim());

  @override
  void initState() {
    super.initState();
    _draft = widget.initialState;
    _load();
  }

  @override
  void dispose() {
    _text.dispose();
    _verse.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _load({Syllabic? syllabic}) {
    final lyric = _draft.selectedLyric(verse);
    _text.text = lyric?.text ?? '';
    _text.selection = TextSelection.collapsed(offset: _text.text.length);
    _syllabic = syllabic ?? lyric?.syllabic ?? Syllabic.single;
    _extend = lyric?.extend;
  }

  void _store() {
    if (verse.isEmpty || RegExp(r'\s').hasMatch(verse)) return;
    final original = _draft.selectedLyric(verse);
    _draft = _draft.setLyric(
      verse,
      Lyric(
        verse: verse,
        text: _text.text,
        syllabic: _syllabic,
        extend: _extend,
        above: original?.above ?? false,
        hidden: original?.hidden ?? false,
        sourceXml: original?.sourceXml,
      ),
    );
  }

  bool _sameNote(EditorState a, EditorState b) =>
      a.selectedMeasureIndex == b.selectedMeasureIndex &&
      a.selectedSymbolIndex == b.selectedSymbolIndex;

  void _advance(String separator) {
    if (verse.isEmpty || RegExp(r'\s').hasMatch(verse)) return;
    final next = _draft.nextLyricNote(1, includeTied: separator == '_');
    if (_sameNote(next, _draft)) {
      _store();
      setState(
        () => _message = 'End of this voice. Apply to keep your lyrics.',
      );
      return;
    }
    if (separator == '-') {
      _syllabic = _syllabic == Syllabic.end || _syllabic == Syllabic.middle
          ? Syllabic.middle
          : Syllabic.begin;
      _extend = null;
    } else if (separator == '_') {
      _extend = _text.text.isEmpty
          ? LyricExtend.continueLine
          : LyricExtend.start;
    }
    _store();
    // Navigate on the updated score, not the earlier snapshot.
    _draft = _draft.nextLyricNote(1, includeTied: separator == '_');
    if (separator == '_') {
      final original = _draft.selectedLyric(verse);
      _draft = _draft.setLyric(
        verse,
        Lyric(
          text: '',
          verse: verse,
          extend: LyricExtend.stop,
          above: original?.above ?? false,
          sourceXml: original?.sourceXml,
        ),
      );
    }
    setState(() {
      _message = null;
      _load(syllabic: separator == '-' ? Syllabic.end : null);
    });
    _focus.requestFocus();
  }

  void _typed(String value) {
    // The same operations work from a hardware or software keyboard. A paste
    // can contain several words and syllables, filling notes in this voice.
    var remaining = value;
    var moved = false;
    while (true) {
      final match = RegExp(r'[ _-]').firstMatch(remaining);
      if (match == null) break;
      _text.text = remaining.substring(0, match.start);
      final before = _draft;
      _advance(match[0]!);
      remaining = remaining.substring(match.end);
      moved = !_sameNote(before, _draft);
      if (_sameNote(before, _draft)) {
        // Keep excess pasted text visible; do not silently discard it.
        remaining = '${_text.text} $remaining'.trim();
        break;
      }
    }
    if (remaining != value && !(remaining.isEmpty && moved)) {
      _text.text = remaining;
      _text.selection = TextSelection.collapsed(offset: remaining.length);
    }
  }

  @override
  Widget build(BuildContext context) {
    final note = _draft.selectedSymbol as Note;
    return Padding(
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
                    'Lyrics',
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
                      const SizedBox(width: 8),
                      Expanded(
                        child: FilledButton(
                          key: const ValueKey('lyrics-apply'),
                          onPressed: !_validVerse
                              ? null
                              : () {
                                  _store();
                                  Navigator.pop<Score>(context, _draft.score);
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
                    Text(
                      'Bar ${_draft.selectedMeasureIndex! + 1} · ${note.pitch} · Voice ${note.voice ?? 1}',
                      style: const TextStyle(color: AppColors.textSecondary),
                    ),
                    const SizedBox(height: 8),
                    SizedBox(
                      height: 126,
                      child: ClipRect(
                        child: FittedBox(
                          fit: BoxFit.contain,
                          child: SizedBox(
                            width: 500,
                            child: ScoreNotationViewer(
                              score: _draft.score,
                              selectedPartIndex: _draft.selectedPartIndex!,
                              firstMeasureIndex: _draft.selectedMeasureIndex!,
                              pageMeasureCount: 1,
                              measuresPerRow: 1,
                              minMeasureWidth: 380,
                              selectedMeasureIndex: 0,
                              selectedSymbolIndex: _draft.selectedSymbolIndex,
                              backgroundColor: Colors.white,
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      key: const ValueKey('lyrics-verse'),
                      controller: _verse,
                      decoration: const InputDecoration(
                        labelText: 'Verse',
                        helperText: 'Number or name (for example, 1 or chorus)',
                      ),
                      onChanged: (_) => setState(() {
                        _store();
                        _activeVerse = _verse.text.trim();
                        _load();
                      }),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      key: const ValueKey('lyrics-text'),
                      controller: _text,
                      focusNode: _focus,
                      autofocus: true,
                      decoration: const InputDecoration(
                        labelText: 'Syllable',
                        hintText: 'Type lyrics here',
                      ),
                      onChanged: _typed,
                      onSubmitted: (_) => _advance(' '),
                    ),
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        OutlinedButton(
                          onPressed: () => _advance(' '),
                          child: const Text('Next word'),
                        ),
                        OutlinedButton(
                          onPressed: () => _advance('-'),
                          child: const Text('Hyphen -'),
                        ),
                        OutlinedButton(
                          onPressed: () => _advance('_'),
                          child: const Text('Extend _'),
                        ),
                        OutlinedButton(
                          onPressed: () {
                            _store();
                            setState(() {
                              _draft = _draft.nextLyricNote(
                                -1,
                                includeTied: true,
                              );
                              _message = null;
                              _load();
                            });
                          },
                          child: const Text('Previous note'),
                        ),
                        TextButton(
                          onPressed: () {
                            setState(() {
                              _draft = _draft.setLyric(verse, null);
                              _load();
                            });
                          },
                          child: const Text('Remove syllable'),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<Syllabic>(
                      key: ValueKey(
                        'lyrics-syllabic-${_draft.selectedMeasureIndex}-${_draft.selectedSymbolIndex}-$_syllabic',
                      ),
                      initialValue: _syllabic,
                      isExpanded: true,
                      decoration: const InputDecoration(
                        labelText: 'Syllable in word',
                      ),
                      items: [
                        for (final s in Syllabic.values)
                          DropdownMenuItem(value: s, child: Text(s.name)),
                      ],
                      onChanged: (v) {
                        if (v != null) setState(() => _syllabic = v);
                      },
                    ),
                    const SizedBox(height: 8),
                    DropdownButtonFormField<String>(
                      key: ValueKey(
                        'lyrics-extend-${_draft.selectedMeasureIndex}-${_draft.selectedSymbolIndex}-$_extend',
                      ),
                      initialValue: _extend?.name ?? 'none',
                      isExpanded: true,
                      decoration: const InputDecoration(
                        labelText: 'Extension line',
                      ),
                      items: const [
                        DropdownMenuItem(value: 'none', child: Text('None')),
                        DropdownMenuItem(value: 'start', child: Text('Start')),
                        DropdownMenuItem(
                          value: 'continueLine',
                          child: Text('Continue'),
                        ),
                        DropdownMenuItem(value: 'stop', child: Text('Stop')),
                      ],
                      onChanged: (v) => setState(
                        () => _extend = LyricExtend.values
                            .where((e) => e.name == v)
                            .firstOrNull,
                      ),
                    ),
                    const SizedBox(height: 12),
                    const Text(
                      'Space: next word · -: next syllable · _: hold across the next note. Use the buttons on a phone. Lyrics stay in this voice. Apply saves all changes together.',
                    ),
                    if (_message != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: Text(_message!),
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
}
