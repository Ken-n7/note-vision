/// MusicXML beam values, numbered from the primary (eighth-note) beam.
enum BeamValue {
  begin('begin'),
  continueBeam('continue'),
  end('end'),
  forwardHook('forward hook'),
  backwardHook('backward hook');

  const BeamValue(this.xmlValue);
  final String xmlValue;

  static BeamValue? parse(String value) {
    for (final beam in values) {
      if (beam.xmlValue == value.trim().toLowerCase()) return beam;
    }
    return null;
  }
}
