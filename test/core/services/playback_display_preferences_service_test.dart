import 'package:flutter_test/flutter_test.dart';
import 'package:note_vision/core/services/playback_display_preferences_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  group('PlaybackDisplayPreferencesService', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
      PlaybackDisplayPreferencesService.showSymbolGlowNotifier.value = false;
    });

    test('show symbol glow defaults to false', () async {
      final value = await PlaybackDisplayPreferencesService.getShowSymbolGlow();

      expect(value, isFalse);
      expect(
        PlaybackDisplayPreferencesService.showSymbolGlowNotifier.value,
        isFalse,
      );
    });

    test('setShowSymbolGlow persists and notifies value', () async {
      await PlaybackDisplayPreferencesService.setShowSymbolGlow(true);

      expect(
        PlaybackDisplayPreferencesService.showSymbolGlowNotifier.value,
        isTrue,
      );
      expect(
        await PlaybackDisplayPreferencesService.getShowSymbolGlow(),
        isTrue,
      );
    });
  });
}
