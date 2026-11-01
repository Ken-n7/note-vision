import 'package:note_vision/core/models/score.dart';
import 'package:note_vision/core/services/playback_mix.dart';
import 'dart:typed_data';

import 'package:note_vision/core/models/musical_time.dart';
import 'package:note_vision/core/services/playback_converter.dart';
import 'package:xml/xml.dart';

/// What a musician reads from a partwise MusicXML document, one fact per
/// line, independent of how the file encodes it (divisions, element order,
/// layout). MuseScore's export and Note Vision's export are both reduced to
/// these facts and compared as multisets.
List<String> notationFacts(XmlDocument doc) {
  final root = doc.rootElement;
  final facts = <String>[];
  final title =
      _text(root.getElement('work'), 'work-title') ??
      _text(root, 'movement-title');
  if (title != null) facts.add('title "$title"');
  final creators =
      root.getElement('identification')?.findElements('creator') ?? const [];
  for (final creator in creators) {
    final value = creator.innerText.trim();
    if (value.isNotEmpty) {
      facts.add('creator ${creator.getAttribute('type')} "$value"');
    }
  }
  final names = {
    for (final p in root.findAllElements('score-part'))
      p.getAttribute('id'): _text(p, 'part-name') ?? '',
  };
  for (final (pi, part) in root.findElements('part').indexed) {
    final p = 'P${pi + 1}';
    facts.add('$p name "${names[part.getAttribute('id')]}"');
    var divisions = MusicalTime.one;
    for (final (mi, measure) in part.findElements('measure').indexed) {
      final m = '$p m${mi + 1}';
      final lines = <String>[];
      final number = measure.getAttribute('number');
      if (number != '${mi + 1}') lines.add('$m number=$number');
      if (measure.getAttribute('implicit') == 'yes') lines.add('$m implicit');
      var cursor = MusicalTime.zero;
      var chordOnset = MusicalTime.zero;
      MusicalTime ticks(String? value) => value == null
          ? MusicalTime.zero
          : MusicalTime.decimal(value) / divisions;
      for (final e in measure.childElements) {
        switch (e.name.local) {
          case 'attributes':
            final div = _text(e, 'divisions');
            if (div != null) divisions = MusicalTime.decimal(div);
            for (final key in e.findElements('key')) {
              lines.add('$m @$cursor key fifths=${_text(key, 'fifths')}');
            }
            for (final time in e.findElements('time')) {
              final symbol = time.getAttribute('symbol');
              lines.add(
                '$m @$cursor time ${_text(time, 'beats')}/${_text(time, 'beat-type')}'
                '${symbol == null || symbol == 'normal' ? '' : ' $symbol'}',
              );
            }
            final staves = _text(e, 'staves');
            if (staves != null && staves != '1') lines.add('$m staves=$staves');
            for (final clef in e.findElements('clef')) {
              final octave = _text(clef, 'clef-octave-change');
              lines.add(
                '$m @$cursor s=${clef.getAttribute('number') ?? 1} clef '
                '${_text(clef, 'sign')}${_text(clef, 'line') ?? ''}'
                '${octave == null ? '' : ' octave=$octave'}',
              );
            }
          case 'backup':
            cursor -= ticks(_text(e, 'duration'));
          case 'forward':
            cursor += ticks(_text(e, 'duration'));
          case 'note':
            final grace = e.getElement('grace');
            final duration = grace == null
                ? ticks(_text(e, 'duration'))
                : MusicalTime.zero;
            if (e.getElement('chord') == null) {
              chordOnset = cursor;
              cursor += duration;
            }
            lines.add('$m @$chordOnset ${_note(e, duration, grace)}');
          case 'direction':
            final at = cursor + ticks(_text(e, 'offset'));
            final staff = 's=${_text(e, 'staff') ?? 1}';
            for (final type in e.findElements('direction-type')) {
              for (final d in type.childElements) {
                // MuseScore writes an empty <words> beside a metronome mark.
                if (d.name.local != 'words' || d.innerText.trim().isNotEmpty) {
                  lines.add('$m @$at $staff ${_direction(d)}');
                }
              }
            }
            final tempo = e.getElement('sound')?.getAttribute('tempo');
            if (tempo != null) lines.add('$m @$at tempo=$tempo');
          case 'harmony':
            final at = cursor + ticks(_text(e, 'offset'));
            final root = e.getElement('root');
            final bass = e.getElement('bass');
            lines.add(
              '$m @$at harmony ${_text(root, 'root-step')}'
              '${_alter(_text(root, 'root-alter'))} ${_text(e, 'kind')}'
              '${bass == null ? '' : ' /${_text(bass, 'bass-step')}${_alter(_text(bass, 'bass-alter'))}'}',
            );
          case 'barline':
            final parts = [
              e.getAttribute('location') ?? 'right',
              ?_text(e, 'bar-style'),
              if (e.getElement('repeat') case final r?)
                'repeat=${r.getAttribute('direction')}',
              if (e.getElement('ending') case final end?)
                'ending=${end.getAttribute('number')}:${end.getAttribute('type')}',
            ];
            lines.add('$m barline ${parts.join(' ')}');
        }
      }
      lines.sort();
      facts.addAll(lines);
    }
  }
  return facts;
}

String _note(XmlElement e, MusicalTime duration, XmlElement? grace) {
  final out = <String>[
    'v=${_text(e, 'voice') ?? 1}',
    's=${_text(e, 'staff') ?? 1}',
  ];
  final pitch = e.getElement('pitch');
  final rest = e.getElement('rest');
  final unpitched = e.getElement('unpitched');
  if (pitch != null) {
    out.add(
      'note ${_text(pitch, 'step')}${_alter(_text(pitch, 'alter'))}'
      '${_text(pitch, 'octave')}',
    );
  } else if (unpitched != null) {
    out.add(
      'unpitched ${_text(unpitched, 'display-step')}'
      '${_text(unpitched, 'display-octave')}',
    );
  } else {
    out.add(rest?.getAttribute('measure') == 'yes' ? 'rest(measure)' : 'rest');
  }
  out.add(
    grace == null
        ? 'dur=$duration'
        : (grace.getAttribute('slash') == 'yes' ? 'grace/' : 'grace'),
  );
  out.add('${_text(e, 'type') ?? '-'}${'.' * e.findElements('dot').length}');
  final accidental = _text(e, 'accidental');
  if (accidental != null) out.add('acc=$accidental');
  final mod = e.getElement('time-modification');
  if (mod != null) {
    out.add(
      'tuplet=${_text(mod, 'actual-notes')}:${_text(mod, 'normal-notes')}',
    );
  }
  final notations = e.findElements('notations');
  final ties = {
    for (final t in e.findElements('tie')) t.getAttribute('type'),
    for (final n in notations)
      for (final t in n.findElements('tied')) t.getAttribute('type'),
  }.toList()..sort();
  if (ties.isNotEmpty) out.add('tie=${ties.join('+')}');
  for (final n in notations) {
    for (final s in n.findElements('slur')) {
      out.add('slur=${s.getAttribute('type')}');
    }
    for (final t in n.findElements('tuplet')) {
      out.add('tuplet-${t.getAttribute('type')}');
    }
  }
  final marks = [
    for (final n in notations) ...[
      for (final group in ['articulations', 'ornaments', 'technical'])
        for (final g in n.findElements(group))
          for (final mark in g.childElements) mark.name.local,
      for (final mark in n.childElements)
        if (const {
          'fermata',
          'arpeggiate',
          'glissando',
        }.contains(mark.name.local))
          mark.name.local,
    ],
  ]..sort();
  if (marks.isNotEmpty) out.add('marks=${marks.join(',')}');
  final beams = [
    for (final b in e.findElements('beam'))
      '${b.getAttribute('number') ?? 1}:${b.innerText.trim()}',
  ]..sort();
  if (beams.isNotEmpty) out.add('beam=${beams.join(',')}');
  for (final lyric in e.findElements('lyric')) {
    final syllabic = _text(lyric, 'syllabic');
    out.add(
      'lyric${lyric.getAttribute('number') ?? 1}='
      '${syllabic == null ? '' : '$syllabic:'}${_text(lyric, 'text') ?? ''}'
      '${lyric.getElement('extend') == null ? '' : '~'}',
    );
  }
  if (e.getAttribute('print-object') == 'no') out.add('hidden');
  return out.join(' ');
}

String _direction(XmlElement d) => switch (d.name.local) {
  'dynamics' =>
    'dynamics ${d.childElements.map((c) => c.name.local).join(' ')}',
  'wedge' => 'wedge ${d.getAttribute('type')}',
  'words' => 'words "${d.innerText.trim()}"',
  'rehearsal' => 'rehearsal "${d.innerText.trim()}"',
  // MusicXML 4 can write <segno/> as <symbol>segno</symbol>.
  'symbol' => 'direction ${d.innerText.trim()}',
  'metronome' =>
    'metronome ${_text(d, 'beat-unit')}'
        '${'.' * d.findElements('beat-unit-dot').length}=${_text(d, 'per-minute')}',
  final other => 'direction $other',
};

String _alter(String? alter) => switch (alter) {
  null || '0' => '',
  '1' => '#',
  '2' => '##',
  '-1' => 'b',
  '-2' => 'bb',
  final other => '(alter=$other)',
};

String? _text(XmlElement? e, String name) {
  final value = e?.getElement(name)?.innerText.trim();
  return value == null || value.isEmpty ? null : value;
}

/// Only what transposition changes: key signatures, and each note's pitch
/// and written accidental at its place in the bar.
List<String> pitchFacts(List<String> facts) => [
  for (final fact in facts)
    if (fact.contains(' key '))
      fact
    else if (RegExp(r'^(\S+ \S+ @\S+) v=\S+ s=\S+ note (\S+)').firstMatch(fact)
        case final m?)
      '${m[1]} ${m[2]}${RegExp(r' acc=\S+').firstMatch(fact)?[0] ?? ''}',
];

/// Sounding notes as `@onset key dur` and `@onset key vel` (loudness) in
/// quarter notes, so tempo marks do not matter. Instruments are separate facts. Times are rounded to 1/96 quarter:
/// MuseScore releases each note one tick early.
List<String> midiFacts(Uint8List bytes) {
  final data = ByteData.sublistView(bytes);
  var pos = 0;
  String chunk() => String.fromCharCodes(bytes.sublist(pos, pos += 4));
  int u32() => data.getUint32((pos += 4) - 4);
  int varLen() {
    var value = 0;
    while (true) {
      final b = bytes[pos++];
      value = (value << 7) | (b & 0x7f);
      if (b < 0x80) return value;
    }
  }

  if (chunk() != 'MThd') throw const FormatException('Not a MIDI file');
  final headerEnd = u32() + pos;
  final tracks = data.getUint16(pos + 2);
  final ppq = data.getUint16(pos + 4);
  pos = headerEnd;
  MusicalTime q(int ticks) => _quarters(ticks / ppq);

  final facts = <String>[];
  final programs = <String>{};
  for (var t = 0; t < tracks; t++) {
    if (chunk() != 'MTrk') throw const FormatException('Bad MIDI track');
    final end = u32() + pos;
    var tick = 0;
    var status = 0;
    final open = <int, List<int>>{};
    while (pos < end) {
      tick += varLen();
      if (bytes[pos] >= 0x80) status = bytes[pos++];
      if (status == 0xff) {
        pos++;
        final length = varLen();
        pos += length;
        continue;
      }
      if (status == 0xf0 || status == 0xf7) {
        final length = varLen();
        pos += length;
        continue;
      }
      final kind = status >> 4;
      final channel = status & 0x0f;
      final a = bytes[pos++];
      final b = kind == 0xc || kind == 0xd ? 0 : bytes[pos++];
      if (kind == 0xc) programs.add(channel == 9 ? 'drums' : '$a');
      final key = channel << 8 | a;
      if (kind == 0x9 && b > 0) {
        open.putIfAbsent(key, () => []).add(tick);
        facts.add('@${q(tick)} key=$a vel=$b');
      } else if (kind == 0x8 || kind == 0x9) {
        final starts = open[key];
        if (starts == null || starts.isEmpty) continue;
        final start = starts.removeAt(0);
        facts.add('@${q(start)} key=$a dur=${q(tick - start)}');
      }
    }
    pos = end;
  }
  return [...facts, for (final p in programs) 'program $p'];
}

MusicalTime _quarters(num quarters) => MusicalTime((quarters * 96).round(), 96);

/// Note Vision's playback, in the same form as [midiFacts]. Event times are
/// milliseconds at 120 BPM (500 per quarter), with the saved instrument mix.
List<String> playbackFacts(PlaybackPlan plan, Score score) {
  final mix = PlaybackMix(
    score,
    plan.events.where((e) => !e.isRest).map((e) => e.partIndex).toSet(),
  );
  return [
    for (final e in plan.events)
      if (!e.isRest) ...[
        '@${_quarters(e.baseOnsetMs / 500)} key=${e.midiNote} '
            'dur=${_quarters(e.baseDurationMs / 500)}',
        '@${_quarters(e.baseOnsetMs / 500)} key=${e.midiNote} vel=${e.velocity}',
      ],
    for (final program in mix.settings.values.map((s) => s.program).toSet())
      'program $program',
  ];
}

/// Multiset difference: `- ` facts only MuseScore has, `+ ` facts only Note
/// Vision has. The header counts how many MuseScore facts Note Vision matches.
String compareFacts(String label, List<String> reference, List<String> ours) {
  final remaining = <String, int>{};
  for (final fact in ours) {
    remaining[fact] = (remaining[fact] ?? 0) + 1;
  }
  final missing = <String>[];
  for (final fact in reference) {
    final left = remaining[fact] ?? 0;
    if (left > 0) {
      remaining[fact] = left - 1;
    } else {
      missing.add(fact);
    }
  }
  final extra = [
    for (final MapEntry(:key, :value) in remaining.entries)
      for (var i = 0; i < value; i++) key,
  ];
  final matched = reference.length - missing.length;
  return [
    '## $label: $matched/${reference.length} MuseScore facts match'
        '${extra.isEmpty ? '' : ', ${extra.length} differ in Note Vision'}',
    for (final fact in missing..sort()) '- $fact',
    for (final fact in extra..sort()) '+ $fact',
  ].join('\n');
}
