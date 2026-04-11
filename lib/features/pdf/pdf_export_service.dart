import 'dart:io';

import 'package:note_vision/core/models/score.dart';
import 'package:note_vision/features/pdf/pdf_score_renderer.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

/// Renders a [Score] to PDF and shares it via the system share sheet.
///
/// Generates the PDF in a background isolate (via [PdfScoreRenderer.render]),
/// writes the bytes to a temp file, opens the share sheet, then deletes the
/// temp file after the sheet is dismissed.
class PdfExportService {
  const PdfExportService();

  static const _renderer = PdfScoreRenderer();

  /// Generates the PDF and opens the system share sheet.
  ///
  /// Throws on render or I/O failure.
  Future<void> exportAndShare(Score score) async {
    final bytes = await _renderer.render(score);
    final dir = await getTemporaryDirectory();
    final fileName = _safeFileName(score.title);
    final file = File('${dir.path}/$fileName.pdf');
    await file.writeAsBytes(bytes, flush: true);

    try {
      await SharePlus.instance.share(
        ShareParams(
          files: [
            XFile(
              file.path,
              mimeType: 'application/pdf',
              name: '$fileName.pdf',
            ),
          ],
          subject: score.title.isEmpty ? 'Score' : score.title,
        ),
      );
    } finally {
      if (await file.exists()) await file.delete();
    }
  }

  String _safeFileName(String title) {
    final trimmed = title.trim();
    if (trimmed.isEmpty) return 'score';
    return trimmed.replaceAll(RegExp(r'[^\w\-]'), '_');
  }
}
