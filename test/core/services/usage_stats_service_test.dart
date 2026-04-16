import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:note_vision/core/services/usage_stats_service.dart';

void main() {
  setUpAll(() {
    TestWidgetsFlutterBinding.ensureInitialized();
  });

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('UsageStatsService', () {
    test('loadStats returns all zeros on first launch', () async {
      final stats = await UsageStatsService.loadStats();
      expect(stats.scans, 0);
      expect(stats.edits, 0);
      expect(stats.exports, 0);
      expect(stats.playbacks, 0);
    });

    test('incrementScans increments scan count by 1', () async {
      await UsageStatsService.incrementScans();
      final stats = await UsageStatsService.loadStats();
      expect(stats.scans, 1);
    });

    test('incrementEdits increments edit count by 1', () async {
      await UsageStatsService.incrementEdits();
      final stats = await UsageStatsService.loadStats();
      expect(stats.edits, 1);
    });

    test('incrementExports increments export count by 1', () async {
      await UsageStatsService.incrementExports();
      final stats = await UsageStatsService.loadStats();
      expect(stats.exports, 1);
    });

    test('incrementPlaybacks increments playback count by 1', () async {
      await UsageStatsService.incrementPlaybacks();
      final stats = await UsageStatsService.loadStats();
      expect(stats.playbacks, 1);
    });

    test('loadStats returns correct values after mixed increments', () async {
      await UsageStatsService.incrementScans();
      await UsageStatsService.incrementEdits();
      await UsageStatsService.incrementEdits();
      await UsageStatsService.incrementExports();
      final stats = await UsageStatsService.loadStats();
      expect(stats.scans, 1);
      expect(stats.edits, 2);
      expect(stats.exports, 1);
      expect(stats.playbacks, 0);
    });

    test('multiple incrementScans calls accumulate', () async {
      await UsageStatsService.incrementScans();
      await UsageStatsService.incrementScans();
      await UsageStatsService.incrementScans();
      final stats = await UsageStatsService.loadStats();
      expect(stats.scans, 3);
    });

    test('multiple incrementEdits calls accumulate', () async {
      for (var i = 0; i < 5; i++) {
        await UsageStatsService.incrementEdits();
      }
      final stats = await UsageStatsService.loadStats();
      expect(stats.edits, 5);
    });

    test('counters are independent — incrementing one does not affect others', () async {
      await UsageStatsService.incrementPlaybacks();
      await UsageStatsService.incrementPlaybacks();
      final stats = await UsageStatsService.loadStats();
      expect(stats.scans, 0);
      expect(stats.edits, 0);
      expect(stats.exports, 0);
      expect(stats.playbacks, 2);
    });
  });
}
