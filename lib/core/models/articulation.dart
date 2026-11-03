/// Marks on a note (a fermata also on a rest), named as MusicXML names them.
/// [group] is the MusicXML `<notations>` child they belong to; a fermata is
/// its own element.
enum Articulation {
  staccato('staccato', 'articulations'),
  staccatissimo('staccatissimo', 'articulations'),
  tenuto('tenuto', 'articulations'),
  accent('accent', 'articulations'),
  marcato('strong-accent', 'articulations'),
  fermata('fermata', null),
  trill('trill-mark', 'ornaments'),
  mordent('mordent', 'ornaments'),
  invertedMordent('inverted-mordent', 'ornaments'),
  turn('turn', 'ornaments');

  const Articulation(this.xmlName, this.group);

  final String xmlName;
  final String? group;

  /// Drawn next to the notehead, on the side away from the stem.
  bool get nearHead => group == 'articulations';

  static Articulation? fromXml(String name) =>
      values.where((a) => a.xmlName == name).firstOrNull;

  static List<Articulation> listFromJson(Object? json) => json is List
      ? [
          for (final name in json)
            ?values.where((a) => a.name == name).firstOrNull,
        ]
      : const [];
}
