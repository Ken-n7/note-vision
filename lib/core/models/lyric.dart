/// A syllable attached to a note. Verse identifiers are MusicXML tokens, not
/// necessarily integers (a chorus may be named).
enum Syllabic { single, begin, middle, end }

enum LyricExtend { start, continueLine, stop }

class Lyric {
  const Lyric({
    required this.text,
    this.verse = '1',
    this.syllabic = Syllabic.single,
    this.extend,
    this.above = false,
    this.hidden = false,
    this.sourceXml,
  });

  final String text, verse;
  final Syllabic syllabic;
  final LyricExtend? extend;
  final bool above, hidden;

  /// Keeps imported elisions, formatting and unmodeled lyric metadata through
  /// project saves and generated exports. Unchanged lyrics are emitted intact.
  final String? sourceXml;

  Map<String, dynamic> toJson() => {
    'text': text,
    'verse': verse,
    'syllabic': syllabic.name,
    if (extend != null) 'extend': extend!.name,
    if (above) 'above': true,
    if (hidden) 'hidden': true,
    if (sourceXml != null) 'sourceXml': sourceXml,
  };

  factory Lyric.fromJson(Map<String, dynamic> json) => Lyric(
    text: json['text'] as String? ?? '',
    verse: json['verse'] as String? ?? '1',
    syllabic: Syllabic.values.firstWhere(
      (v) => v.name == json['syllabic'],
      orElse: () => Syllabic.single,
    ),
    extend: LyricExtend.values
        .where((v) => v.name == json['extend'])
        .firstOrNull,
    above: json['above'] == true,
    hidden: json['hidden'] == true,
    sourceXml: json['sourceXml'] as String?,
  );

  static List<Lyric> listFromJson(dynamic value) => value is List
      ? List.unmodifiable(
          value.whereType<Map>().map(
            (v) => Lyric.fromJson(Map<String, dynamic>.from(v)),
          ),
        )
      : const [];
}
