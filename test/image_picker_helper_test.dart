import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:note_vision/core/utils/image_picker_helper.dart';
// 👆 replace with your real package name

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const MethodChannel channel = MethodChannel(
    'plugins.flutter.io/image_picker',
  );

  Widget createTestApp() {
    return const MaterialApp(home: Scaffold(body: TestWidget()));
  }

  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  group('ImagePickerHelper Tests', () {
    setUp(() {
      messenger.setMockMethodCallHandler(channel, null);
    });

    tearDown(() {
      messenger.setMockMethodCallHandler(channel, null);
    });

    testWidgets('Returns File when image is picked', (
      WidgetTester tester,
    ) async {
      messenger.setMockMethodCallHandler(channel, (MethodCall methodCall) async {
        if (methodCall.method == 'pickImage') {
          return '/fake/path/test_image.jpg';
        }
        return null;
      });

      await tester.pumpWidget(createTestApp());

      final context = tester.element(find.byType(TestWidget));

      final file = await ImagePickerHelper.pickFromGallery(context);

      expect(file, isA<File>());
      expect(file!.path, '/fake/path/test_image.jpg');
    });

    testWidgets('Returns null when user cancels', (WidgetTester tester) async {
      messenger.setMockMethodCallHandler(channel, (MethodCall methodCall) async {
        return null; // simulate cancel
      });

      await tester.pumpWidget(createTestApp());

      final context = tester.element(find.byType(TestWidget));

      final file = await ImagePickerHelper.pickFromCamera(context);

      expect(file, isNull);
    });

    testWidgets('Shows SnackBar when exception occurs', (
      WidgetTester tester,
    ) async {
      messenger.setMockMethodCallHandler(channel, (MethodCall methodCall) async {
        throw PlatformException(code: 'ERROR', message: 'Camera failed');
      });

      await tester.pumpWidget(createTestApp());

      final context = tester.element(find.byType(TestWidget));

      final file = await ImagePickerHelper.pickFromCamera(context);

      await tester.pump(); // allow snackbar to show

      expect(file, isNull);
      expect(find.textContaining('Failed to pick image'), findsOneWidget);
    });
  });
}

class TestWidget extends StatelessWidget {
  const TestWidget({super.key});

  @override
  Widget build(BuildContext context) {
    return const SizedBox();
  }
}
