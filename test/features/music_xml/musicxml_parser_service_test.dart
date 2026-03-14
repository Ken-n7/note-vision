import 'package:flutter_test/flutter_test.dart';

import 'package:note_vision/features/musicXML/musicxml_parser_service.dart';

void main() {
  const parser = MusicXmlParserService();

  group('MusicXmlParserService.parse', () {
    test('returns success for valid score-partwise MusicXML', () {
      const xml = '''<?xml version="1.0" encoding="UTF-8"?>
<score-partwise version="3.1">
  <part-list>
    <score-part id="P1"><part-name>Piano</part-name></score-part>
  </part-list>
  <part id="P1">
    <measure number="1"/>
  </part>
</score-partwise>''';

      final result = parser.parse(xml);

      expect(result.success, isTrue);
      expect(result.document, isNotNull);
      expect(result.rootTagName, 'score-partwise');
      expect(result.errorMessage, isNull);
      expect(result.validationErrors, isEmpty);
      expect(result.warnings, isEmpty);
    });

    test('fails with readable message for non-MusicXML XML', () {
      const xml = '<catalog><book id="1"/></catalog>';

      final result = parser.parse(xml);

      expect(result.success, isFalse);
      expect(result.rootTagName, 'catalog');
      expect(result.errorMessage, startsWith('Invalid MusicXML score:'));
      expect(
        result.validationErrors,
        contains(
          'Unsupported MusicXML root element "catalog". Expected score-partwise or score-timewise.',
        ),
      );
    });

    test('fails gracefully when score is missing parts and measures', () {
      const xml = '''<score-partwise>
  <part-list>
    <score-part id="P1"><part-name>Piano</part-name></score-part>
  </part-list>
</score-partwise>''';

      final result = parser.parse(xml);

      expect(result.success, isFalse);
      expect(
        result.validationErrors,
        contains('MusicXML score must contain at least one <part> element.'),
      );
      expect(
        result.validationErrors,
        contains('MusicXML score must contain at least one <measure> element.'),
      );
    });

    test('returns warnings for supported equivalent score-timewise root', () {
      const xml = '''<score-timewise>
  <part-list>
    <score-part id="P1"><part-name>Piano</part-name></score-part>
  </part-list>
  <measure number="1">
    <part id="P1"/>
  </measure>
</score-timewise>''';

      final result = parser.parse(xml);

      expect(result.success, isTrue);
      expect(
        result.warnings,
        contains(
          'score-timewise is accepted, but score-partwise is recommended for best compatibility.',
        ),
      );
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
