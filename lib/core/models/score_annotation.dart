import 'musical_time.dart';

enum AnnotationKind { staffText, systemText, rehearsal, tempo, chord }

/// Beat-attached notation, independent of the notes in a bar. Times are exact
/// quarter notes, so a marking can sit between notes or in an empty bar.
class ScoreAnnotation {
  const ScoreAnnotation({
    required this.kind,
    this.offset = MusicalTime.zero,
    this.text = '',
    this.tempo,
    this.beatUnit = 'quarter',
    this.beatDots = 0,
    this.perMinute,
    this.chord,
    this.staff = 1,
    this.below = false,
    this.hidden = false,
    this.sourceIndex,
    this.sourceXml,
  });
  final AnnotationKind kind;
  final MusicalTime offset;
  final String text, beatUnit;
  final double? tempo, perMinute;
  final int beatDots, staff;
  final ChordSymbol? chord;
  final bool below, hidden;
  final int? sourceIndex;
  final String? sourceXml;
  bool get system =>
      kind == AnnotationKind.systemText ||
      kind == AnnotationKind.tempo ||
      kind == AnnotationKind.rehearsal;
  String get label => kind == AnnotationKind.chord
      ? chord?.label ?? text
      : kind == AnnotationKind.tempo
      ? [
          if (text.isNotEmpty) text,
          if (perMinute != null)
            '$beatUnit${'.' * beatDots} = ${number(perMinute!)}',
          if (perMinute == null && tempo != null && text.isEmpty)
            'quarter = ${number(tempo!)}',
        ].join('  ')
      : text;
  static String number(double n) =>
      n == n.roundToDouble() ? '${n.toInt()}' : '$n';
  Map<String, dynamic> toJson() => {
    'kind': kind.name,
    'offset': offset.toJson(),
    'text': text,
    if (tempo != null) 'tempo': tempo,
    'beatUnit': beatUnit,
    'beatDots': beatDots,
    if (perMinute != null) 'perMinute': perMinute,
    if (chord != null) 'chord': chord!.toJson(),
    'staff': staff,
    if (below) 'below': true,
    if (hidden) 'hidden': true,
    if (sourceIndex != null) 'sourceIndex': sourceIndex,
    if (sourceXml != null) 'sourceXml': sourceXml,
  };
  factory ScoreAnnotation.fromJson(Map<String, dynamic> j) => ScoreAnnotation(
    kind: AnnotationKind.values.byName(j['kind'] as String),
    offset: j['offset'] == null
        ? MusicalTime.zero
        : MusicalTime.fromJson(Map<String, dynamic>.from(j['offset'] as Map)),
    text: j['text'] as String? ?? '',
    tempo: (j['tempo'] as num?)?.toDouble(),
    beatUnit: j['beatUnit'] as String? ?? 'quarter',
    beatDots: j['beatDots'] as int? ?? 0,
    perMinute: (j['perMinute'] as num?)?.toDouble(),
    chord: j['chord'] == null
        ? null
        : ChordSymbol.fromJson(Map<String, dynamic>.from(j['chord'] as Map)),
    staff: j['staff'] as int? ?? 1,
    below: j['below'] == true,
    hidden: j['hidden'] == true,
    sourceIndex: j['sourceIndex'] as int?,
    sourceXml: j['sourceXml'] as String?,
  );
}

/// Common lead-sheet chord kinds. Unknown imported kinds/degrees retain their
/// original XML; accompaniment is limited to these explicitly defined voicings.
class ChordSymbol {
  const ChordSymbol({
    required this.root,
    this.alter = 0,
    this.kind = 'major',
    this.bass,
    this.bassAlter = 0,
    this.kindText,
  });
  final String root, kind;
  final int alter, bassAlter;
  final String? bass, kindText;
  static const kinds = <String, (String, List<int>)>{
    'major': ('', [0, 4, 7]),
    'minor': ('m', [0, 3, 7]),
    'dominant': ('7', [0, 4, 7, 10]),
    'major-seventh': ('maj7', [0, 4, 7, 11]),
    'minor-seventh': ('m7', [0, 3, 7, 10]),
    'diminished': ('dim', [0, 3, 6]),
    'augmented': ('aug', [0, 4, 8]),
    'half-diminished': ('m7b5', [0, 3, 6, 10]),
    'diminished-seventh': ('dim7', [0, 3, 6, 9]),
    'major-sixth': ('6', [0, 4, 7, 9]),
    'minor-sixth': ('m6', [0, 3, 7, 9]),
    'suspended-second': ('sus2', [0, 2, 7]),
    'suspended-fourth': ('sus4', [0, 5, 7]),
    'power': ('5', [0, 7]),
    'dominant-ninth': ('9', [0, 4, 7, 10, 14]),
    'major-ninth': ('maj9', [0, 4, 7, 11, 14]),
    'minor-ninth': ('m9', [0, 3, 7, 10, 14]),
  };
  static String accidental(int value) => switch (value) {
    -2 => 'bb',
    -1 => 'b',
    1 => '#',
    2 => '##',
    _ => '',
  };
  String get label => kind == 'none'
      ? 'N.C.'
      : '$root${accidental(alter)}${kindText ?? kinds[kind]?.$1 ?? ' ($kind)'}'
            '${bass == null ? '' : '/$bass${accidental(bassAlter)}'}';
  static ChordSymbol? parse(String value) {
    if (value.trim().toUpperCase() == 'N.C.') {
      return const ChordSymbol(root: 'C', kind: 'none');
    }
    final m = RegExp(
      r'^([A-Ga-g])(bb|##|#|b|x)?([^/]*)(?:/([A-Ga-g])(bb|##|#|b|x)?)?$',
    ).firstMatch(value.trim());
    if (m == null) return null;
    final suffix = m[3]!.trim();
    final kind = kinds.entries
        .where((e) => e.value.$1 == suffix)
        .firstOrNull
        ?.key;
    if (kind == null) return null;
    int alter(String? v) => switch (v) {
      'bb' => -2,
      'b' => -1,
      '#' => 1,
      '##' || 'x' => 2,
      _ => 0,
    };
    return ChordSymbol(
      root: m[1]!.toUpperCase(),
      alter: alter(m[2]),
      kind: kind,
      bass: m[4]?.toUpperCase(),
      bassAlter: alter(m[5]),
    );
  }

  static int pitchClass(String step, int alter) =>
      ((const {'C': 0, 'D': 2, 'E': 4, 'F': 5, 'G': 7, 'A': 9, 'B': 11}[step] ??
              0) +
          alter) %
      12;
  List<int> get midiNotes =>
      kinds[kind] == null ||
          !const {'A', 'B', 'C', 'D', 'E', 'F', 'G'}.contains(root) ||
          alter.abs() > 2 ||
          bassAlter.abs() > 2
      ? const []
      : [
          36 + pitchClass(bass ?? root, bass == null ? alter : bassAlter),
          ...({
            for (final interval in kinds[kind]!.$2)
              60 + (pitchClass(root, alter) + interval) % 12,
          }.toList()..sort()),
        ];
  Map<String, dynamic> toJson() => {
    'root': root,
    'alter': alter,
    'kind': kind,
    if (bass != null) 'bass': bass,
    'bassAlter': bassAlter,
    if (kindText != null) 'kindText': kindText,
  };
  factory ChordSymbol.fromJson(Map<String, dynamic> j) => ChordSymbol(
    root: j['root'] as String,
    alter: j['alter'] as int? ?? 0,
    kind: j['kind'] as String? ?? 'major',
    bass: j['bass'] as String?,
    bassAlter: j['bassAlter'] as int? ?? 0,
    kindText: j['kindText'] as String?,
  );
}
