import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:note_vision/core/services/image_storage_service.dart';
import 'package:note_vision/features/collection/presentation/collection_screen.dart';
import 'package:note_vision/features/collection/presentation/widgets/empty_collection.dart';
import 'package:note_vision/features/collection/presentation/widgets/score_card.dart';

class FakeImageStorageService extends ImageStorageService {
  FakeImageStorageService(this.paths);

  final List<String> paths;

  @override
  Future<List<String>> getSavedImages() async {
    return paths;
  }
}

void main() {
  Widget makeTestableWidget(Widget child) {
    return MaterialApp(
      home: child,
    );
  }

  group('CollectionScreen', () {
    testWidgets('shows loading indicator first', (WidgetTester tester) async {
      final service = FakeImageStorageService([]);

      await tester.pumpWidget(
        makeTestableWidget(
          CollectionScreen(imageStorageService: service),
        ),
      );

      expect(find.byType(CircularProgressIndicator), findsOneWidget);
    });

    testWidgets('shows empty state when there are no saved images',
        (WidgetTester tester) async {
      final service = FakeImageStorageService([]);

      await tester.pumpWidget(
        makeTestableWidget(
          CollectionScreen(imageStorageService: service),
        ),
      );

      await tester.pumpAndSettle();

      expect(find.byType(EmptyCollection), findsOneWidget);
      expect(find.text('No projects yet'), findsOneWidget);
      expect(find.text('Scan or import a music sheet to get started'),
          findsOneWidget);
      expect(find.byKey(const ValueKey('addImageButton')), findsOneWidget);
    });

    testWidgets('shows score cards when saved images exist',
        (WidgetTester tester) async {
      final service = FakeImageStorageService([
        '/fake/path/image1.jpg',
        '/fake/path/image2.jpg',
      ]);

      await tester.pumpWidget(
        makeTestableWidget(
          CollectionScreen(imageStorageService: service),
        ),
      );

      await tester.pumpAndSettle();

      expect(find.byType(ScoreCard), findsNWidgets(2));
    });

    testWidgets('shows app bar and bottom navigation',
        (WidgetTester tester) async {
      final service = FakeImageStorageService([]);

      await tester.pumpWidget(
        makeTestableWidget(
          CollectionScreen(imageStorageService: service),
        ),
      );

      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('collectionAppBar')), findsOneWidget);
      expect(find.text('My Files'), findsOneWidget);

      expect(find.byKey(const ValueKey('mainBottomNav')), findsOneWidget);
      expect(find.text('Add Files'), findsOneWidget);
      expect(find.text('Info'), findsOneWidget);
      expect(find.text('Edit'), findsOneWidget);
      expect(find.text('Result'), findsOneWidget);
    });
  });
}