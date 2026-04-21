import 'dart:convert';
import 'dart:io';

import 'package:archive/archive_io.dart';
import 'package:file_picker/file_picker.dart';

import 'musicxml_import_exception.dart';
import 'musicxml_import_result.dart';
import 'musicxml_parser_service.dart';

/// Service responsible for picking and reading a MusicXML file.
class MusicXmlImporter {
  MusicXmlImporter({FilePicker? filePicker, MusicXmlParserService? parser})
    : _filePicker = filePicker ?? FilePicker.platform,
      _parser = parser ?? const MusicXmlParserService();

  final FilePicker _filePicker;
  final MusicXmlParserService _parser;
  static const _allowedExtensions = ['xml', 'mxl'];

  /// Opens the file picker and returns a [MusicXmlImportResult].
  ///
  /// Returns `null` if the user cancels the picker.
  /// Throws [MusicXmlImportException] if the file cannot be read.
  Future<MusicXmlImportResult?> pickAndRead() async {
    // First attempt: restricted to known extensions
    FilePickerResult? result = await _filePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: _allowedExtensions,
      allowMultiple: false,
      withData: false,
    );

    // Fallback: Android may not recognize .musicxml MIME type,
    // so we open with no filter and validate the extension manually.
    result ??= await _filePicker.pickFiles(
      type: FileType.any,
      allowMultiple: false,
      withData: false,
    );

    // User cancelled — return null, do not throw.
    if (result == null || result.files.isEmpty) return null;

    final PlatformFile pickedFile = result.files.single;
    final String? path = pickedFile.path;

    if (path == null) {
      throw const MusicXmlImportException(
        'Could not resolve file path. The file may be unavailable.',
      );
    }

    final String fileName = pickedFile.name;

    // Validate extension manually (needed when fallback picker was used)
    final String ext = fileName.split('.').last.toLowerCase();
    if (!_allowedExtensions.contains(ext)) {
      throw MusicXmlImportException(
        'Unsupported file type ".$ext". Please select a .xml or .mxl file.',
      );
    }

    try {
      final String content = await _readFileContent(path, fileName);

      if (content.trim().isEmpty) {
        throw const MusicXmlImportException('The selected file is empty.');
      }

      return MusicXmlImportResult(
        fileName: fileName,
        xmlContent: content,
        parseResult: _parser.parse(content),
      );
    } on MusicXmlImportException {
      rethrow;
    } catch (e) {
      throw MusicXmlImportException(
        'Failed to read "$fileName": ${e.toString()}',
      );
    }
  }

  /// Reads file content as a string, handling .mxl archives and encoding fallback.
  Future<String> _readFileContent(String path, String fileName) async {
    // Handle .mxl compressed MusicXML archives
    if (fileName.toLowerCase().endsWith('.mxl')) {
      return _readMxlFile(path);
    }

    // UTF-8 with Latin-1 fallback for non-standard encodings
    try {
      return await File(path).readAsString(encoding: utf8);
    } catch (_) {
      return await File(path).readAsString(encoding: latin1);
    }
  }

  /// Decompresses an .mxl file and extracts the XML content inside.
  Future<String> _readMxlFile(String path) async {
    final bytes = await File(path).readAsBytes();
    final archive = ZipDecoder().decodeBytes(bytes);

    for (final file in archive) {
      // Skip directories and Mac metadata files
      if (!file.isFile) continue;
      if (file.name.startsWith('__MACOSX')) continue;

      if (file.name.endsWith('.xml')) {
        final content = file.content as List<int>;
        try {
          return utf8.decode(content);
        } catch (_) {
          return latin1.decode(content);
        }
      }
    }

    throw const MusicXmlImportException(
      'No XML content found inside the .mxl file.',
    );
  }
}
