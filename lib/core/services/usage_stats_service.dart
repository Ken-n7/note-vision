import 'package:shared_preferences/shared_preferences.dart';

class UsageStats {
  const UsageStats({
    required this.scans,
    required this.exports,
    required this.playbacks,
  });

  final int scans;
  final int exports;
  final int playbacks;
}

class UsageStatsService {
  static const String _keyScans = 'stats_scans';
  static const String _keyExports = 'stats_exports';
  static const String _keyPlaybacks = 'stats_playbacks';

  static String _keyScoreEdits(String scoreId) => 'stats_edits_$scoreId';

  static Future<void> incrementScans() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_keyScans, (prefs.getInt(_keyScans) ?? 0) + 1);
  }

  static Future<void> incrementScoreEdits(String scoreId) async {
    final prefs = await SharedPreferences.getInstance();
    final key = _keyScoreEdits(scoreId);
    await prefs.setInt(key, (prefs.getInt(key) ?? 0) + 1);
  }

  static Future<int> loadScoreEdits(String scoreId) async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt(_keyScoreEdits(scoreId)) ?? 0;
  }

  static Future<void> incrementExports() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_keyExports, (prefs.getInt(_keyExports) ?? 0) + 1);
  }

  static Future<void> incrementPlaybacks() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_keyPlaybacks, (prefs.getInt(_keyPlaybacks) ?? 0) + 1);
  }

  static Future<UsageStats> loadStats() async {
    final prefs = await SharedPreferences.getInstance();
    return UsageStats(
      scans: prefs.getInt(_keyScans) ?? 0,
      exports: prefs.getInt(_keyExports) ?? 0,
      playbacks: prefs.getInt(_keyPlaybacks) ?? 0,
    );
  }
}
