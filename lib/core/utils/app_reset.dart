import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../services/debug_mode_service.dart';

class AppReset {
  /// Wipes all user data (prefs + project files) and sets the debug mode flag
  /// to [debugMode]. Call this before navigating back to OnboardingScreen.
  static Future<void> clearAndSetDebugMode({required bool debugMode}) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.clear();
    await DebugModeService.setEnabled(debugMode);

    final docsDir = await getApplicationDocumentsDirectory();
    final projectsDir = Directory(p.join(docsDir.path, 'projects'));
    if (await projectsDir.exists()) {
      await projectsDir.delete(recursive: true);
    }
  }
}
