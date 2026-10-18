import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:note_vision/core/models/measure.dart';
import 'package:note_vision/core/models/note.dart';
import 'package:note_vision/core/models/part.dart';
import 'package:note_vision/core/models/score.dart';
import 'package:note_vision/core/models/score_review.dart';
import 'package:note_vision/core/services/score_source_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const score = Score(
    id: 'scan',
    title: '',
    composer: '',
    parts: [
      Part(
        id: 'p',
        name: 'Staff',
        measures: [
          Measure(
            number: 1,
            symbols: [
              Note(
                step: 'C',
                octave: 4,
                duration: 2,
                type: 'quarter',
                reviewId: 'detection-1',
                source: SourceRegion(
                  pageId: '',
                  x: 20,
                  y: 30,
                  width: 10,
                  height: 20,
                ),
              ),
            ],
          ),
        ],
      ),
    ],
  );

  test(
    'scan evidence is portable and coordinates match the saved page',
    () async {
      final image = img.Image(width: 200, height: 100);
      final attached = await ScoreSourceService.attach(
        score,
        Uint8List.fromList(img.encodePng(image)),
        width: 200,
        height: 100,
      );
      final page = attached.sourcePages.single;
      expect(img.decodeImage(base64Decode(page.imageBase64)), isNotNull);
      final note = attached.getSymbolAt(0, 0, 0) as Note;
      expect(note.source?.pageId, page.id);
      expect(note.source?.x, .1);
      expect(note.source?.y, .3);
      expect(note.source?.width, .05);
      expect(note.source?.height, .2);
      expect(note.reviewId, '${page.id}:detection-1');
      expect(attached.parts.single.measures.single.source?.pageId, page.id);
    },
  );

  test(
    'unreadable optional evidence never prevents editing a mapped score',
    () async {
      final attached = await ScoreSourceService.attach(
        score,
        Uint8List.fromList([1, 2, 3]),
        width: 200,
        height: 100,
      );
      expect(attached.sourcePages, isEmpty);
      expect((attached.getSymbolAt(0, 0, 0) as Note).pitch, 'C4');
    },
  );
}
