import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xml/xml.dart';
import 'package:note_vision/features/editor/domain/editor_actions.dart';
import 'package:note_vision/features/editor/model/editor_state.dart';
import 'package:note_vision/features/musicXML/musicxml_preserving_exporter.dart';
import 'package:note_vision/features/musicXML/musicxml_score_converter.dart';

import '../../../support/editor_controls_harness.dart';

void main() {
  setUpAll(loadControlsFonts);

  testWidgets(
    'export explains unsupported edits and the project remains savable',
    (tester) async {
      final xml = File(
        'test/musicxml_testfiles/08_polyphonic_preservation.musicxml',
      ).readAsStringSync();
      final score = const MusicXmlScoreConverter().convert(
        XmlDocument.parse(xml),
      );
      final changed = EditorState(score: score).appendMeasureAtEnd().score;
      final (_, storage) = await pumpControls(
        tester,
        score: changed,
        size: const Size(390, 844),
        existingProject: true,
      );
      await tester.tap(find.byTooltip('More'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Export MusicXML…'));
      await tester.pumpAndSettle();
      expect(
        find.text(const MusicXmlPreservationException().message),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      expect(storage.saved, hasLength(1));
      final saved = storage.saved.single.decodeScore();
      expect(saved.musicXmlSource!.xml, score.musicXmlSource!.xml);
      expect([for (final p in saved.parts) p.staff], [1, 2]);
      expect(saved.parts.first.measures, hasLength(4));
    },
  );
}
