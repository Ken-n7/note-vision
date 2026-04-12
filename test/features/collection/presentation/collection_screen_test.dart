import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:note_vision/core/models/project.dart';
import 'package:note_vision/core/services/project_storage_service.dart';
import 'package:note_vision/features/collection/presentation/collection_screen.dart';
import 'package:note_vision/features/collection/presentation/widgets/empty_collection.dart';
import 'package:note_vision/features/editor/presentation/editor_shell_screen.dart';

// ── Fake service ──────────────────────────────────────────────────────────────

class FakeProjectStorageService extends ProjectStorageService {
  FakeProjectStorageService(this._future);

  final Future<List<Project>> _future;

  @override
  Future<List<Project>> loadAllProjects() => _future;

  @override
  Future<void> deleteProject(String id) async {}
}

// ── Minimal valid scoreJson ───────────────────────────────────────────────────

const _minimalScoreJson =
    '{"id":"test","title":"Test","composer":"","parts":[{"id":"P1","name":"Part 1","measures":[{"number":1,"clef":null,"timeSignature":null,"keySignature":null,"symbols":[]}]}]}';

Project _makeProject(String name, {String id = '1'}) => Project(
      id: id,
      name: name,
      createdAt: DateTime(2026, 1, 1),
      updatedAt: DateTime(2026, 3, 20),
      scoreJson: _minimalScoreJson,
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
      expect(find.byKey(const ValueKey('addImageButton')), findsOneWidget);
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
      expect(find.text('2 projects'), findsOneWidget);
    });

    testWidgets('shows app bar content and bottom navigation labels', (
      WidgetTester tester,
    ) async {
      final service = FakeProjectStorageService(Future.value([]));

      await tester.pumpWidget(
        makeTestableWidget(CollectionScreen(storageService: service)),
      );

      await pumpLoadedState(tester);

      expect(find.byType(AppBar), findsOneWidget);
      expect(find.text('Note Vision'), findsOneWidget);
      expect(find.text('MY COLLECTION'), findsOneWidget);
      expect(find.text('Add Files'), findsOneWidget);
      expect(find.text('Info'), findsOneWidget);
      expect(find.text('Edit'), findsOneWidget);
      expect(find.text('Result'), findsOneWidget);
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
                builder: (_) => const Scaffold(body: Text('Editor Route Opened')),
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
  });
}
