import 'package:xml/xml.dart';

import 'musicxml_validation_result.dart';

/// Performs structural validation to ensure an XML document is a supported MusicXML score.
class MusicXmlValidatorService {
  const MusicXmlValidatorService();

  static const Set<String> _supportedRootTags = {
    'score-partwise',
    'score-timewise',
  };

  MusicXmlValidationResult validate(XmlDocument document) {
    final rootTagName = document.rootElement.name.local;
    final errors = <String>[];
    final warnings = <String>[];

    if (!_supportedRootTags.contains(rootTagName)) {
      errors.add(
        'Unsupported MusicXML root element "$rootTagName". Expected score-partwise or score-timewise.',
      );
    }

    final parts = document.findAllElements('part').toList();
    if (parts.isEmpty) {
      errors.add('MusicXML score must contain at least one <part> element.');
    }

    final measures = document.findAllElements('measure').toList();
    if (measures.isEmpty) {
      errors.add('MusicXML score must contain at least one <measure> element.');
    }

    final partList = document.findAllElements('part-list').toList();
    if (partList.isEmpty) {
      errors.add('MusicXML score is missing required <part-list> metadata.');
    }

    if (rootTagName == 'score-timewise') {
      warnings.add(
        'score-timewise is accepted, but score-partwise is recommended for best compatibility.',
      );
    }

    if (parts.isNotEmpty && parts.first.getAttribute('id') == null) {
      warnings.add('First <part> element has no id attribute.');
    }

    return MusicXmlValidationResult(
      isValid: errors.isEmpty,
      validationErrors: errors,
      warnings: warnings,
    );
  }
}