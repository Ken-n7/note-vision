/// Thrown when a MusicXML file cannot be read or is invalid.
class MusicXmlImportException implements Exception {
  final String message;

  const MusicXmlImportException(this.message);

  @override
  String toString() => 'MusicXmlImportException: $message';
}
