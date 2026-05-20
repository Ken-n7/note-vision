import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:note_vision/core/models/key_signature.dart';
import 'package:note_vision/core/models/measure.dart';
import 'package:note_vision/core/models/note.dart';
import 'package:note_vision/core/models/part.dart';
import 'package:note_vision/core/models/project.dart';
import 'package:note_vision/core/models/score.dart';
import 'package:note_vision/core/models/time_signature.dart';
import 'package:note_vision/core/services/project_storage_service.dart';
import 'package:note_vision/features/collection/presentation/collection_screen.dart';
import 'package:note_vision/features/collection/presentation/widgets/empty_collection.dart';
import 'package:note_vision/features/editor/presentation/editor_shell_screen.dart';

// ── Fake service ──────────────────────────────────────────────────────────────

class FakeProjectStorageService extends ProjectStorageService {
  FakeProjectStorageService(this._future);

  final Future<List<Project>> _future;
  final deletedIds = <String>[];
  final savedProjects = <Project>[];

  @override
  Future<List<Project>> loadAllProjects() => _future;

  @override
  Future<void> saveProject(Project project) async {
    savedProjects.add(project);
  }

  @override
  Future<void> deleteProject(String id) async {
    deletedIds.add(id);
  }
}

// ── Minimal valid scoreJson ───────────────────────────────────────────────────

final _simpleMelodyScoreJson = jsonEncode(
  Score(
    id: 'test',
    title: 'Test',
    composer: '',
    parts: [
      Part(
        id: 'P1',
        name: 'Part 1',
        measures: const [
          Measure(
            number: 1,
            timeSignature: TimeSignature(beats: 4, beatType: 4),
            keySignature: KeySignature(fifths: 0),
            symbols: [
              Note(step: 'C', octave: 4, duration: 1, type: 'quarter'),
              Note(step: 'D', octave: 4, duration: 1, type: 'quarter'),
            ],
          ),
        ],
      ),
    ],
  ).toJson(),
);

Project _makeProject(String name, {String id = '1'}) => Project(
  id: id,
  name: name,
  createdAt: DateTime(2026, 1, 1),
  updatedAt: DateTime(2026, 3, 20),
  scoreJson: _simpleMelodyScoreJson,
);

// ── Tests ─────────────────────────────────────────────────────────────────────

void main() {
  Widget makeTestableWidget(Widget child) => MaterialApp(home: child);

  Future<void> pumpLoadedState(WidgetTester tester) async {
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
  }

  group('CollectionScreen', () {
    testWidgets('shows loading indicator first', (WidgetTester tester) async {
      final completer = Completer<List<Project>>();
      final service = FakeProjectStorageService(completer.future);

      await tester.pumpWidget(
        makeTestableWidget(CollectionScreen(storageService: service)),
      );

      expect(find.byType(CircularProgressIndicator), findsOneWidget);

      completer.complete([]);
      await pumpLoadedState(tester);
    });

    testWidgets('shows empty state when there are no saved projects', (
      WidgetTester tester,
    ) async {
      final service = FakeProjectStorageService(Future.value([]));

      await tester.pumpWidget(
        makeTestableWidget(CollectionScreen(storageService: service)),
      );

      await pumpLoadedState(tester);

      expect(find.byType(EmptyCollection), findsOneWidget);
      expect(find.text('Your collection\nis empty'), findsOneWidget);
      expect(find.byKey(const ValueKey('scanImageButton')), findsOneWidget);
      expect(
        find.byKey(const ValueKey('importMusicXmlButton')),
        findsOneWidget,
      );
      expect(find.byKey(const ValueKey('newScoreButton')), findsOneWidget);
    });

    testWidgets('shows project tiles when saved projects exist', (
      WidgetTester tester,
    ) async {
      final service = FakeProjectStorageService(
        Future.value([
          _makeProject('Symphony No. 1', id: '1'),
          _makeProject('Moonlight Sonata', id: '2'),
        ]),
      );

      await tester.pumpWidget(
        makeTestableWidget(CollectionScreen(storageService: service)),
      );

      await pumpLoadedState(tester);

      expect(find.text('Symphony No. 1'), findsOneWidget);
      expect(find.text('Moonlight Sonata'), findsOneWidget);
      expect(find.text('Simple Melody'), findsNWidgets(2));
      expect(find.text('2 projects'), findsOneWidget);
    });

    testWidgets('shows app bar content and FAB', (WidgetTester tester) async {
      final service = FakeProjectStorageService(Future.value([]));

      await tester.pumpWidget(
        makeTestableWidget(CollectionScreen(storageService: service)),
      );

      await pumpLoadedState(tester);

      expect(find.byType(AppBar), findsOneWidget);
      expect(find.text('Note Vision'), findsOneWidget);
      expect(find.text('MY COLLECTION'), findsOneWidget);
      expect(find.byType(FloatingActionButton), findsAtLeastNWidgets(1));
    });

    testWidgets('keeps speed dial actions out of the closed layout', (
      WidgetTester tester,
    ) async {
      final service = FakeProjectStorageService(
        Future.value([_makeProject('Existing Score', id: 'speed-dial')]),
      );

      await tester.pumpWidget(
        makeTestableWidget(CollectionScreen(storageService: service)),
      );

      await pumpLoadedState(tester);

      expect(find.byType(FloatingActionButton), findsOneWidget);
      expect(find.text('New Score'), findsNothing);
      expect(find.text('Import MusicXML'), findsNothing);
      expect(find.text('Scan Image'), findsNothing);

      await tester.tap(find.byType(FloatingActionButton));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 220));

      expect(find.text('New Score'), findsOneWidget);
      expect(find.text('Import MusicXML'), findsOneWidget);
      expect(find.text('Scan Image'), findsOneWidget);
      expect(find.text('Import Feedback'), findsNothing);
      expect(find.text('Import Score'), findsNothing);
      expect(find.text('Export All'), findsNothing);
      expect(find.byType(FloatingActionButton), findsNWidgets(4));
    });

    testWidgets('opens editor route when project tile is tapped', (
      WidgetTester tester,
    ) async {
      final service = FakeProjectStorageService(
        Future.value([_makeProject('Test Score', id: '1')]),
      );

      await tester.pumpWidget(
        MaterialApp(
          onGenerateRoute: (settings) {
            if (settings.name == EditorShellScreen.routeName) {
              return MaterialPageRoute<void>(
                builder: (_) =>
                    const Scaffold(body: Text('Editor Route Opened')),
              );
            }
            return MaterialPageRoute<void>(
              builder: (_) => CollectionScreen(storageService: service),
            );
          },
        ),
      );

      await pumpLoadedState(tester);
      await tester.tap(find.text('Test Score'));
      await tester.pumpAndSettle();

      expect(find.text('Editor Route Opened'), findsOneWidget);
    });

    testWidgets('shows visible project actions menu', (
      WidgetTester tester,
    ) async {
      final service = FakeProjectStorageService(
        Future.value([_makeProject('Action Score', id: 'actions')]),
      );

      await tester.pumpWidget(
        makeTestableWidget(CollectionScreen(storageService: service)),
      );

      await pumpLoadedState(tester);

      await tester.tap(find.byTooltip('Project actions'));
      await tester.pumpAndSettle();

      expect(find.text('Rename'), findsOneWidget);
      expect(find.text('Export'), findsOneWidget);
      expect(find.text('Delete'), findsOneWidget);
    });

    testWidgets('renames a project from the actions menu', (
      WidgetTester tester,
    ) async {
      final service = FakeProjectStorageService(
        Future.value([_makeProject('Old Score', id: 'rename')]),
      );

      await tester.pumpWidget(
        makeTestableWidget(CollectionScreen(storageService: service)),
      );

      await pumpLoadedState(tester);
      await tester.tap(find.byTooltip('Project actions'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Rename'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'New Score');
      await tester.tap(find.text('Rename').last);
      await tester.pumpAndSettle();

      expect(service.savedProjects.single.name, 'New Score');
      expect(find.text('New Score'), findsOneWidget);
      expect(find.text('Old Score'), findsNothing);
    });
  });
}
