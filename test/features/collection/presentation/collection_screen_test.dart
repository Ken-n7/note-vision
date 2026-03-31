import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:note_vision/core/services/image_storage_service.dart';
import 'package:note_vision/features/collection/presentation/collection_screen.dart';
import 'package:note_vision/features/collection/presentation/widgets/empty_collection.dart';
import 'package:note_vision/features/collection/presentation/widgets/score_card.dart';
import 'package:note_vision/features/editor/presentation/editor_shell_screen.dart';

class FakeImageStorageService extends ImageStorageService {
  FakeImageStorageService(this.paths);

  final Future<List<String>> paths;

  @override
  Future<List<String>> getSavedImages() => paths;
}

void main() {
  Widget makeTestableWidget(Widget child) {
    return MaterialApp(home: child);
  }

  Future<void> pumpLoadedState(WidgetTester tester) async {
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
  }

  group('CollectionScreen', () {
    testWidgets('shows loading indicator first', (WidgetTester tester) async {
      final completer = Completer<List<String>>();
      final service = FakeImageStorageService(completer.future);

      await tester.pumpWidget(
        makeTestableWidget(CollectionScreen(imageStorageService: service)),
      );

      expect(find.byType(CircularProgressIndicator), findsOneWidget);

      completer.complete([]);
      await pumpLoadedState(tester);
    });

    testWidgets('shows empty state when there are no saved images', (
      WidgetTester tester,
    ) async {
      final service = FakeImageStorageService(Future.value([]));

      await tester.pumpWidget(
        makeTestableWidget(CollectionScreen(imageStorageService: service)),
      );

      await pumpLoadedState(tester);

      expect(find.byType(EmptyCollection), findsOneWidget);
      expect(find.text('Your collection\nis empty'), findsOneWidget);
      expect(
        find.text(
          'Scan or import a music sheet\nto start building your collection.',
        ),
        findsOneWidget,
      );
      expect(find.byKey(const ValueKey('addImageButton')), findsOneWidget);
    });

    testWidgets('shows score cards when saved images exist', (
      WidgetTester tester,
    ) async {
      final service = FakeImageStorageService(
        Future.value(['/fake/path/image1.jpg', '/fake/path/image2.jpg']),
      );

      await tester.pumpWidget(
        makeTestableWidget(CollectionScreen(imageStorageService: service)),
      );

      await pumpLoadedState(tester);

      expect(find.byType(ScoreCard), findsNWidgets(2));
    });

    testWidgets('shows app bar content and bottom navigation labels', (
      WidgetTester tester,
    ) async {
      final service = FakeImageStorageService(Future.value([]));

      await tester.pumpWidget(
        makeTestableWidget(CollectionScreen(imageStorageService: service)),
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

    testWidgets('opens editor route when score card is tapped', (
      WidgetTester tester,
    ) async {
      final service = FakeImageStorageService(
        Future.value(['/fake/path/image1.jpg']),
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
              builder: (_) => CollectionScreen(imageStorageService: service),
            );
          },
        ),
      );

      await pumpLoadedState(tester);
      await tester.tap(find.byType(ScoreCard));
      await tester.pumpAndSettle();

      expect(find.text('Editor Route Opened'), findsOneWidget);
    });
  });
}
