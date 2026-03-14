class ParsedMetadata {
  final String rootTag;
  final String? title;
  final String? composer;
  final int partCount;
  final int measureCount;
  final int noteCount;
  final List<String> validationErrors;
  final List<String> warnings;

  const ParsedMetadata({
    required this.rootTag,
    required this.title,
    required this.composer,
    required this.partCount,
    required this.measureCount,
    required this.noteCount,
    this.validationErrors = const [],
    this.warnings = const [],
  });
}