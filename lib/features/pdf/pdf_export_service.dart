import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:note_vision/core/models/score.dart';
import 'package:note_vision/core/utils/export_file_name.dart';
import 'package:note_vision/features/pdf/pdf_score_renderer.dart';

/// Renders a [Score] to PDF and saves it to a user-chosen location via the
/// system file picker.
class PdfExportService {
  const PdfExportService();

  static const _renderer = PdfScoreRenderer();

  /// Generates the PDF and opens the OS save dialog so the user picks a
  /// location. Returns the saved file path, or `null` if cancelled.
  ///
  /// Throws on render failure.
  Future<String?> exportToDevice(Score score) async {
    final bytes = Uint8List.fromList(await _renderer.render(score));
    final fileName = safeExportFileName(score.title);

    return FilePicker.platform.saveFile(
      fileName: '$fileName.pdf',
      bytes: bytes,
      type: FileType.custom,
      allowedExtensions: ['pdf'],
    );
  }
}
