import 'package:xml/xml.dart';

import 'musicxml_parse_result.dart';
import 'musicxml_validator_service.dart';

/// Parses raw MusicXML text into a structured XML document result.
class MusicXmlParserService {
  const MusicXmlParserService({MusicXmlValidatorService? validator})
    : _validator = validator ?? const MusicXmlValidatorService();

  final MusicXmlValidatorService _validator;

  MusicXmlParseResult parse(String rawXml) {
    if (rawXml.trim().isEmpty) {
      return MusicXmlParseResult.failure(errorMessage: 'XML input is empty.');
    }

    try {
      final document = XmlDocument.parse(rawXml);
      final rootTagName = document.rootElement.name.local;
      final validationResult = _validator.validate(document);

      if (!validationResult.isValid) {
        return MusicXmlParseResult.failure(
          errorMessage:
              'Invalid MusicXML score: ${validationResult.validationErrors.first}',
          rootTagName: rootTagName,
          document: document,
          validationErrors: validationResult.validationErrors,
          warnings: validationResult.warnings,
        );
      }

      return MusicXmlParseResult.success(
        document: document,
        rootTagName: rootTagName,
        warnings: validationResult.warnings,
      );
    } on XmlException catch (e) {
      return MusicXmlParseResult.failure(
        errorMessage: 'Malformed XML: ${e.message}',
      );
    } catch (e) {
      if (_looksLikeXmlMalformedError(e)) {
        return MusicXmlParseResult.failure(errorMessage: 'Malformed XML: $e');
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
