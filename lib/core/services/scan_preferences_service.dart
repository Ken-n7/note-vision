import 'package:shared_preferences/shared_preferences.dart';

class ScanPreferencesService {
  static const String _keySkipPreview = 'scan_skip_preview';
  static const String _keySkipReview  = 'scan_skip_review';

  static Future<bool> getSkipPreview() => _get(_keySkipPreview);
  static Future<bool> getSkipReview()  => _get(_keySkipReview);
  static Future<void> setSkipPreview(bool v) => _set(_keySkipPreview, v);
  static Future<void> setSkipReview(bool v)  => _set(_keySkipReview, v);

  static Future<bool> _get(String key) async =>
      (await SharedPreferences.getInstance()).getBool(key) ?? false;

  static Future<void> _set(String key, bool value) async =>
      (await SharedPreferences.getInstance()).setBool(key, value);
}
