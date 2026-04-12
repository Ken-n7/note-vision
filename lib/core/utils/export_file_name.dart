/// Returns a filesystem-safe file name derived from [title].
/// Falls back to `'score'` when the title is blank.
String safeExportFileName(String title) {
  final trimmed = title.trim();
  if (trimmed.isEmpty) return 'score';
  return trimmed.replaceAll(RegExp(r'[^\w\-]'), '_');
}
