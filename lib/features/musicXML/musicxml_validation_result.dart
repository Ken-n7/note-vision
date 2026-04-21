class MusicXmlValidationResult {
  final bool isValid;
  final List<String> validationErrors;
  final List<String> warnings;

  const MusicXmlValidationResult({
    required this.isValid,
    this.validationErrors = const [],
    this.warnings = const [],
  });
}