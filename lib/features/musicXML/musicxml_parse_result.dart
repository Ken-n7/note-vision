import 'package:xml/xml.dart';

/// Structured outcome of a MusicXML parsing attempt.
class MusicXmlParseResult {
  final bool success;
  final String? rootTagName;
  final XmlDocument? document;
  final String? errorMessage;

  const MusicXmlParseResult._({
    required this.success,
    this.rootTagName,
    this.document,
    this.errorMessage,
  });

  factory MusicXmlParseResult.success({
    required XmlDocument document,
    required String rootTagName,
  }) {
    return MusicXmlParseResult._(
      success: true,
      document: document,
      rootTagName: rootTagName,
    );
  }

  factory MusicXmlParseResult.failure({required String errorMessage}) {
    return MusicXmlParseResult._(success: false, errorMessage: errorMessage);
  }
}