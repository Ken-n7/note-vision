import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:note_vision/core/models/clef.dart';
import 'package:note_vision/core/models/key_signature.dart';
import 'package:note_vision/core/models/measure.dart';
import 'package:note_vision/core/models/note.dart';
import 'package:note_vision/core/models/part.dart';
import 'package:note_vision/core/models/project.dart';
import 'package:note_vision/core/models/rest.dart';
import 'package:note_vision/core/models/score.dart';
import 'package:note_vision/core/models/time_signature.dart';
import 'package:note_vision/core/services/project_storage_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

// ── helpers ──────────────────────────────────────────────────────────────────

Score _buildFullScore() => const Score(
  id: 'score-1',
  title: 'Test Sonata',
  composer: 'Tester',
  parts: [
    Part(
      id: 'p1',
      name: 'Treble',
      measures: [
        Measure(
          number: 1,
          clef: Clef(sign: 'G', line: 2),
          timeSignature: TimeSignature(beats: 4, beatType: 4),
          keySignature: KeySignature(fifths: 2),
          symbols: [
            Note(step: 'C', octave: 4, duration: 2, type: 'quarter'),
            Note(
              step: 'E',
              octave: 4,
              alter: 1,
              duration: 2,
              type: 'quarter',
              voice: 1,
              staff: 1,
            ),
            Rest(duration: 2, type: 'quarter'),
            Rest(duration: 1, type: 'eighth', voice: 1, staff: 1),
          ],
        ),
        Measure(
          number: 2,
          symbols: [
            Note(step: 'G', octave: 5, alter: -1, duration: 4, type: 'half'),
            Note(step: 'A', octave: 4, alter: -2, duration: 8, type: 'whole'),
          ],
        ),
      ],
    ),
    Part(
      id: 'p2',
      name: 'Bass',
      measures: [
        Measure(
          number: 1,
          clef: Clef(sign: 'F', line: 4),
          symbols: [Note(step: 'C', octave: 2, duration: 8, type: 'whole')],
        ),
      ],
    ),
  ],
);

// ── ScoreModel serialization round-trips ─────────────────────────────────────

void main() {
  group('Note toJson / fromJson', () {
    test('round-trips all fields', () {
      const note = Note(
        step: 'D',
        octave: 5,
        alter: -1,
        duration: 4,
        type: 'half',
        voice: 2,
        staff: 1,
      );
      final decoded = Note.fromJson(note.toJson());
      expect(decoded.step, note.step);
      expect(decoded.octave, note.octave);
      expect(decoded.alter, note.alter);
      expect(decoded.duration, note.duration);
      expect(decoded.type, note.type);
      expect(decoded.voice, note.voice);
      expect(decoded.staff, note.staff);
    });

    test('round-trips without optional fields', () {
      const note = Note(step: 'C', octave: 4, duration: 2, type: 'quarter');
      final decoded = Note.fromJson(note.toJson());
      expect(decoded.alter, isNull);
      expect(decoded.voice, isNull);
      expect(decoded.staff, isNull);
    });

    test('toJson includes symbolType discriminator', () {
      const note = Note(step: 'C', octave: 4, duration: 2, type: 'quarter');
      expect(note.toJson()['symbolType'], 'note');
    });

    test('round-trips all alter values', () {
      for (final alter in [-2, -1, 0, 1, 2]) {
        final note = Note(
          step: 'C',
          octave: 4,
          alter: alter,
          duration: 2,
          type: 'quarter',
        );
        expect(Note.fromJson(note.toJson()).alter, alter);
      }
    });
  });

  group('Rest toJson / fromJson', () {
    test('round-trips all fields', () {
      const rest = Rest(duration: 1, type: 'eighth', voice: 1, staff: 2);
      final decoded = Rest.fromJson(rest.toJson());
      expect(decoded.duration, rest.duration);
      expect(decoded.type, rest.type);
      expect(decoded.voice, rest.voice);
      expect(decoded.staff, rest.staff);
    });

    test('round-trips without optional fields', () {
      const rest = Rest(duration: 8, type: 'whole');
      final decoded = Rest.fromJson(rest.toJson());
      expect(decoded.voice, isNull);
      expect(decoded.staff, isNull);
    });

    test('toJson includes symbolType discriminator', () {
      expect(
        const Rest(duration: 2, type: 'quarter').toJson()['symbolType'],
        'rest',
      );
    });
  });

  group('Clef toJson / fromJson', () {
    test('round-trips treble clef', () {
      const clef = Clef(sign: 'G', line: 2);
      final decoded = Clef.fromJson(clef.toJson());
      expect(decoded.sign, 'G');
      expect(decoded.line, 2);
    });

    test('round-trips bass clef', () {
      const clef = Clef(sign: 'F', line: 4);
      final decoded = Clef.fromJson(clef.toJson());
      expect(decoded.sign, 'F');
      expect(decoded.line, 4);
    });

    test('toJson includes symbolType discriminator', () {
      expect(const Clef(sign: 'G', line: 2).toJson()['symbolType'], 'clef');
    });
  });

  group('KeySignature toJson / fromJson', () {
    test('round-trips positive fifths', () {
      const ks = KeySignature(fifths: 3);
      expect(KeySignature.fromJson(ks.toJson()).fifths, 3);
    });

    test('round-trips negative fifths', () {
      const ks = KeySignature(fifths: -4);
      expect(KeySignature.fromJson(ks.toJson()).fifths, -4);
    });

    test('round-trips zero fifths', () {
      const ks = KeySignature(fifths: 0);
      expect(KeySignature.fromJson(ks.toJson()).fifths, 0);
    });
  });

  group('TimeSignature toJson / fromJson', () {
    test('round-trips 4/4', () {
      const ts = TimeSignature(beats: 4, beatType: 4);
      final decoded = TimeSignature.fromJson(ts.toJson());
      expect(decoded.beats, 4);
      expect(decoded.beatType, 4);
    });

    test('round-trips 3/8', () {
      const ts = TimeSignature(beats: 3, beatType: 8);
      final decoded = TimeSignature.fromJson(ts.toJson());
      expect(decoded.beats, 3);
      expect(decoded.beatType, 8);
    });
  });

  group('Measure toJson / fromJson', () {
    test('round-trips measure with all metadata', () {
      const measure = Measure(
        number: 1,
        clef: Clef(sign: 'G', line: 2),
        timeSignature: TimeSignature(beats: 3, beatType: 4),
        keySignature: KeySignature(fifths: -1),
        symbols: [
          Note(step: 'C', octave: 4, duration: 2, type: 'quarter'),
          Rest(duration: 2, type: 'quarter'),
        ],
      );

      final decoded = Measure.fromJson(measure.toJson());

      expect(decoded.number, 1);
      expect(decoded.clef?.sign, 'G');
      expect(decoded.timeSignature?.beats, 3);
      expect(decoded.keySignature?.fifths, -1);
      expect(decoded.symbols.length, 2);
      expect(decoded.symbols[0], isA<Note>());
      expect(decoded.symbols[1], isA<Rest>());
    });

    test('round-trips measure with no metadata', () {
      const measure = Measure(
        number: 2,
        symbols: [Note(step: 'G', octave: 4, duration: 4, type: 'half')],
      );

      final decoded = Measure.fromJson(measure.toJson());

      expect(decoded.clef, isNull);
      expect(decoded.timeSignature, isNull);
      expect(decoded.keySignature, isNull);
      expect(decoded.symbols.length, 1);
    });

    test('round-trips Clef in symbols list', () {
      const measure = Measure(number: 1, symbols: [Clef(sign: 'F', line: 4)]);
      final decoded = Measure.fromJson(measure.toJson());
      expect(decoded.symbols.first, isA<Clef>());
      expect((decoded.symbols.first as Clef).sign, 'F');
    });

    test('throws FormatException for unknown symbolType', () {
      final bad = {
        'number': 1,
        'symbols': [
          {'symbolType': 'unknown_type'},
        ],
      };
      expect(() => Measure.fromJson(bad), throwsFormatException);
    });
  });

  group('Part toJson / fromJson', () {
    test('round-trips part with multiple measures', () {
      const part = Part(
        id: 'p1',
        name: 'Treble',
        measures: [
          Measure(number: 1, symbols: []),
          Measure(number: 2, symbols: []),
        ],
      );

      final decoded = Part.fromJson(part.toJson());

      expect(decoded.id, 'p1');
      expect(decoded.name, 'Treble');
      expect(decoded.measures.length, 2);
    });
  });

  group('Score toJson / fromJson', () {
    test('round-trips full multi-part score', () {
      final score = _buildFullScore();
      final decoded = Score.fromJson(score.toJson());

      expect(decoded.id, score.id);
      expect(decoded.title, score.title);
      expect(decoded.composer, score.composer);
      expect(decoded.parts.length, 2);

      final part0 = decoded.parts[0];
      expect(part0.id, 'p1');
      expect(part0.measures.length, 2);

      final m0 = part0.measures[0];
      expect(m0.clef?.sign, 'G');
      expect(m0.timeSignature?.beats, 4);
      expect(m0.keySignature?.fifths, 2);
      expect(m0.symbols.length, 4);

      final note = m0.symbols[0] as Note;
      expect(note.step, 'C');
      expect(note.octave, 4);
      expect(note.alter, isNull);

      final sharpNote = m0.symbols[1] as Note;
      expect(sharpNote.alter, 1);
      expect(sharpNote.voice, 1);
      expect(sharpNote.staff, 1);

      expect(m0.symbols[2], isA<Rest>());
      expect(m0.symbols[3], isA<Rest>());
      expect((m0.symbols[3] as Rest).type, 'eighth');

      final m1 = part0.measures[1];
      expect((m1.symbols[0] as Note).alter, -1);
      expect((m1.symbols[1] as Note).alter, -2);

      final part1 = decoded.parts[1];
      expect(part1.name, 'Bass');
      expect((part1.measures[0].clef)?.sign, 'F');
    });

    test('round-trips through JSON string (jsonEncode / jsonDecode)', () {
      final score = _buildFullScore();
      final json = jsonEncode(score.toJson());
      final decoded = Score.fromJson(jsonDecode(json) as Map<String, dynamic>);
      expect(decoded.id, score.id);
      expect(decoded.parts[0].measures[0].symbols.length, 4);
    });
  });

  // ── Project serialization ─────────────────────────────────────────────────

  group('Project toJson / fromJson', () {
    test('round-trips all fields', () {
      final createdAt = DateTime(2026, 4, 10, 12, 0, 0);
      final updatedAt = DateTime(2026, 4, 10, 15, 30, 0);
      final project = Project(
        id: '1712740800000',
        name: 'My Sonata',
        createdAt: createdAt,
        updatedAt: updatedAt,
        scoreJson: jsonEncode(_buildFullScore().toJson()),
      );

      final decoded = Project.fromJson(project.toJson());

      expect(decoded.id, project.id);
      expect(decoded.name, project.name);
      expect(decoded.createdAt, project.createdAt);
      expect(decoded.updatedAt, project.updatedAt);
      expect(decoded.scoreJson, project.scoreJson);
    });

    test('decodeScore returns identical Score', () {
      final score = _buildFullScore();
      final project = Project.create(name: 'Test', score: score);
      final decoded = project.decodeScore();

      expect(decoded.id, score.id);
      expect(decoded.title, score.title);
      expect(decoded.parts.length, score.parts.length);
      expect(
        decoded.parts[0].measures[0].symbols.length,
        score.parts[0].measures[0].symbols.length,
      );
    });

    test('Project.create sets createdAt == updatedAt', () {
      final project = Project.create(name: 'New', score: _buildFullScore());
      expect(project.createdAt, project.updatedAt);
    });

    test('copyWithUpdated refreshes updatedAt and preserves createdAt', () {
      final original = Project.create(
        name: 'Original',
        score: _buildFullScore(),
      );
      final updated = original.copyWithUpdated(name: 'Renamed');

      expect(updated.id, original.id);
      expect(updated.name, 'Renamed');
      expect(updated.createdAt, original.createdAt);
      expect(
        updated.updatedAt.isAfter(original.updatedAt) ||
            updated.updatedAt == original.updatedAt,
        isTrue,
      );
    });

    test('round-trips through jsonEncode / jsonDecode', () {
      final project = Project.create(name: 'Sonata', score: _buildFullScore());
      final raw = jsonEncode(project.toJson());
      final decoded = Project.fromJson(jsonDecode(raw) as Map<String, dynamic>);
      expect(decoded.id, project.id);
      expect(decoded.name, project.name);
      expect(decoded.decodeScore().title, project.decodeScore().title);
    });
  });

  // ── ProjectStorageService ─────────────────────────────────────────────────

  group('ProjectStorageService', () {
    late Directory tempDir;
    late ProjectStorageService service;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      tempDir = await Directory.systemTemp.createTemp('nv_project_test_');
      service = ProjectStorageService(projectsDirOverride: () async => tempDir);
    });

    tearDown(() async {
      if (await tempDir.exists()) await tempDir.delete(recursive: true);
    });

    test('saveProject writes file to correct path', () async {
      final project = Project.create(name: 'Test', score: _buildFullScore());
      await service.saveProject(project);

      final file = File('${tempDir.path}/${project.id}.json');
      expect(await file.exists(), isTrue);
    });

    test('loadProject returns null for unknown id', () async {
      expect(await service.loadProject('nonexistent'), isNull);
    });

    test('saveProject then loadProject round-trips correctly', () async {
      final original = Project.create(name: 'Loaded', score: _buildFullScore());
      await service.saveProject(original);

      final loaded = await service.loadProject(original.id);
      expect(loaded, isNotNull);
      expect(loaded!.id, original.id);
      expect(loaded.name, original.name);
      expect(loaded.decodeScore().title, original.decodeScore().title);
    });

    test(
      'loadAllProjects returns projects sorted by updatedAt descending',
      () async {
        final score = _buildFullScore();

        final older = Project(
          id: '1000',
          name: 'Older',
          createdAt: DateTime(2026, 1, 1),
          updatedAt: DateTime(2026, 1, 1),
          scoreJson: jsonEncode(score.toJson()),
        );
        final newer = Project(
          id: '2000',
          name: 'Newer',
          createdAt: DateTime(2026, 3, 1),
          updatedAt: DateTime(2026, 3, 1),
          scoreJson: jsonEncode(score.toJson()),
        );

        await service.saveProject(older);
        await service.saveProject(newer);

        final all = await service.loadAllProjects();
        expect(all.length, 2);
        expect(all[0].id, newer.id);
        expect(all[1].id, older.id);
      },
    );

    test('deleteProject removes file and entry from index', () async {
      final project = Project.create(
        name: 'ToDelete',
        score: _buildFullScore(),
      );
      await service.saveProject(project);

      await service.deleteProject(project.id);

      expect(await service.loadProject(project.id), isNull);
      final all = await service.loadAllProjects();
      expect(all.any((p) => p.id == project.id), isFalse);
    });

    test('saveProject updates name in index on re-save', () async {
      final project = Project.create(
        name: 'Original',
        score: _buildFullScore(),
      );
      await service.saveProject(project);

      final renamed = project.copyWithUpdated(name: 'Renamed');
      await service.saveProject(renamed);

      final all = await service.loadAllProjects();
      expect(all.length, 1);
      expect(all.first.name, 'Renamed');
    });

    test('deleteProject on nonexistent id does not throw', () async {
      expect(() => service.deleteProject('ghost'), returnsNormally);
    });
  });
}
