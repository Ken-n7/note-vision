import 'package:flutter_test/flutter_test.dart';

import 'package:note_vision/features/musicXML/musicxml_parser_service.dart';

void main() {
  const parser = MusicXmlParserService();

  group('MusicXmlParserService.parse', () {
    test('returns success for valid XML and exposes root tag name', () {
      const xml = '''<?xml version="1.0" encoding="UTF-8"?>
<score-partwise version="3.1">
  <part-list/>
</score-partwise>''';

      final result = parser.parse(xml);

      expect(result.success, isTrue);
      expect(result.document, isNotNull);
      expect(result.rootTagName, 'score-partwise');
      expect(result.errorMessage, isNull);
    });

    test('returns controlled error for malformed XML', () {
      const malformedXml = '<score-partwise><part-list></score-partwise>';

      final result = parser.parse(malformedXml);

      expect(result.success, isFalse);
      expect(result.document, isNull);
      expect(result.rootTagName, isNull);
      expect(result.errorMessage, startsWith('Malformed XML:'));
    });

    test('returns controlled error for blank input', () {
      final result = parser.parse('   \n\t');

      expect(result.success, isFalse);
      expect(result.document, isNull);
      expect(result.rootTagName, isNull);
      expect(result.errorMessage, 'XML input is empty.');
    });
  });
}