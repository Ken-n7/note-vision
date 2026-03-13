import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:file_picker/file_picker.dart';
import 'package:mocktail/mocktail.dart';

import 'package:note_vision/features/musicXML/musicxml_import_exception.dart';
import 'package:note_vision/features/musicXML/musicxml_importer.dart';

// ─── Mocks ───────────────────────────────────────────────────────────────────

class MockFilePicker extends Mock implements FilePicker {}

// ─── Helpers ─────────────────────────────────────────────────────────────────

Future<String> _writeTempFile(String fileName, String content) async {
  final dir = Directory.systemTemp.createTempSync('musicxml_test_');
  final file = File('${dir.path}/$fileName');
  await file.writeAsString(content, encoding: utf8);
  return file.path;
}

List<int> _buildMxlBytes(String xmlContent, {String entryName = 'score.xml'}) {
  final archive = Archive();
  final bytes = utf8.encode(xmlContent);
  archive.addFile(ArchiveFile(entryName, bytes.length, bytes));
  return ZipEncoder().encode(archive)!;
}

String get _validXml => '''<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE score-partwise PUBLIC
  "-//Recordare//DTD MusicXML 3.1 Partwise//EN"
  "http://www.musicxml.org/dtds/partwise.dtd">
<score-partwise version="3.1">
  <part-list>
    <score-part id="P1"><part-name>Music</part-name></score-part>
  </part-list>
  <part id="P1">
    <measure number="1"/>
  </part>
</score-partwise>''';

FilePickerResult _fakeResult(String filePath) {
  // Split on both separators to handle Windows paths correctly
  final name = filePath.split(RegExp(r'[/\\]')).last;
  return FilePickerResult([
    PlatformFile(path: filePath, name: name, size: 0),
  ]);
}

// ─── Tests ────────────────────────────────────────────────────────────────────

void main() {
  late MockFilePicker mockPicker;
  late MusicXmlImporter importer;

  // ✅ FIX: Register fallback values for all types used with any()
  setUpAll(() {
    registerFallbackValue(FileType.any);
    registerFallbackValue(<String>[]);
  });

  setUp(() {
    mockPicker = MockFilePicker();
    importer = MusicXmlImporter(filePicker: mockPicker);
  });

  // ── Helper: stub both picker calls ───────────────────────────────────────

  void stubPicker({
    FilePickerResult? first,
    FilePickerResult? second,
  }) {
    var callCount = 0;
    when(
      () => mockPicker.pickFiles(
        type: any(named: 'type'),
        allowedExtensions: any(named: 'allowedExtensions'),
        allowMultiple: any(named: 'allowMultiple'),
        withData: any(named: 'withData'),
      ),
    ).thenAnswer((_) async {
      callCount++;
      return callCount == 1 ? first : second;
    });
  }

  // ══════════════════════════════════════════════════════════════════════════
  // GROUP 1 — Happy paths
  // ══════════════════════════════════════════════════════════════════════════

  group('pickAndRead — happy paths', () {
    test('reads a valid .musicxml file via custom picker', () async {
      final path = await _writeTempFile('happy_birthday.musicxml', _validXml);
      stubPicker(first: _fakeResult(path));

      final result = await importer.pickAndRead();

      expect(result, isNotNull);
      expect(result!.fileName, 'happy_birthday.musicxml');
      expect(result.xmlContent, contains('<score-partwise'));
    });

    test('reads a valid .xml file via custom picker', () async {
      final path = await _writeTempFile('score.xml', _validXml);
      stubPicker(first: _fakeResult(path));

      final result = await importer.pickAndRead();

      expect(result, isNotNull);
      expect(result!.fileName, 'score.xml');
      expect(result.xmlContent, contains('<score-partwise'));
    });

    test('reads a valid .mxl compressed file', () async {
      final mxlBytes = _buildMxlBytes(_validXml);
      final dir = Directory.systemTemp.createTempSync('mxl_test_');
      final file = File('${dir.path}/score.mxl')
        ..writeAsBytesSync(mxlBytes);

      stubPicker(first: _fakeResult(file.path));

      final result = await importer.pickAndRead();

      expect(result, isNotNull);
      expect(result!.fileName, 'score.mxl');
      expect(result.xmlContent, contains('<score-partwise'));
    });

    test('falls back to FileType.any when custom picker returns null (Android .musicxml MIME issue)', () async {
      final path = await _writeTempFile('happy_birthday.musicxml', _validXml);
      stubPicker(first: null, second: _fakeResult(path));

      final result = await importer.pickAndRead();

      expect(result, isNotNull);
      expect(result!.fileName, 'happy_birthday.musicxml');
    });

    test('reads Latin-1 encoded file without throwing', () async {
      final latin1Content = latin1.encode(_validXml);
      final dir = Directory.systemTemp.createTempSync('latin1_test_');
      final file = File('${dir.path}/score.xml')
        ..writeAsBytesSync(latin1Content);

      stubPicker(first: _fakeResult(file.path));

      final result = await importer.pickAndRead();

      expect(result, isNotNull);
      expect(result!.xmlContent, isNotEmpty);
    });

    test('reads .mxl with .musicxml entry name inside archive', () async {
      final mxlBytes = _buildMxlBytes(_validXml, entryName: 'score.musicxml');
      final dir = Directory.systemTemp.createTempSync('mxl_entry_test_');
      final file = File('${dir.path}/piece.mxl')
        ..writeAsBytesSync(mxlBytes);

      stubPicker(first: _fakeResult(file.path));

      final result = await importer.pickAndRead();

      expect(result!.xmlContent, contains('<score-partwise'));
    });

    test('skips __MACOSX metadata entries in .mxl archive', () async {
      final archive = Archive();
      final junk = utf8.encode('<not-xml/>');
      archive.addFile(ArchiveFile('__MACOSX/._score.xml', junk.length, junk));
      final real = utf8.encode(_validXml);
      archive.addFile(ArchiveFile('score.xml', real.length, real));

      final mxlBytes = ZipEncoder().encode(archive)!;
      final dir = Directory.systemTemp.createTempSync('mac_meta_test_');
      final file = File('${dir.path}/piece.mxl')
        ..writeAsBytesSync(mxlBytes);

      stubPicker(first: _fakeResult(file.path));

      final result = await importer.pickAndRead();
      expect(result!.xmlContent, contains('<score-partwise'));
    });
  });

  // ══════════════════════════════════════════════════════════════════════════
  // GROUP 2 — Cancel flows
  // ══════════════════════════════════════════════════════════════════════════

  group('pickAndRead — cancel flow', () {
    test('returns null when user cancels both pickers', () async {
      stubPicker(first: null, second: null);

      final result = await importer.pickAndRead();

      expect(result, isNull);
    });

    test('does not throw when user cancels', () async {
      stubPicker(first: null, second: null);

      await expectLater(importer.pickAndRead(), completes);
    });
  });

  // ══════════════════════════════════════════════════════════════════════════
  // GROUP 3 — Error flows
  // ══════════════════════════════════════════════════════════════════════════

  group('pickAndRead — error flows', () {
    test('throws MusicXmlImportException for unsupported extension', () async {
      final path = await _writeTempFile('document.pdf', '<pdf/>');
      stubPicker(first: null, second: _fakeResult(path));

      await expectLater(
        importer.pickAndRead(),
        throwsA(
          isA<MusicXmlImportException>().having(
            (e) => e.message, 'message', contains('Unsupported file type'),
          ),
        ),
      );
    });

    test('throws MusicXmlImportException for empty file', () async {
      final path = await _writeTempFile('empty.musicxml', '');
      stubPicker(first: _fakeResult(path));

      await expectLater(
        importer.pickAndRead(),
        throwsA(
          isA<MusicXmlImportException>().having(
            (e) => e.message, 'message', contains('empty'),
          ),
        ),
      );
    });

    test('throws MusicXmlImportException for whitespace-only file', () async {
      final path = await _writeTempFile('blank.xml', '   \n\t  ');
      stubPicker(first: _fakeResult(path));

      await expectLater(
        importer.pickAndRead(),
        throwsA(isA<MusicXmlImportException>()),
      );
    });

    test('throws MusicXmlImportException when .mxl contains no XML entry', () async {
      final archive = Archive();
      final bytes = utf8.encode('some random data');
      archive.addFile(ArchiveFile('README.txt', bytes.length, bytes));
      final mxlBytes = ZipEncoder().encode(archive)!;

      final dir = Directory.systemTemp.createTempSync('bad_mxl_test_');
      final file = File('${dir.path}/bad.mxl')
        ..writeAsBytesSync(mxlBytes);

      stubPicker(first: _fakeResult(file.path));

      await expectLater(
        importer.pickAndRead(),
        throwsA(
          isA<MusicXmlImportException>().having(
            (e) => e.message, 'message', contains('No XML content found'),
          ),
        ),
      );
    });

    test('throws MusicXmlImportException when file path is null', () async {
      when(
        () => mockPicker.pickFiles(
          type: any(named: 'type'),
          allowedExtensions: any(named: 'allowedExtensions'),
          allowMultiple: any(named: 'allowMultiple'),
          withData: any(named: 'withData'),
        ),
      ).thenAnswer(
        (_) async => FilePickerResult([
          PlatformFile(path: null, name: 'score.musicxml', size: 0),
        ]),
      );

      await expectLater(
        importer.pickAndRead(),
        throwsA(
          isA<MusicXmlImportException>().having(
            (e) => e.message, 'message', contains('Could not resolve file path'),
          ),
        ),
      );
    });

    test('throws MusicXmlImportException for unreadable file', () async {
      when(
        () => mockPicker.pickFiles(
          type: any(named: 'type'),
          allowedExtensions: any(named: 'allowedExtensions'),
          allowMultiple: any(named: 'allowMultiple'),
          withData: any(named: 'withData'),
        ),
      ).thenAnswer(
        (_) async => FilePickerResult([
          PlatformFile(
            path: '/nonexistent/path/score.musicxml',
            name: 'score.musicxml',
            size: 0,
          ),
        ]),
      );

      await expectLater(
        importer.pickAndRead(),
        throwsA(isA<MusicXmlImportException>()),
      );
    });
  });
}