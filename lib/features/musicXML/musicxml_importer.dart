import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive_io.dart';
import 'package:file_picker/file_picker.dart';
import 'package:xml/xml.dart';

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
  static const _allowedExtensions = ['xml', 'musicxml', 'mxl'];

  /// Opens the file picker and returns a [MusicXmlImportResult].
  ///
  /// Returns `null` if the user cancels the picker.
  /// Throws [MusicXmlImportException] if the file cannot be read.
  Future<MusicXmlImportResult?> pickAndRead() async {
    // One picker showing every file: filtered by extension, Android greys
    // out .musicxml and .mxl (no MIME type for them) and some pickers show
    // an empty list. The extension is checked below instead.
    final result = await _filePicker.pickFiles(
      type: FileType.any,
      allowMultiple: false,
      withData: false,
    );

    // User cancelled — return null, do not throw.
    if (result == null || result.files.isEmpty) return null;

    final PlatformFile pickedFile = result.files.single;
    final String fileName = pickedFile.name;

    final String ext = fileName.contains('.')
        ? fileName.split('.').last.toLowerCase()
        : '';
    if (!_allowedExtensions.contains(ext)) {
      throw MusicXmlImportException(
        'Unsupported file type .$ext. Please select a .xml, .musicxml, or .mxl file.',
      );
    }

    final String? path = pickedFile.path;
    if (path == null) {
      throw const MusicXmlImportException(
        'Could not resolve file path. The file may be unavailable.',
      );
    }

    try {
      final bytes = await File(path).readAsBytes();
      final String content = ext == 'mxl'
          ? _readMxl(bytes)
          : decodeXmlText(bytes);

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

  /// XML text from [bytes]: UTF-16 when the file starts with a UTF-16 byte
  /// order mark (some notation programs save MusicXML that way), else UTF-8
  /// without its byte order mark, else Latin-1.
  static String decodeXmlText(List<int> bytes) {
    if (bytes.length >= 2 &&
        ((bytes[0] == 0xFF && bytes[1] == 0xFE) ||
            (bytes[0] == 0xFE && bytes[1] == 0xFF))) {
      final littleEndian = bytes[0] == 0xFF;
      final units = <int>[
        for (var i = 2; i + 1 < bytes.length; i += 2)
          littleEndian
              ? bytes[i] | (bytes[i + 1] << 8)
              : (bytes[i] << 8) | bytes[i + 1],
      ];
      return String.fromCharCodes(units);
    }
    final start =
        bytes.length >= 3 &&
            bytes[0] == 0xEF &&
            bytes[1] == 0xBB &&
            bytes[2] == 0xBF
        ? 3
        : 0;
    final body = bytes.sublist(start);
    try {
      return utf8.decode(body);
    } on FormatException {
      return latin1.decode(body);
    }
  }

  /// The score inside an .mxl archive: the file META-INF/container.xml
  /// names as its root, else the first other .xml or .musicxml entry.
  String _readMxl(Uint8List bytes) {
    final archive = ZipDecoder().decodeBytes(bytes);
    ArchiveFile? entry(String name) {
      for (final file in archive.files) {
        if (file.isFile && file.name == name) return file;
      }
      return null;
    }

    String? rootPath;
    final container = entry('META-INF/container.xml');
    if (container != null) {
      try {
        final doc = XmlDocument.parse(
          decodeXmlText(container.content as List<int>),
        );
        rootPath = doc
            .findAllElements('rootfile')
            .firstOrNull
            ?.getAttribute('full-path');
      } on XmlException {
        rootPath = null;
      }
    }

    var score = rootPath == null ? null : entry(rootPath);
    if (score == null) {
      for (final file in archive.files) {
        final name = file.name.toLowerCase();
        if (!file.isFile ||
            name.startsWith('meta-inf/') ||
            name.startsWith('__macosx')) {
          continue;
        }
        if (name.endsWith('.xml') || name.endsWith('.musicxml')) {
          score = file;
          break;
        }
      }
    }
    if (score == null) {
      throw const MusicXmlImportException(
        'No XML content found inside the .mxl file.',
      );
    }
    return decodeXmlText(score.content as List<int>);
  }
}
