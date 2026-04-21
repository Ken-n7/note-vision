import 'package:flutter/material.dart';
import 'package:xml/xml.dart';
import 'package:note_vision/core/models/score.dart';
import 'package:note_vision/features/musicXML/musicxml_import_exception.dart';
import 'package:note_vision/features/musicXML/musicxml_import_result.dart';
import 'package:note_vision/features/musicXML/musicxml_importer.dart';
import 'package:note_vision/features/musicXML/musicxml_parse_result.dart';
import 'package:note_vision/features/musicXML/musicxml_score_converter.dart';

import '../model/inspector_state.dart';
import '../model/parsed_metadata.dart';

class MusicXmlInspectorController extends ChangeNotifier {
  MusicXmlInspectorController({
    MusicXmlImporter? importer,
    MusicXmlScoreConverter? converter,
  })  : _importer = importer ?? MusicXmlImporter(),
        _converter = converter ?? const MusicXmlScoreConverter();

  final MusicXmlImporter _importer;
  final MusicXmlScoreConverter _converter;

  InspectorState state = InspectorState.empty();
  bool isLoading = false;

  Future<void> onImportPressed() async {
    isLoading = true;
    notifyListeners();

    try {
      // MusicXmlImporter handles file picking, .mxl decompression, encoding
      // fallback, and runs MusicXmlParserService → MusicXmlValidatorService.
      final MusicXmlImportResult? result = await _importer.pickAndRead();

      // User cancelled — leave existing state untouched.
      if (result == null) {
        isLoading = false;
        notifyListeners();
        return;
      }

      final parseResult = result.parseResult;

      // ── Case 1: XML could not be parsed at all ──────────────────────────
      if (parseResult.document == null) {
        state = InspectorState.parseError(
          fileName: result.fileName,
          errorMessage: parseResult.errorMessage ?? 'Unknown parse error.',
        );
        isLoading = false;
        notifyListeners();
        return;
      }

      // ── Extract metadata from the parsed document ───────────────────────
      final metadata = _extractMetadata(parseResult);

      // ── Case 2: Parsed but validation failed ────────────────────────────
      if (!parseResult.success) {
        state = InspectorState.validationError(
          fileName: result.fileName,
          metadata: metadata,
          rawXml: result.xmlContent,
          errorMessage: parseResult.errorMessage ??
              parseResult.validationErrors.join('\n'),
        );
        isLoading = false;
        notifyListeners();
        return;
      }

      // ── Case 3: Fully valid — convert to Score domain model ─────────────
      Score? score;
      try {
        score = _converter.convert(parseResult.document!);
      } catch (_) {
        // Conversion failure is non-fatal; show whatever metadata we have.
      }

      state = InspectorState.success(
        fileName: result.fileName,
        metadata: metadata,
        rawXml: result.xmlContent,
        score: score,
      );
    } on MusicXmlImportException catch (e) {
      state = InspectorState.parseError(
        fileName: state.fileName ?? 'unknown',
        errorMessage: e.message,
      );
    } catch (e) {
      state = InspectorState.parseError(
        fileName: state.fileName ?? 'unknown',
        errorMessage: e.toString(),
      );
    }

    isLoading = false;
    notifyListeners();
  }

  // ── Helpers ───────────────────────────────────────────────────────────────

  /// Extracts display metadata from a [MusicXmlParseResult] whose document
  /// is non-null. Works for both success and validation-failure states.
  ParsedMetadata _extractMetadata(MusicXmlParseResult parseResult) {
    final doc = parseResult.document!;
    final root = doc.rootElement;

    final rootTag = '<${root.name.local}>';

    final workTitle =
        root.findAllElements('work-title').firstOrNull?.innerText.trim();
    final movementTitle =
        root.findAllElements('movement-title').firstOrNull?.innerText.trim();
    final title = (workTitle?.isNotEmpty == true)
        ? workTitle
        : (movementTitle?.isNotEmpty == true)
            ? movementTitle
            : null;

    final composer = root
        .findAllElements('creator')
        .where((e) => e.getAttribute('type') == 'composer')
        .firstOrNull
        ?.innerText
        .trim();

    final partCount = root.findAllElements('part').length;
    final measureCount = root.findAllElements('measure').length;

    // In MusicXML, rests are <note> elements that contain a <rest> child.
    final allNoteElements = root.findAllElements('note').toList();
    final restCount = allNoteElements
        .where((n) => n.findElements('rest').isNotEmpty)
        .length;
    final noteCount = allNoteElements.length - restCount;

    return ParsedMetadata(
      rootTag: rootTag,
      title: (title?.isEmpty == true) ? null : title,
      composer: (composer?.isEmpty == true) ? null : composer,
      partCount: partCount,
      measureCount: measureCount,
      noteCount: noteCount,
      restCount: restCount,
      validationErrors: parseResult.validationErrors,
      warnings: parseResult.warnings,
    );
  }

}