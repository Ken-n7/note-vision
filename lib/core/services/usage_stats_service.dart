import 'package:shared_preferences/shared_preferences.dart';

class UsageStats {
  const UsageStats({
    required this.scans,
    required this.edits,
    required this.exports,
    required this.playbacks,
  });

  final int scans;
  final int edits;
  final int exports;
  final int playbacks;
}

class UsageStatsService {
  static const String _keyScans     = 'stats_scans';
  static const String _keyEdits     = 'stats_edits';
  static const String _keyExports   = 'stats_exports';
  static const String _keyPlaybacks = 'stats_playbacks';

  static Future<void> incrementScans() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_keyScans, (prefs.getInt(_keyScans) ?? 0) + 1);
  }

  static Future<void> incrementEdits() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_keyEdits, (prefs.getInt(_keyEdits) ?? 0) + 1);
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
      scans:     prefs.getInt(_keyScans)     ?? 0,
      edits:     prefs.getInt(_keyEdits)     ?? 0,
      exports:   prefs.getInt(_keyExports)   ?? 0,
      playbacks: prefs.getInt(_keyPlaybacks) ?? 0,
    );
  }
}
