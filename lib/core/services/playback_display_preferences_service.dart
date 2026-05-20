import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

class PlaybackDisplayPreferencesService {
  static const String _keyShowSymbolGlow = 'playback_show_symbol_glow';

  static final ValueNotifier<bool> showSymbolGlowNotifier = ValueNotifier<bool>(
    false,
  );

  static Future<bool> getShowSymbolGlow() async {
    final prefs = await SharedPreferences.getInstance();
    final value = prefs.getBool(_keyShowSymbolGlow) ?? false;
    showSymbolGlowNotifier.value = value;
    return value;
  }

  static Future<void> setShowSymbolGlow(bool value) async {
    showSymbolGlowNotifier.value = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyShowSymbolGlow, value);
  }
}
