import 'package:xml/xml.dart';

/// Structured outcome of a MusicXML parsing attempt.
class MusicXmlParseResult {
  final bool success;
  final String? rootTagName;
  final XmlDocument? document;
  final String? errorMessage;
  final List<String> validationErrors;
  final List<String> warnings;

  const MusicXmlParseResult._({
    required this.success,
    this.rootTagName,
    this.document,
    this.errorMessage,
    this.validationErrors = const [],
    this.warnings = const [],
  });

  factory MusicXmlParseResult.success({
    required XmlDocument document,
    required String rootTagName,
    List<String> warnings = const [],
  }) {
    return MusicXmlParseResult._(
      success: true,
      document: document,
      rootTagName: rootTagName,
      warnings: warnings,
    );
  }

  factory MusicXmlParseResult.failure({
    required String errorMessage,
    String? rootTagName,
    XmlDocument? document,
    List<String> validationErrors = const [],
    List<String> warnings = const [],
  }) {
    return MusicXmlParseResult._(
      success: false,
      errorMessage: errorMessage,
      rootTagName: rootTagName,
      document: document,
      validationErrors: validationErrors,
      warnings: warnings,
    );
  }
}
