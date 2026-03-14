import 'package:note_vision/core/models/score.dart';

import 'parsed_metadata.dart';

enum ScreenState { empty, success, parseError, validationError }

class InspectorState {
  final ScreenState status;
  final String? fileName;
  final ParsedMetadata? metadata;
  final String? errorMessage;
  final String? rawXml;
  final Score? score;

  const InspectorState._({
    required this.status,
    this.fileName,
    this.metadata,
    this.errorMessage,
    this.rawXml,
    this.score,
  });

  factory InspectorState.empty() =>
      const InspectorState._(status: ScreenState.empty);

  factory InspectorState.success({
    required String fileName,
    required ParsedMetadata metadata,
    required String rawXml,
    Score? score,
  }) =>
      InspectorState._(
        status: ScreenState.success,
        fileName: fileName,
        metadata: metadata,
        rawXml: rawXml,
        score: score,
      );

  /// Parse failed before we could even read a root tag.
  factory InspectorState.parseError({
    required String fileName,
    required String errorMessage,
  }) =>
      InspectorState._(
        status: ScreenState.parseError,
        fileName: fileName,
        errorMessage: errorMessage,
      );

  /// XML parsed but failed MusicXML structural validation.
  factory InspectorState.validationError({
    required String fileName,
    required ParsedMetadata metadata,
    required String rawXml,
    required String errorMessage,
  }) =>
      InspectorState._(
        status: ScreenState.validationError,
        fileName: fileName,
        metadata: metadata,
        rawXml: rawXml,
        errorMessage: errorMessage,
      );
}