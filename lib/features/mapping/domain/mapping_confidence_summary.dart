class MappingConfidenceSummary {
  final int inputSymbolCount;
  final int mappedSymbolCount;
  final int droppedSymbolCount;
  final double? averageDetectionConfidence;

  const MappingConfidenceSummary({
    required this.inputSymbolCount,
    required this.mappedSymbolCount,
    required this.droppedSymbolCount,
    this.averageDetectionConfidence,
  });
}
