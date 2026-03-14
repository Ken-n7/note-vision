import 'package:xml/xml.dart';

import 'musicxml_parse_result.dart';

/// Parses raw MusicXML text into a structured XML document result.
class MusicXmlParserService {
  const MusicXmlParserService();

  MusicXmlParseResult parse(String rawXml) {
    if (rawXml.trim().isEmpty) {
      return MusicXmlParseResult.failure(
        errorMessage: 'XML input is empty.',
      );
    }

    try {
      final document = XmlDocument.parse(rawXml);
      final rootTagName = document.rootElement.name.local;

      return MusicXmlParseResult.success(
        document: document,
        rootTagName: rootTagName,
      );
    } on XmlException catch (e) {
      return MusicXmlParseResult.failure(
        errorMessage: 'Malformed XML: ${e.message}',
      );
    } catch (e) {
      if (_looksLikeXmlMalformedError(e)) {
        return MusicXmlParseResult.failure(
          errorMessage: 'Malformed XML: $e',
        );
      }

      return MusicXmlParseResult.failure(
        errorMessage: 'XML parsing failed: $e',
      );
    }
  }

  bool _looksLikeXmlMalformedError(Object error) {
    final text = error.toString();
    return text.contains('XmlTagException') ||
        text.contains('XmlParserException') ||
        text.contains('Expected </');
  }
}