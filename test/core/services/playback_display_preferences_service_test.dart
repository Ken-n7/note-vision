import 'package:flutter_test/flutter_test.dart';
import 'package:note_vision/core/services/playback_display_preferences_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  group('PlaybackDisplayPreferencesService', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
      PlaybackDisplayPreferencesService.showSymbolGlowNotifier.value = true;
    });

    test('show symbol glow defaults to true', () async {
      final value = await PlaybackDisplayPreferencesService.getShowSymbolGlow();

      expect(value, isTrue);
      expect(
        PlaybackDisplayPreferencesService.showSymbolGlowNotifier.value,
        isTrue,
      );
    });

    test('setShowSymbolGlow persists and notifies value', () async {
      await PlaybackDisplayPreferencesService.setShowSymbolGlow(false);

      expect(
        PlaybackDisplayPreferencesService.showSymbolGlowNotifier.value,
        isFalse,
      );
      expect(
        await PlaybackDisplayPreferencesService.getShowSymbolGlow(),
        isFalse,
      );
    });
  });
}
