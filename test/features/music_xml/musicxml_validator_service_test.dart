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

    test('returns validation error when part exists but is not declared', () {
      final doc = XmlDocument.parse('''
<score-partwise>
  <part-list>
    <score-part id="P1"><part-name>Piano</part-name></score-part>
  </part-list>
  <part id="P2"><measure number="1"/></part>
</score-partwise>
''');

      final result = validator.validate(doc);

      expect(result.isValid, isFalse);
      expect(
        result.validationErrors,
        contains('<part id="P2"> is not declared in <part-list>.'),
      );
    });

    test('allows repeated part ids in score-timewise across measures', () {
      final doc = XmlDocument.parse('''
<score-timewise>
  <part-list>
    <score-part id="P1"><part-name>Violin</part-name></score-part>
  </part-list>
  <measure number="1">
    <part id="P1"><note><rest/></note></part>
  </measure>
  <measure number="2">
    <part id="P1"><note><rest/></note></part>
  </measure>
</score-timewise>
''');

      final result = validator.validate(doc);

      expect(result.isValid, isTrue);
      expect(result.validationErrors, isEmpty);
    });

    test('returns validation error for duplicate part ids', () {
      final doc = XmlDocument.parse('''
<score-partwise>
  <part-list>
    <score-part id="P1"><part-name>Piano</part-name></score-part>
  </part-list>
  <part id="P1"><measure number="1"/></part>
  <part id="P1"><measure number="2"/></part>
</score-partwise>
''');

      final result = validator.validate(doc);

      expect(result.isValid, isFalse);
      expect(
        result.validationErrors,
        contains('Duplicate <part> id "P1" found in score.'),
      );
    });
  });
}
