import 'package:flutter_test/flutter_test.dart';
import 'package:xml/xml.dart';

import 'package:note_vision/features/musicXML/musicxml_validator_service.dart';

void main() {
  const validator = MusicXmlValidatorService();

  group('MusicXmlValidatorService.validate', () {
    test('returns valid for minimal supported score-partwise', () {
      final doc = XmlDocument.parse('''
<score-partwise>
  <part-list>
    <score-part id="P1"><part-name>Piano</part-name></score-part>
  </part-list>
  <part id="P1"><measure number="1"/></part>
</score-partwise>
''');

      final result = validator.validate(doc);

      expect(result.isValid, isTrue);
      expect(result.validationErrors, isEmpty);
      expect(result.warnings, isEmpty);
    });

    test('returns validation errors when required elements are missing', () {
      final doc = XmlDocument.parse('<score-partwise></score-partwise>');

      final result = validator.validate(doc);

      expect(result.isValid, isFalse);
      expect(result.validationErrors.length, 3);
    });
  });
}
