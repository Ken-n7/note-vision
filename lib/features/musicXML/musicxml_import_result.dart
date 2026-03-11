/// Holds the result of a MusicXML file import operation.
class MusicXmlImportResult {
  final String fileName;
  final String xmlContent;

  const MusicXmlImportResult({
    required this.fileName,
    required this.xmlContent,
  });
}