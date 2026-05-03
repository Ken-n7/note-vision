import 'package:shared_preferences/shared_preferences.dart';

class ScanPreferencesService {
  static const String _keySkipPreview = 'scan_skip_preview';
  static const String _keySkipReview  = 'scan_skip_review';

  static Future<bool> getSkipPreview() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_keySkipPreview) ?? false;
  }

  static Future<bool> getSkipReview() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_keySkipReview) ?? false;
  }

  static Future<void> setSkipPreview(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keySkipPreview, value);
  }

  static Future<void> setSkipReview(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keySkipReview, value);
  }
}
