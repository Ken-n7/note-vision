import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/project.dart';
import '../../features/musicXML/musicxml_parser_service.dart';
import '../../features/musicXML/musicxml_score_converter.dart';
import 'project_storage_service.dart';

/// Seeds bundled MusicXML samples into the project collection in debug builds.
///
/// Bump [_seedVersion] whenever new sample files are added so devices that
/// already ran a previous seed pick up the new ones.
class SampleSeeder {
  static const _seedVersion = 1;
  static const _prefKey = 'samples_seeded_v$_seedVersion';

  static const _assets = [
    'assets/samples/01_treble_clef.xml',
    'assets/samples/02_bass_clef.xml',
    'assets/samples/03_alto_clef.xml',
    'assets/samples/04_tenor_clef.xml',
    'assets/samples/05_dotted_notes.xml',
    'assets/samples/06_chords.xml',
    'assets/samples/07_beamed_eighths.xml',
    'assets/samples/08_key_signatures.xml',
    'assets/samples/09_repeat_barlines.xml',
    'assets/samples/10_alto_clef_key_sig.xml',
  ];

  static const _parser = MusicXmlParserService();
  static const _converter = MusicXmlScoreConverter();

  static Future<void> seedIfNeeded(ProjectStorageService storage) async {
    if (!kDebugMode) return;

    final prefs = await SharedPreferences.getInstance();
    if (prefs.getBool(_prefKey) == true) return;

    for (final assetPath in _assets) {
      try {
        final xml = await rootBundle.loadString(assetPath);
        final parseResult = _parser.parse(xml);
        if (parseResult.document == null || !parseResult.success) continue;

        final score = _converter.convert(parseResult.document!);
        final fileName = assetPath.split('/').last.replaceAll('.xml', '');

        final project = Project(
          id: 'sample_$fileName',
          name: '[Sample] ${score.title}',
          createdAt: DateTime(2024),
          updatedAt: DateTime(2024),
          scoreJson: jsonEncode(score.toJson()),
        );
        await storage.saveProject(project);
      } catch (_) {
        // Skip any sample that fails to parse
      }
    }

    await prefs.setBool(_prefKey, true);
  }
}
