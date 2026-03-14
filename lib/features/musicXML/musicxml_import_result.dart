import 'musicxml_parse_result.dart';

/// Holds the result of a MusicXML file import operation.
class MusicXmlImportResult {
  final String fileName;
  final String xmlContent;
  final MusicXmlParseResult parseResult;

  const MusicXmlImportResult({
    required this.fileName,
    required this.xmlContent,
    required this.parseResult,
  });
}
